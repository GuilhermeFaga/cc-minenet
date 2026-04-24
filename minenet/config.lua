local storage = require("storage")
local config = {}

config.path = "/minenet/data/config.json"

config.defaults = {
  token = "change-me",
  heartbeat_timeout = 30,
  fuel_margin = 100,
  inventory_return_ratio = 0.85,
  base = nil,
  dropoff = nil,
  fuel = nil,
  area = nil,
  branch_length = 32,
  branch_spacing = 3,
  tunnel_height = 2
}

local function merge(a, b)
  local out = {}
  for k, v in pairs(a or {}) do out[k] = v end
  for k, v in pairs(b or {}) do out[k] = v end
  return out
end

function config.load()
  return merge(config.defaults, storage.read(config.path, {}))
end

function config.save(c)
  return storage.write(config.path, c)
end

return config
