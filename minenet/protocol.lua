local protocol = {}

protocol.VERSION = 1
protocol.NAME_DISCOVERY = "minenet.discovery"
protocol.NAME_CONTROL = "minenet.control"
protocol.NAME_STATUS = "minenet.status"
protocol.DEFAULT_TOKEN = "change-me"

function protocol.findModemSide()
  local sides = { "top", "bottom", "left", "right", "front", "back" }
  for i = 1, #sides do
    if peripheral.getType(sides[i]) == "modem" then return sides[i] end
  end
  return nil
end

function protocol.openModem(side)
  side = side or protocol.findModemSide()
  if not side then return false, "no modem found" end
  if not rednet.isOpen(side) then rednet.open(side) end
  return true, side
end

function protocol.msg(t, turtleId, payload, token)
  return {
    version = protocol.VERSION,
    token = token or protocol.DEFAULT_TOKEN,
    type = t,
    turtle_id = turtleId,
    time = os.epoch and os.epoch("utc") or os.clock(),
    payload = payload or {}
  }
end

function protocol.valid(message, token)
  if type(message) ~= "table" then return false end
  if message.version ~= protocol.VERSION then return false end
  if token and message.token ~= token then return false end
  if type(message.type) ~= "string" then return false end
  return true
end

function protocol.send(id, protoName, t, turtleId, payload, token)
  return rednet.send(id, protocol.msg(t, turtleId, payload, token), protoName)
end

function protocol.broadcast(protoName, t, turtleId, payload, token)
  rednet.broadcast(protocol.msg(t, turtleId, payload, token), protoName)
end

function protocol.receive(protoName, timeout, token)
  while true do
    local id, message, proto = rednet.receive(protoName, timeout)
    if not id then return nil, nil, nil end
    if protocol.valid(message, token) then return id, message, proto end
  end
end

return protocol
