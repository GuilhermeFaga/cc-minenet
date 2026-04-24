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
nav.shouldAbort = nil
nav.onWait = nil
nav.reserveEnabled = true

local function clonePos(pos)
  if not pos then return nil end
  return { x = pos.x, y = pos.y, z = pos.z }
end

local function checkAbort()
  if nav.shouldAbort then
    local abort, reason = nav.shouldAbort()
    if abort then return true, reason or "aborted" end
  end
  return false, nil
end

local function waitNotice(reason, to, attempt)
  if nav.onWait then pcall(nav.onWait, reason, to, attempt) end
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
  for attempt = 1, 10 do
    local abort, abortReason = checkAbort()
    if abort then return false, abortReason end

    protocol.send(nav.serverId, protocol.NAME_ROUTE, "reserve_move", nav.turtleId, {
      from = nav.current(),
      to = to
    }, nav.token)

    local id, msg = protocol.receive(protocol.NAME_ROUTE, 1.0, nav.token)
    if id == nav.serverId and msg then
      if msg.type == "reserve_ok" then return true end
      if msg.type == "reserve_denied" then
        local reason = (msg.payload and msg.payload.reason) or "reserved"
        waitNotice(reason, to, attempt)
        sleep(0.25 + attempt * 0.1)
      end
    else
      waitNotice("no_route_reply", to, attempt)
      sleep(0.2)
    end
  end
  waitNotice("reservation_timeout", to, 10)
  return false, "reservation_timeout"
end

local function callBeforeMove(to)
  local abort, abortReason = checkAbort()
  if abort then return false, abortReason end
  if nav.beforeMove then
    local ok, reason = nav.beforeMove(to)
    if not ok then return false, reason or "blocked_by_beforeMove" end
  end
  return true
end

local function digForward()
  for i = 1, 12 do
    local abort, abortReason = checkAbort()
    if abort then return false, abortReason end
    if not turtle.detect() then return true end
    turtle.dig()
    sleep(0.2)
  end
  return not turtle.detect()
end

local function digUp()
  for i = 1, 12 do
    local abort, abortReason = checkAbort()
    if abort then return false, abortReason end
    if not turtle.detectUp() then return true end
    turtle.digUp()
    sleep(0.2)
  end
  return not turtle.detectUp()
end

local function digDown()
  for i = 1, 12 do
    local abort, abortReason = checkAbort()
    if abort then return false, abortReason end
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
    local abort, abortReason = checkAbort()
    if abort then return false, abortReason end
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
  if shouldDig then
    ok, reason = digForward()
    if not ok then return false, reason or "dig_blocked" end
  end
  ok, reason = turtle.forward()
  if ok then
    nav.pos = to
    nav.save()
    nav.mapAir(nav.pos)
    sendMoveResult(true)
    return true
  end
  sendMoveResult(false, reason or "blocked")
  waitNotice(reason or "blocked", to, 0)
  return false, reason or "blocked"
end

function nav.up(shouldDig)
  if not nav.pos then return false, "unknown_position" end
  local to = { x = nav.pos.x, y = nav.pos.y + 1, z = nav.pos.z }
  local ok, reason = callBeforeMove(to)
  if not ok then return false, reason end
  ok, reason = reserve(to)
  if not ok then return false, reason end
  if shouldDig then
    ok, reason = digUp()
    if not ok then return false, reason or "dig_up_blocked" end
  end
  ok, reason = turtle.up()
  if ok then
    nav.pos = to
    nav.save()
    nav.mapAir(nav.pos)
    sendMoveResult(true)
    return true
  end
  sendMoveResult(false, reason or "blocked_up")
  waitNotice(reason or "blocked_up", to, 0)
  return false, reason or "blocked_up"
end

function nav.down(shouldDig)
  if not nav.pos then return false, "unknown_position" end
  local to = { x = nav.pos.x, y = nav.pos.y - 1, z = nav.pos.z }
  local ok, reason = callBeforeMove(to)
  if not ok then return false, reason end
  ok, reason = reserve(to)
  if not ok then return false, reason end
  if shouldDig then
    ok, reason = digDown()
    if not ok then return false, reason or "dig_down_blocked" end
  end
  ok, reason = turtle.down()
  if ok then
    nav.pos = to
    nav.save()
    nav.mapAir(nav.pos)
    sendMoveResult(true)
    return true
  end
  sendMoveResult(false, reason or "blocked_down")
  waitNotice(reason or "blocked_down", to, 0)
  return false, reason or "blocked_down"
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
    local abort, abortReason = checkAbort()
    if abort then return false, abortReason end
    local ok, reason = fn(shouldDig)
    if ok then return true end
    if reason == "out_of_fuel" or reason == "shutdown" or reason == "hard_reset" or reason == "recalled" then
      return false, reason
    end
    waitNotice(reason or "move_failed", nil, attempt)
    sleep(0.25 + math.min(attempt * 0.05, 1))
  end
  return false, "move_retry_limit"
end

local function abortIfNeeded()
  local abort, abortReason = checkAbort()
  if abort then return false, abortReason end
  return true
end

function nav.goTo(dest, options)
  options = options or {}
  if not dest then return false, "no_destination" end
  if not nav.pos then
    local ok = nav.syncGps(5)
    if not ok then return false, "unknown_position" end
  end
  local dig = options.dig ~= false
  local ok, reason

  while nav.pos.y < dest.y do
    ok, reason = abortIfNeeded(); if not ok then return false, reason end
    ok, reason = retryMove(nav.up, dig); if not ok then return false, reason end
  end
  while nav.pos.y > dest.y do
    ok, reason = abortIfNeeded(); if not ok then return false, reason end
    ok, reason = retryMove(nav.down, dig); if not ok then return false, reason end
  end
  while nav.pos.x < dest.x do
    ok, reason = abortIfNeeded(); if not ok then return false, reason end
    ok, reason = nav.face(1); if not ok then return false, reason end
    ok, reason = retryMove(nav.forward, dig); if not ok then return false, reason end
  end
  while nav.pos.x > dest.x do
    ok, reason = abortIfNeeded(); if not ok then return false, reason end
    ok, reason = nav.face(3); if not ok then return false, reason end
    ok, reason = retryMove(nav.forward, dig); if not ok then return false, reason end
  end
  while nav.pos.z < dest.z do
    ok, reason = abortIfNeeded(); if not ok then return false, reason end
    ok, reason = nav.face(2); if not ok then return false, reason end
    ok, reason = retryMove(nav.forward, dig); if not ok then return false, reason end
  end
  while nav.pos.z > dest.z do
    ok, reason = abortIfNeeded(); if not ok then return false, reason end
    ok, reason = nav.face(0); if not ok then return false, reason end
    ok, reason = retryMove(nav.forward, dig); if not ok then return false, reason end
  end
  if dest.heading ~= nil then
    ok, reason = nav.face(dest.heading)
    if not ok then return false, reason end
  end
  return true
end

nav.load()
return nav
