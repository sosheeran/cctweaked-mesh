-- logfile.lua
--
-- reading/writing the actual log files on disk. one file per
-- category, capped at 500 lines each so they don't grow forever -
-- once a category hits the cap, oldest entries get dropped.
-- CRITICAL entries are the exception: they go to their own file
-- and are never trimmed, since those are the ones you actually
-- want to be able to go back and find later.

local M = {}

local BASE          = "/log/data/"
local MAX_ENTRIES    = 500
local CRITICAL_FILE  = "/log/data/critical.log"

local CATEGORIES = {
  audit    = "audit.log",
  security = "security.log",
  network  = "network.log",
  errors   = "errors.log",
  system   = "system.log",
}

local function ensureDir()
  if not fs.exists("/log/data") then
    fs.makeDir("/log/data")
  end
end

local function getPath(category)
  local fname = CATEGORIES[category] or (category .. ".log")
  return BASE .. fname
end

local function readEntries(path)
  local entries = {}
  if not fs.exists(path) then return entries end
  local f = fs.open(path, "r")
  if not f then return entries end
  local line = f.readLine()
  while line do
    if line ~= "" then table.insert(entries, line) end
    line = f.readLine()
  end
  f.close()
  return entries
end

local function writeEntries(path, entries)
  local f = fs.open(path, "w")
  if not f then return false end
  for _, line in ipairs(entries) do
    f.writeLine(line)
  end
  f.close()
  return true
end

-- one log entry -> one printable line
function M.format(entry)
  local ts = entry.ts or os.date()
  return string.format("[%s] [%-5s] [%-16s] %s",
    ts,
    (entry.level  or "INFO"):sub(1, 5),
    (entry.source or "unknown"):sub(1, 16),
    tostring(entry.message or ""))
end

-- breaks a line into chunks that fit the monitor width, with a
-- small indent on wrapped continuation lines so they're visually
-- distinct from the start of the next entry
function M.wrap(line, width)
  width = width or 51
  if #line <= width then return {line} end

  local lines  = { line:sub(1, width) }
  local indent = "          "
  local pos    = width + 1

  while pos <= #line do
    table.insert(lines,
      indent .. line:sub(pos, pos + width - #indent - 1))
    pos = pos + width - #indent
  end
  return lines
end

-- note: this reads the whole category file, appends one line,
-- and rewrites the whole thing back out. fine at a 500-line cap,
-- would want append-mode writes instead if log volume ever got
-- a lot heavier than this network actually produces
function M.append(entry)
  ensureDir()

  local formatted = M.format(entry)

  if entry.level == "CRITICAL" then
    local f = fs.open(CRITICAL_FILE, "a")
    if f then
      f.writeLine(formatted)
      f.close()
    end
  end

  local path    = getPath(entry.category or "system")
  local entries = readEntries(path)
  table.insert(entries, formatted)

  if #entries > MAX_ENTRIES then
    local trimmed = {}
    local start = #entries - MAX_ENTRIES + 1
    for i = start, #entries do
      table.insert(trimmed, entries[i])
    end
    entries = trimmed
  end

  return writeEntries(path, entries)
end

function M.tail(category, n)
  n = n or 20
  local entries = readEntries(getPath(category))
  local result  = {}
  local start   = math.max(1, #entries - n + 1)
  for i = start, #entries do
    table.insert(result, entries[i])
  end
  return result
end

function M.getCritical()
  return readEntries(CRITICAL_FILE)
end

function M.deleteCritical(idx)
  local entries = readEntries(CRITICAL_FILE)
  if not entries[idx] then return false end
  table.remove(entries, idx)
  return writeEntries(CRITICAL_FILE, entries)
end

function M.clearCritical()
  if fs.exists(CRITICAL_FILE) then
    fs.delete(CRITICAL_FILE)
  end
  return true
end

function M.getCounts()
  local counts = {}
  for cat, fname in pairs(CATEGORIES) do
    counts[cat] = #readEntries(BASE .. fname)
  end
  counts.critical = #readEntries(CRITICAL_FILE)
  return counts
end

function M.getCategories()
  local cats = {}
  for cat in pairs(CATEGORIES) do
    table.insert(cats, cat)
  end
  table.sort(cats)
  return cats
end

return M
