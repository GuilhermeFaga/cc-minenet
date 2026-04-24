local protocol = require("minenet.protocol")
local storage = require("minenet.storage")
local util = require("minenet.util")
local nav = require("minenet.nav")

local DATA = "/minenet/data"
local ID_PATH = DATA.."/identity.json"
local STATE_PATH = DATA.."/state.json"
storage.ensureDir(DATA)

local identity = storage.read(ID_PATH, {})
local state = storage.read(STATE_PATH, {status="boot", job=nil, paused=false})
local serverId = identity.server
local cfg = identity.config or {token="change-me", inventoryFullRatio=0.85, fuelSafetyMargin=100}
local token = cfg.token or "change-me"

local function save() storage.write(ID_PATH, identity); storage.write(STATE_PATH, state) end
local function statusPayload(status)
  return {status=status or state.status, pos=nav.pos or util.gpsPos(1), fuel=turtle.getFuelLevel(), inv=util.inventoryRatio(), job_id=state.job and state.job.id or nil}
end
local function send(kind, payload, channel)
  if serverId then protocol.send(serverId, kind, payload or statusPayload(), token, identity.turtle_id, channel or protocol.STATUS) end
end
local function open()
  protocol.openRednet(cfg.modemSide)
end
local function locateServer()
  if serverId then return serverId end
  local ids = {rednet.lookup(protocol.DISCOVERY, protocol.HOSTNAME)}
  if #ids > 0 then serverId = ids[1]; return serverId end
  protocol.broadcast("hello", {label=os.getComputerLabel(), computer_id=os.getComputerID(), pos=util.gpsPos(3)}, token, nil, protocol.DISCOVERY)
  local deadline = os.clock() + 8
  while os.clock() < deadline do
    local id,msg = rednet.receive(protocol.CONTROL, 2)
    if id and msg and msg.type == "registered" then serverId = id; return serverId,msg end
  end
end
local function register()
  open()
  local id,msg = locateServer()
  if not id then error("No MineNet server found. Start server and check modem range/token.") end
  if msg and msg.type == "registered" then
    identity.server = id; identity.turtle_id = msg.payload.turtle_id; identity.name = msg.payload.name; identity.color = msg.payload.color; identity.config = msg.payload.config; cfg = identity.config; token = cfg.token
    if identity.name then os.setComputerLabel(identity.name) end
    save()
  elseif not identity.turtle_id then
    protocol.broadcast("hello", {label=os.getComputerLabel(), computer_id=os.getComputerID(), pos=util.gpsPos(3)}, token, nil, protocol.DISCOVERY)
  end
  nav.init(serverId, token, identity.turtle_id)
end
local function unload()
  if not cfg.dropoff then return false,"dropoff unset" end
  state.status="unload"; send("status"); save()
  nav.goto(cfg.dropoff)
  for i=1,16 do
    turtle.select(i)
    local detail = turtle.getItemDetail(i)
    if detail and not (cfg.keepItems and cfg.keepItems[detail.name]) then turtle.drop() end
  end
  turtle.select(1)
  return true
end
local function refuel()
  if turtle.getFuelLevel() == "unlimited" then return true end
  if not cfg.fuel then return false,"fuel point unset" end
  state.status="refuel"; send("status"); save()
  nav.goto(cfg.fuel)
  for i=1,16 do
    turtle.select(i)
    if turtle.refuel(0) then turtle.refuel() end
  end
  -- Try to pull fuel from chest in front, then refuel.
  for i=1,16 do
    if turtle.getItemCount(i) == 0 then turtle.select(i); turtle.suck(16); if turtle.refuel(0) then turtle.refuel() end end
  end
  turtle.select(1)
  return true
end
local function needUnload()
  return util.inventoryRatio() >= (cfg.inventoryFullRatio or 0.85) or util.firstFreeSlot() == nil
end
local function needFuel(extra)
  local f = turtle.getFuelLevel()
  if f == "unlimited" then return false end
  if not nav.pos then return f < (cfg.fuelSafetyMargin or 100) end
  local d = 0
  if cfg.fuel then d = util.dist(nav.pos, cfg.fuel) end
  return f < d + (extra or 0) + (cfg.fuelSafetyMargin or 100)
end
local function inspectMap()
  local blocks = {}
  local function add(p, ok, data)
    if ok and data then blocks[util.key(p)] = {state="solid", block=data.name, updated=protocol.now()} else blocks[util.key(p)] = {state="air", updated=protocol.now()} end
  end
  if not nav.pos then return end
  local dirs = {{h=nav.heading,p={x=nav.pos.x,y=nav.pos.y,z=nav.pos.z}}}
  local ok,data = turtle.inspect(); local d={{x=0,z=-1},{x=1,z=0},{x=0,z=1},{x=-1,z=0}}[nav.heading+1]; add({x=nav.pos.x+d.x,y=nav.pos.y,z=nav.pos.z+d.z}, ok, data)
  ok,data = turtle.inspectUp(); add({x=nav.pos.x,y=nav.pos.y+1,z=nav.pos.z}, ok, data)
  ok,data = turtle.inspectDown(); add({x=nav.pos.x,y=nav.pos.y-1,z=nav.pos.z}, ok, data)
  send("map_update", {blocks=blocks}, protocol.MAP)
end
local function faceDirection(dir)
  local h = ({north=0,east=1,south=2,west=3})[dir] or 1
  nav.turnTo(h)
end
local function mineBranch(job)
  nav.goto(job.start)
  faceDirection(job.direction or "east")
  for i=1,(job.length or 32) do
    if state.paused then return false,"paused" end
    if needUnload() then local resume=util.copy(nav.pos); unload(); refuel(); nav.goto(resume); faceDirection(job.direction or "east") end
    if needFuel(job.length - i) then local resume=util.copy(nav.pos); refuel(); nav.goto(resume); faceDirection(job.direction or "east") end
    state.status="mining"; send("status"); inspectMap()
    while turtle.detectUp() do turtle.digUp(); sleep(0.1) end
    nav.forwardDig()
    if (job.height or 2) > 1 then turtle.digUp() end
    storage.write(STATE_PATH, state)
  end
  return true
end
local function doJob(job)
  state.job = job; state.status="job"; save(); send("job_ack", {job_id=job.id})
  local ok, err = false, "unknown job"
  if job.type == "mine_branch" then ok, err = mineBranch(job) end
  if ok then send("job_done", {job_id=job.id, pos=nav.pos}); state.job=nil; state.status="idle"; save() else state.status="error:"..tostring(err); save(); send("error", {error=err, job_id=job.id}) end
end
local function heartbeatLoop()
  while true do
    nav.pos = nav.pos or util.gpsPos(1)
    send("heartbeat", statusPayload())
    sleep(3)
  end
end
local function commandLoop()
  while true do
    local id,msg,proto = rednet.receive(nil, 1)
    if id == serverId and protocol.valid(msg, token) then
      if msg.type == "job_assign" and msg.payload and msg.payload.job and not state.job then doJob(msg.payload.job)
      elseif msg.type == "pause" then state.paused=true; state.status="paused"; save()
      elseif msg.type == "resume" then state.paused=false; state.status="idle"; save()
      elseif msg.type == "recall" then state.paused=true; state.status="recall"; save(); if cfg.base then nav.goto(cfg.base) elseif cfg.dropoff then nav.goto(cfg.dropoff) end
      elseif msg.type == "registered" then identity.turtle_id=msg.payload.turtle_id; identity.config=msg.payload.config; cfg=identity.config; token=cfg.token; save()
      end
    end
  end
end
local function main()
  register()
  state.status="idle"; save()
  parallel.waitForAny(heartbeatLoop, commandLoop)
end
main()
