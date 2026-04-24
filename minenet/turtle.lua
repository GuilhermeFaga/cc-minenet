package.path = package.path .. ";/minenet/?.lua;./?.lua"

local protocol = require("protocol")
local storage = require("storage")
local configMod = require("config")
local util = require("util")
local nav = require("nav")
local fuel = require("fuel")

local IDENTITY_PATH = "/minenet/data/identity.tbl"
local LOG_DIR = "/minenet/logs"
local cfg = configMod.load()
local identity = storage.read(IDENTITY_PATH, {})

local running = true
local status = "booting"
local alert = nil
local serverId = identity.server_id
local currentJob = nil
local paused = false
local recallRequested = false
local handlingRecall = false
local hardResetRequested = false
local busy = false
local heldStations = {}
local lastLog = nil
local lastError = nil

local pollControlOnce
local pauseIfNeeded
local maybeHandleRecall
local performHardReset
local releaseStation

local function nowText()
  if os.date then return os.date("%H:%M:%S") end
  return tostring(math.floor(os.clock()))
end

local function logPath()
  local id = identity.turtle_id or os.getComputerID()
  return LOG_DIR .. "/turtle_" .. tostring(id) .. ".log"
end

local function rotateLogIfNeeded(path)
  if fs.exists(path) and fs.getSize(path) > (cfg.log_max_bytes or 64000) then
    if fs.exists(path .. ".old") then fs.delete(path .. ".old") end
    fs.move(path, path .. ".old")
  end
end

local function logEvent(level, message, data)
  storage.ensureDir(LOG_DIR .. "/dummy")
  local path = logPath()
  rotateLogIfNeeded(path)
  local line = nowText() .. " [" .. tostring(level or "INFO") .. "] " .. tostring(message or "")
  if data ~= nil then
    local ok, text = pcall(textutils.serialize, data)
    if ok and text then line = line .. " " .. string.gsub(text, "\n", " ") end
  end
  local h = fs.open(path, "a")
  if h then
    h.writeLine(line)
    h.close()
  end
  lastLog = message
  if level == "ERROR" then lastError = tostring(message) end
end

local function saveIdentity()
  identity.server_id = serverId
  storage.write(IDENTITY_PATH, identity)
end

local function setStatus(newStatus, newAlert)
  if newStatus and newStatus ~= status then
    logEvent("INFO", "status " .. tostring(status) .. " -> " .. tostring(newStatus), { alert = newAlert })
  end
  status = newStatus or status
  alert = newAlert
end

local function fuelText()
  local raw = fuel.rawLevel()
  if raw == "unlimited" then return "unlimited" end
  return tostring(raw)
end

local function send(messageType, payload)
  if not serverId then return false end
  return protocol.send(serverId, protocol.NAME_STATUS, messageType, identity.turtle_id, payload or {}, cfg.token)
end

local function statusPayload(extra)
  local fuelItems, fuelSlots = fuel.countFuelItems()
  local payload = {
    status = status,
    alert = alert,
    pos = nav.current(),
    heading = nav.heading,
    fuel = fuel.rawLevel(),
    fuel_items = fuelItems,
    fuel_slots = fuelSlots,
    inventory = util.inventoryRatio(),
    free_slots = util.inventoryFreeSlots(),
    job_id = currentJob and currentJob.id or nil,
    paused = paused,
    recall = recallRequested,
    hard_reset = hardResetRequested,
    last_log = lastLog,
    last_error = lastError
  }
  for k, v in pairs(extra or {}) do payload[k] = v end
  return payload
end

local function report(messageType, extra)
  send(messageType or "status", statusPayload(extra))
end

local function openModemOrError()
  local ok, side = protocol.openModem()
  if not ok then error(side or "No modem found") end
  return side
end

local function ensureHeading()
  if nav.heading ~= nil then return true end
  if identity.heading ~= nil then
    nav.setHeading(identity.heading); return true
  end
  print("MineNet needs the turtle heading once.")
  print("0=N  1=E  2=S  3=W")
  local h = util.readHeading("Which way is the turtle facing?", 0)
  nav.setHeading(h)
  identity.heading = h
  saveIdentity()
  return true
end

local function applyServerConfig(p)
  cfg.token = p.token or cfg.token
  cfg.base = p.base or cfg.base
  cfg.dropoff = p.dropoff or cfg.dropoff
  cfg.fuel = p.fuel or cfg.fuel
  cfg.area = p.area or cfg.area
  cfg.mining_mode = p.mining_mode or cfg.mining_mode
  cfg.volume_width = p.volume_width or cfg.volume_width
  cfg.volume_height = p.volume_height or cfg.volume_height
  cfg.volume_depth = p.volume_depth or cfg.volume_depth
  cfg.branch_length = p.branch_length or cfg.branch_length
  cfg.branch_spacing = p.branch_spacing or cfg.branch_spacing
  cfg.tunnel_width = p.tunnel_width or cfg.tunnel_width
  cfg.tunnel_height = p.tunnel_height or cfg.tunnel_height
  cfg.fuel_min = p.fuel_min or cfg.fuel_min
  cfg.fuel_margin = p.fuel_margin or cfg.fuel_margin
  cfg.fuel_target = p.fuel_target or cfg.fuel_target
  cfg.player_resume_fuel = p.player_resume_fuel or cfg.player_resume_fuel
  cfg.station_lock_attempts = p.station_lock_attempts or cfg.station_lock_attempts
  cfg.log_max_bytes = p.log_max_bytes or cfg.log_max_bytes
  if p.keep_fuel_on_unload ~= nil then cfg.keep_fuel_on_unload = p.keep_fuel_on_unload end
  cfg.fuel_keep_items = p.fuel_keep_items or cfg.fuel_keep_items
  configMod.save(cfg)
end

local function discoverServer()
  openModemOrError()

  if not serverId then
    local found = rednet.lookup(protocol.NAME_DISCOVERY, "minenet-server")
    if found then serverId = found end
  end

  local hello = {
    computer_id = os.getComputerID(),
    label = os.getComputerLabel(),
    turtle_id = identity.turtle_id,
    pos = nav.current(),
    heading = nav.heading,
    capabilities = { gps = true, mining = true, fuel_inventory = true, logging = true }
  }

  if serverId then
    protocol.send(serverId, protocol.NAME_DISCOVERY, "hello", identity.turtle_id, hello, cfg.token)
  else
    protocol.broadcast(protocol.NAME_DISCOVERY, "hello", identity.turtle_id, hello, cfg.token)
  end

  local start = os.clock()
  while os.clock() - start < 12 do
    local id, msg = rednet.receive(protocol.NAME_CONTROL, 2)
    if id and type(msg) == "table" and msg.type == "registered" then
      local p = msg.payload or {}
      serverId = id
      identity.server_id = id
      identity.turtle_id = p.turtle_id or msg.turtle_id or identity.turtle_id
      identity.color = p.color or identity.color
      applyServerConfig(p)
      saveIdentity()
      nav.setServer(serverId, cfg.token, identity.turtle_id)
      logEvent("INFO", "registered", { turtle_id = identity.turtle_id, server = serverId })
      return true
    end
  end

  if serverId and identity.turtle_id then
    nav.setServer(serverId, cfg.token, identity.turtle_id)
    return true
  end
  return false
end

local function estimatedFuelNeed(dest, extraWork)
  if fuel.rawLevel() == "unlimited" then return 0 end
  extraWork = tonumber(extraWork) or 0
  local margin = cfg.fuel_margin or 120
  local minimum = cfg.fuel_min or 40
  if not nav.pos then return minimum + extraWork end

  local toDest = 0
  if dest then toDest = util.dist(nav.pos, dest) end

  local toFuel = 0
  if cfg.fuel then
    if dest then toFuel = util.dist(dest, cfg.fuel) else toFuel = util.dist(nav.pos, cfg.fuel) end
  end

  local need = toDest + toFuel + margin + extraWork
  if need < minimum then need = minimum end
  if fuel.limit() > 0 and need > fuel.limit() then need = fuel.limit() end
  return need
end

local function fuelNeededToReachStation()
  if fuel.rawLevel() == "unlimited" then return 0 end
  if not cfg.fuel or not nav.pos then return cfg.fuel_min or 40 end
  return util.dist(nav.pos, cfg.fuel) + 2
end

releaseStation = function(stationName, force)
  if not stationName then return end
  if serverId and identity.turtle_id and (heldStations[stationName] or force) then
    protocol.send(serverId, protocol.NAME_ROUTE, "station_release", identity.turtle_id, { station = stationName },
      cfg.token)
  end
  heldStations[stationName] = nil
end

local function requestStation(stationName)
  if not serverId or not identity.turtle_id then return true end
  local attempts = cfg.station_lock_attempts or 120
  for attempt = 1, attempts do
    if pollControlOnce then pollControlOnce() end
    if hardResetRequested then return false, "hard_reset" end
    if recallRequested and not handlingRecall and stationName ~= "dropoff" then return false, "recalled" end

    setStatus("waiting_" .. stationName, stationName .. " station queue")
    report("status", { station = stationName, station_attempt = attempt })
    protocol.send(serverId, protocol.NAME_ROUTE, "station_request", identity.turtle_id, { station = stationName },
      cfg.token)

    local id, msg = protocol.receive(protocol.NAME_ROUTE, 1, cfg.token)
    if id == serverId and msg then
      if msg.type == "station_granted" and msg.payload and msg.payload.station == stationName then
        heldStations[stationName] = true
        logEvent("INFO", "station granted", { station = stationName })
        return true
      elseif msg.type == "station_wait" then
        local owner = msg.payload and msg.payload.owner or "?"
        setStatus("waiting_" .. stationName, stationName .. " station busy by " .. tostring(owner))
      end
    end
    sleep(0.5)
  end
  logEvent("WARN", "station lock timeout", { station = stationName })
  return false, stationName .. "_station_busy"
end

local function enterOutOfFuel(minFuel, why, allowPartial)
  minFuel = math.max(minFuel or (cfg.player_resume_fuel or 1), cfg.player_resume_fuel or 1)
  if fuel.limit() > 0 then minFuel = math.min(minFuel, fuel.limit()) end
  setStatus("out_of_fuel", why or "Insert coal/fuel into this turtle")
  logEvent("WARN", "out of fuel", { needed = minFuel, reason = why })
  term.clear()
  term.setCursorPos(1, 1)
  print("MineNet turtle is OUT OF FUEL")
  print("Insert coal/charcoal/coal block/lava bucket.")
  print("Needed fuel: " .. tostring(minFuel))
  print("Any usable fuel lets me resume and seek station.")
  report("status")

  while running do
    if pollControlOnce then pollControlOnce() end
    if hardResetRequested then return false, "hard_reset" end
    local before = fuel.level()
    local ok, consumed = fuel.tryRefuelTo(minFuel, true)
    local after = fuel.level()
    if ok or after >= minFuel or (allowPartial ~= false and after > 0 and (after > before or (consumed or 0) > 0)) then
      setStatus("refueled", nil)
      logEvent("INFO", "manual fuel added", { before = before, after = after, consumed = consumed })
      report("status", { event = "manual_fuel_added", needed = minFuel })
      return true
    end
    term.setCursorPos(1, 6)
    term.clearLine()
    term.write("Fuel: " .. fuelText() .. "  waiting...")
    report("status")
    sleep(2)
  end
  return false, "shutdown"
end

local function ensureFuelForMove(to)
  if fuel.rawLevel() == "unlimited" then return true end
  if hardResetRequested then return false, "hard_reset" end
  if fuel.level() < (cfg.fuel_min or 40) then
    fuel.tryRefuelTo(cfg.fuel_min or 40, true)
  end
  if fuel.level() >= 1 then return true end
  local ok, reason = enterOutOfFuel(1, "Insert fuel so I can move", true)
  if ok and fuel.level() >= 1 then return true end
  return false, reason or "out_of_fuel"
end

nav.beforeMove = ensureFuelForMove

local function suckBySide(side)
  side = side or "front"
  if side == "up" then return turtle.suckUp() end
  if side == "down" then return turtle.suckDown() end
  return turtle.suck()
end

local function dropBySide(side, count)
  side = side or "front"
  if side == "up" then return turtle.dropUp(count) end
  if side == "down" then return turtle.dropDown(count) end
  return turtle.drop(count)
end

local function faceStation(station)
  if station and station.heading ~= nil then return nav.face(station.heading) end
  return true
end

local function goFuelStation(targetFuel, resumeStatus)
  if not cfg.fuel then return false, "no_fuel_station" end
  if fuel.rawLevel() == "unlimited" then return true end
  targetFuel = math.min(targetFuel or cfg.fuel_target or 800, fuel.limit())

  local neededToReach = util.dist(nav.pos, cfg.fuel) + 2
  if fuel.level() < neededToReach then fuel.tryRefuelTo(neededToReach, true) end
  if fuel.level() < neededToReach then
    local ok = enterOutOfFuel(neededToReach, "Need fuel to reach fuel station", true)
    if not ok then return false, "out_of_fuel" end
  end

  local lockOk, lockReason = requestStation("fuel")
  if not lockOk then return false, lockReason end

  setStatus("to_fuel", nil)
  report("status")
  local ok, reason = nav.goTo(cfg.fuel, { dig = true })
  if not ok then
    releaseStation("fuel"); return false, reason
  end

  ok, reason = faceStation(cfg.fuel)
  if not ok then
    releaseStation("fuel"); return false, reason
  end
  setStatus("refueling", nil)
  report("status")

  local attempts = cfg.fuel_station_wait or 8
  for i = 1, attempts do
    if pollControlOnce then pollControlOnce() end
    if hardResetRequested then
      releaseStation("fuel"); return false, "hard_reset"
    end
    fuel.tryRefuelTo(targetFuel, true)
    if fuel.level() >= targetFuel then
      setStatus(resumeStatus or "idle", nil)
      logEvent("INFO", "refueled at station", { fuel = fuel.level() })
      report("status", { event = "refueled_at_station" })
      releaseStation("fuel")
      return true
    end
    suckBySide(cfg.fuel.side or "front")
    fuel.tryRefuelTo(targetFuel, true)
    if fuel.level() >= targetFuel then
      setStatus(resumeStatus or "idle", nil)
      logEvent("INFO", "refueled at station", { fuel = fuel.level() })
      report("status", { event = "refueled_at_station" })
      releaseStation("fuel")
      return true
    end
    setStatus("fuel_station_empty", "Fuel chest empty or unreachable")
    report("status")
    sleep(1.5)
  end

  if fuel.level() <= 0 then
    releaseStation("fuel")
    enterOutOfFuel(1, "Fuel station empty; insert fuel", true)
  end
  if fuel.level() > 0 then
    setStatus(resumeStatus or "idle", "Fuel station did not reach target")
    report("status", { event = "fuel_station_partial" })
    releaseStation("fuel")
    return false, "fuel_station_empty"
  end
  releaseStation("fuel")
  return false, "fuel_station_empty"
end

local function ensureFuelForRoute(dest, resumeStatus, extraWork)
  if fuel.rawLevel() == "unlimited" then return true end
  if hardResetRequested then return false, "hard_reset" end

  local need = estimatedFuelNeed(dest, extraWork)
  local stationNeed = fuelNeededToReachStation()
  if fuel.level() >= need then return true end

  fuel.tryRefuelTo(need, true)
  if fuel.level() >= need then return true end

  if cfg.fuel and nav.pos then
    if fuel.level() < stationNeed then
      fuel.tryRefuelTo(stationNeed, true)
    end
    if fuel.level() < stationNeed then
      local ok, reason = enterOutOfFuel(stationNeed, "Need fuel to reach refuel chest", true)
      if not ok then return false, reason or "out_of_fuel" end
    end

    if fuel.level() >= stationNeed then
      local ok, reason = goFuelStation(math.max(need, cfg.fuel_target or 800), resumeStatus or status)
      if ok and fuel.level() >= need then return true end
      -- Do not continue mining on a partial refill unless it is still enough to return safely.
      if fuel.level() >= need then return true end
      return false, reason or "not_enough_fuel_after_station"
    end
  end

  local ok, reason = enterOutOfFuel(need, "Need more fuel for safe route", true)
  if ok then
    fuel.tryRefuelTo(need, true)
    if fuel.level() >= need then return true end
    if cfg.fuel and nav.pos and fuel.level() >= fuelNeededToReachStation() then
      local stationOk, stationReason = goFuelStation(math.max(need, cfg.fuel_target or 800), resumeStatus or status)
      if stationOk and fuel.level() >= need then return true end
      return false, stationReason or "not_enough_fuel_after_manual"
    end
  end
  return false, reason or "out_of_fuel"
end

local function unloadSlot(slot, side, keepCount)
  turtle.select(slot)
  local blocked = false
  local attempts = 0
  while turtle.getItemCount(slot) > keepCount and attempts < 6 do
    attempts = attempts + 1
    local before = turtle.getItemCount(slot)
    local amount = before - keepCount
    local ok = dropBySide(side, amount)
    sleep(0.15)
    local after = turtle.getItemCount(slot)
    if after <= keepCount then return true end
    if not ok or after >= before then
      blocked = true
      break
    end
  end
  return not blocked and turtle.getItemCount(slot) <= keepCount
end

local function unloadInventory()
  if not cfg.dropoff then
    setStatus("inventory_full", "No drop-off configured")
    report("status")
    return false, "no_dropoff"
  end

  local resumeStatus = status
  local ok, reason = ensureFuelForRoute(cfg.dropoff, "returning")
  if not ok then return false, reason end

  ok, reason = requestStation("dropoff")
  if not ok then return false, reason end

  setStatus("returning", nil)
  report("status")
  ok, reason = nav.goTo(cfg.dropoff, { dig = true })
  if not ok then
    releaseStation("dropoff"); return false, reason
  end

  ok, reason = faceStation(cfg.dropoff)
  if not ok then
    releaseStation("dropoff"); return false, reason
  end
  setStatus("unloading", nil)
  report("status")

  local side = cfg.dropoff.side or "front"
  local keepFuel = cfg.keep_fuel_on_unload ~= false
  local fuelReserve = keepFuel and (cfg.fuel_keep_items or 1) or 0
  local keptFuel = 0
  local blocked = false
  local finalBlocked = false

  for pass = 1, 2 do
    for i = 1, 16 do
      if pollControlOnce then pollControlOnce() end
      if hardResetRequested then
        releaseStation("dropoff"); return false, "hard_reset"
      end
      local count = turtle.getItemCount(i)
      if count > 0 then
        local keep = 0
        if keepFuel and fuel.isPreferredFuelSlot(i) and keptFuel < fuelReserve then
          keep = math.min(count, fuelReserve - keptFuel)
          keptFuel = keptFuel + keep
        end
        if not unloadSlot(i, side, keep) then blocked = true end
      end
    end
    if not blocked then break end
    setStatus("dropoff_full", "Drop-off chest full or unreachable")
    report("status")
    finalBlocked = true
    sleep(cfg.dropoff_wait or 5)
    blocked = false
  end

  turtle.select(1)
  releaseStation("dropoff")

  local leftover = 0
  for i = 1, 16 do
    if turtle.getItemCount(i) > 0 then leftover = leftover + 1 end
  end
  if leftover > (fuelReserve > 0 and 1 or 0) and finalBlocked then
    setStatus("dropoff_full", "Could not unload all items")
    report("status")
    return false, "dropoff_full"
  end

  if currentJob then
    setStatus(resumeStatus == "unloading" and "moving" or resumeStatus, nil)
  else
    setStatus("idle", nil)
  end
  logEvent("INFO", "unloaded", { leftover_slots = leftover })
  report("status", { event = "unloaded" })
  return true
end

local function ensureInventorySpace()
  local ratio = util.inventoryRatio()
  if ratio < (cfg.inventory_return_ratio or 0.85) and util.inventoryFreeSlots() > 0 then return true end
  local ok = unloadInventory()
  if ok and util.inventoryFreeSlots() > 0 then return true end

  setStatus("inventory_full", "Inventory full; empty turtle or configure drop-off")
  report("status")
  while running and util.inventoryFreeSlots() == 0 do
    if pollControlOnce then pollControlOnce() end
    if hardResetRequested then return false, "hard_reset" end
    sleep(2)
    report("status")
  end
  setStatus("idle", nil)
  return true
end

pollControlOnce = function()
  local id, msg = protocol.receive(protocol.NAME_CONTROL, 0.05, cfg.token)
  if id ~= serverId or not msg then return nil end
  if msg.type == "pause" then
    paused = true
    setStatus("paused", "Paused by server")
    report("status")
  elseif msg.type == "resume" then
    paused = false
    setStatus("idle", nil)
    report("status")
  elseif msg.type == "recall" then
    recallRequested = true
    paused = false
    setStatus("returning", "Recall requested")
    report("status")
  elseif msg.type == "hard_reset" then
    hardResetRequested = true
    paused = false
    recallRequested = false
    setStatus("resetting", "Hard reset requested")
    logEvent("WARN", "hard reset command received", msg.payload)
    report("status", { clear_job = true })
  elseif msg.type == "shutdown" then
    running = false
  elseif msg.type == "config_update" then
    local p = msg.payload or {}
    for k, v in pairs(p) do cfg[k] = v end
    configMod.save(cfg)
    logEvent("INFO", "config updated")
  end
  return msg.type
end

pauseIfNeeded = function()
  while running and paused do
    pollControlOnce()
    if hardResetRequested then return false, "hard_reset" end
    if recallRequested then return false, "recalled" end
    setStatus("paused", "Paused by server")
    report("status")
    sleep(1)
  end
  return running
end

maybeHandleRecall = function()
  if recallRequested then
    local home = cfg.dropoff or cfg.base
    local ok, reason = true, nil
    handlingRecall = true
    if home then
      ok, reason = ensureFuelForRoute(home, "returning")
      if ok then ok, reason = nav.goTo(home, { dig = true }) end
      if ok and cfg.dropoff then ok, reason = unloadInventory() end
    end
    handlingRecall = false
    if hardResetRequested then return false, "hard_reset" end
    if ok then
      recallRequested = false
      currentJob = nil
      setStatus("idle", nil)
      logEvent("INFO", "recall complete")
      report("status", { event = "recall_complete", clear_job = true })
      return true
    end
    setStatus("recall_blocked", reason or "Could not return home")
    logEvent("WARN", "recall blocked", { reason = reason })
    report("status")
    return false, reason
  end
  return false
end

performHardReset = function(reason, shouldReport)
  logEvent("WARN", "local hard reset", { reason = reason })
  releaseStation("fuel", true)
  releaseStation("dropoff", true)
  currentJob = nil
  busy = false
  paused = false
  recallRequested = false
  handlingRecall = false
  hardResetRequested = false
  alert = nil
  pcall(function() nav.syncGps(2) end)
  setStatus("idle", nil)
  if shouldReport ~= false then report("reset_ack", { clear_job = true, reason = reason or "hard_reset" }) end
end

nav.shouldAbort = function()
  pollControlOnce()
  if hardResetRequested then return true, "hard_reset" end
  if recallRequested and not handlingRecall then return true, "recalled" end
  if paused then
    local ok, reason = pauseIfNeeded()
    if not ok then return true, reason or "paused" end
  end
  return false, nil
end

nav.onWait = function(reason, to, attempt)
  if status ~= "waiting_path" then setStatus("waiting_path", tostring(reason or "path blocked")) end
  if attempt == 1 or (attempt or 0) % 5 == 0 then
    report("status", { wait_reason = reason, wait_to = to, wait_attempt = attempt })
    logEvent("INFO", "waiting for path", { reason = reason, to = to, attempt = attempt })
  end
end

local function maintainBeforeWork(dest, extraWork)
  pollControlOnce()
  local ok, reason = pauseIfNeeded()
  if not ok then return false, reason end
  local recalled, recallReason = maybeHandleRecall()
  if hardResetRequested then return false, "hard_reset" end
  if recalled then return false, "recalled" end
  if recallReason then return false, recallReason end

  local resume = nav.current()
  local target = dest or nav.pos
  ok, reason = ensureFuelForRoute(target, status, extraWork)
  if not ok then return false, reason end

  if target and nav.pos and util.dist(nav.pos, target) > 0 then
    ok, reason = nav.goTo(target, { dig = true })
    if not ok then return false, reason end
    if resume and resume.heading ~= nil then nav.face(resume.heading) end
  end

  ok, reason = ensureInventorySpace()
  if not ok then return false, reason end

  if target and nav.pos and util.dist(nav.pos, target) > 0 then
    ok, reason = ensureFuelForRoute(target, status, extraWork)
    if not ok then return false, reason end
    ok, reason = nav.goTo(target, { dig = true })
    if not ok then return false, reason end
    if resume and resume.heading ~= nil then nav.face(resume.heading) end
  end

  return true
end

local function clearColumn(height)
  height = math.max(tonumber(height) or 1, 1)
  if height <= 1 then return true end

  for level = 2, height do
    local ok, reason = nav.digUp()
    if not ok then return false, reason end
    if level < height then
      ok, reason = nav.up(true)
      if not ok then return false, reason end
    end
  end

  for level = 2, height - 1 do
    local ok, reason = nav.down(false)
    if not ok then return false, reason end
  end
  return true
end

local function moveSideStep(direction, baseHeading)
  local sideHeading = direction == "right" and ((baseHeading + 1) % 4) or ((baseHeading + 3) % 4)
  local ok, reason = nav.face(sideHeading)
  if not ok then return false, reason end
  ok, reason = nav.forward(true)
  if not ok then return false, reason end
  ok, reason = nav.face(baseHeading)
  if not ok then return false, reason end
  return true
end

local function clearWallColumn(height, baseHeading)
  height = math.max(tonumber(height) or 1, 1)
  baseHeading = util.normHeading(baseHeading or nav.heading or 1)

  local ok, reason = nav.face(baseHeading)
  if not ok then return false, reason end

  ok, reason = nav.digForward()
  if not ok then return false, reason or "dig_forward_failed" end

  for level = 2, height do
    ok, reason = nav.up(true)
    if not ok then return false, reason end
    ok, reason = nav.face(baseHeading)
    if not ok then return false, reason end
    ok, reason = nav.digForward()
    if not ok then return false, reason or "dig_forward_failed" end
  end

  for level = 2, height do
    ok, reason = nav.down(false)
    if not ok then return false, reason end
  end

  ok, reason = nav.face(baseHeading)
  if not ok then return false, reason end
  return true
end

local function clearTunnelSlice(width, height, baseHeading)
  width = math.max(tonumber(width) or 1, 1)
  height = math.max(tonumber(height) or 1, 1)
  baseHeading = util.normHeading(baseHeading or nav.heading or 1)

  local ok, reason = nav.face(baseHeading)
  if not ok then return false, reason end
  ok, reason = clearColumn(height)
  if not ok then return false, reason end

  local right = math.floor((width - 1) / 2)
  local left = (width - 1) - right

  for i = 1, right do
    ok, reason = moveSideStep("right", baseHeading)
    if not ok then return false, reason end
    ok, reason = clearColumn(height)
    if not ok then return false, reason end
  end
  for i = 1, right do
    ok, reason = moveSideStep("left", baseHeading)
    if not ok then return false, reason end
  end

  for i = 1, left do
    ok, reason = moveSideStep("left", baseHeading)
    if not ok then return false, reason end
    ok, reason = clearColumn(height)
    if not ok then return false, reason end
  end
  for i = 1, left do
    ok, reason = moveSideStep("right", baseHeading)
    if not ok then return false, reason end
  end

  ok, reason = nav.face(baseHeading)
  if not ok then return false, reason end
  return true
end

local function failJob(job, reason, progress)
  reason = reason or "unknown"
  logEvent(reason == "hard_reset" and "WARN" or "ERROR", "job failed",
    { job = job and job.id, reason = reason, progress = progress })
  if reason == "hard_reset" then
    performHardReset("job interrupted by hard reset")
  elseif reason == "recalled" then
    report("job_failed", { job_id = job and job.id, reason = reason, progress = progress, clear_job = true })
    currentJob = nil
    busy = false
    maybeHandleRecall()
  else
    setStatus("error", reason)
    report("job_failed", { job_id = job and job.id, reason = reason, progress = progress, clear_job = true })
    currentJob = nil
    busy = false
  end
  return false, reason
end

local function mineVolumeColumn(job)
  busy = true
  currentJob = job
  setStatus("moving", "volume d" .. tostring(job.depth_index or 0) .. " c" .. tostring(job.column_index or 0))
  logEvent("INFO", "volume column job started", job)
  report("status", { job_id = job.id })

  local stand = job.stand or job.start
  if not stand then return failJob(job, "missing_stand") end
  local height = job.height or cfg.volume_height or cfg.tunnel_height or 1
  local extraWork = (height - 1) * 2 + 4

  local ok, reason = maintainBeforeWork(stand, extraWork)
  if not ok then return failJob(job, reason) end

  ok, reason = nav.goTo(stand, { dig = true })
  if not ok then return failJob(job, reason) end

  ok, reason = ensureFuelForRoute(stand, "mining", extraWork)
  if not ok then return failJob(job, reason) end

  ok, reason = nav.face(job.heading or 1)
  if not ok then return failJob(job, reason) end

  setStatus("mining", "wall d" .. tostring(job.depth_index or 0) .. " c" .. tostring(job.column_index or 0))
  report("status", { progress = 0, total = height })

  ok, reason = clearWallColumn(height, job.heading or 1)
  if not ok then return failJob(job, reason, 0) end

  setStatus("idle", nil)
  logEvent("INFO", "volume column done", { job = job.id, depth = job.depth_index, column = job.column_index })
  report("job_done", { job_id = job.id, pos = nav.current(), clear_job = true })
  currentJob = nil
  busy = false
  return true
end

local function mineBranch(job)
  busy = true
  currentJob = job
  setStatus("moving", nil)
  logEvent("INFO", "job started", job)
  report("status", { job_id = job.id })

  local start = job.start
  if start then
    local ok, reason = maintainBeforeWork(start,
      (job.width or cfg.tunnel_width or 1) * (job.height or cfg.tunnel_height or 1) * 2)
    if not ok then return failJob(job, reason) end
    ok, reason = nav.goTo(start, { dig = true })
    if not ok then return failJob(job, reason) end
  end

  local ok, reason = nav.face(job.heading or 1)
  if not ok then return failJob(job, reason) end
  setStatus("mining", nil)
  report("status")

  local length = job.length or cfg.branch_length or 48
  local width = job.width or cfg.tunnel_width or 3
  local height = job.height or cfg.tunnel_height or 3
  ok, reason = clearTunnelSlice(width, height, job.heading or 1)
  if not ok then return failJob(job, reason, 0) end

  for step = 1, length do
    if not running then break end
    pollControlOnce()
    ok, reason = pauseIfNeeded()
    if not ok then return failJob(job, reason, step) end
    local recalled, recallReason = maybeHandleRecall()
    if hardResetRequested then return failJob(job, "hard_reset", step) end
    if recalled then return failJob(job, "recalled", step) end
    if recallReason then return failJob(job, recallReason, step) end

    local maintained, maintainReason = maintainBeforeWork(nav.pos, width * height * 2 + 4)
    if not maintained then return failJob(job, maintainReason, step) end
    setStatus("mining", nil)
    ok, reason = nav.face(job.heading or 1)
    if not ok then return failJob(job, reason, step) end

    nav.digForward()
    ok, reason = nav.forward(true)
    if not ok then return failJob(job, reason, step) end
    ok, reason = clearTunnelSlice(width, height, job.heading or 1)
    if not ok then return failJob(job, reason, step) end
    report("status", { progress = step, total = length })
  end

  if cfg.dropoff then unloadInventory() end
  setStatus("idle", nil)
  logEvent("INFO", "job done", { job = job.id })
  report("job_done", { job_id = job.id, pos = nav.current(), clear_job = true })
  currentJob = nil
  busy = false
  return true
end

local function runJob(job)
  if job and job.type == "volume_column" then
    return mineVolumeColumn(job)
  end
  return mineBranch(job)
end

local function safeRunJob(job)
  local ok, a, b = xpcall(function() return runJob(job) end, function(err)
    if debug and debug.traceback then return debug.traceback(err) end
    return tostring(err)
  end)
  if not ok then
    lastError = tostring(a)
    logEvent("ERROR", "job crashed", { job = job and job.id, traceback = tostring(a) })
    setStatus("error", "crash; see turtle log")
    report("job_failed", { job_id = job and job.id, reason = "crash", detail = tostring(a), clear_job = true })
    currentJob = nil
    busy = false
    return false, "crash"
  end
  return a, b
end

local function heartbeatLoop()
  while running do
    report("heartbeat")
    sleep(3)
  end
end

local function commandLoop()
  local lastJobRequest = 0
  while running do
    local id, msg = protocol.receive(protocol.NAME_CONTROL, 1, cfg.token)
    if id == serverId and msg then
      if msg.type == "job_assign" and not busy then
        safeRunJob(msg.payload or {})
      elseif msg.type == "go_unload" and not busy then
        unloadInventory()
      elseif msg.type == "go_fuel" and not busy then
        goFuelStation(cfg.fuel_target or 800, "idle")
      elseif msg.type == "pause" then
        paused = true
        setStatus("paused", "Paused by server")
      elseif msg.type == "resume" then
        paused = false
        setStatus("idle", nil)
      elseif msg.type == "recall" then
        recallRequested = true
        if not busy then maybeHandleRecall() end
      elseif msg.type == "hard_reset" then
        hardResetRequested = true
        if not busy then performHardReset("server command") end
      elseif msg.type == "shutdown" then
        running = false
      elseif msg.type == "config_update" then
        local p = msg.payload or {}
        for k, v in pairs(p) do cfg[k] = v end
        configMod.save(cfg)
        logEvent("INFO", "config updated")
      end
    end

    if hardResetRequested and not busy then performHardReset("pending hard reset") end

    if not busy and not paused and not hardResetRequested and os.clock() - lastJobRequest > 5 then
      lastJobRequest = os.clock()
      if status == "idle" or status == "refueled" then report("need_job") end
    end
  end
end

term.clear()
term.setCursorPos(1, 1)
print("MineNet turtle starting")
logEvent("INFO", "program starting", { computer = os.getComputerID() })
local modemSide = openModemOrError()
print("Modem: " .. tostring(modemSide))

local okGps, gpsErr = nav.syncGps(5)
if okGps then print("GPS: " .. util.formatPos(nav.pos)) else
  print("GPS warning: " .. tostring(gpsErr)); logEvent("WARN", "gps failed", gpsErr)
end
ensureHeading()

if not discoverServer() then error("Could not find/register with MineNet server") end
nav.setServer(serverId, cfg.token, identity.turtle_id)
setStatus("idle", nil)
print("Registered as Turtle " .. tostring(identity.turtle_id))
print("Waiting for jobs...")
report("status")

parallel.waitForAny(heartbeatLoop, commandLoop)
setStatus("offline", "program stopped")
logEvent("INFO", "program stopped")
report("status")
