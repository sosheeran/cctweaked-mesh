-- discover.lua
-- scans every storage column, figures out what item lives in it
-- (using NBT-aware metadata so it correctly tells apart things
-- like differently-charged vis crystals that share an item ID),
-- and writes the result to storage.cfg. run this after physically
-- adding new columns or after setup.

local storage = require("/scripts/lib/storage")
local printer = require("/scripts/lib/printer")
local monitor = require("/scripts/lib/monitor")
local MODEM   = "back"

if not rednet.isOpen(MODEM) then pcall(rednet.open, MODEM) end

local has_printer = printer.open("Discover")
local has_monitor = monitor.open("DISCOVER")

local function out(line, mon_color)
  if has_printer then printer.writeLine(line or "")
  else print(line or "") end
  if has_monitor and mon_color then
    monitor.addLine(line or "", mon_color)
  end
end

local function loadConfig()
  local cfg = {}
  if not fs.exists("/data/config.cfg") then
    return nil, "config.cfg not found - run setup first"
  end
  local f = fs.open("/data/config.cfg", "r")
  local line = f.readLine()
  while line do
    local k, v = line:match("^%s*(.-)%s*=%s*(.-)%s*$")
    if k and v and k ~= "" then cfg[k] = v end
    line = f.readLine()
  end
  f.close()
  if not cfg.send then return nil, "send chest not configured" end
  return cfg, nil
end

local function loadColumns()
  local columns = {}
  if not fs.exists("/data/columns.cfg") then
    return nil, "columns.cfg not found - run setup first"
  end
  local f = fs.open("/data/columns.cfg", "r")
  local line = f.readLine()
  while line do
    if not line:match("^#") and line:match("|") then
      local bot, mid, top = line:match(
        "^%s*(.-)%s*|%s*(.-)%s*|%s*(.-)%s*$")
      if bot and mid and top and
         bot ~= "" and mid ~= "" and top ~= "" then
        table.insert(columns, {bottom=bot, mid=mid, top=top})
      end
    end
    line = f.readLine()
  end
  f.close()
  if #columns == 0 then
    return nil, "No columns defined - run setup first"
  end
  return columns, nil
end

local function validate(cfg, columns)
  local issues = {}
  -- Note: bash and buffer are ender chests now
  -- just warn if offline, not fatal
  if not peripheral.wrap(cfg.bash) then
    table.insert(issues, "BASH ender chest offline: " ..
      cfg.bash) end
  if not peripheral.wrap(cfg.send) then
    table.insert(issues, "BUFFER ender chest offline: " ..
      cfg.send) end
  if cfg.bash == cfg.send then
    table.insert(issues, "Bash and buffer are same chest!") end
  -- Check storage columns (obsidian chests)
  for i, col in ipairs(columns) do
    for pos, chest in pairs(
      {bottom=col.bottom, mid=col.mid, top=col.top}) do
      if chest ~= "" and not peripheral.wrap(chest) then
        table.insert(issues,
          "Col "..i.." "..pos.." offline: "..chest) end
    end
  end
  return issues
end

-- Main
print("=== DISCOVER ===")
print("")

local cfg, cfg_err = loadConfig()
if not cfg then
  out("ERROR: " .. cfg_err, colors.red)
  if has_monitor then monitor.render() end
  if has_printer then printer.close() end
  return
end

local columns, col_err = loadColumns()
if not columns then
  out("ERROR: " .. col_err, colors.red)
  if has_monitor then monitor.render() end
  if has_printer then printer.close() end
  return
end

print("Bash:    " .. cfg.bash)
print("Buffer:  " .. cfg.send)
print("Columns: " .. #columns)
print("")

local issues = validate(cfg, columns)
if #issues > 0 then
  print("WARNINGS:")
  for _, issue in ipairs(issues) do
    print("  ! " .. issue)
  end
  local fatal = false
  for _, issue in ipairs(issues) do
    if issue:find("same chest") or issue:find("in column") then
      fatal = true
    end
  end
  if fatal then
    out("Fatal errors - run setup to fix", colors.red)
    if has_monitor then monitor.render() end
    if has_printer then printer.close() end
    return
  end
  print("")
end

local store   = storage.load()
local found_items = {}  -- for monitor display
local found, skipped, empty, errors = 0, 0, 0, 0

for col_idx, col in ipairs(columns) do
  local chest = peripheral.wrap(col.bottom)
  if not chest then
    print("OFFLINE: col " .. col_idx)
    errors = errors + 1
  else
    local meta = nil
    local ok_list, items = pcall(chest.list)
    if ok_list and items then
      for slot, _ in pairs(items) do
        local ok_meta, m = pcall(chest.getItemMeta, slot)
        if ok_meta and m then meta = m; break end
      end
    end

    if meta then
      local damage   = meta.damage or 0
      local display  = meta.displayName or meta.name
      local mod      = meta.name:match("^(.-):")  or "unknown"
      local base_key = storage.makeKey(meta.name, damage)
      local key      = base_key

      if store[key] and store[key].chest ~= col.bottom then
        key = base_key .. ":" ..
              display:lower():gsub("[%s/%-]", "_")
      end

      if store[key] then
        print("SKIP: " .. display .. " (mapped)")
        skipped = skipped + 1
      else
        store[key] = {
          chest   = col.bottom,
          mid     = col.mid,
          top     = col.top,
          display = display,
          mod     = mod,
        }
        print("FOUND: " .. display)
        table.insert(found_items, display)
        found = found + 1
      end
    else
      print("EMPTY: col " .. col_idx)
      empty = empty + 1
    end
  end
end

print("")
print(string.rep("-", 25))
print("New:     " .. found)
print("Skipped: " .. skipped)
print("Empty:   " .. empty)
if errors > 0 then print("Errors:  " .. errors) end

-- Print to paper
if has_printer then
  printer.writeLine("DISCOVER RESULTS")
  printer.writeLine(string.rep("-", 25))
  printer.writeLine("Columns: " .. #columns)
  printer.writeLine("New:     " .. found)
  printer.writeLine("Skipped: " .. skipped)
  printer.writeLine("Empty:   " .. empty)
  if errors > 0 then
    printer.writeLine("Errors:  " .. errors)
  end
  if #found_items > 0 then
    printer.writeLine("")
    printer.writeLine("NEW ITEMS FOUND:")
    for _, name in ipairs(found_items) do
      printer.writeLine("  " .. name)
    end
  end
  printer.close()
end

-- Monitor: show found items or summary
if has_monitor then
  monitor.addLine("Columns: " .. #columns)
  monitor.addLine("")
  if #found_items > 0 then
    monitor.addLine("NEW ITEMS:", colors.green)
    for _, name in ipairs(found_items) do
      monitor.addLine("  " .. name, colors.green)
    end
  else
    monitor.addLine("No new items found", colors.yellow)
    monitor.addLine("Skipped: " .. skipped)
  end
  monitor.addLine("")
  monitor.addLine(string.rep("-", 40))
  if errors > 0 then
    monitor.addLine("Errors: " .. errors, colors.red)
  else
    monitor.addLine("Done", colors.green)
  end
  monitor.render()
end

if found > 0 then
  if storage.save(store) then
    print("Saved to storage.cfg")
  else
    print("ERROR: could not save!")
  end
else
  print("Nothing new to save")
end
