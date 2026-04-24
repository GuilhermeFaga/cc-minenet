local util = {}

function util.key(p) return tostring(p.x)..","..tostring(p.y)..","..tostring(p.z) end
function util.copy(p) return {x=p.x,y=p.y,z=p.z} end
function util.eq(a,b) return a and b and a.x==b.x and a.y==b.y and a.z==b.z end
function util.dist(a,b) return math.abs(a.x-b.x)+math.abs(a.y-b.y)+math.abs(a.z-b.z) end
function util.pos(x,y,z) return {x=math.floor(x), y=math.floor(y), z=math.floor(z)} end
function util.gpsPos(timeout)
  local x,y,z = gps.locate(timeout or 2)
  if x then return util.pos(x,y,z) end
  return nil
end
function util.inventoryRatio()
  if not turtle then return 0 end
  local used, total = 0, 16
  for i=1,16 do if turtle.getItemCount(i) > 0 then used = used + 1 end end
  return used / total
end
function util.firstFreeSlot()
  if not turtle then return nil end
  for i=1,16 do if turtle.getItemCount(i) == 0 then return i end end
  return nil
end
function util.colorFor(n)
  local list = {colors.red,colors.orange,colors.yellow,colors.lime,colors.green,colors.cyan,colors.lightBlue,colors.blue,colors.purple,colors.magenta,colors.pink,colors.white,colors.lightGray,colors.gray,colors.brown}
  return list[((n-1)%#list)+1]
end
return util
