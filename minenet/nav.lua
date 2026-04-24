local protocol = require("protocol")
local util = require("util")

local nav = {}
nav.pos = nil
nav.heading = 0 -- 0 north -Z, 1 east +X, 2 south +Z, 3 west -X
nav.server_id = nil
nav.token = "change-me"
nav.turtle_id = nil

local dirs = {
  {x=0, z=-1},
  {x=1, z=0},
  {x=0, z=1},
  {x=-1, z=0}
}

function nav.syncGps(timeout)
  if not gps or not gps.locate then return false, "gps api missing" end
  local x,y,z = gps.locate(timeout or 3)
  if not x then return false, "gps locate failed" end
  nav.pos = {x=math.floor(x), y=math.floor(y), z=math.floor(z)}
  return true
end

function nav.setServer(id, token, turtleId)
  nav.server_id = id
  nav.token = token
  nav.turtle_id = turtleId
end

local function reserve(to)
  if not nav.server_id then return true end
  protocol.send(nav.server_id, protocol.NAME_CONTROL, "reserve_move", nav.turtle_id, {from=nav.pos, to=to}, nav.token)
  local id, msg = protocol.receive(protocol.NAME_CONTROL, 2, nav.token)
  if id == nav.server_id and msg and msg.type == "reserve_ok" then return true end
  return false
end

local function reportMove(ok, to)
  if nav.server_id then
    protocol.send(nav.server_id, protocol.NAME_STATUS, "move_result", nav.turtle_id, {ok=ok, pos=nav.pos, intended=to}, nav.token)
  end
end

function nav.turnLeft()
  local ok = turtle.turnLeft()
  if ok then nav.heading = (nav.heading + 3) % 4 end
  return ok
end

function nav.turnRight()
  local ok = turtle.turnRight()
  if ok then nav.heading = (nav.heading + 1) % 4 end
  return ok
end

function nav.face(h)
  h = h % 4
  while nav.heading ~= h do
    local r = (h - nav.heading) % 4
    if r == 1 then nav.turnRight() else nav.turnLeft() end
  end
end

function nav.forward()
  if not nav.pos then nav.syncGps(2) end
  local d = dirs[nav.heading + 1]
  local to = {x=nav.pos.x + d.x, y=nav.pos.y, z=nav.pos.z + d.z}
  if not reserve(to) then return false, "reserved" end
  local ok, err = turtle.forward()
  if ok then nav.pos = to end
  reportMove(ok, to)
  return ok, err
end

function nav.up()
  if not nav.pos then nav.syncGps(2) end
  local to = {x=nav.pos.x, y=nav.pos.y + 1, z=nav.pos.z}
  if not reserve(to) then return false, "reserved" end
  local ok, err = turtle.up()
  if ok then nav.pos = to end
  reportMove(ok, to)
  return ok, err
end

function nav.down()
  if not nav.pos then nav.syncGps(2) end
  local to = {x=nav.pos.x, y=nav.pos.y - 1, z=nav.pos.z}
  if not reserve(to) then return false, "reserved" end
  local ok, err = turtle.down()
  if ok then nav.pos = to end
  reportMove(ok, to)
  return ok, err
end

function nav.digForward()
  local ok, data = turtle.inspect()
  if ok and nav.server_id then
    local d = dirs[nav.heading + 1]
    local p = {x=nav.pos.x+d.x, y=nav.pos.y, z=nav.pos.z+d.z}
    protocol.send(nav.server_id, protocol.NAME_MAP, "map_update", nav.turtle_id, {blocks={[util.key(p)]={state="solid", name=data.name}}}, nav.token)
  end
  while turtle.detect() do turtle.dig(); sleep(0.2) end
end

function nav.safeForward()
  nav.digForward()
  local ok, err = nav.forward()
  if not ok and turtle.detect() then turtle.dig(); sleep(0.2); ok, err = nav.forward() end
  return ok, err
end

function nav.gotoY(y)
  while nav.pos and nav.pos.y < y do
    while turtle.detectUp() do turtle.digUp(); sleep(0.2) end
    local ok = nav.up(); if not ok then return false end
  end
  while nav.pos and nav.pos.y > y do
    while turtle.detectDown() do turtle.digDown(); sleep(0.2) end
    local ok = nav.down(); if not ok then return false end
  end
  return true
end

function nav.gotoXZ(x,z)
  while nav.pos and nav.pos.x ~= x do
    if nav.pos.x < x then nav.face(1) else nav.face(3) end
    if not nav.safeForward() then sleep(0.5) end
  end
  while nav.pos and nav.pos.z ~= z do
    if nav.pos.z < z then nav.face(2) else nav.face(0) end
    if not nav.safeForward() then sleep(0.5) end
  end
  return true
end

function nav.goto(pos)
  if not nav.pos then local ok = nav.syncGps(3); if not ok then return false end end
  nav.gotoY(pos.y)
  nav.gotoXZ(pos.x, pos.z)
  nav.gotoY(pos.y)
  return true
end

return nav
