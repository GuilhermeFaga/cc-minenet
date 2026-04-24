local files = {"protocol.lua","storage.lua","config.lua","util.lua","nav.lua","turtle.lua"}
if not fs.exists("/minenet") then fs.makeDir("/minenet") end
if not fs.exists("/minenet/data") then fs.makeDir("/minenet/data") end
if fs.exists("/disk/minenet") then for _, f in ipairs(files) do fs.copy("/disk/minenet/"..f, "/minenet/"..f) end end
local h = fs.open("/startup.lua", "w"); h.write('shell.run("/minenet/turtle.lua")\n'); h.close()
print("Installed MineNet turtle. Make sure token matches server, then reboot.")
