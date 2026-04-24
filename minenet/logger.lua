local logger = {}

local path = "/minenet/logs/minenet.log"
local maxSize = 60000

local function ensureDir(p)
  local dir = fs.getDir(p)
  if dir and dir ~= "" and not fs.exists(dir) then fs.makeDir(dir) end
end

local function nowText()
  if textutils and textutils.formatTime and os.time then
    return textutils.formatTime(os.time(), true)
  end
  if os.epoch then return tostring(os.epoch("utc")) end
  return tostring(math.floor(os.clock() * 1000))
end

function logger.init(name)
  ensureDir("/minenet/logs/.keep")
  name = tostring(name or "minenet")
  name = string.gsub(name, "[^%w%-%_%.]", "_")
  path = "/minenet/logs/" .. name .. ".log"
  if fs.exists(path) and fs.getSize(path) > maxSize then
    local backup = path .. ".1"
    if fs.exists(backup) then fs.delete(backup) end
    fs.move(path, backup)
  end
  logger.info("logger started", path)
end

function logger.path()
  return path
end

function logger.line(level, ...)
  local parts = {}
  for i = 1, select("#", ...) do
    local v = select(i, ...)
    if type(v) == "table" then
      if textutils and textutils.serialize then
        parts[#parts + 1] = textutils.serialize(v)
      else
        parts[#parts + 1] = "<table>"
      end
    else
      parts[#parts + 1] = tostring(v)
    end
  end
  local ok = pcall(function()
    ensureDir(path)
    local h = fs.open(path, "a")
    if h then
      h.writeLine("[" .. nowText() .. "] [" .. tostring(level or "INFO") .. "] " .. table.concat(parts, " "))
      h.close()
    end
  end)
  return ok
end

function logger.info(...) return logger.line("INFO", ...) end

function logger.warn(...) return logger.line("WARN", ...) end

function logger.error(...) return logger.line("ERROR", ...) end

function logger.debug(...) return logger.line("DEBUG", ...) end

return logger
