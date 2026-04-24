local protocol = require("minenet.protocol")
local util = require("minenet.util")
local nav = {}
nav.heading = 0 -- 0 north -z, 1 east +x, 2 south +z, 3 west -x
nav.pos = nil
nav.server = nil
nav.token = nil
nav.turtle_id = nil

local delta = {{x=0,z=-1},{x=1,z=0},{x=0,z=1},{x=-1,z=0}}
function nav.init(server, token, turtle_id)
  nav.server=server; nav.token=token; nav.turtle_id=turtle_id; nav.pos = util.gpsPos(3) or nav.pos
end
function nav.turnTo(h)
  while nav.heading ~= h do turtle.turnRight(); nav.heading = (nav.heading + 1) % 4 end
end
local function reserve(to)
  if not nav.server then return true end
  protocol.send(nav.server, "reserve_move", {from=nav.pos,to=to}, nav.token, nav.turtle_id, protocol.ROUTE)
  local id,msg = rednet.receive(protocol.ROUTE, 4)
  return id == nav.server and msg and msg.type == "reserve_ok"
end
function nav.forwardDig()
  local d = delta[nav.heading+1]
  local to = {x=nav.pos.x+d.x,y=nav.pos.y,z=nav.pos.z+d.z}
  if not reserve(to) then return false, "reservation denied" end
  while turtle.detect() do turtle.dig(); sleep(0.2) end
  local ok, err = turtle.forward()
  if ok then protocol.send(nav.server,"release_pos",{pos=nav.pos},nav.token,nav.turtle_id,protocol.ROUTE); nav.pos=to end
  return ok, err
end
function nav.upDig()
  local to = {x=nav.pos.x,y=nav.pos.y+1,z=nav.pos.z}
  if not reserve(to) then return false, "reservation denied" end
  while turtle.detectUp() do turtle.digUp(); sleep(0.2) end
  local ok, err = turtle.up(); if ok then protocol.send(nav.server,"release_pos",{pos=nav.pos},nav.token,nav.turtle_id,protocol.ROUTE); nav.pos=to end; return ok,err
end
function nav.downDig()
  local to = {x=nav.pos.x,y=nav.pos.y-1,z=nav.pos.z}
  if not reserve(to) then return false, "reservation denied" end
  while turtle.detectDown() do turtle.digDown(); sleep(0.2) end
  local ok, err = turtle.down(); if ok then protocol.send(nav.server,"release_pos",{pos=nav.pos},nav.token,nav.turtle_id,protocol.ROUTE); nav.pos=to end; return ok,err
end
function nav.stepAxis(axis, target)
  while nav.pos and nav.pos[axis] ~= target do
    if axis == "y" then if nav.pos.y < target then nav.upDig() else nav.downDig() end
    elseif axis == "x" then nav.turnTo(nav.pos.x < target and 1 or 3); nav.forwardDig()
    elseif axis == "z" then nav.turnTo(nav.pos.z < target and 2 or 0); nav.forwardDig() end
  end
end
function nav.goto(p)
  if not nav.pos then nav.pos = util.gpsPos(3); if not nav.pos then return false,"gps failed" end end
  nav.stepAxis("y", p.y); nav.stepAxis("x", p.x); nav.stepAxis("z", p.z)
  return util.eq(nav.pos, p)
end
return nav
