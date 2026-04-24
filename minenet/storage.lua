local storage = {}

function storage.ensureDir(path)
  if not fs.exists(path) then fs.makeDir(path) end
end

function storage.read(path, default)
  if not fs.exists(path) then return default end
  local h = fs.open(path, "r")
  if not h then return default end
  local s = h.readAll()
  h.close()
  if not s or s == "" then return default end
  local ok, value = pcall(textutils.unserializeJSON, s)
  if ok and value ~= nil then return value end
  ok, value = pcall(textutils.unserialize, s)
  if ok and value ~= nil then return value end
  return default
end

function storage.write(path, value)
  local dir = fs.getDir(path)
  if dir and dir ~= "" then storage.ensureDir(dir) end
  local h = fs.open(path, "w")
  if not h then error("Cannot write " .. path) end
  if textutils.serializeJSON then h.write(textutils.serializeJSON(value)) else h.write(textutils.serialize(value)) end
  h.close()
end

return storage
