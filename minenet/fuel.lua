local fuel = {}

fuel.preferredNames = {
  ["minecraft:coal"] = true,
  ["minecraft:charcoal"] = true,
  ["minecraft:coal_block"] = true,
  ["minecraft:lava_bucket"] = true,
  ["minecraft:blaze_rod"] = true
}

function fuel.level()
  local value = turtle.getFuelLevel()
  if value == "unlimited" then return 1000000000 end
  return value or 0
end

function fuel.rawLevel()
  return turtle.getFuelLevel()
end

function fuel.limit()
  local value = turtle.getFuelLimit()
  if value == "unlimited" then return 1000000000 end
  return value or 0
end

function fuel.isPreferredName(name)
  return name and fuel.preferredNames[name] == true
end

function fuel.slotName(slot)
  local detail = turtle.getItemDetail(slot)
  if detail then return detail.name end
  return nil
end

function fuel.canRefuelSlot(slot)
  if turtle.getItemCount(slot) <= 0 then return false end
  local old = turtle.getSelectedSlot()
  turtle.select(slot)
  local ok = turtle.refuel(0)
  turtle.select(old)
  return ok
end

function fuel.isPreferredFuelSlot(slot)
  if turtle.getItemCount(slot) <= 0 then return false end
  local name = fuel.slotName(slot)
  if fuel.isPreferredName(name) then return true end
  return false
end

function fuel.isAnyFuelSlot(slot)
  return fuel.canRefuelSlot(slot)
end

function fuel.countFuelItems()
  local count = 0
  local slots = 0
  for i = 1, 16 do
    if fuel.canRefuelSlot(i) then
      count = count + turtle.getItemCount(i)
      slots = slots + 1
    end
  end
  return count, slots
end

local function consumeSlot(slot, target)
  local old = turtle.getSelectedSlot()
  turtle.select(slot)
  local consumed = 0
  while turtle.getItemCount(slot) > 0 and fuel.level() < target do
    if not turtle.refuel(1) then break end
    consumed = consumed + 1
  end
  turtle.select(old)
  return consumed
end

function fuel.tryRefuelTo(target, allowAnyFuel)
  if turtle.getFuelLevel() == "unlimited" then return true, 0 end
  target = math.min(target or 0, fuel.limit())
  local consumed = 0

  for i = 1, 16 do
    if fuel.isPreferredFuelSlot(i) and fuel.level() < target then
      consumed = consumed + consumeSlot(i, target)
    end
  end

  if allowAnyFuel then
    for i = 1, 16 do
      if fuel.level() >= target then break end
      if fuel.canRefuelSlot(i) then consumed = consumed + consumeSlot(i, target) end
    end
  end

  return fuel.level() >= target, consumed
end

function fuel.anyFuelAvailable()
  for i = 1, 16 do
    if fuel.canRefuelSlot(i) then return true end
  end
  return false
end

return fuel
