-- storage_log.lua
-- current stock levels for everything in storage.cfg, with
-- filtering options for spotting low or near-full columns.
--
-- usage:
--   storage_log              show all
--   storage_log iron         filter by name/mod/key
--   storage_log --low        low stock only
--   storage_log --high       high/overflow only

local storage = require("/scripts/lib/storage")
local printer = require("/scripts/lib/printer")
local monitor = require("/scripts/lib/monitor")

local args      = {...}
local filter    = nil
local low_only  = false
local high_only = false

for _, a in ipairs(args) do
  if a == "--low"      then low_only  = true
  elseif a == "--high" then high_only = true
  else filter = a:lower() end
end

local LOW  = 10
local HIGH = 85

local title = "Stock Log"
if filter    then title = "Stock: " .. filter end
if low_only  then title = "Stock LOW"  end
if high_only then title = "Stock HIGH" end

local has_printer = printer.open(title)
local has_monitor = monitor.open("STOCK LOG")

local function out(line)
  if has_printer then printer.writeLine(line or "")
  else print(line or "") end
end

local store = storage.load()
if not next(store) then
  print("storage.cfg empty - run: discover")
  if has_printer then printer.close() end
  if has_monitor then
    monitor.addLine("storage.cfg empty", colors.red)
    monitor.addLine("Run: discover", colors.yellow)
    monitor.render()
  end
  return
end

local results = {}
for key, data in pairs(store) do
  if not filter or
     data.display:lower():find(filter,1,true) or
     key:lower():find(filter,1,true) or
     data.mod:lower():find(filter,1,true) then
    local total, pct, overflow = storage.getStock(data)
    local show = true
    if low_only  and pct > LOW  and not overflow then show = false end
    if high_only and pct < HIGH and not overflow then show = false end
    if show then
      table.insert(results, {
        display  = data.display,
        mod      = data.mod,
        total    = total,
        pct      = pct,
        overflow = overflow,
      })
    end
  end
end

table.sort(results, function(a,b)
  if a.mod ~= b.mod then return a.mod < b.mod end
  return a.display < b.display
end)

out(title:upper())
out(string.rep("-", 25))
out("")

local low_n, high_n, overflow_n = 0, 0, 0
local current_mod = nil
local monitor_items = {}  -- HIGH and OVERFLOW items for monitor

for _, r in ipairs(results) do
  if r.mod ~= current_mod then
    if current_mod then out("") end
    out("[" .. r.mod:upper():sub(1,23) .. "]")
    current_mod = r.mod
  end

  local tag = ""
  if r.overflow        then tag=" OVR"; overflow_n=overflow_n+1
  elseif r.pct>=HIGH   then tag=" HI";  high_n=high_n+1
  elseif r.pct<=LOW    then tag=" LO";  low_n=low_n+1
  end

  local name = ("  " .. r.display):sub(1, 18)
  out(string.format("%-18s %3d%%%s", name, r.pct, tag))

  -- Collect HIGH and OVERFLOW for monitor
  if r.overflow then
    table.insert(monitor_items, {
      text  = r.display:sub(1,25) .. " OVERFLOW",
      color = colors.red,
    })
  elseif r.pct >= HIGH then
    table.insert(monitor_items, {
      text  = r.display:sub(1,25) .. " " .. r.pct .. "%",
      color = colors.orange,
    })
  end
end

out("")
out(string.rep("-", 25))
out(string.format("Items: %d", #results))
if low_n      > 0 then out("Low:      " .. low_n)      end
if high_n     > 0 then out("High:     " .. high_n)     end
if overflow_n > 0 then out("Overflow: " .. overflow_n) end

if has_printer then printer.close() end

-- Monitor: show HIGH and OVERFLOW items only
if has_monitor then
  if #monitor_items == 0 then
    monitor.addLine("All items normal", colors.green)
    monitor.addLine("")
    monitor.addLine(string.format(
      "Items: %d  Low: %d", #results, low_n))
  else
    monitor.addLine("NEEDS ATTENTION:", colors.yellow)
    monitor.addLine("")
    for _, item in ipairs(monitor_items) do
      monitor.addLine("  " .. item.text, item.color)
    end
    monitor.addLine("")
    monitor.addLine(string.rep("-", 40))
    if overflow_n > 0 then
      monitor.addLine("Overflow: " .. overflow_n, colors.red)
    end
    if high_n > 0 then
      monitor.addLine("High:     " .. high_n, colors.orange)
    end
  end
  monitor.render()
end
