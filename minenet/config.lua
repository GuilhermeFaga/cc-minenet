local storage = require("storage")
local config = {}

config.path = "/minenet/data/config.json"

config.defaults = {
  token = "change-me",
  modemSide = nil,
  heartbeatTimeout = 30,
  movementTimeout = 6,
  inventoryFullRatio = 0.85,
  fuelSafetyMargin = 100,
  base = nil,
  dropoff = nil,
  fuel = nil,
  mining = {
    min = nil,
    max = nil,
    mode = "branch",
    tunnelSpacing = 3,
    branchLength = 48,
    branchHeight = 2,
  },
  blacklist = {
    ["minecraft:lava"] = true,
    ["minecraft:water"] = false,
    ["minecraft:bedrock"] = true,
  },
}

local function merge(a, b)
  local out = {}
  for k, v in pairs(a or {}) do
    if type(v) == "table" then out[k] = merge(v, {}) else out[k] = v end
  end
  for k, v in pairs(b or {}) do
    if type(v) == "table" and type(out[k]) == "table" then out[k] = merge(out[k], v) else out[k] = v end
  end
  return out
end

function config.load()
  return merge(config.defaults, storage.read(config.path, {}))
end

function config.save(c)
  storage.write(config.path, c)
end

return config
