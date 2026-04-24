local storage = {}

local function parent(path)
  local p = string.match(path, "^(.+)/[^/]+$")
  if p and p ~= "" and not fs.exists(p) then fs.makeDir(p) end
end

function storage.read(path, default)
  if not fs.exists(path) then return default end
  local h = fs.open(path, "r")
  if not h then return default end
  local text = h.readAll()
  h.close()
  if not text or text == "" then return default end
  local ok, data = pcall(textutils.unserializeJSON, text)
  if ok and data ~= nil then return data end
  ok, data = pcall(textutils.unserialize, text)
  if ok and data ~= nil then return data end
  return default
end

function storage.write(path, data)
  parent(path)
  local h = fs.open(path, "w")
  if not h then return false end
  if textutils.serializeJSON then
    h.write(textutils.serializeJSON(data))
  else
    h.write(textutils.serialize(data))
  end
  h.close()
  return true
end

return storage
