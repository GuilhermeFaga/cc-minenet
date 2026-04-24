package.path = package.path .. ";/minenet/?.lua;./?.lua"

local protocol = require("protocol")
local storage = require("storage")
local configMod = require("config")
local util = require("util")

local VERSION = "MineNet clean v2"
local TURTLES_PATH = "/minenet/data/turtles.tbl"
local JOBS_PATH = "/minenet/data/jobs.tbl"
local MAP_PATH = "/minenet/data/map.tbl"

local cfg = configMod.load()
local turtles = storage.read(TURTLES_PATH, {})
local jobs = storage.read(JOBS_PATH, {})
local worldMap = storage.read(MAP_PATH, {})
local reservations = {}
local running = true
local viewMode = "status"
local lastSave = os.clock()

local function saveAll()
  configMod.save(cfg)
  storage.write(TURTLES_PATH, turtles)
  storage.write(JOBS_PATH, jobs)
  storage.write(MAP_PATH, worldMap)
  lastSave = os.clock()
end

local function sortedIds()
  local ids = {}
  for id in pairs(turtles) do ids[#ids + 1] = id end
  table.sort(ids, function(a, b) return (tonumber(a) or 0) < (tonumber(b) or 0) end)
  return ids
end

local function nextTurtleId()
  local n = 1
  while turtles[tostring(n)] do n = n + 1 end
  return n
end

local function activeTurtleCount()
  local count = 0
  for _, t in pairs(turtles) do
    if t.last_seen and os.clock() - t.last_seen <= (cfg.turtle_status_timeout or 25) then count = count + 1 end
  end
  return count
end

local function jobCountByStatus(status)
  local count = 0
  for _, job in pairs(jobs) do
    if job.status == status then count = count + 1 end
  end
  return count
end

local function promptStation(title, existing)
  util.clear(term)
  local pos = util.promptPos(title .. " stand position", existing)
  local heading = util.readHeading("Facing chest/input? 0=N 1=E 2=S 3=W", existing and existing.heading or 0)
  write("Interact side front/up/down [" .. tostring(existing and existing.side or "front") .. "]: ")
  local side = read()
  if side == "" then side = existing and existing.side or "front" end
  if side ~= "up" and side ~= "down" then side = "front" end
  pos.heading = heading
  pos.side = side
  return pos
end

local function promptMining()
  util.clear(term)
  print("Mining configuration")
  cfg.area = cfg.area or {}
  cfg.area.start = util.promptPos("Mining start position", cfg.area.start)
  cfg.area.heading = util.readHeading("Tunnel heading? 0=N 1=E 2=S 3=W", cfg.area.heading or 1)
  cfg.branch_length = util.readNumber("Branch length [" .. tostring(cfg.branch_length or 48) .. "]: ",
    cfg.branch_length or 48)
  cfg.branch_spacing = util.readNumber("Lane spacing [" .. tostring(cfg.branch_spacing or 3) .. "]: ",
    cfg.branch_spacing or 3)
  cfg.tunnel_height = util.readNumber("Tunnel height [" .. tostring(cfg.tunnel_height or 2) .. "]: ",
    cfg.tunnel_height or 2)
  cfg.max_jobs = util.readNumber("Max jobs [" .. tostring(cfg.max_jobs or 500) .. "]: ", cfg.max_jobs or 500)
  write("Reset lane counter? y/N: ")
  local reset = read()
  if reset == "y" or reset == "Y" then
    cfg.next_lane = 0
    cfg.next_job_number = 1
  end
  saveAll()
end

local function showAddTurtle()
  util.clear(term)
  print("Add a new turtle")
  print("")
  print("1. Give turtle a wireless modem and fuel.")
  print("2. Copy the minenet folder onto it.")
  print("3. Run these commands on the turtle:")
  print("")
  print("delete /minenet")
  print("copy disk/minenet /minenet")
  print("cd /minenet")
  print("turtle.lua")
  print("")
  print("First run asks for heading: 0=N 1=E 2=S 3=W")
  print("Then it auto-registers and receives a color/id.")
  print("")
  print("Press enter to return.")
  read()
end

local function cleanReservations()
  local now = os.clock()
  for key, res in pairs(reservations) do
    if not res.expire or res.expire < now then reservations[key] = nil end
  end
end

local function releaseReservationsFor(turtleId)
  for key, res in pairs(reservations) do
    if res.turtle_id == turtleId then reservations[key] = nil end
  end
end

local function isOccupiedByOther(turtleId, pos)
  if not pos then return false end
  local key = util.posKey(pos)
  for id, t in pairs(turtles) do
    if tonumber(id) ~= turtleId and t.pos and util.posKey(t.pos) == key then
      local live = not t.last_seen or os.clock() - t.last_seen <= (cfg.turtle_status_timeout or 25)
      if live then return true end
    end
  end
  return false
end

local function reservationConflict(turtleId, from, to)
  cleanReservations()
  local toKey = util.posKey(to)
  local fromKey = util.posKey(from)
  local existing = reservations[toKey]
  if existing and existing.turtle_id ~= turtleId then return true, "reserved" end
  for _, res in pairs(reservations) do
    if res.turtle_id ~= turtleId and res.from == toKey and res.to == fromKey then return true, "head_on" end
  end
  return false, nil
end

local function registerTurtle(sender, msg)
  local p = msg.payload or {}
  local existing = nil
  if p.turtle_id and turtles[tostring(p.turtle_id)] then existing = tonumber(p.turtle_id) end
  if not existing then
    for id, t in pairs(turtles) do
      if t.computer_id == p.computer_id then existing = tonumber(id) end
    end
  end

  local id = existing or nextTurtleId()
  local key = tostring(id)
  turtles[key] = turtles[key] or {}
  local t = turtles[key]
  t.computer_id = p.computer_id
  t.rednet_id = sender
  t.label = p.label or t.label or ("Turtle-" .. tostring(id))
  t.color = t.color or util.colorList[((id - 1) % #util.colorList) + 1]
  t.pos = p.pos or t.pos
  t.heading = p.heading or t.heading
  t.status = "registered"
  t.alert = nil
  t.last_seen = os.clock()

  protocol.send(sender, protocol.NAME_CONTROL, "registered", id, {
    turtle_id = id,
    color = t.color,
    token = cfg.token,
    base = cfg.base,
    dropoff = cfg.dropoff,
    fuel = cfg.fuel,
    area = cfg.area,
    branch_length = cfg.branch_length,
    branch_spacing = cfg.branch_spacing,
    tunnel_height = cfg.tunnel_height
  }, cfg.token)
  saveAll()
end

local function updateTurtle(id, sender, payload)
  local key = tostring(id)
  turtles[key] = turtles[key] or {}
  local t = turtles[key]
  t.rednet_id = sender or t.rednet_id
  t.last_seen = os.clock()
  t.status = payload.status or t.status or "online"
  t.alert = payload.alert
  t.pos = payload.pos or t.pos
  t.heading = payload.heading or (payload.pos and payload.pos.heading) or t.heading
  t.fuel = payload.fuel or t.fuel
  t.fuel_items = payload.fuel_items or t.fuel_items
  t.fuel_slots = payload.fuel_slots or t.fuel_slots
  t.inventory = payload.inventory or t.inventory
  t.free_slots = payload.free_slots or t.free_slots
  t.job = payload.job_id or t.job
  t.paused = payload.paused
  t.recall = payload.recall
end

local function laneOffset(lane)
  lane = lane or 0
  if lane == 0 then return 0 end
  local magnitude = math.floor((lane + 1) / 2)
  if lane % 2 == 1 then return magnitude end
  return -magnitude
end

local function createJob(turtleId)
  if not cfg.area or not cfg.area.start then return nil, "missing_mining_start" end
  if cfg.max_jobs and (cfg.next_job_number or 1) > cfg.max_jobs then return nil, "max_jobs_reached" end

  local jobNumber = cfg.next_job_number or 1
  cfg.next_job_number = jobNumber + 1
  local lane = cfg.next_lane or 0
  cfg.next_lane = lane + 1

  local heading = util.normHeading(cfg.area.heading or 1)
  local offset = laneOffset(lane) * (cfg.branch_spacing or 3)
  local sideDir = util.dirForHeading((heading + 1) % 4)
  local start = {
    x = cfg.area.start.x + sideDir.x * offset,
    y = cfg.area.start.y,
    z = cfg.area.start.z + sideDir.z * offset
  }

  local id = "job-" .. tostring(jobNumber)
  local job = {
    id = id,
    type = "branch",
    lane = lane,
    offset = offset,
    start = start,
    heading = heading,
    length = cfg.branch_length or 48,
    height = cfg.tunnel_height or 2,
    assigned = turtleId,
    status = "assigned",
    created = os.epoch and os.epoch("utc") or os.clock()
  }
  jobs[id] = job
  return job
end

local function canAssignJob(t)
  if not t then return false end
  if t.job then return false end
  local s = t.status or ""
  if s == "out_of_fuel" or s == "fuel_station_empty" or s == "inventory_full" then return false end
  if s == "mining" or s == "moving" or s == "returning" or s == "unloading" or s == "refueling" or s == "to_fuel" then return false end
  return true
end

local function assignJobIfPossible(id)
  if not cfg.mining_enabled or cfg.paused then return false end
  local key = tostring(id)
  local t = turtles[key]
  if not canAssignJob(t) then return false end
  if not t.rednet_id then return false end
  local job, reason = createJob(tonumber(id))
  if not job then
    t.alert = reason
    return false
  end
  t.job = job.id
  t.status = "assigned"
  protocol.send(t.rednet_id, protocol.NAME_CONTROL, "job_assign", tonumber(id), job, cfg.token)
  saveAll()
  return true
end

local function assignJobsToIdle()
  for _, id in ipairs(sortedIds()) do assignJobIfPossible(tonumber(id)) end
end

local function sendAll(messageType, payload)
  for id, t in pairs(turtles) do
    if t.rednet_id then protocol.send(t.rednet_id, protocol.NAME_CONTROL, messageType, tonumber(id), payload or {},
        cfg.token) end
  end
end

local function sendConfigUpdate()
  sendAll("config_update", {
    base = cfg.base,
    dropoff = cfg.dropoff,
    fuel = cfg.fuel,
    area = cfg.area,
    branch_length = cfg.branch_length,
    branch_spacing = cfg.branch_spacing,
    tunnel_height = cfg.tunnel_height,
    inventory_return_ratio = cfg.inventory_return_ratio,
    fuel_min = cfg.fuel_min,
    fuel_margin = cfg.fuel_margin,
    fuel_target = cfg.fuel_target,
    keep_fuel_on_unload = cfg.keep_fuel_on_unload
  })
end

local function mergeMap(turtleId, blocks)
  if type(blocks) ~= "table" then return end
  for _, block in pairs(blocks) do
    if type(block) == "table" and block.pos then
      local key = util.posKey(block.pos)
      worldMap[key] = {
        state = block.state or "seen",
        name = block.name,
        turtle_id = turtleId,
        updated = os.clock()
      }
    end
  end
end

local function handleMessage(sender, msg, proto)
  if type(msg) ~= "table" then return end
  if msg.type == "hello" then
    if cfg.accept_new_turtles then registerTurtle(sender, msg) end
    return
  end
  if not protocol.valid(msg, cfg.token, false) then return end

  local id = tonumber(msg.turtle_id)
  if not id then return end
  local payload = msg.payload or {}

  if msg.type == "heartbeat" or msg.type == "status" or msg.type == "need_job" then
    updateTurtle(id, sender, payload)
    if msg.type == "need_job" then assignJobIfPossible(id) end
  elseif msg.type == "reserve_move" then
    updateTurtle(id, sender, { pos = payload.from })
    local conflict, reason = reservationConflict(id, payload.from, payload.to)
    if payload.to and not conflict and not isOccupiedByOther(id, payload.to) then
      reservations[util.posKey(payload.to)] = {
        turtle_id = id,
        from = util.posKey(payload.from),
        to = util.posKey(payload.to),
        expire = os.clock() + (cfg.reservation_seconds or 4)
      }
      protocol.send(sender, protocol.NAME_ROUTE, "reserve_ok", id, { to = payload.to }, cfg.token)
    else
      protocol.send(sender, protocol.NAME_ROUTE, "reserve_denied", id, { reason = reason or "occupied" }, cfg.token)
    end
  elseif msg.type == "move_result" then
    updateTurtle(id, sender, payload)
    releaseReservationsFor(id)
    if payload.pos then worldMap[util.posKey(payload.pos)] = { state = "air", turtle_id = id, updated = os.clock() } end
  elseif msg.type == "map_update" then
    updateTurtle(id, sender, {})
    mergeMap(id, payload.blocks)
  elseif msg.type == "job_done" then
    updateTurtle(id, sender, payload)
    local job = jobs[payload.job_id]
    if job then
      job.status = "done"; job.finished = os.epoch and os.epoch("utc") or os.clock()
    end
    turtles[tostring(id)].job = nil
    turtles[tostring(id)].status = "idle"
    assignJobIfPossible(id)
  elseif msg.type == "job_failed" then
    updateTurtle(id, sender, payload)
    local job = jobs[payload.job_id]
    if job then
      job.status = "failed"; job.reason = payload.reason
    end
    turtles[tostring(id)].job = nil
  end
end

local function networkLoop()
  while running do
    local sender, msg, proto = rednet.receive(nil, 0.25)
    if sender then handleMessage(sender, msg, proto) end
    cleanReservations()
    if os.clock() - lastSave > 10 then saveAll() end
  end
end

local function short(text, len)
  text = tostring(text or "")
  if #text <= len then return text end
  return string.sub(text, 1, len - 1) .. "~"
end

local function drawDashboard(target, compact)
  target = target or term
  local w, h = target.getSize()
  util.clear(target)
  target.setCursorPos(1, 1)
  target.setTextColor(colors.cyan)
  target.write(VERSION)
  target.setTextColor(colors.white)
  target.write("  ")
  target.setTextColor(cfg.mining_enabled and colors.lime or colors.red)
  target.write(cfg.mining_enabled and "MINING ON" or "MINING OFF")
  target.setTextColor(colors.white)
  target.write("  ")
  target.setTextColor(cfg.paused and colors.yellow or colors.white)
  target.write(cfg.paused and "PAUSED" or "LIVE")

  target.setCursorPos(1, 2)
  target.setTextColor(colors.white)
  target.write("Turtles " .. tostring(activeTurtleCount()) .. "/" .. tostring(#sortedIds()))
  target.write("  Jobs A:" ..
  tostring(jobCountByStatus("assigned")) ..
  " D:" .. tostring(jobCountByStatus("done")) .. " F:" .. tostring(jobCountByStatus("failed")))

  target.setCursorPos(1, 3)
  target.setTextColor(colors.gray or colors.grey)
  local mine = cfg.area and cfg.area.start and
  (util.formatPos(cfg.area.start) .. " " .. util.headingName(cfg.area.heading)) or "unset"
  target.write(short(
  "Drop " .. util.formatPos(cfg.dropoff) .. "  Fuel " .. util.formatPos(cfg.fuel) .. "  Mine " .. mine, w))

  target.setCursorPos(1, 5)
  target.setTextColor(colors.white)
  target.write(short("ID  Status          Fuel   F# Inv Pos              Job      Alert", w))
  target.setCursorPos(1, 6)
  target.write(string.rep("-", math.min(w, 70)))

  local row = 7
  for _, id in ipairs(sortedIds()) do
    if row > h - (compact and 0 or 2) then break end
    local t = turtles[id]
    local displayStatus = t.status or "unknown"
    if t.last_seen and os.clock() - t.last_seen > (cfg.turtle_status_timeout or 25) then displayStatus = "offline" end
    target.setCursorPos(1, row)
    target.setTextColor(util.statusColor(displayStatus))
    local inv = math.floor((t.inventory or 0) * 100)
    local pos = t.pos and util.formatPos(t.pos) or "?"
    local line = string.format("%2s  %-14s %-6s %-2s %3d%% %-16s %-8s %s",
      id,
      short(displayStatus, 14),
      short(tostring(t.fuel or "?"), 6),
      short(tostring(t.fuel_items or 0), 2),
      inv,
      short(pos, 16),
      short(t.job or "-", 8),
      short(t.alert or "", math.max(1, w - 58))
    )
    target.write(short(line, w))
    row = row + 1
  end

  if not compact then
    target.setTextColor(colors.yellow)
    target.setCursorPos(1, h - 1)
    target.write(short("1 Base  2 Drop  3 Fuel  4 Mine config  G Start/Stop  P Pause  R Recall", w))
    target.setCursorPos(1, h)
    target.write(short("5 Add turtle  V Map/List  [ ] Y-layer  S Save  Q Quit", w))
  end
  target.setTextColor(colors.white)
end

local function mapCenter()
  if cfg.area and cfg.area.start then return cfg.area.start end
  for _, t in pairs(turtles) do if t.pos then return t.pos end end
  return { x = 0, y = 0, z = 0 }
end

local function drawMap(target)
  target = target or term
  local w, h = target.getSize()
  util.clear(target)
  local center = mapCenter()
  local layerY = cfg.monitor.map_y or center.y
  target.setTextColor(colors.cyan)
  target.setCursorPos(1, 1)
  target.write("MineNet map  Y=" .. tostring(layerY) .. "  center " .. util.formatPos(center))
  target.setTextColor(colors.gray or colors.grey)
  target.setCursorPos(1, 2)
  target.write(".=tunnel  T=turtle  V=list  [ ] layer")

  local mapTop = 4
  local mapHeight = h - 5
  local halfW = math.floor(w / 2)
  local halfH = math.floor(mapHeight / 2)

  local turtleAt = {}
  for id, t in pairs(turtles) do
    if t.pos and t.pos.y == layerY then turtleAt[util.posKey(t.pos)] = { id = id, color = t.color or colors.white } end
  end

  for sy = 0, mapHeight - 1 do
    target.setCursorPos(1, mapTop + sy)
    local z = center.z + sy - halfH
    for sx = 0, w - 1 do
      local x = center.x + sx - halfW
      local key = tostring(x) .. "," .. tostring(layerY) .. "," .. tostring(z)
      local turtleInfo = turtleAt[key]
      if turtleInfo then
        target.setTextColor(turtleInfo.color)
        target.write("T")
      elseif worldMap[key] and worldMap[key].state == "air" then
        target.setTextColor(colors.gray or colors.grey)
        target.write(".")
      else
        target.setTextColor(colors.black)
        target.write(" ")
      end
    end
  end
  target.setTextColor(colors.white)
end

local function redrawMain()
  if viewMode == "map" then drawMap(term) else drawDashboard(term, false) end
end

local function confirmQuit()
  util.clear(term)
  write("Quit MineNet server? y/N: ")
  local a = read()
  return a == "y" or a == "Y"
end

local function handleKey(char)
  if char == "1" then
    cfg.base = util.promptPos("Base/home position", cfg.base)
    saveAll(); sendConfigUpdate()
  elseif char == "2" then
    cfg.dropoff = promptStation("Drop-off", cfg.dropoff)
    saveAll(); sendConfigUpdate()
  elseif char == "3" then
    cfg.fuel = promptStation("Fuel station", cfg.fuel)
    saveAll(); sendConfigUpdate()
  elseif char == "4" then
    promptMining()
    sendConfigUpdate()
  elseif char == "5" then
    showAddTurtle()
  elseif char == "g" or char == "G" then
    cfg.mining_enabled = not cfg.mining_enabled
    saveAll()
    if cfg.mining_enabled then assignJobsToIdle() end
  elseif char == "p" or char == "P" then
    cfg.paused = not cfg.paused
    saveAll()
    sendAll(cfg.paused and "pause" or "resume", {})
  elseif char == "r" or char == "R" then
    cfg.paused = true
    saveAll()
    sendAll("recall", { home = cfg.dropoff or cfg.base })
  elseif char == "v" or char == "V" then
    if viewMode == "map" then viewMode = "status" else viewMode = "map" end
  elseif char == "[" then
    cfg.monitor.map_y = (cfg.monitor.map_y or mapCenter().y) - 1
    saveAll()
  elseif char == "]" then
    cfg.monitor.map_y = (cfg.monitor.map_y or mapCenter().y) + 1
    saveAll()
  elseif char == "s" or char == "S" then
    saveAll()
  elseif char == "q" or char == "Q" then
    if confirmQuit() then running = false end
  end
end

local function uiLoop()
  local timer = os.startTimer(0.5)
  redrawMain()
  while running do
    local event, a = os.pullEvent()
    if event == "timer" and a == timer then
      redrawMain()
      timer = os.startTimer(0.5)
    elseif event == "char" then
      handleKey(a)
      redrawMain()
      timer = os.startTimer(0.5)
    end
  end
end

local function monitorLoop()
  while running do
    local mon = util.firstPeripheral("monitor")
    if mon then
      pcall(function() mon.setTextScale(0.5) end)
      drawDashboard(mon, true)
    end
    sleep(2)
  end
end

local ok, side = protocol.openModem()
if not ok then
  print("MineNet server error: " .. tostring(side)); return
end
rednet.host(protocol.NAME_DISCOVERY, "minenet-server")
print("MineNet server started on modem " .. tostring(side))
sleep(0.5)

parallel.waitForAny(networkLoop, monitorLoop, uiLoop)
saveAll()
util.clear(term)
print("MineNet server stopped. Data saved.")
