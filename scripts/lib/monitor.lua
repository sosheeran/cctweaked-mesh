-- monitor.lua
--
-- generic buffered monitor display, used by several of the admin
-- scripts in this folder plus the log/noc servers. build up a
-- list of lines with addLine/addHeader/addSeparator, then
-- M.render() draws all of it at once - simpler than redirecting
-- to the monitor and writing line by line throughout a script.

local M = {}

local mon   = nil
local lines = {}
local title = ""

function M.open(t)
  mon = peripheral.find("monitor")
  if not mon then return false end

  title = t or ""
  lines = {}
  pcall(mon.setTextScale, 0.5)
  pcall(mon.setBackgroundColor, colors.black)
  pcall(mon.setTextColor, colors.white)
  pcall(mon.clear)
  pcall(mon.setCursorPos, 1, 1)
  return true
end

function M.isOpen()
  return mon ~= nil
end

function M.addLine(line, color)
  table.insert(lines, { text = line or "", color = color or colors.white })
end

function M.addSeparator()
  local w = 0
  if mon then
    local ok, mw = pcall(mon.getSize)
    if ok then w = mw end
  end
  M.addLine(string.rep("-", w > 0 and w or 40))
end

function M.addHeader(text)
  M.addLine(text, colors.yellow)
end

function M.render()
  if not mon then return false end

  local old = term.redirect(mon)
  local w, h = term.getSize()
  term.setBackgroundColor(colors.black)
  term.clear()

  if title ~= "" then
    term.setTextColor(colors.yellow)
    term.setCursorPos(1, 1)
    local pad = math.floor((w - #title) / 2)
    term.write(string.rep(" ", math.max(0, pad)) .. title)
    term.setTextColor(colors.white)
    term.setCursorPos(1, 2)
    term.write(string.rep("-", w))
  end

  local start_y = title ~= "" and 3 or 1
  for i, line_data in ipairs(lines) do
    local y = start_y + i - 1
    if y > h then break end
    term.setCursorPos(1, y)
    term.setTextColor(line_data.color or colors.white)
    local text = line_data.text
    if #text > w then text = text:sub(1, w) end
    term.write(text)
  end

  term.setTextColor(colors.white)
  term.redirect(old)
  return true
end

-- shorthand for open + fill + render in one call
function M.display(t, lines_data)
  if not M.open(t) then return false end
  for _, l in ipairs(lines_data or {}) do
    if type(l) == "string" then
      M.addLine(l)
    else
      M.addLine(l.text, l.color)
    end
  end
  return M.render()
end

function M.clear()
  if not mon then return false end
  pcall(mon.clear)
  pcall(mon.setCursorPos, 1, 1)
  lines = {}
  return true
end

return M
