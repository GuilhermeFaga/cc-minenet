local storage = require("storage")
local util = require("util")

local config = {}
config.PATH = "/minenet/data/config.tbl"

config.DEFAULTS = {
  token = "change-me",
  mining_enabled = false,
  paused = false,
  accept_new_turtles = true,
  branch_length = 48,
  branch_spacing = 3,
  tunnel_height = 2,
  max_jobs = 500,
  next_lane = 0,
  inventory_return_ratio = 0.85,
  fuel_min = 40,
  fuel_margin = 100,
  fuel_target = 800,
  fuel_station_wait = 8,
  keep_fuel_on_unload = true,
  turtle_status_timeout = 25,
  reservation_seconds = 4,
  area = {
    start = nil,
    heading = 1
  },
  base = nil,
  dropoff = nil,
  fuel = nil,
  monitor = {
    mode = "status",
    map_y = nil,
    zoom = 1
  }
}

function config.load()
  local cfg = storage.read(config.PATH, {})
  util.mergeDefaults(cfg, util.copy(config.DEFAULTS))
  return cfg
end

function config.save(cfg)
  storage.write(config.PATH, cfg)
end

return config
