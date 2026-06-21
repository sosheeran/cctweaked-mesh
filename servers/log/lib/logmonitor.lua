-- logmonitor.lua
--
-- renders the log server's monitor: a critical-alerts section up
-- top (if any), a merged feed of recent entries across every
-- category below that, color coded by level, plus a status bar
-- with per-category counts.

local logfile = require("/log/lib/logfile")
local M       = {}

local LEVEL_COLOR = {
  INFO     = colors.white,
  WARN     = colors.yellow,
  ERROR    = colors.red,
  AUDIT    = colors.cyan,
  SEC      = colors.orange,
  NET      = colors.lightBlue,
  CRITICAL = colors.red,
}

local mon   = nil
local mon_w = 51
local mon_h = 19
local SCALE = 0.5

function M.open()
  mon = peripheral.find("monitor")
  if not mon then return false end
  pcall(mon.setTextScale, SCALE)
  pcall(mon.setBackgroundColor, colors.black)
  pcall(mon.setTextColor, colors.white)
  local ok_size, w, h = pcall(mon.getSize)
  if ok_size then mon_w = w; mon_h = h end
  return true
end

local function setColor(c)
  if mon and mon.setTextColor then
    pcall(mon.setTextColor, c)
  end
end

local function writeLine(y, text, color)
  if not mon then return end
  pcall(mon.setCursorPos, 1, y)
  setColor(color or colors.white)
  if #text < mon_w then
    text = text .. string.rep(" ", mon_w - #text)
  else
    text = text:sub(1, mon_w)
  end
  pcall(mon.write, text)
end

-- logfile.format pads the level to exactly 5 chars with
-- string.format("%-5s", ...), which means short levels like
-- INFO/WARN/SEC/NET come out with trailing spaces before the
-- closing bracket - e.g. "[INFO ]" not "[INFO]". the original
-- bracket match here didn't account for that gap and so silently
-- failed to color anything except ERROR/AUDIT/CRITICAL (the ones
-- that happen to already be 5 characters), with everything else
-- quietly falling through to plain white. %s* in the pattern
-- below absorbs that padding so every level matches correctly.
local function lineColor(line)
  for level, color in pairs(LEVEL_COLOR) do
    if line:find("%[" .. level:sub(1, 5) .. "%s*%]") then
      return color
    end
  end
  return colors.white
end

function M.render(last_source, last_msg)
  if not mon then M.open() end
  if not mon then return false end

  local old = term.redirect(mon)
  term.setBackgroundColor(colors.black)
  term.clear()

  local y = 1

  term.setCursorPos(1, y)
  term.setBackgroundColor(colors.gray)
  term.setTextColor(colors.yellow)
  local title = " LOG SERVER "
  local pad   = math.floor((mon_w - #title) / 2)
  term.write(string.rep(" ", pad) .. title ..
             string.rep(" ", mon_w - pad - #title))
  term.setBackgroundColor(colors.black)
  y = y + 1

  term.setCursorPos(1, y)
  term.setTextColor(colors.gray)
  term.write(string.rep("-", mon_w))
  y = y + 1

  local criticals = logfile.getCritical()
  if #criticals > 0 then
    term.setCursorPos(1, y)
    term.setTextColor(colors.red)
    term.write(" !! CRITICAL (" .. #criticals .. ") !!")
    y = y + 1

    local c = criticals[#criticals]
    for _, line in ipairs(logfile.wrap(c, mon_w - 2)) do
      if y > mon_h - 3 then break end
      term.setCursorPos(1, y)
      term.setTextColor(colors.red)
      term.write(" " .. line:sub(1, mon_w - 1))
      y = y + 1
    end

    term.setCursorPos(1, y)
    term.setTextColor(colors.gray)
    term.write(string.rep("-", mon_w))
    y = y + 1
  end

  -- pull a handful of recent entries from every category and
  -- merge them into one chronological feed
  local all_recent = {}
  for _, cat in ipairs(logfile.getCategories()) do
    for _, e in ipairs(logfile.tail(cat, 5)) do
      table.insert(all_recent, e)
    end
  end

  table.sort(all_recent, function(a, b)
    local ta = a:match("^%[(%d+:%d+:%d+)%]") or ""
    local tb = b:match("^%[(%d+:%d+:%d+)%]") or ""
    return ta < tb
  end)

  local lines_available = mon_h - y - 2
  local start = math.max(1, #all_recent - lines_available + 1)

  for i = start, #all_recent do
    if y > mon_h - 2 then break end
    local line  = all_recent[i]
    local color = lineColor(line)
    for _, wl in ipairs(logfile.wrap(line, mon_w - 1)) do
      if y > mon_h - 2 then break end
      term.setCursorPos(1, y)
      term.setTextColor(color)
      term.write(" " .. wl:sub(1, mon_w - 1))
      y = y + 1
    end
  end

  local counts = logfile.getCounts()
  local status = string.format(
    " A:%-3d S:%-3d E:%-3d N:%-3d",
    counts.audit or 0, counts.security or 0,
    counts.errors or 0, counts.network or 0)

  term.setCursorPos(1, mon_h - 1)
  term.setTextColor(colors.gray)
  term.write(string.rep("-", mon_w))

  term.setCursorPos(1, mon_h)
  term.setTextColor(colors.lightGray)
  term.write(status:sub(1, mon_w))

  term.setTextColor(colors.white)
  term.redirect(old)
  return true
end

return M
