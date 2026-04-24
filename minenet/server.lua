local protocol = require("minenet.protocol")
local storage = require("minenet.storage")
local configMod = require("minenet.config")
local util = require("minenet.util")

local DATA = "/minenet/data"
local TURTLES = DATA.."/turtles.json"
local JOBS = DATA.."/jobs.json"
local MAP = DATA.."/map.json"

storage.ensureDir(DATA)
local cfg = configMod.load()
local turtles = storage.read(TURTLES, {})
local jobs = storage.read(JOBS, {queue={}, active={}, completed={}})
local world = storage.read(MAP, {blocks={}, tunnels={}, reservations={}})
local nextId = storage.read(DATA.."/next_id.json", {value=1})

local function saveAll()
  storage.write(TURTLES, turtles)
  storage.write(JOBS, jobs)
  storage.write(MAP, world)
  storage.write(DATA.."/next_id.json", nextId)
  configMod.save(cfg)
end

local function clear() term.clear(); term.setCursorPos(1,1) end
local function readPos(prompt)
  print(prompt .. " (uses GPS if blank, or x y z):")
  write("> ")
  local line = read()
  if line == "" then
    local p = util.gpsPos(5)
    if not p then print("GPS locate failed."); sleep(1); return nil end
    return p
  end
  local x,y,z = line:match("^%s*(-?%d+)%s+(-?%d+)%s+(-?%d+)%s*$")
  if not x then print("Invalid position."); sleep(1); return nil end
  return {x=tonumber(x), y=tonumber(y), z=tonumber(z)}
end

local function addBranchJobs()
  if not cfg.mining.min or not cfg.mining.max then return false, "Set mining area first." end
  local min, max = cfg.mining.min, cfg.mining.max
  local spacing = cfg.mining.tunnelSpacing or 3
  local len = cfg.mining.branchLength or 48
  local y = min.y
  for z=min.z,max.z,spacing do
    table.insert(jobs.queue, {
      id = "job-"..protocol.now().."-"..z,
      type = "mine_branch",
      start = {x=min.x, y=y, z=z},
      direction = "east",
      length = math.min(len, max.x-min.x+1),
      height = cfg.mining.branchHeight or 2,
      state = "queued",
    })
  end
  saveAll()
  return true
end

local function assignJob(tid)
  if #jobs.queue == 0 then return nil end
  local job = table.remove(jobs.queue, 1)
  job.state = "active"; job.turtle_id = tid; job.assigned = protocol.now()
  jobs.active[tostring(tid)] = job
  saveAll()
  return job
end

local function getMonitor()
  for _, name in ipairs(peripheral.getNames()) do
    if peripheral.getType(name) == "monitor" then return peripheral.wrap(name) end
  end
end

local function drawStatus(target)
  local old = term.redirect(target or term.current())
  term.clear(); term.setCursorPos(1,1)
  print("MineNet Manager  ID #"..os.getComputerID())
  print("Queue:"..#jobs.queue.." Active:"..(function() local n=0 for _ in pairs(jobs.active) do n=n+1 end return n end)())
  print("Drop:"..(cfg.dropoff and util.key(cfg.dropoff) or "unset").." Fuel:"..(cfg.fuel and util.key(cfg.fuel) or "unset"))
  print(string.rep("-", 50))
  print("ID Name       Status     Fuel Inv  Position")
  for id, t in pairs(turtles) do
    local age = math.floor((protocol.now() - (t.last or 0))/1000)
    local stale = age > (cfg.heartbeatTimeout or 30)
    local pos = t.pos and util.key(t.pos) or "?"
    print(string.format("%2s %-10s %-9s %5s %3s%% %s%s", id, t.name or "?", stale and "offline" or (t.status or "idle"), tostring(t.fuel or "?"), tostring(math.floor((t.inv or 0)*100)), pos, stale and " !" or ""))
  end
  term.redirect(old)
end

local function drawMap(target)
  local old = term.redirect(target or term.current())
  term.clear(); term.setCursorPos(1,1)
  print("MineNet live map (top-down)")
  local minx,maxx,minz,maxz = 999999,-999999,999999,-999999
  for _, t in pairs(turtles) do if t.pos then minx=math.min(minx,t.pos.x); maxx=math.max(maxx,t.pos.x); minz=math.min(minz,t.pos.z); maxz=math.max(maxz,t.pos.z) end end
  if minx == 999999 then print("No turtle positions yet."); term.redirect(old); return end
  minx,maxx,minz,maxz = minx-5,maxx+5,minz-5,maxz+5
  local w,h = term.getSize()
  local lookup = {}; for id,t in pairs(turtles) do if t.pos then lookup[t.pos.x..","..t.pos.z] = tostring(id):sub(-1) end end
  for z=minz, math.min(maxz, minz+h-4) do
    local line = ""
    for x=minx, math.min(maxx, minx+w-1) do line = line .. (lookup[x..","..z] or ".") end
    print(line)
  end
  term.redirect(old)
end

local function handleMessage(sender, msg, proto)
  if not protocol.valid(msg, cfg.token) then return end
  local p = msg.payload or {}
  if msg.type == "hello" then
    local existing
    for id,t in pairs(turtles) do if t.computer_id == sender then existing = id end end
    local tid = existing or tostring(nextId.value)
    if not existing then nextId.value = nextId.value + 1 end
    turtles[tid] = turtles[tid] or {}
    local t = turtles[tid]
    t.computer_id = sender; t.name = p.label or ("Turtle-"..tid); t.color = t.color or util.colorFor(tonumber(tid)); t.status = "registered"; t.last = protocol.now(); t.pos = p.pos
    protocol.send(sender, "registered", {turtle_id=tonumber(tid), name=t.name, color=t.color, config=cfg}, cfg.token, nil, protocol.CONTROL)
    saveAll()
  elseif msg.type == "heartbeat" or msg.type == "status" then
    local tid = tostring(msg.turtle_id or p.turtle_id or "")
    if tid ~= "" then
      turtles[tid] = turtles[tid] or {name="Turtle-"..tid, color=util.colorFor(tonumber(tid) or 1), computer_id=sender}
      local t = turtles[tid]
      t.computer_id = sender; t.last = protocol.now(); t.pos = p.pos or t.pos; t.fuel = p.fuel or t.fuel; t.inv = p.inv or t.inv; t.status = p.status or t.status; t.job_id = p.job_id or t.job_id
      if not jobs.active[tid] and #jobs.queue > 0 and t.status ~= "need_fuel" and t.status ~= "need_unload" then
        local job = assignJob(tonumber(tid)); protocol.send(sender, "job_assign", {job=job}, cfg.token, tonumber(tid), protocol.CONTROL)
      end
      saveAll()
    end
  elseif msg.type == "job_done" then
    local tid = tostring(msg.turtle_id)
    local job = jobs.active[tid]
    if job then job.state="completed"; job.completed=protocol.now(); table.insert(jobs.completed, job); jobs.active[tid]=nil end
    saveAll()
  elseif msg.type == "map_update" then
    for k,v in pairs(p.blocks or {}) do world.blocks[k] = v end
    saveAll()
  elseif msg.type == "reserve_move" then
    local to = p.to; local from = p.from; local key = to and util.key(to)
    local ok = true; local reason = nil
    if key and world.reservations[key] and world.reservations[key] ~= msg.turtle_id then ok=false; reason="reserved" end
    for id,t in pairs(turtles) do if tostring(id) ~= tostring(msg.turtle_id) and util.eq(t.pos, to) then ok=false; reason="occupied" end end
    if ok and key then world.reservations[key] = msg.turtle_id end
    protocol.send(sender, ok and "reserve_ok" or "reserve_denied", {from=from,to=to,reason=reason}, cfg.token, msg.turtle_id, protocol.ROUTE)
  elseif msg.type == "release_pos" then
    if p.pos then world.reservations[util.key(p.pos)] = nil end
  end
end

local function networkLoop()
  protocol.openRednet(cfg.modemSide)
  pcall(rednet.host, protocol.DISCOVERY, protocol.HOSTNAME)
  while true do
    local sender, msg, proto = rednet.receive(nil, 0.5)
    if sender then handleMessage(sender, msg, proto) end
  end
end

local function uiLoop()
  while true do
    clear(); drawStatus()
    print("\n1 Set dropoff  2 Set fuel  3 Set area")
    print("4 Generate branch jobs  5 Save  6 Map")
    print("7 Recall all  8 Pause all  9 Resume all")
    print("Enter refreshes. Ctrl+T exits.")
    write("> ")
    local s = read(nil, nil, function() return {"1","2","3","4","5","6","7","8","9"} end)
    if s == "1" then cfg.dropoff = readPos("Drop-off point") or cfg.dropoff; saveAll()
    elseif s == "2" then cfg.fuel = readPos("Fuel point") or cfg.fuel; saveAll()
    elseif s == "3" then cfg.mining.min = readPos("Mining min corner") or cfg.mining.min; cfg.mining.max = readPos("Mining max corner") or cfg.mining.max; saveAll()
    elseif s == "4" then local ok,err=addBranchJobs(); if not ok then print(err); sleep(1) end
    elseif s == "5" then saveAll()
    elseif s == "6" then clear(); drawMap(); print("Press enter"); read()
    elseif s == "7" or s == "8" or s == "9" then local cmd = s=="7" and "recall" or s=="8" and "pause" or "resume"; protocol.broadcast(cmd, {}, cfg.token, nil, protocol.CONTROL)
    end
  end
end

local function monitorLoop()
  while true do
    local mon = getMonitor()
    if mon then mon.setTextScale(0.5); drawStatus(mon) end
    sleep(2)
  end
end

parallel.waitForAny(networkLoop, uiLoop, monitorLoop)
