-- health.lua
-- storage health/audit tool
--
-- Run:
--   health
--
-- Checks:
--   - config files exist
--   - special chests are online
--   - storage columns have 3 chests
--   - mapped chests are online
--   - duplicate assignments
--   - mixed-item columns
--   - rough fullness per column
--
-- Also:
--   - Displays local warning summary on attached monitor

-- ============================================================
-- PATHS
-- ============================================================

local CONFIG_PATH  = "/data/config.cfg"
local COLUMNS_PATH = "/data/columns.cfg"

-- ============================================================
-- BASIC UI
-- ============================================================

local function color(c)
  if term.isColor and term.isColor() then
    term.setTextColor(c)
  end
end

local function reset()
  color(colors.white)
end

local function ok(msg)
  color(colors.green)
  print("[OK] " .. msg)
  reset()
end

local function warn(msg)
  color(colors.yellow)
  print("[WARN] " .. msg)
  reset()
end

local function err(msg)
  color(colors.red)
  print("[ERR] " .. msg)
  reset()
end

local function info(msg)
  color(colors.lightGray)
  print("[INFO] " .. msg)
  reset()
end

-- ============================================================
-- HELPERS
-- ============================================================

local function trim(s)
  if not s then return "" end
  return tostring(s):match("^%s*(.-)%s*$")
end

local function chestNum(name)
  if not name then return "?" end
  return tostring(name):match("_(%d+)$") or "?"
end

local function isOnline(name)
  return type(name) == "string" and peripheral.wrap(name) ~= nil
end

local function centerText(text, width)
  text = tostring(text)
  local pad = math.max(0, width - #text)
  local left = math.floor(pad / 2)
  local right = pad - left
  return string.rep(" ", left) .. text .. string.rep(" ", right)
end

local function countKeys(t)
  local n = 0
  for _ in pairs(t) do n = n + 1 end
  return n
end

local function firstKey(t)
  for k in pairs(t) do return k end
  return nil
end

local function mergeCounts(target, source)
  for k, v in pairs(source) do
    target[k] = (target[k] or 0) + v
  end
end

-- ============================================================
-- MONITOR DISPLAY
-- ============================================================

local function getMonitor()
  local mon = peripheral.find("monitor")
  if not mon then return nil end

  pcall(mon.setTextScale, 0.5)
  pcall(mon.setBackgroundColor, colors.black)
  pcall(mon.setTextColor, colors.white)

  return mon
end

local function displayWarningsOnMonitor(warnings)
  local mon = getMonitor()
  if not mon then
    warn("No monitor found for warning display.")
    return false
  end

  mon.clear()
  mon.setCursorPos(1, 1)

  local oldTerm = term.redirect(mon)
  local w, h = term.getSize()

  term.setBackgroundColor(colors.black)
  term.clear()

  term.setTextColor(colors.yellow)
  term.setCursorPos(1, 1)
  term.write(centerText("STORAGE HEALTH", w))

  term.setTextColor(colors.white)
  term.setCursorPos(1, 2)
  term.write(string.rep("-", w))

  if #warnings == 0 then
    term.setTextColor(colors.green)
    term.setCursorPos(1, 4)
    term.write(centerText("All systems healthy", w))

    term.setTextColor(colors.lightGray)
    term.setCursorPos(1, 6)
    term.write(centerText("No warnings found", w))

    term.redirect(oldTerm)
    return true
  end

  term.setTextColor(colors.red)
  term.setCursorPos(1, 4)
  term.write("WARNINGS: " .. tostring(#warnings))

  local line = 6
  term.setTextColor(colors.yellow)

  for i, msg in ipairs(warnings) do
    if line > h then
      break
    end

    term.setCursorPos(1, line)

    local text = tostring(i) .. ". " .. tostring(msg)
    if #text > w then
      text = text:sub(1, math.max(1, w - 3)) .. "..."
    end

    term.write(text)
    line = line + 1
  end

  if #warnings > (h - 5) then
    term.setTextColor(colors.lightGray)
    term.setCursorPos(1, h)
    term.write("More warnings in terminal")
  end

  term.redirect(oldTerm)
  return true
end

-- ============================================================
-- CONFIG LOADING
-- ============================================================

local function loadConfig()
  local cfg = {}

  if not fs.exists(CONFIG_PATH) then
    return nil, "Missing " .. CONFIG_PATH
  end

  local f = fs.open(CONFIG_PATH, "r")
  if not f then
    return nil, "Could not open " .. CONFIG_PATH
  end

  local line = f.readLine()
  while line do
    local clean = trim(line)

    if clean ~= "" and not clean:match("^#") then
      local k, v = clean:match("^%s*(.-)%s*=%s*(.-)%s*$")

      if k and v and k ~= "" then
        cfg[trim(k)] = trim(v)
      end
    end

    line = f.readLine()
  end

  f.close()
  return cfg
end

local function loadColumns()
  if not fs.exists(COLUMNS_PATH) then
    return nil, "Missing " .. COLUMNS_PATH
  end

  local columns = {}
  local f = fs.open(COLUMNS_PATH, "r")
  if not f then
    return nil, "Could not open " .. COLUMNS_PATH
  end

  local line = f.readLine()
  while line do
    local clean = trim(line)

    if clean ~= "" and not clean:match("^#") and clean:find("|", 1, true) then
      local bottom, mid, top =
        clean:match("^%s*(.-)%s*|%s*(.-)%s*|%s*(.-)%s*$")

      bottom = trim(bottom)
      mid = trim(mid)
      top = trim(top)

      table.insert(columns, {
        bottom = bottom,
        mid = mid,
        top = top,
      })
    end

    line = f.readLine()
  end

  f.close()

  if #columns == 0 then
    return nil, "No columns found in " .. COLUMNS_PATH
  end

  return columns
end

-- ============================================================
-- INVENTORY STATS
-- ============================================================

local function getInventoryStats(name)
  local inv = peripheral.wrap(name)

  if not inv or not inv.list then
    return {
      online = false,
      usedSlots = 0,
      totalSlots = 0,
      itemCounts = {},
      totalItems = 0,
    }
  end

  local totalSlots = 0

  if inv.size then
    local okSize, size = pcall(inv.size)
    if okSize and size then
      totalSlots = size
    end
  end

  local itemCounts = {}
  local usedSlots = 0
  local totalItems = 0

  local okList, items = pcall(inv.list)

  if okList and items then
    for _, stack in pairs(items) do
      if stack then
        usedSlots = usedSlots + 1
        totalItems = totalItems + (stack.count or 0)

        local itemName = stack.name or "unknown"
        itemCounts[itemName] = (itemCounts[itemName] or 0) + (stack.count or 0)
      end
    end
  end

  return {
    online = true,
    usedSlots = usedSlots,
    totalSlots = totalSlots,
    itemCounts = itemCounts,
    totalItems = totalItems,
  }
end

-- ============================================================
-- COLUMN REPORT
-- ============================================================

local function printColumnReport(i, col)
  local names = {
    bottom = col.bottom,
    mid = col.mid,
    top = col.top,
  }

  local totalSlots = 0
  local usedSlots = 0
  local totalItems = 0
  local mergedItems = {}
  local offline = false

  for _, name in pairs(names) do
    local stats = getInventoryStats(name)

    if not stats.online then
      offline = true
    end

    totalSlots = totalSlots + stats.totalSlots
    usedSlots = usedSlots + stats.usedSlots
    totalItems = totalItems + stats.totalItems

    mergeCounts(mergedItems, stats.itemCounts)
  end

  local itemTypes = countKeys(mergedItems)
  local mainItem = firstKey(mergedItems) or "(empty)"

  local fullness = 0
  if totalSlots > 0 then
    fullness = math.floor((usedSlots / totalSlots) * 100)
  end

  local status = "OK"
  local statusColor = colors.green

  if offline then
    status = "OFFLINE"
    statusColor = colors.red
  elseif itemTypes > 1 then
    status = "MIXED"
    statusColor = colors.yellow
  elseif fullness >= 90 then
    status = "FULL"
    statusColor = colors.yellow
  elseif itemTypes == 0 then
    status = "EMPTY"
    statusColor = colors.lightGray
  end

  color(statusColor)
  print(string.format(
    "%-5d %-8s %-8s %-8s %-8s %-8s %s",
    i,
    chestNum(col.bottom),
    chestNum(col.mid),
    chestNum(col.top),
    tostring(fullness) .. "%",
    status,
    mainItem
  ))
  reset()

  return {
    offline = offline,
    mixed = itemTypes > 1,
    full = fullness >= 90,
    empty = itemTypes == 0,
    fullness = fullness,
    mainItem = mainItem,
    totalItems = totalItems,
  }
end

-- ============================================================
-- MAIN
-- ============================================================

local function main()
  term.setBackgroundColor(colors.black)
  term.clear()
  term.setCursorPos(1, 1)

  local warnings = {}

  color(colors.yellow)
  print("=== STORAGE HEALTH CHECK ===")
  reset()
  print("")

  local cfg, cfgErr = loadConfig()
  if not cfg then
    err(cfgErr)
    table.insert(warnings, cfgErr)
    displayWarningsOnMonitor(warnings)
    return
  end

  local columns, colErr = loadColumns()
  if not columns then
    err(colErr)
    table.insert(warnings, colErr)
    displayWarningsOnMonitor(warnings)
    return
  end

  ok("Loaded config.cfg")
  ok("Loaded columns.cfg")
  info("Columns: " .. tostring(#columns))
  print("")

  -- ============================================================
  -- ASSIGNMENT / DUPLICATE CHECK
  -- ============================================================

  local assigned = {}
  local duplicateCount = 0

  local function addAssignment(name, label)
    if not name or name == "" then
      local msg = label .. " is blank"
      err(msg)
      table.insert(warnings, msg)
      return
    end

    if assigned[name] then
      local msg = "Duplicate chest " .. chestNum(name)

      err("Duplicate assignment: " .. tostring(name))
      err("  Used by: " .. tostring(assigned[name]))
      err("  Used by: " .. tostring(label))

      table.insert(warnings, msg)
      duplicateCount = duplicateCount + 1
    else
      assigned[name] = label
    end
  end

  -- ============================================================
  -- SPECIAL CHESTS
  -- ============================================================

  color(colors.cyan)
  print("Special chests:")
  reset()

  for k, v in pairs(cfg) do
    addAssignment(v, "special " .. tostring(k))

    if isOnline(v) then
      ok(tostring(k) .. " online: chest " .. chestNum(v))
    else
      local msg = tostring(k) .. " chest offline"
      err(msg .. ": " .. tostring(v))
      table.insert(warnings, msg)
    end
  end

  print("")

  -- ============================================================
  -- STORAGE ASSIGNMENTS
  -- ============================================================

  for i, col in ipairs(columns) do
    addAssignment(col.bottom, "column " .. i .. " bottom")
    addAssignment(col.mid,    "column " .. i .. " mid")
    addAssignment(col.top,    "column " .. i .. " top")
  end

  -- ============================================================
  -- COLUMN REPORT
  -- ============================================================

  color(colors.cyan)
  print("Column summary:")
  reset()

  print(string.format(
    "%-5s %-8s %-8s %-8s %-8s %-8s %s",
    "COL",
    "BOTTOM",
    "MID",
    "TOP",
    "USED",
    "STATUS",
    "ITEM"
  ))

  print(string.rep("-", 74))

  local offlineCols = 0
  local mixedCols = 0
  local fullCols = 0
  local emptyCols = 0

  for i, col in ipairs(columns) do
    local result = printColumnReport(i, col)

    if result.offline then
      offlineCols = offlineCols + 1
      table.insert(warnings, "Column " .. tostring(i) .. " offline")
    end

    if result.mixed then
      mixedCols = mixedCols + 1
      table.insert(warnings, "Column " .. tostring(i) .. " mixed items")
    end

    if result.full then
      fullCols = fullCols + 1
      table.insert(warnings, "Column " .. tostring(i) .. " nearly full")
    end

    if result.empty then
      emptyCols = emptyCols + 1
    end
  end

  -- ============================================================
  -- SUMMARY
  -- ============================================================

  print("")
  color(colors.yellow)
  print("Summary:")
  reset()

  print(" Offline columns:   " .. tostring(offlineCols))
  print(" Mixed columns:     " .. tostring(mixedCols))
  print(" Nearly full cols:  " .. tostring(fullCols))
  print(" Empty columns:     " .. tostring(emptyCols))
  print(" Duplicates:        " .. tostring(duplicateCount))
  print(" Total warnings:    " .. tostring(#warnings))
  print("")

  if offlineCols == 0 and mixedCols == 0 and duplicateCount == 0 then
    ok("Storage map looks sane.")
  else
    warn("Storage map needs attention.")
    warn("Use column_edit to repair changed or duplicate chests.")
  end

  print("")

  if displayWarningsOnMonitor(warnings) then
    ok("Health summary sent to monitor.")
  end
end

main()