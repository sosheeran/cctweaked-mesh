-- column_edit.lua
-- manual repair tool for columns.cfg
--
-- Use this when a modem/chest peripheral name changes.
-- This edits /data/columns.cfg without rediscovering the entire warehouse.
--
-- Column layout:
--   bottom | mid | top
--
-- Example:
--   ironchest_obsidian_1 | ironchest_obsidian_2 | ironchest_obsidian_3
--
-- Run:
--   column_edit

-- ============================================================
-- SETTINGS
-- ============================================================

local CONFIG_PATH  = "/data/config.cfg"
local COLUMNS_PATH = "/data/columns.cfg"
local STORAGE_PATH = "/data/storage.cfg"

local CHEST_MATCH = "ironchest_obsidian"

local W, H = term.getSize()

local printer = nil
do
  local ok, mod = pcall(require, "/scripts/lib/printer")
  if ok then
    printer = mod
  end
end

-- ============================================================
-- BASIC UI
-- ============================================================

local function setColor(color)
  if term.isColor and term.isColor() then
    term.setTextColor(color)
  end
end

local function centerText(text, width)
  text = tostring(text)
  local pad = math.max(0, width - #text)
  local left = math.floor(pad / 2)
  local right = pad - left
  return string.rep(" ", left) .. text .. string.rep(" ", right)
end

local function resetColor()
  setColor(colors.white)
end

local function clear()
  term.setBackgroundColor(colors.black)
  resetColor()
  term.clear()
  term.setCursorPos(1, 1)
end

local function header(title)
  W, H = term.getSize()
  setColor(colors.yellow)
  print(string.rep("=", W))
  print(" " .. title)
  print(string.rep("=", W))
  resetColor()
end

local function ok(msg)
  setColor(colors.green)
  print("[OK] " .. msg)
  resetColor()
end

local function warn(msg)
  setColor(colors.yellow)
  print("[WARN] " .. msg)
  resetColor()
end

local function err(msg)
  setColor(colors.red)
  print("[ERR] " .. msg)
  resetColor()
end

local function pause()
  print("")
  io.write("Press Enter...")
  io.read()
end

local function yesNo(prompt)
  io.write(prompt .. " (y/n): ")
  local ans = io.read()
  if not ans then return false end
  ans = ans:lower()
  return ans == "y" or ans == "yes"
end

local function readNumber(prompt)
  io.write(prompt)
  local n = tonumber(io.read())
  return n
end

-- ============================================================
-- STRING HELPERS
-- ============================================================

local function trim(s)
  if not s then return "" end
  return s:match("^%s*(.-)%s*$")
end

local function escapePattern(s)
  return tostring(s):gsub("([^%w])", "%%%1")
end

local function chestNum(name)
  if not name then return "?" end
  return tostring(name):match("_(%d+)$") or "?"
end

local function isOnline(name)
  if not name or name == "" then return false end
  return peripheral.wrap(name) ~= nil
end

local function isStorageChest(name)
  return type(name) == "string" and name:find(CHEST_MATCH, 1, true) ~= nil
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

local function monitorClear(mon)
  mon = mon or getMonitor()
  if not mon then return false end

  mon.clear()
  mon.setCursorPos(1, 1)
  return true
end

local function drawMonitorChest(mon, y, label, name)
  if not mon then return false end

  local oldTerm = term.redirect(mon)
  local mw, mh = term.getSize()

  local num = chestNum(name)
  local online = isOnline(name)
  local color = online and colors.white or colors.red

  local box = {
    "+-------------------+",
    "|                   |",
    "|--------[O]--------|",
    "|                   |",
    "| " .. centerText(num, 17) .. " |",
    "|                   |",
    "+-------------------+",
  }

  setColor(color)

  for i, line in ipairs(box) do
    local x = math.max(1, math.floor((mw - #line) / 2) + 1)
    term.setCursorPos(x, y + i - 1)
    term.write(line)
  end

  local tag = label
  if not online then tag = tag .. " OFFLINE" end

  local lx = math.max(1, math.floor((mw - #tag) / 2) + 1)
  term.setCursorPos(lx, y + #box)
  term.write(tag)

  resetColor()
  term.redirect(oldTerm)
  return true
end

local function drawColumnOnMonitor(colIndex, col)
  local mon = getMonitor()
  if not mon then return false end

  monitorClear(mon)

  local oldTerm = term.redirect(mon)
  local mw, mh = term.getSize()

  setColor(colors.yellow)
  local title = "COLUMN " .. tostring(colIndex)
  term.setCursorPos(math.max(1, math.floor((mw - #title) / 2) + 1), 1)
  term.write(title)
  resetColor()

  term.redirect(oldTerm)

  drawMonitorChest(mon, 3,  "TOP",    col.top)
  drawMonitorChest(mon, 12, "MID",    col.mid)
  drawMonitorChest(mon, 21, "BOTTOM", col.bottom)

  return true
end

-- ============================================================
-- CONFIG LOAD/SAVE
-- ============================================================

local function loadConfig()
  local cfg = {}

  if not fs.exists(CONFIG_PATH) then
    return cfg
  end

  local f = fs.open(CONFIG_PATH, "r")
  if not f then return cfg end

  local line = f.readLine()
  while line do
    local k, v = line:match("^%s*(.-)%s*=%s*(.-)%s*$")
    if k and v and k ~= "" then
      cfg[trim(k)] = trim(v)
    end
    line = f.readLine()
  end

  f.close()
  return cfg
end

local function loadColumns()
  if not fs.exists(COLUMNS_PATH) then
    return nil, "columns.cfg not found. Run setup first."
  end

  local columns = {}
  local f = fs.open(COLUMNS_PATH, "r")
  if not f then
    return nil, "Could not open columns.cfg."
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

      if bottom ~= "" and mid ~= "" and top ~= "" then
        table.insert(columns, {
          bottom = bottom,
          mid = mid,
          top = top,
        })
      end
    end

    line = f.readLine()
  end

  f.close()

  if #columns == 0 then
    return nil, "No valid columns found in columns.cfg."
  end

  return columns, nil
end

local function saveColumns(columns)
  if not fs.exists("/data") then
    fs.makeDir("/data")
  end

  local f = fs.open(COLUMNS_PATH, "w")
  if not f then
    return false, "Could not write columns.cfg."
  end

  f.writeLine("# Column assignments")
  f.writeLine("# Format: bottom | mid | top")
  f.writeLine("# Edited by column_edit.lua")
  f.writeLine("")

  for _, col in ipairs(columns) do
    f.writeLine(
      tostring(col.bottom) ..
      " | " ..
      tostring(col.mid) ..
      " | " ..
      tostring(col.top)
    )
  end

  f.close()
  return true
end

-- ============================================================
-- STORAGE.CFG REPAIR
-- ============================================================

local function updateStorageCfg(oldName, newName)
  if not fs.exists(STORAGE_PATH) then
    return 0
  end

  local lines = {}
  local count = 0

  local f = fs.open(STORAGE_PATH, "r")
  if not f then return 0 end

  local line = f.readLine()
  while line do
    if line:find(oldName, 1, true) then
      line = line:gsub(escapePattern(oldName), newName)
      count = count + 1
    end

    table.insert(lines, line)
    line = f.readLine()
  end

  f.close()

  local g = fs.open(STORAGE_PATH, "w")
  if not g then return count end

  for _, l in ipairs(lines) do
    g.writeLine(l)
  end

  g.close()
  return count
end

-- ============================================================
-- CHEST SCANNING
-- ============================================================

local function scanChests()
  local chests = {}

  for _, name in ipairs(peripheral.getNames()) do
    if isStorageChest(name) then
      local num = tonumber(name:match("_(%d+)$")) or 0

      local firstItem = "(empty)"
      local inv = peripheral.wrap(name)

      if inv and inv.list then
        local okList, items = pcall(inv.list)
        if okList and items then
          for slot, stack in pairs(items) do
            if stack then
              firstItem = stack.name or "(item)"
              break
            end
          end
        end
      end

      table.insert(chests, {
        name = name,
        num = num,
        firstItem = firstItem,
      })
    end
  end

  table.sort(chests, function(a, b)
    return a.num < b.num
  end)

  return chests
end

local function buildAssignedMap(columns, cfg)
  local assigned = {}

  for i, col in ipairs(columns) do
    assigned[col.bottom] = "Column " .. i .. " bottom"
    assigned[col.mid]    = "Column " .. i .. " mid"
    assigned[col.top]    = "Column " .. i .. " top"
  end

  if cfg then
    for k, v in pairs(cfg) do
      if type(v) == "string" and v ~= "" then
        assigned[v] = "SPECIAL: " .. tostring(k)
      end
    end
  end

  return assigned
end

local function findChestByNumber(chests, num)
  for _, c in ipairs(chests) do
    if c.num == num then
      return c
    end
  end

  return nil
end

local function findDuplicateAssignments(columns, cfg)
  local seen = {}
  local dupes = {}

  local function add(name, label)
    if not name or name == "" then return end

    if seen[name] then
      table.insert(dupes, name .. " used by " .. seen[name] .. " and " .. label)
    else
      seen[name] = label
    end
  end

  if cfg then
    for k, v in pairs(cfg) do
      add(v, "special " .. tostring(k))
    end
  end

  for i, col in ipairs(columns) do
    add(col.bottom, "column " .. i .. " bottom")
    add(col.mid,    "column " .. i .. " mid")
    add(col.top,    "column " .. i .. " top")
  end

  return dupes
end

-- ============================================================
-- TERMINAL DISPLAYS
-- ============================================================

local function drawSummary(columns, cfg)
  print("")
  print(string.format(
    " %-5s %-8s %-8s %-8s %-10s",
    "COL", "BOTTOM", "MID", "TOP", "STATUS"
  ))

  print(" " .. string.rep("-", 48))

  for i, col in ipairs(columns) do
    local botOk = isOnline(col.bottom)
    local midOk = isOnline(col.mid)
    local topOk = isOnline(col.top)

    local status = "OK"
    local color = colors.white

    if not botOk or not midOk or not topOk then
      status = "OFFLINE"
      color = colors.red
    end

    setColor(color)
    print(string.format(
      " %-5d %-8s %-8s %-8s %-10s",
      i,
      chestNum(col.bottom),
      chestNum(col.mid),
      chestNum(col.top),
      status
    ))
    resetColor()
  end

  print("")

  if cfg then
    setColor(colors.lightGray)
    print("Special chests:")
    for k, v in pairs(cfg) do
      local status = isOnline(v) and "online" or "OFFLINE"
      print(" " .. tostring(k) .. ": " .. chestNum(v) .. " " .. status)
    end
    resetColor()
    print("")
  end
end

local function drawColumnText(colIndex, col)
  print("")
  setColor(colors.yellow)
  print("COLUMN " .. tostring(colIndex))
  resetColor()
  print("")

  local function row(label, name)
    local online = isOnline(name)
    local color = online and colors.white or colors.red

    setColor(color)
    print(string.format(
      " %-7s chest %-5s %s",
      label,
      chestNum(name),
      online and "online" or "OFFLINE"
    ))
    setColor(colors.lightGray)
    print("         " .. tostring(name))
    resetColor()
  end

  row("TOP", col.top)
  row("MID", col.mid)
  row("BOTTOM", col.bottom)

  print("")
end

local function showAvailableChests(chests, assigned)
  print("")
  print(string.format(
    " %-6s %-38s %-18s %s",
    "NUM", "PERIPHERAL", "CONTENTS", "ASSIGNMENT"
  ))

  print(" " .. string.rep("-", 78))

  for _, c in ipairs(chests) do
    local assignment = assigned[c.name] or ""
    local online = isOnline(c.name)

    local color = colors.white
    if assignment ~= "" then color = colors.lightGray end
    if not online then color = colors.red end

    setColor(color)
    print(string.format(
      " %-6d %-38s %-18s %s",
      c.num,
      c.name:sub(1, 38),
      tostring(c.firstItem):sub(1, 18),
      assignment
    ))
    resetColor()
  end

  print("")
end

-- ============================================================
-- VALIDATION
-- ============================================================

local function validate(columns, cfg)
  local issues = {}

  local function checkOnline(name, label)
    if not name or name == "" then
      table.insert(issues, label .. " is blank")
      return
    end

    if not isOnline(name) then
      table.insert(issues, label .. " OFFLINE: " .. name)
    end
  end

  if cfg then
    for k, v in pairs(cfg) do
      checkOnline(v, "Special " .. tostring(k))
    end
  end

  for i, col in ipairs(columns) do
    checkOnline(col.bottom, "Column " .. i .. " bottom")
    checkOnline(col.mid,    "Column " .. i .. " mid")
    checkOnline(col.top,    "Column " .. i .. " top")
  end

  local dupes = findDuplicateAssignments(columns, cfg)
  for _, d in ipairs(dupes) do
    table.insert(issues, "Duplicate: " .. d)
  end

  return issues
end

local function runValidation(columns, cfg)
  clear()
  header("VALIDATE STORAGE MAP")

  local issues = validate(columns, cfg)

  if #issues == 0 then
    ok("No issues found.")
  else
    err("Issues found:")
    print("")

    for _, issue in ipairs(issues) do
      err(" " .. issue)
    end
  end

  pause()
end

-- ============================================================
-- PRINTING
-- ============================================================

local function printColumn(colIndex, col)
  if not printer or not printer.open then
    warn("Printer library not available.")
    return
  end

  local hasPrinter = printer.open("Column " .. tostring(colIndex))
  if not hasPrinter then
    warn("No printer found.")
    return
  end

  printer.writeLine("COLUMN " .. tostring(colIndex))
  printer.writeLine("-------------------------")
  printer.writeLine("")

  printer.writeLine("TOP:    " .. tostring(col.top))
  printer.writeLine("MID:    " .. tostring(col.mid))
  printer.writeLine("BOTTOM: " .. tostring(col.bottom))

  printer.writeLine("")
  printer.writeLine("Numbers:")
  printer.writeLine("TOP:    " .. chestNum(col.top))
  printer.writeLine("MID:    " .. chestNum(col.mid))
  printer.writeLine("BOTTOM: " .. chestNum(col.bottom))

  printer.close()
  ok("Printed column " .. tostring(colIndex))
end

-- ============================================================
-- EDITING
-- ============================================================

local function choosePosition(col)
  print("Which chest changed?")
  print(" [1] Bottom  current: " .. chestNum(col.bottom))
  print(" [2] Mid     current: " .. chestNum(col.mid))
  print(" [3] Top     current: " .. chestNum(col.top))
  print(" [0] Cancel")
  print("")

  local pos = readNumber("Position: ")

  if pos == 0 or pos == nil then
    return nil
  end

  if pos == 1 then return "bottom", "BOTTOM" end
  if pos == 2 then return "mid", "MID" end
  if pos == 3 then return "top", "TOP" end

  return false
end

local function editColumn(columns, cfg)
  clear()
  header("EDIT COLUMN")

  drawSummary(columns, cfg)

  local colIndex = readNumber("Column number: ")
  if not colIndex or not columns[colIndex] then
    err("Invalid column.")
    pause()
    return
  end

  local col = columns[colIndex]

  drawColumnOnMonitor(colIndex, col)
  drawColumnText(colIndex, col)

  local posName, posLabel = choosePosition(col)
  if posName == nil then
    warn("Cancelled.")
    pause()
    return
  end

  if posName == false then
    err("Invalid position.")
    pause()
    return
  end

  local oldName = col[posName]

  clear()
  header("SELECT NEW CHEST")

  drawColumnOnMonitor(colIndex, col)
  drawColumnText(colIndex, col)

  local chests = scanChests()
  local assigned = buildAssignedMap(columns, cfg)

  showAvailableChests(chests, assigned)

  print("Changing:")
  print(" Column:   " .. tostring(colIndex))
  print(" Position: " .. posLabel)
  print(" Old:      " .. tostring(oldName))
  print("")

  local newNum = readNumber("New chest number: ")
  if not newNum then
    err("Invalid chest number.")
    pause()
    return
  end

  local newChest = findChestByNumber(chests, newNum)
  if not newChest then
    err("Chest number " .. tostring(newNum) .. " not found.")
    pause()
    return
  end

  local newName = newChest.name

  if newName == oldName then
    warn("That is already the assigned chest.")
    pause()
    return
  end

  local currentUse = assigned[newName]
  if currentUse then
    warn("That chest is already assigned:")
    warn(" " .. currentUse)
    print("")
    if not yesNo("Use it anyway") then
      warn("Cancelled.")
      pause()
      return
    end
  end

  clear()
  header("CONFIRM CHANGE")

  print("Column " .. tostring(colIndex) .. " " .. posLabel)
  print("")
  print("FROM:")
  print(" " .. tostring(oldName))
  print("")
  print("TO:")
  print(" " .. tostring(newName))
  print("")

  if not yesNo("Save this change") then
    warn("Cancelled.")
    pause()
    return
  end

  columns[colIndex][posName] = newName

  local saved, saveErr = saveColumns(columns)
  if not saved then
    err(saveErr or "Save failed.")
    columns[colIndex][posName] = oldName
    pause()
    return
  end

  local storageUpdates = updateStorageCfg(oldName, newName)

  ok("Updated /data/columns.cfg")

  if storageUpdates > 0 then
    ok("Updated /data/storage.cfg entries: " .. tostring(storageUpdates))
  else
    warn("No storage.cfg references changed.")
  end

  drawColumnOnMonitor(colIndex, columns[colIndex])
  print("")
  ok("Column repaired.")
  pause()
end

-- ============================================================
-- MAIN
-- ============================================================

local function main()
  while true do
    clear()
    header("COLUMN EDITOR")

    local cfg = loadConfig()
    local columns, loadErr = loadColumns()

    if not columns then
      err(loadErr)
      return
    end

    monitorClear(getMonitor())

    print("Loaded columns: " .. tostring(#columns))
    print("")

    drawSummary(columns, cfg)

    print("Options:")
    print(" [e] Edit column chest")
    print(" [v] Validate map")
    print(" [m] Show column on monitor")
    print(" [p] Print column")
    print(" [q] Quit")
    print("")

    io.write("Choice: ")
    local choice = io.read()

    if not choice then
      return
    end

    choice = choice:lower()

    if choice == "q" then
      clear()
      print("Done.")
      return

    elseif choice == "e" then
      editColumn(columns, cfg)

    elseif choice == "v" then
      runValidation(columns, cfg)

    elseif choice == "m" then
      local n = readNumber("Column number: ")
      if n and columns[n] then
        if drawColumnOnMonitor(n, columns[n]) then
          ok("Column sent to monitor.")
        else
          err("No monitor found.")
        end
      else
        err("Invalid column.")
      end
      pause()

    elseif choice == "p" then
      local n = readNumber("Column number: ")
      if n and columns[n] then
        printColumn(n, columns[n])
      else
        err("Invalid column.")
      end
      pause()

    else
      warn("Unknown option.")
      pause()
    end
  end
end

main()