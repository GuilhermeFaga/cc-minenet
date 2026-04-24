local storage = {}

local function serialize(value)
  if textutils.serialize then return textutils.serialize(value) end
  return textutils.serialise(value)
end

local function unserialize(text)
  if textutils.unserialize then return textutils.unserialize(text) end
  return textutils.unserialise(text)
end

function storage.ensureDir(path)
  local dir = fs.getDir(path)
  if dir and dir ~= "" and not fs.exists(dir) then fs.makeDir(dir) end
end

function storage.read(path, defaultValue)
  if not fs.exists(path) then return defaultValue end
  local handle = fs.open(path, "r")
  if not handle then return defaultValue end
  local content = handle.readAll()
  handle.close()
  if not content or content == "" then return defaultValue end
  local ok, data = pcall(unserialize, content)
  if ok and data ~= nil then return data end
  if textutils.unserializeJSON then
    local okJson, dataJson = pcall(textutils.unserializeJSON, content)
    if okJson and dataJson ~= nil then return dataJson end
  end
  return defaultValue
end

function storage.write(path, value)
  storage.ensureDir(path)
  local handle = fs.open(path, "w")
  if not handle then error("Could not write " .. tostring(path)) end
  handle.write(serialize(value))
  handle.close()
end

function storage.backup(path)
  if not fs.exists(path) then return false end
  local suffix = tostring(os.epoch and os.epoch("utc") or math.floor(os.clock() * 1000))
  fs.copy(path, path .. "." .. suffix .. ".bak")
  return true
end

return storage
