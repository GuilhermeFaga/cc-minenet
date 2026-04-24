local repo = "https://raw.githubusercontent.com/GuilhermeFaga/cc-minenet/main/"
local files = {
  "config.lua",
  "fuel.lua",
  "nav.lua",
  "protocol.lua",
  "server.lua",
  "storage.lua",
  "turtle.lua",
  "util.lua"
}

local target = "/minenet"

if fs.exists(target) then
  print("Removing old /minenet")
  fs.delete(target)
end

fs.makeDir(target)

for _, file in ipairs(files) do
  local url = repo .. "minenet/" .. file
  local out = target .. "/" .. file

  print("Downloading " .. file)
  local ok, err = pcall(function()
    shell.run("wget", url, out)
  end)

  if not ok or not fs.exists(out) then
    error("Failed to download " .. file .. ": " .. tostring(err))
  end
end

print("Install complete.")
print("Run:")
print("  cd /minenet")
print("  server.lua  -- on computer")
print("  turtle.lua  -- on turtle")
