package.path = package.path .. ";/minenet/?.lua;./?.lua"

local protocol = require("protocol")
local storage = require("storage")
local configMod = require("config")
local util = require("util")
local nav = require("nav")
local fuel = require("fuel")

local IDENTITY_PATH = "/minenet/data/identity.tbl"
local cfg = configMod.load()
local identity = storage.read(IDENTITY_PATH, {})

local running = true
local status = "booting"
local alert = nil
local serverId = identity.server_id
local currentJob = nil
local paused = false
local recallRequested = false
local busy = false

local function saveIdentity()
  identity.server_id = serverId
  storage.write(IDENTITY_PATH, identity)
end

local function setStatus(newStatus, newAlert)
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
    recall = recallRequested
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
    capabilities = { gps = true, mining = true, fuel_inventory = true }
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
      cfg.token = p.token or cfg.token
      cfg.base = p.base or cfg.base
      cfg.dropoff = p.dropoff or cfg.dropoff
      cfg.fuel = p.fuel or cfg.fuel
      cfg.area = p.area or cfg.area
      cfg.branch_length = p.branch_length or cfg.branch_length
      cfg.branch_spacing = p.branch_spacing or cfg.branch_spacing
      cfg.tunnel_height = p.tunnel_height or cfg.tunnel_height
      configMod.save(cfg)
      saveIdentity()
      nav.setServer(serverId, cfg.token, identity.turtle_id)
      return true
    end
  end

  if serverId and identity.turtle_id then
    nav.setServer(serverId, cfg.token, identity.turtle_id)
    return true
  end
  return false
end

local function minimumFuelTo(point)
  if fuel.rawLevel() == "unlimited" then return 0 end
  local margin = cfg.fuel_margin or 100
  if not point or not nav.pos then return cfg.fuel_min or 40 end
  return util.dist(nav.pos, point) + margin
end

local function enterOutOfFuel(minFuel, why)
  minFuel = math.max(minFuel or 1, 1)
  if fuel.limit() > 0 then minFuel = math.min(minFuel, fuel.limit()) end
  setStatus("out_of_fuel", why or "Insert coal/fuel into this turtle")
  term.clear()
  term.setCursorPos(1, 1)
  print("MineNet turtle is OUT OF FUEL")
  print("Insert coal/charcoal/coal block/lava bucket.")
  print("Needed fuel: " .. tostring(minFuel))
  report("status")

  while running do
    local ok = fuel.tryRefuelTo(minFuel, true)
    if ok or fuel.level() >= minFuel then
      setStatus("idle", nil)
      report("status", { event = "refueled_by_player" })
      return true
    end
    term.setCursorPos(1, 5)
    term.clearLine()
    term.write("Fuel: " .. fuelText() .. "  waiting...")
    report("status")
    sleep(2)
  end
  return false, "shutdown"
end

local function ensureFuelForMove(to)
  if fuel.rawLevel() == "unlimited" then return true end
  if fuel.level() >= 1 then return true end
  fuel.tryRefuelTo(cfg.fuel_min or 40, true)
  if fuel.level() >= 1 then return true end
  return enterOutOfFuel(1, "Insert fuel so I can move")
end

nav.beforeMove = ensureFuelForMove

local function suckBySide(side)
  side = side or "front"
  if side == "up" then return turtle.suckUp() end
  if side == "down" then return turtle.suckDown() end
  return turtle.suck()
end

local function dropBySide(side)
  side = side or "front"
  if side == "up" then return turtle.dropUp() end
  if side == "down" then return turtle.dropDown() end
  return turtle.drop()
end

local function faceStation(station)
  if station and station.heading ~= nil then nav.face(station.heading) end
end

local function goFuelStation(targetFuel)
  if not cfg.fuel then return false, "no_fuel_station" end
  if fuel.rawLevel() == "unlimited" then return true end
  targetFuel = math.min(targetFuel or cfg.fuel_target or 800, fuel.limit())

  local neededToReach = util.dist(nav.pos, cfg.fuel) + 2
  if fuel.level() < neededToReach then
    fuel.tryRefuelTo(neededToReach, true)
  end
  if fuel.level() < neededToReach then
    return enterOutOfFuel(neededToReach, "Need fuel to reach fuel station")
  end

  setStatus("to_fuel", nil)
  report("status")
  local ok, reason = nav.goTo(cfg.fuel, { dig = true })
  if not ok then return false, reason end

  faceStation(cfg.fuel)
  setStatus("refueling", nil)
  report("status")

  local attempts = cfg.fuel_station_wait or 8
  for i = 1, attempts do
    fuel.tryRefuelTo(targetFuel, true)
    if fuel.level() >= targetFuel then
      setStatus("idle", nil)
      report("status", { event = "refueled_at_station" })
      return true
    end
    suckBySide(cfg.fuel.side or "front")
    fuel.tryRefuelTo(targetFuel, true)
    if fuel.level() >= targetFuel then
      setStatus("idle", nil)
      report("status", { event = "refueled_at_station" })
      return true
    end
    setStatus("fuel_station_empty", "Fuel chest empty or unreachable")
    report("status")
    sleep(1.5)
  end

  return enterOutOfFuel(targetFuel, "Fuel station empty; insert fuel")
end

local function ensureFuelForRoute(dest)
  if fuel.rawLevel() == "unlimited" then return true end
  local need = math.max(minimumFuelTo(dest), cfg.fuel_min or 40)
  if fuel.level() >= need then return true end

  fuel.tryRefuelTo(math.max(need, cfg.fuel_target or 800), true)
  if fuel.level() >= need then return true end

  if cfg.fuel and nav.pos and util.dist(nav.pos, cfg.fuel) + 2 <= fuel.level() then
    local ok = goFuelStation(math.max(need, cfg.fuel_target or 800))
    if ok and fuel.level() >= need then return true end
  end

  return enterOutOfFuel(need, "Need more fuel for safe route")
end

local function shouldKeepSlotOnUnload(slot)
  if not cfg.keep_fuel_on_unload then return false end
  return fuel.isPreferredFuelSlot(slot)
end

local function unloadInventory()
  if not cfg.dropoff then
    setStatus("inventory_full", "No drop-off configured")
    report("status")
    return false, "no_dropoff"
  end

  ensureFuelForRoute(cfg.dropoff)
  setStatus("returning", nil)
  report("status")
  local ok, reason = nav.goTo(cfg.dropoff, { dig = true })
  if not ok then return false, reason end

  faceStation(cfg.dropoff)
  setStatus("unloading", nil)
  report("status")
  for i = 1, 16 do
    turtle.select(i)
    if turtle.getItemCount(i) > 0 and not shouldKeepSlotOnUnload(i) then
      dropBySide(cfg.dropoff.side or "front")
    end
  end
  turtle.select(1)
  setStatus("idle", nil)
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
    sleep(2)
    report("status")
  end
  setStatus("idle", nil)
  return true
end

local function pollControlOnce()
  local id, msg = protocol.receive(protocol.NAME_CONTROL, 0.05, cfg.token)
  if id ~= serverId or not msg then return end
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
  elseif msg.type == "shutdown" then
    running = false
  elseif msg.type == "config_update" then
    local p = msg.payload or {}
    util.mergeDefaults(p, {})
    for k, v in pairs(p) do cfg[k] = v end
    configMod.save(cfg)
  end
end

local function pauseIfNeeded()
  while running and paused do
    setStatus("paused", "Paused by server")
    report("status")
    sleep(1)
    pollControlOnce()
  end
  return running
end

local function maybeHandleRecall()
  if recallRequested then
    local home = cfg.dropoff or cfg.base
    if home then
      ensureFuelForRoute(home)
      nav.goTo(home, { dig = true })
      if cfg.dropoff then unloadInventory() end
    end
    recallRequested = false
    setStatus("idle", nil)
    report("status", { event = "recall_complete" })
    return true
  end
  return false
end

local function maintainBeforeWork(dest)
  pollControlOnce()
  pauseIfNeeded()
  if maybeHandleRecall() then return false, "recalled" end

  local resume = nav.current()
  local target = dest or nav.pos
  local ok, reason = ensureFuelForRoute(target)
  if not ok then return false, reason end

  if target and nav.pos and util.dist(nav.pos, target) > 0 then
    ok, reason = ensureFuelForRoute(target)
    if not ok then return false, reason end
    ok, reason = nav.goTo(target, { dig = true })
    if not ok then return false, reason end
    if resume and resume.heading ~= nil then nav.face(resume.heading) end
  end

  ok, reason = ensureInventorySpace()
  if not ok then return false, reason end

  if target and nav.pos and util.dist(nav.pos, target) > 0 then
    ok, reason = ensureFuelForRoute(target)
    if not ok then return false, reason end
    ok, reason = nav.goTo(target, { dig = true })
    if not ok then return false, reason end
    if resume and resume.heading ~= nil then nav.face(resume.heading) end
  end

  return true
end

local function digTunnelHeight(height)
  height = height or 2
  if height <= 1 then return true end
  nav.digUp()
  if height <= 2 then return true end
  for level = 3, height do
    local ok = nav.up(true)
    if not ok then return false end
    nav.digUp()
  end
  for level = 3, height do
    local ok = nav.down(false)
    if not ok then return false end
  end
  return true
end

local function mineBranch(job)
  busy = true
  currentJob = job
  recallRequested = false
  setStatus("moving", nil)
  report("status", { job_id = job.id })

  local start = job.start
  if start then
    local ok, reason = maintainBeforeWork(start)
    if not ok then
      busy = false; return false, reason
    end
    ok, reason = nav.goTo(start, { dig = true })
    if not ok then
      setStatus("error", reason)
      report("job_failed", { job_id = job.id, reason = reason })
      busy = false
      return false, reason
    end
  end

  nav.face(job.heading or 1)
  setStatus("mining", nil)
  report("status")

  local length = job.length or cfg.branch_length or 48
  local height = job.height or cfg.tunnel_height or 2
  for step = 1, length do
    if not running then break end
    pollControlOnce()
    pauseIfNeeded()
    if maybeHandleRecall() then
      report("job_failed", { job_id = job.id, reason = "recalled", progress = step })
      currentJob = nil
      busy = false
      return false, "recalled"
    end
    maintainBeforeWork(nav.pos)

    nav.digForward()
    local ok, reason = nav.forward(true)
    if not ok then
      setStatus("error", reason)
      report("job_failed", { job_id = job.id, reason = reason, progress = step })
      currentJob = nil
      busy = false
      return false, reason
    end
    digTunnelHeight(height)
    report("status", { progress = step, total = length })
  end

  if cfg.dropoff then unloadInventory() end
  setStatus("idle", nil)
  report("job_done", { job_id = job.id, pos = nav.current() })
  currentJob = nil
  busy = false
  return true
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
        mineBranch(msg.payload or {})
      elseif msg.type == "go_unload" and not busy then
        unloadInventory()
      elseif msg.type == "go_fuel" and not busy then
        goFuelStation(cfg.fuel_target or 800)
      elseif msg.type == "pause" then
        paused = true
      elseif msg.type == "resume" then
        paused = false
      elseif msg.type == "recall" then
        recallRequested = true
        if not busy then maybeHandleRecall() end
      elseif msg.type == "shutdown" then
        running = false
      elseif msg.type == "config_update" then
        local p = msg.payload or {}
        for k, v in pairs(p) do cfg[k] = v end
        configMod.save(cfg)
      end
    end

    if not busy and not paused and os.clock() - lastJobRequest > 5 then
      lastJobRequest = os.clock()
      if status == "idle" then report("need_job") end
    end
  end
end

term.clear()
term.setCursorPos(1, 1)
print("MineNet turtle starting")
local modemSide = openModemOrError()
print("Modem: " .. tostring(modemSide))

local okGps, gpsErr = nav.syncGps(5)
if okGps then print("GPS: " .. util.formatPos(nav.pos)) else print("GPS warning: " .. tostring(gpsErr)) end
ensureHeading()

if not discoverServer() then error("Could not find/register with MineNet server") end
nav.setServer(serverId, cfg.token, identity.turtle_id)
setStatus("idle", nil)
print("Registered as Turtle " .. tostring(identity.turtle_id))
print("Waiting for jobs...")
report("status")

parallel.waitForAny(heartbeatLoop, commandLoop)
setStatus("offline", "program stopped")
report("status")
