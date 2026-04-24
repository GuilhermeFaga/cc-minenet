local protocol = {}

protocol.VERSION = 1
protocol.DISCOVERY = "minenet.discovery"
protocol.CONTROL = "minenet.control"
protocol.STATUS = "minenet.status"
protocol.MAP = "minenet.map"
protocol.ROUTE = "minenet.route"
protocol.HOSTNAME = "minenet.server"
protocol.DEFAULT_TOKEN = "change-me"

function protocol.now()
  if os.epoch then return os.epoch("utc") end
  return math.floor(os.clock() * 1000)
end

function protocol.message(kind, payload, token, turtle_id)
  return {
    version = protocol.VERSION,
    token = token or protocol.DEFAULT_TOKEN,
    type = kind,
    turtle_id = turtle_id,
    time = protocol.now(),
    payload = payload or {},
  }
end

function protocol.valid(msg, token)
  return type(msg) == "table" and msg.version == protocol.VERSION and msg.token == token and type(msg.type) == "string"
end

function protocol.openRednet(preferredSide)
  if rednet.isOpen and rednet.isOpen() then return true end
  if preferredSide and peripheral.getType(preferredSide) == "modem" then
    rednet.open(preferredSide)
    return true
  end
  local opened = false
  for _, side in ipairs(peripheral.getNames()) do
    if peripheral.getType(side) == "modem" then
      rednet.open(side)
      opened = true
    end
  end
  if not opened then error("No modem found. Attach/equip a wired or wireless modem.") end
  return opened
end

function protocol.send(id, kind, payload, token, turtle_id, channel)
  return rednet.send(id, protocol.message(kind, payload, token, turtle_id), channel or protocol.CONTROL)
end

function protocol.broadcast(kind, payload, token, turtle_id, channel)
  return rednet.broadcast(protocol.message(kind, payload, token, turtle_id), channel or protocol.DISCOVERY)
end

function protocol.receive(channel, timeout, token)
  local id, msg, proto = rednet.receive(channel, timeout)
  if not id then return nil end
  if token and not protocol.valid(msg, token) then return nil, "invalid", id, msg, proto end
  return id, msg, proto
end

return protocol
