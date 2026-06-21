-- item_scan.lua
-- one-off diagnostic: dump every item ID sitting in a specific
-- chest to the monitor. the chest number below is hardcoded from
-- whatever was being debugged at the time - change it before
-- reusing this for a different chest.

local chest_name = "minecraft:ironchest_obsidian_14"
local mon = peripheral.find("monitor")
if not mon then print("No monitor found"); return end

mon.setTextScale(0.5)
mon.setBackgroundColor(colors.black)
mon.setTextColor(colors.white)
mon.clear()
mon.setCursorPos(1,1)

local chest = peripheral.wrap(chest_name)
if not chest then
  mon.write("No chest found"); return
end

local ok, items = pcall(chest.list)
if not ok or not items or not next(items) then
  mon.write("Chest empty"); return
end

-- Sort by name then damage
local sorted = {}
for slot, stack in pairs(items) do
  table.insert(sorted, stack)
end
table.sort(sorted, function(a,b)
  if a.name == b.name then
    return (a.damage or 0) < (b.damage or 0)
  end
  return a.name < b.name
end)

local w, h = mon.getSize()
local y = 1
for _, stack in ipairs(sorted) do
  if y > h then break end
  mon.setCursorPos(1, y)
  local line = string.format("d=%-5d %s",
    stack.damage or 0, stack.name)
  mon.write(line:sub(1, w))
  y = y + 1
end

mon.setCursorPos(1, h)
mon.setTextColor(colors.lightGray)
mon.write("Total: " .. #sorted)
print("Done - check monitor")
