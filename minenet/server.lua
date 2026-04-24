package.path = package.path .. ";/minenet/?.lua;./?.lua"

local protocol = require("protocol")
local storage = require("storage")
local configMod = require("config")
local util = require("util")

local cfg = configMod.load()
local turtles = storage.read("/minenet/data/turtles.json", {})
local jobs = storage.read("/minenet/data/jobs.json", {})
local reservations = {}
local running = true

local function saveAll()
  storage.write("/minenet/data/turtles.json", turtles)
  storage.write("/minenet/data/jobs.json", jobs)
  configMod.save(cfg)
end

local function nextTurtleId()
  local n = 1
  while turtles[tostring(n)] do n = n + 1 end
  return n
end

local function getPos(prompt)
  print(prompt)
  print("Use GPS current position? y/n")
  local a = read()
  if a == "y" or a == "Y" then
    local x, y, z = gps.locate(5)
    if x then return { x = math.floor(x), y = math.floor(y), z = math.floor(z) } end
    print("GPS failed; enter manually.")
  end
  write("x: "); local x = tonumber(read())
  write("y: "); local y = tonumber(read())
  write("z: "); local z = tonumber(read())
  return { x = x, y = y, z = z }
end

local function drawStatus(target)
  target = target or term
  target.setBackgroundColor(colors.black)
  target.setTextColor(colors.white)
  target.clear()
  target.setCursorPos(1, 1)
  target.write("MineNet Server")
  target.setCursorPos(1, 2)
  target.write("ID Status     Fuel Inv Pos")
  local row = 3
  for id, t in pairs(turtles) do
    target.setCursorPos(1, row)
    target.setTextColor(t.color or colors.white)
    local p = t.pos and util.key(t.pos) or "?"
    local inv = math.floor((t.inventory or 0) * 100)
    target.write(string.format("%2s %-10s %4s %3d%% %s", id, t.status or "?", tostring(t.fuel or "?"), inv, p))
    row = row + 1
  end
  target.setTextColor(colors.white)
end

local function monitorLoop()
  -- Only draw to an attached monitor. Do not redraw the main terminal here,
  -- because the menu uses read() prompts. Redrawing the terminal while read()
  -- is active makes options like 4 appear to do nothing.
  while running do
    local mon = util.firstPeripheral("monitor")
    if mon then
      mon.setTextScale(0.5)
      drawStatus(mon)
    end
    sleep(2)
  end
end

local function makeJob(turtleId)
  if not cfg.area or not cfg.area.start then return nil end
  local id = "job-" .. tostring(os.epoch and os.epoch("utc") or os.clock()) .. "-" .. tostring(turtleId)
  local offset = (#jobs + turtleId - 1) * (cfg.branch_spacing or 3)
  local start = { x = cfg.area.start.x, y = cfg.area.start.y, z = cfg.area.start.z + offset }
  local job = { id = id, type = "branch", start = start, heading = cfg.area.heading or 1, length = cfg.branch_length or
  32, height = cfg.tunnel_height or 2, assigned = turtleId, status = "assigned" }
  table.insert(jobs, job)
  return job
end

local function registerTurtle(sender, msg)
  local payload = msg.payload or {}
  local existing = nil
  for id, t in pairs(turtles) do
    if t.computer_id == payload.computer_id then existing = tonumber(id) end
  end
  local id = existing or nextTurtleId()
  turtles[tostring(id)] = turtles[tostring(id)] or {}
  local t = turtles[tostring(id)]
  t.computer_id = payload.computer_id
  t.rednet_id = sender
  t.label = payload.label or ("Turtle-" .. id)
  t.color = t.color or util.colors[((id - 1) % #util.colors) + 1]
  t.pos = payload.pos
  t.status = "registered"
  t.last_seen = os.clock()
  saveAll()
  protocol.send(sender, protocol.NAME_CONTROL, "registered", id, {
    turtle_id = id, color = t.color, token = cfg.token, dropoff = cfg.dropoff, fuel = cfg.fuel, base = cfg.base
  }, cfg.token)
end

local function occupiedByOther(turtleId, to)
  local k = util.key(to)
  for id, t in pairs(turtles) do
    if tonumber(id) ~= turtleId and t.pos and util.key(t.pos) == k then return true end
  end
  return reservations[k] and reservations[k] ~= turtleId
end

local function networkLoop()
  while running do
    local sender, msg, proto = rednet.receive(0.5)
    if sender and type(msg) == "table" then
      if msg.type == "hello" then
        registerTurtle(sender, msg)
      elseif protocol.valid(msg, cfg.token) then
        local id = tostring(msg.turtle_id or "")
        local t = turtles[id]
        if t then
          t.rednet_id = sender
          t.last_seen = os.clock()
          local p = msg.payload or {}
          if msg.type == "heartbeat" or msg.type == "status" then
            t.status = p.status or t.status
            t.pos = p.pos or t.pos
            t.fuel = p.fuel or t.fuel
            t.inventory = p.inventory or t.inventory
            if not t.job then
              local job = makeJob(tonumber(id))
              if job then
                t.job = job.id; protocol.send(sender, protocol.NAME_CONTROL, "job_assign", tonumber(id), job, cfg.token)
              end
            end
          elseif msg.type == "reserve_move" then
            local to = p.to
            if to and not occupiedByOther(tonumber(id), to) then
              reservations[util.key(to)] = tonumber(id)
              protocol.send(sender, protocol.NAME_CONTROL, "reserve_ok", tonumber(id), { to = to }, cfg.token)
            else
              protocol.send(sender, protocol.NAME_CONTROL, "reserve_denied", tonumber(id), { reason = "occupied" },
                cfg.token)
            end
          elseif msg.type == "move_result" then
            if p.pos then t.pos = p.pos end
            reservations = {}
          elseif msg.type == "job_done" then
            t.job = nil
            t.status = "idle"
          elseif msg.type == "need_unload" then
            protocol.send(sender, protocol.NAME_CONTROL, "go_unload", tonumber(id), { dropoff = cfg.dropoff }, cfg.token)
          elseif msg.type == "need_fuel" then
            protocol.send(sender, protocol.NAME_CONTROL, "go_fuel", tonumber(id), { fuel = cfg.fuel }, cfg.token)
          end
          saveAll()
        end
      end
    end
  end
end

local function menuLoop()
  while running do
    util.clear(term)
    print("MineNet Manager")
    print("1 Set base point")
    print("2 Set dropoff point")
    print("3 Set fuel point")
    print("4 Set mining start")
    print("5 Set branch length")
    print("6 Show turtles")
    print("7 Save")
    print("8 Quit")
    write("> ")
    local c = read()
    if c == "1" then
      cfg.base = getPos("Base point")
    elseif c == "2" then
      cfg.dropoff = getPos("Dropoff point")
    elseif c == "3" then
      cfg.fuel = getPos("Fuel point")
    elseif c == "4" then
      cfg.area = cfg.area or {}
      cfg.area.start = getPos("Mining start point")
      write("Heading 0=N 1=E 2=S 3=W: ")
      cfg.area.heading = tonumber(read()) or 1
      saveAll()
      print("Mining start saved: " .. util.key(cfg.area.start) .. " heading " .. tostring(cfg.area.heading))
      sleep(1.5)
    elseif c == "5" then
      write("Branch length: "); cfg.branch_length = tonumber(read()) or cfg.branch_length
    elseif c == "6" then
      util.clear(term); drawStatus(term); print("Press enter"); read()
    elseif c == "7" then
      saveAll(); print("Saved"); sleep(1)
    elseif c == "8" then
      running = false
    end
  end
end

local ok, side = protocol.openModem()
if not ok then
  print("MineNet server error: " .. side); return
end
rednet.host(protocol.NAME_DISCOVERY, "minenet-server")
print("MineNet server started on modem " .. side)
sleep(1)
parallel.waitForAny(networkLoop, monitorLoop, menuLoop)
saveAll()
