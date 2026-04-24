local util = {}

util.headingNames = { "N", "E", "S", "W" }
util.colorList = {
  colors.red, colors.orange, colors.yellow, colors.lime,
  colors.green, colors.cyan, colors.lightBlue, colors.blue,
  colors.purple, colors.magenta, colors.pink, colors.white
}
util.colorNames = {
  [colors.red] = "red",
  [colors.orange] = "orange",
  [colors.yellow] = "yellow",
  [colors.lime] = "lime",
  [colors.green] = "green",
  [colors.cyan] = "cyan",
  [colors.lightBlue] = "ltblue",
  [colors.blue] = "blue",
  [colors.purple] = "purple",
  [colors.magenta] = "magenta",
  [colors.pink] = "pink",
  [colors.white] = "white"
}

local DIRS = {
  [0] = { x = 0, z = -1 },
  [1] = { x = 1, z = 0 },
  [2] = { x = 0, z = 1 },
  [3] = { x = -1, z = 0 }
}

local function normHeading(h)
  h = tonumber(h) or 0
  h = h % 4
  if h < 0 then h = h + 4 end
  return h
end

function util.normHeading(h)
  return normHeading(h)
end

function util.headingName(h)
  h = normHeading(h)
  return util.headingNames[h + 1] or "?"
end

function util.dirForHeading(h)
  h = normHeading(h)
  return { x = DIRS[h].x, z = DIRS[h].z }
end

function util.posKey(pos)
  if not pos then return "?" end
  return tostring(pos.x) .. "," .. tostring(pos.y) .. "," .. tostring(pos.z)
end

function util.formatPos(pos)
  if not pos then return "?" end
  return tostring(pos.x or "?") .. "," .. tostring(pos.y or "?") .. "," .. tostring(pos.z or "?")
end

function util.copy(value)
  if type(value) ~= "table" then return value end
  local result = {}
  for k, v in pairs(value) do result[k] = util.copy(v) end
  return result
end

function util.mergeDefaults(value, defaults)
  value = value or {}
  for k, v in pairs(defaults or {}) do
    if type(v) == "table" then
      if type(value[k]) ~= "table" then value[k] = {} end
      util.mergeDefaults(value[k], v)
    elseif value[k] == nil then
      value[k] = v
    end
  end
  return value
end

function util.dist(a, b)
  if not a or not b then return 999999 end
  return math.abs((a.x or 0) - (b.x or 0)) + math.abs((a.y or 0) - (b.y or 0)) + math.abs((a.z or 0) - (b.z or 0))
end

function util.inventoryRatio()
  if not turtle then return 0 end
  local filled = 0
  for i = 1, 16 do
    if turtle.getItemCount(i) > 0 then filled = filled + 1 end
  end
  return filled / 16
end

function util.inventoryFreeSlots()
  if not turtle then return 0 end
  local free = 0
  for i = 1, 16 do
    if turtle.getItemCount(i) == 0 then free = free + 1 end
  end
  return free
end

function util.firstPeripheral(peripheralType)
  local names = nil
  if peripheral.getNames then names = peripheral.getNames() end
  if names then
    for i = 1, #names do
      if peripheral.getType(names[i]) == peripheralType then return peripheral.wrap(names[i]), names[i] end
    end
  end
  local sides = { "top", "bottom", "left", "right", "front", "back" }
  for i = 1, #sides do
    if peripheral.getType(sides[i]) == peripheralType then return peripheral.wrap(sides[i]), sides[i] end
  end
  return nil, nil
end

function util.clear(target)
  target = target or term
  target.setBackgroundColor(colors.black)
  target.setTextColor(colors.white)
  target.clear()
  target.setCursorPos(1, 1)
end

function util.safeColor(target, color)
  if target and target.setTextColor and color then target.setTextColor(color) end
end

function util.statusColor(status)
  if status == "error" or status == "out_of_fuel" then return colors.red end
  if status == "fuel_station_empty" or status == "inventory_full" or status == "dropoff_full" or status == "recall_blocked" then return
    colors.orange end
  if status == "mining" then return colors.lime end
  if status == "moving" or status == "returning" or status == "to_fuel" or status == "waiting_path" or status == "waiting_fuel" or status == "waiting_dropoff" then return
    colors.cyan end
  if status == "refueling" or status == "unloading" or status == "paused" or status == "resetting" or status == "reset_sent" then return
    colors.yellow end
  if status == "offline" then return colors.gray or colors.grey end
  return colors.white
end

function util.writeAt(target, x, y, text, color)
  target.setCursorPos(x, y)
  if color then target.setTextColor(color) end
  target.write(tostring(text))
end

function util.readNumber(prompt, defaultValue)
  while true do
    if prompt then write(prompt) end
    local value = read()
    if value == "" and defaultValue ~= nil then return defaultValue end
    local n = tonumber(value)
    if n ~= nil then return n end
    print("Enter a number.")
  end
end

function util.readHeading(prompt, defaultValue)
  print(prompt or "Heading: 0=N 1=E 2=S 3=W")
  local value = util.readNumber("> ", defaultValue or 0)
  return normHeading(value)
end

function util.promptPos(title, defaultPos)
  print(title)
  if gps and gps.locate then
    write("Use current GPS position? y/N: ")
    local answer = read()
    if answer == "y" or answer == "Y" then
      local x, y, z = gps.locate(5)
      if x then
        return { x = math.floor(x + 0.5), y = math.floor(y + 0.5), z = math.floor(z + 0.5) }
      end
      print("GPS failed; enter manually.")
    end
  end
  local x = util.readNumber("x" .. (defaultPos and " [" .. tostring(defaultPos.x) .. "]" or "") .. ": ",
    defaultPos and defaultPos.x or nil)
  local y = util.readNumber("y" .. (defaultPos and " [" .. tostring(defaultPos.y) .. "]" or "") .. ": ",
    defaultPos and defaultPos.y or nil)
  local z = util.readNumber("z" .. (defaultPos and " [" .. tostring(defaultPos.z) .. "]" or "") .. ": ",
    defaultPos and defaultPos.z or nil)
  return { x = x, y = y, z = z }
end

return util
