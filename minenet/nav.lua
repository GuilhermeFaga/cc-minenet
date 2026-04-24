local protocol = require("protocol")
local storage = require("storage")
local util = require("util")

local nav = {}
nav.STATE_PATH = "/minenet/data/nav_state.tbl"
nav.pos = nil
nav.heading = nil
nav.serverId = nil
nav.token = nil
nav.turtleId = nil
nav.beforeMove = nil
nav.reserveEnabled = true

local function clonePos(pos)
  if not pos then return nil end
  return { x = pos.x, y = pos.y, z = pos.z }
end

function nav.load()
  local state = storage.read(nav.STATE_PATH, {})
  if state.pos then nav.pos = state.pos end
  if state.heading ~= nil then nav.heading = util.normHeading(state.heading) end
end

function nav.save()
  storage.write(nav.STATE_PATH, { pos = nav.pos, heading = nav.heading })
end

function nav.setServer(serverId, token, turtleId)
  nav.serverId = serverId
  nav.token = token
  nav.turtleId = turtleId
end

function nav.setHeading(heading)
  nav.heading = util.normHeading(heading)
  nav.save()
end

function nav.current()
  local p = clonePos(nav.pos)
  if p then p.heading = nav.heading end
  return p
end

function nav.syncGps(timeout)
  if not gps or not gps.locate then return false, "GPS API missing" end
  local x, y, z = gps.locate(timeout or 3)
  if not x then return false, "GPS locate failed" end
  nav.pos = { x = math.floor(x + 0.5), y = math.floor(y + 0.5), z = math.floor(z + 0.5) }
  nav.save()
  return true, nav.pos
end

local function sendMoveResult(ok, reason)
  if nav.serverId and nav.turtleId then
    protocol.send(nav.serverId, protocol.NAME_ROUTE, "move_result", nav.turtleId, {
      ok = ok,
      reason = reason,
      pos = nav.current()
    }, nav.token)
  end
end

function nav.mapAir(pos)
  if nav.serverId and nav.turtleId and pos then
    protocol.send(nav.serverId, protocol.NAME_MAP, "map_update", nav.turtleId, {
      blocks = {
        { pos = clonePos(pos), state = "air" }
      }
    }, nav.token)
  end
end

local function reserve(to)
  if not nav.reserveEnabled or not nav.serverId or not nav.turtleId then return true end
  for attempt = 1, 8 do
    protocol.send(nav.serverId, protocol.NAME_ROUTE, "reserve_move", nav.turtleId, {
      from = nav.current(),
      to = to
    }, nav.token)
    local id, msg = protocol.receive(protocol.NAME_ROUTE, 1.5, nav.token)
    if id == nav.serverId and msg then
      if msg.type == "reserve_ok" then return true end
      if msg.type == "reserve_denied" then sleep(0.35 + attempt * 0.1) end
    else
      sleep(0.25)
    end
  end
  return false, "reservation_timeout"
end

local function callBeforeMove(to)
  if nav.beforeMove then
    local ok, reason = nav.beforeMove(to)
    if not ok then return false, reason or "blocked_by_beforeMove" end
  end
  return true
end

local function digForward()
  for i = 1, 12 do
    if not turtle.detect() then return true end
    turtle.dig()
    sleep(0.2)
  end
  return not turtle.detect()
end

local function digUp()
  for i = 1, 12 do
    if not turtle.detectUp() then return true end
    turtle.digUp()
    sleep(0.2)
  end
  return not turtle.detectUp()
end

local function digDown()
  for i = 1, 12 do
    if not turtle.detectDown() then return true end
    turtle.digDown()
    sleep(0.2)
  end
  return not turtle.detectDown()
end

function nav.face(heading)
  heading = util.normHeading(heading)
  if nav.heading == nil then nav.heading = heading end
  while nav.heading ~= heading do
    local rightTurns = (heading - nav.heading) % 4
    if rightTurns == 1 then
      turtle.turnRight()
      nav.heading = (nav.heading + 1) % 4
    elseif rightTurns == 2 then
      turtle.turnRight()
      turtle.turnRight()
      nav.heading = (nav.heading + 2) % 4
    else
      turtle.turnLeft()
      nav.heading = (nav.heading + 3) % 4
    end
    nav.save()
  end
  return true
end

function nav.forward(shouldDig)
  if not nav.pos then return false, "unknown_position" end
  if nav.heading == nil then return false, "unknown_heading" end
  local d = util.dirForHeading(nav.heading)
  local to = { x = nav.pos.x + d.x, y = nav.pos.y, z = nav.pos.z + d.z }
  local ok, reason = callBeforeMove(to)
  if not ok then return false, reason end
  ok, reason = reserve(to)
  if not ok then return false, reason end
  if shouldDig then digForward() end
  ok, reason = turtle.forward()
  if ok then
    nav.pos = to
    nav.save()
    nav.mapAir(nav.pos)
    sendMoveResult(true)
    return true
  end
  sendMoveResult(false, reason)
  return false, reason
end

function nav.up(shouldDig)
  if not nav.pos then return false, "unknown_position" end
  local to = { x = nav.pos.x, y = nav.pos.y + 1, z = nav.pos.z }
  local ok, reason = callBeforeMove(to)
  if not ok then return false, reason end
  ok, reason = reserve(to)
  if not ok then return false, reason end
  if shouldDig then digUp() end
  ok, reason = turtle.up()
  if ok then
    nav.pos = to
    nav.save()
    nav.mapAir(nav.pos)
    sendMoveResult(true)
    return true
  end
  sendMoveResult(false, reason)
  return false, reason
end

function nav.down(shouldDig)
  if not nav.pos then return false, "unknown_position" end
  local to = { x = nav.pos.x, y = nav.pos.y - 1, z = nav.pos.z }
  local ok, reason = callBeforeMove(to)
  if not ok then return false, reason end
  ok, reason = reserve(to)
  if not ok then return false, reason end
  if shouldDig then digDown() end
  ok, reason = turtle.down()
  if ok then
    nav.pos = to
    nav.save()
    nav.mapAir(nav.pos)
    sendMoveResult(true)
    return true
  end
  sendMoveResult(false, reason)
  return false, reason
end

function nav.digForward()
  return digForward()
end

function nav.digUp()
  return digUp()
end

function nav.digDown()
  return digDown()
end

local function retryMove(fn, shouldDig)
  for attempt = 1, 30 do
    local ok, reason = fn(shouldDig)
    if ok then return true end
    if reason == "out_of_fuel" or reason == "shutdown" then return false, reason end
    sleep(0.25 + math.min(attempt * 0.05, 1))
  end
  return false, "move_retry_limit"
end

function nav.goTo(dest, options)
  options = options or {}
  if not dest then return false, "no_destination" end
  if not nav.pos then
    local ok = nav.syncGps(5)
    if not ok then return false, "unknown_position" end
  end
  local dig = options.dig ~= false

  while nav.pos.y < dest.y do
    local ok, reason = retryMove(nav.up, dig)
    if not ok then return false, reason end
  end
  while nav.pos.y > dest.y do
    local ok, reason = retryMove(nav.down, dig)
    if not ok then return false, reason end
  end
  while nav.pos.x < dest.x do
    nav.face(1)
    local ok, reason = retryMove(nav.forward, dig)
    if not ok then return false, reason end
  end
  while nav.pos.x > dest.x do
    nav.face(3)
    local ok, reason = retryMove(nav.forward, dig)
    if not ok then return false, reason end
  end
  while nav.pos.z < dest.z do
    nav.face(2)
    local ok, reason = retryMove(nav.forward, dig)
    if not ok then return false, reason end
  end
  while nav.pos.z > dest.z do
    nav.face(0)
    local ok, reason = retryMove(nav.forward, dig)
    if not ok then return false, reason end
  end
  if dest.heading ~= nil then nav.face(dest.heading) end
  return true
end

nav.load()
return nav
