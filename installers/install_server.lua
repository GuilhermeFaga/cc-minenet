local source = ({ ... })[1] or "disk/minenet"
if not fs.exists(source) then source = "/disk/minenet" end
if not fs.exists(source) then error("Could not find disk/minenet. Run from a disk or pass source path.") end
if fs.exists("/minenet") then fs.delete("/minenet") end
fs.copy(source, "/minenet")
print("MineNet server installed to /minenet")
print("Run: cd /minenet ; server.lua")
