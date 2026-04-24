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

  -- Default mining mode: one shared wall/volume.
  -- area.start is the bottom-left-front block when looking in area.heading direction.
  -- width extends to the turtle's right, height goes up, depth goes forward.
  mining_mode = "volume",
  volume_width = 8,
  volume_height = 3,
  volume_depth = 48,
  volume_depth_index = 0,
  volume_next_col = 0,
  volume_next_column = 0,

  -- Old branch/tunnel values kept for compatibility and optional future use.
  branch_length = 48,
  branch_spacing = 5,
  tunnel_width = 3,
  tunnel_height = 3,

  max_jobs = 500,
  max_active_turtles = 4,
  next_lane = 0,
  next_job_number = 1,

  inventory_return_ratio = 0.85,

  -- Fuel safety: each turtle predicts the cost to reach the fuel station
  -- plus this margin before accepting/moving/continuing mining work.
  fuel_min = 40,
  fuel_margin = 120,
  fuel_target = 800,
  fuel_station_wait = 8,
  player_resume_fuel = 1,
  keep_fuel_on_unload = true,
  fuel_keep_items = 1,

  dropoff_wait = 5,
  turtle_status_timeout = 25,
  reservation_seconds = 4,
  recall_rebroadcast_seconds = 2,
  station_lock_attempts = 120,
  station_lock_seconds = 45,
  hard_reset_broadcast_seconds = 12,
  hard_reset_rebroadcast_seconds = 1,
  log_max_bytes = 64000,

  area = {
    start = nil,
    heading = 1,
    width = 8,
    height = 3,
    depth = 48
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
