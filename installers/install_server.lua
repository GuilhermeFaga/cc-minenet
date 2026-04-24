local files = {
  "protocol.lua","storage.lua","config.lua","util.lua","server.lua"
}
if not fs.exists("/minenet") then fs.makeDir("/minenet") end
if not fs.exists("/minenet/data") then fs.makeDir("/minenet/data") end
if fs.exists("/disk/minenet") then
  for _, f in ipairs(files) do fs.copy("/disk/minenet/"..f, "/minenet/"..f) end
elseif fs.exists("/minenet_src") then
  for _, f in ipairs(files) do fs.copy("/minenet_src/"..f, "/minenet/"..f) end
else
  print("Copy /minenet folder manually, then run /minenet/server.lua")
end
local h = fs.open("/startup.lua", "w"); h.write('shell.run("/minenet/server.lua")\n'); h.close()
print("Installed MineNet server. Edit /minenet/data/config.json token, then reboot.")
