local src = "disk/minenet"
if not fs.exists(src) then src = "/disk/minenet" end
if not fs.exists(src) then error("Put the minenet folder on a disk first") end
if fs.exists("/minenet") then fs.delete("/minenet") end
fs.copy(src, "/minenet")
local h = fs.open("/startup.lua", "w")
h.writeLine('shell.run("/minenet/server.lua")')
h.close()
print("MineNet server installed. Reboot or run /startup.lua")
