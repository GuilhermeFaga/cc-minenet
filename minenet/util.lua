local util = {}

util.colors = {
  colors.red, colors.orange, colors.yellow, colors.lime,
  colors.green, colors.cyan, colors.lightBlue, colors.blue,
  colors.purple, colors.magenta, colors.pink, colors.white
}

function util.key(pos)
  if not pos then return "?" end
  return tostring(pos.x) .. "," .. tostring(pos.y) .. "," .. tostring(pos.z)
end

function util.copy(t)
  local o = {}
  for k, v in pairs(t or {}) do
    if type(v) == "table" then o[k] = util.copy(v) else o[k] = v end
  end
  return o
end

function util.dist(a, b)
  if not a or not b then return 999999 end
  return math.abs(a.x - b.x) + math.abs(a.y - b.y) + math.abs(a.z - b.z)
end

function util.inventoryRatio()
  local filled = 0
  for i = 1, 16 do if turtle.getItemCount(i) > 0 then filled = filled + 1 end end
  return filled / 16
end

function util.firstPeripheral(ptype)
  local sides = { "top", "bottom", "left", "right", "front", "back" }
  for i = 1, #sides do
    if peripheral.getType(sides[i]) == ptype then return peripheral.wrap(sides[i]), sides[i] end
  end
  return nil, nil
end

function util.clear(t)
  t = t or term
  t.clear()
  t.setCursorPos(1, 1)
end

return util
