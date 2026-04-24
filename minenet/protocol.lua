local protocol = {}

protocol.VERSION = 2
protocol.NAME_DISCOVERY = "minenet.discovery"
protocol.NAME_CONTROL = "minenet.control"
protocol.NAME_STATUS = "minenet.status"
protocol.NAME_ROUTE = "minenet.route"
protocol.NAME_MAP = "minenet.map"
protocol.DEFAULT_TOKEN = "change-me"

local SIDE_NAMES = { "top", "bottom", "left", "right", "front", "back" }

local function hasType(name, wanted)
  if not peripheral or not peripheral.getType then return false end
  local t = peripheral.getType(name)
  if t == wanted then return true end
  if type(t) == "table" then
    for i = 1, #t do
      if t[i] == wanted then return true end
    end
  end
  return false
end

function protocol.findModemSide()
  if peripheral and peripheral.getNames then
    local names = peripheral.getNames()
    for i = 1, #names do
      if hasType(names[i], "modem") then return names[i] end
    end
  end
  for i = 1, #SIDE_NAMES do
    if hasType(SIDE_NAMES[i], "modem") then return SIDE_NAMES[i] end
  end
  return nil
end

function protocol.openModem(side)
  if not rednet then return false, "rednet API missing" end
  side = side or protocol.findModemSide()
  if not side then return false, "no modem found" end
  if not rednet.isOpen(side) then rednet.open(side) end
  return true, side
end

local function now()
  if os.epoch then return os.epoch("utc") end
  return math.floor(os.clock() * 1000)
end

function protocol.msg(messageType, turtleId, payload, token)
  return {
    version = protocol.VERSION,
    token = token or protocol.DEFAULT_TOKEN,
    type = messageType,
    turtle_id = turtleId,
    time = now(),
    payload = payload or {}
  }
end

function protocol.valid(message, token, allowHello)
  if type(message) ~= "table" then return false end
  if message.version ~= protocol.VERSION then return false end
  if type(message.type) ~= "string" then return false end
  if token and message.token ~= token then
    if allowHello and message.type == "hello" then return true end
    return false
  end
  return true
end

function protocol.send(id, protoName, messageType, turtleId, payload, token)
  if not id then return false end
  return rednet.send(id, protocol.msg(messageType, turtleId, payload, token), protoName)
end

function protocol.broadcast(protoName, messageType, turtleId, payload, token)
  rednet.broadcast(protocol.msg(messageType, turtleId, payload, token), protoName)
end

function protocol.receive(protoName, timeout, token)
  while true do
    local id, message, proto = rednet.receive(protoName, timeout)
    if not id then return nil, nil, nil end
    if protocol.valid(message, token, false) then return id, message, proto end
  end
end

return protocol
