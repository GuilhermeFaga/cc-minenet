-- MineNet GitHub installer for CC:Tweaked
-- Usage:
--   wget https://raw.githubusercontent.com/GuilhermeFaga/cc-minenet/main/install.lua install
--   install

local owner = "GuilhermeFaga"
local repo = "cc-minenet"
local branch = "main"
local base = "https://raw.githubusercontent.com/" .. owner .. "/" .. repo .. "/" .. branch .. "/"
local target = "/minenet"

local files = {
  "protocol.lua",
  "storage.lua",
  "util.lua",
  "config.lua",
  "fuel.lua",
  "logger.lua",
  "server.lua",
  "nav.lua",
  "turtle.lua"
}

local function download(url, out)
  if fs.exists(out) then fs.delete(out) end
  local ok = shell.run("wget", url, out)
  if not ok or not fs.exists(out) then
    error("Failed to download " .. url)
  end
end

print("Installing MineNet from GitHub...")
if fs.exists(target) then fs.delete(target) end
fs.makeDir(target)

for _, file in ipairs(files) do
  print("- " .. file)
  download(base .. "minenet/" .. file, target .. "/" .. file)
end

print("Done.")
print("Run on server: cd /minenet && server.lua")
print("Run on turtle: cd /minenet && turtle.lua")
