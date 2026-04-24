local storage = require("storage")
local util = require("util")

local config = {}
config.PATH = "/minenet/data/config.tbl"

config.DEFAULTS = {
  token = "change-me",
  mining_enabled = false,
  paused = false,
  recall_all = false,
  accept_new_turtles = true,

  branch_length = 48,
  branch_spacing = 5,
  tunnel_width = 3,
  tunnel_height = 3,
  max_jobs = 500,
  next_lane = 0,
  next_job_number = 1,

  inventory_return_ratio = 0.85,

  fuel_min = 40,
  fuel_margin = 100,
  fuel_target = 800,
  fuel_station_wait = 8,
  player_resume_fuel = 1,
  keep_fuel_on_unload = true,
  fuel_keep_items = 1,

  dropoff_wait = 5,
  turtle_status_timeout = 25,
  reservation_seconds = 4,
  recall_rebroadcast_seconds = 2,

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
