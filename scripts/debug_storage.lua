-- debug_storage.lua
-- raw inventory dump - every unique item across every obsidian
-- chest on the network, regardless of whether it's actually
-- mapped in storage.cfg yet. useful for sanity-checking what
-- physically exists before running discover.

local printer = require("/scripts/lib/printer")
local monitor = require("/scripts/lib/monitor")
local MODEM   = "back"

if not rednet.isOpen(MODEM) then pcall(rednet.open, MODEM) end

local has_printer = printer.open("Storage Dump")
local has_monitor = monitor.open("STORAGE CONTENTS")

local function out(line)
  if has_printer then printer.writeLine(line or "")
  else print(line or "") end
end

-- Find all obsidian chests
local chests = {}
for _, name in ipairs(peripheral.getNames()) do
  if name:find("ironchest_obsidian") then
    local num = tonumber(name:match("_(%d+)$"))
    if num then table.insert(chests, {name=name, num=num}) end
  end
end

if #chests == 0 then
  print("No obsidian chests found.")
  print("Check modem + cable connections.")
  if has_monitor then
    monitor.addLine("No chests found!", colors.red)
    monitor.addLine("Check connections", colors.yellow)
    monitor.render()
  end
  if has_printer then printer.close() end
  return
end

table.sort(chests, function(a,b) return a.num < b.num end)
print("Found " .. #chests .. " chests - scanning...")

-- Collect unique items using item_id:damage:displayname as key
-- This correctly differentiates NBT items like vis crystals
local items_found = {}
local seen = {}

local i = 1
while i <= #chests do
  local bot = chests[i]
  local mid = chests[i+1]
  local top = chests[i+2]

  if mid and top and
     mid.num == bot.num+1 and
     top.num == bot.num+2 then

    local chest = peripheral.wrap(bot.name)
    if chest then
      local ok_list, items = pcall(chest.list)
      if ok_list and items then
        for slot, stack in pairs(items) do
          local ok_meta, meta = pcall(chest.getItemMeta, slot)
          local display = stack.name
          local damage  = 0
          if ok_meta and meta then
            damage  = meta.damage or 0
            display = meta.displayName or meta.name
          end
          local key = stack.name ..
                      ":" .. tostring(damage) ..
                      ":" .. display:lower():gsub("%s+", "_")
          if not seen[key] then
            seen[key] = true
            table.insert(items_found, {
              key     = key,
              display = display,
              mod     = stack.name:match("^(.-):")  or "minecraft",
              chest   = bot.name,
            })
          end
          break
        end
      end
    end
    i = i + 3
  else
    i = i + 1
  end
end

table.sort(items_found, function(a,b)
  if a.mod ~= b.mod then return a.mod < b.mod end
  return a.display < b.display
end)

print("Found " .. #items_found .. " unique items")
print("Printing...")

-- Print to paper
out("STORAGE CONTENTS")
out("Time: " .. tostring(os.time()))
out(string.rep("-", 25))
out("")

local current_mod = nil
for _, item in ipairs(items_found) do
  if item.mod ~= current_mod then
    if current_mod then out("") end
    out("[" .. item.mod:upper():sub(1,23) .. "]")
    current_mod = item.mod
  end
  out("  " .. item.display:sub(1, 23))
end

out("")
out(string.rep("-", 25))
out("Total: " .. #items_found)

if has_printer then printer.close() end

-- Monitor: show item list by mod
if has_monitor then
  monitor.addLine("Total: " .. #items_found, colors.white)
  monitor.addLine("")
  local cur_mod = nil
  for _, item in ipairs(items_found) do
    if item.mod ~= cur_mod then
      if cur_mod then monitor.addLine("") end
      monitor.addLine("[" .. item.mod:upper():sub(1,20) .. "]",
        colors.yellow)
      cur_mod = item.mod
    end
    monitor.addLine("  " .. item.display:sub(1, 35))
  end
  monitor.render()
end
