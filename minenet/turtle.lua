package.path = package.path .. ";/minenet/?.lua;./?.lua"

local protocol = require("protocol")
local storage = require("storage")
local configMod = require("config")
local util = require("util")
local nav = require("nav")

local cfg = configMod.load()
local identityPath = "/minenet/data/identity.json"
local identity = storage.read(identityPath, {})
local running = true
local currentJob = nil
local serverId = identity.server_id
local status = "booting"

local function saveIdentity() storage.write(identityPath, identity) end

local function posPayload()
  if not nav.pos then nav.syncGps(2) end
  return nav.pos
end

local function inventoryRatio()
  return util.inventoryRatio()
end

local function send(t, payload)
  if not serverId then return false end
  return protocol.send(serverId, protocol.NAME_STATUS, t, identity.turtle_id, payload or {}, cfg.token)
end

local function heartbeatLoop()
  while running do
    send("heartbeat", {status=status, pos=posPayload(), fuel=turtle.getFuelLevel(), inventory=inventoryRatio()})
    sleep(3)
  end
end

local function discoverServer()
  local ok, side = protocol.openModem()
  if not ok then error("No modem found") end
  local found = rednet.lookup(protocol.NAME_DISCOVERY, "minenet-server")
  if found then serverId = found; identity.server_id = found; saveIdentity(); return true end
  print("Searching for MineNet server...")
  protocol.broadcast(protocol.NAME_DISCOVERY, "hello", nil, {
    computer_id=os.getComputerID(), label=os.getComputerLabel(), pos=posPayload()
  }, cfg.token)
  local start = os.clock()
  while os.clock() - start < 10 do
    local id, msg = protocol.receive(protocol.NAME_CONTROL, 2, nil)
    if id and msg and msg.type == "registered" then
      serverId = id
      identity.server_id = id
      identity.turtle_id = msg.payload.turtle_id or msg.turtle_id
      identity.color = msg.payload.color
      cfg.token = msg.payload.token or cfg.token
      cfg.dropoff = msg.payload.dropoff or cfg.dropoff
      cfg.fuel = msg.payload.fuel or cfg.fuel
      cfg.base = msg.payload.base or cfg.base
      configMod.save(cfg)
      saveIdentity()
      nav.setServer(serverId, cfg.token, identity.turtle_id)
      return true
    end
  end
  return false
end

local function register()
  protocol.send(serverId, protocol.NAME_DISCOVERY, "hello", nil, {
    computer_id=os.getComputerID(), label=os.getComputerLabel(), pos=posPayload()
  }, cfg.token)
end

local function unload()
  if not cfg.dropoff then return false end
  status = "unloading"
  nav.goto(cfg.dropoff)
  for i=1,16 do
    turtle.select(i)
    if turtle.getItemCount(i) > 0 then turtle.drop() end
  end
  turtle.select(1)
  send("status", {status=status, pos=nav.pos, fuel=turtle.getFuelLevel(), inventory=inventoryRatio()})
  return true
end

local function refuel()
  if not cfg.fuel then return false end
  status = "refueling"
  nav.goto(cfg.fuel)
  for i=1,16 do
    turtle.select(i)
    if turtle.getItemCount(i) > 0 then turtle.refuel() end
  end
  turtle.select(1)
  send("status", {status=status, pos=nav.pos, fuel=turtle.getFuelLevel(), inventory=inventoryRatio()})
  return true
end

local function ensureSupplies()
  if inventoryRatio() >= (cfg.inventory_return_ratio or 0.85) then
    send("need_unload", {pos=nav.pos})
    unload()
  end
  local fuel = turtle.getFuelLevel()
  if fuel ~= "unlimited" and fuel < (cfg.fuel_margin or 100) then
    send("need_fuel", {pos=nav.pos})
    refuel()
  end
end

local function digColumn(height)
  for h=1,height do
    if turtle.detectUp() then turtle.digUp() end
    if h < height then nav.up() end
  end
  for h=1,height-1 do nav.down() end
end

local function mineBranch(job)
  currentJob = job
  status = "moving"
  if job.start then nav.goto(job.start) end
  nav.face(job.heading or 1)
  status = "mining"
  local length = job.length or 32
  local height = job.height or 2
  for i=1,length do
    ensureSupplies()
    digColumn(height)
    nav.digForward()
    local ok = nav.forward()
    if not ok then sleep(0.5); nav.digForward(); nav.forward() end
    send("status", {status=status, pos=nav.pos, fuel=turtle.getFuelLevel(), inventory=inventoryRatio()})
  end
  status = "returning"
  if cfg.dropoff then unload() end
  send("job_done", {job_id=job.id, pos=nav.pos})
  currentJob = nil
  status = "idle"
end

local function commandLoop()
  while running do
    local id, msg = protocol.receive(protocol.NAME_CONTROL, 1, cfg.token)
    if id == serverId and msg then
      if msg.type == "job_assign" then
        mineBranch(msg.payload or {})
      elseif msg.type == "go_unload" then
        unload()
      elseif msg.type == "go_fuel" then
        refuel()
      elseif msg.type == "shutdown" then
        running = false
      end
    end
  end
end

term.clear(); term.setCursorPos(1,1)
print("MineNet turtle starting")
local ok, err = nav.syncGps(5)
if not ok then print("Warning: "..tostring(err)) end
if not discoverServer() then error("Could not find/register with server") end
if not identity.turtle_id then register() end
nav.setServer(serverId, cfg.token, identity.turtle_id)
status = "idle"
print("Registered as turtle "..tostring(identity.turtle_id))
parallel.waitForAny(heartbeatLoop, commandLoop)
