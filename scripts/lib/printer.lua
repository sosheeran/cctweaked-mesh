-- printer.lua
--
-- shared wrapper for printing admin reports to paper. assumes a
-- printer peripheral is physically attached to the left side of
-- whatever computer runs the script - that's a real hardware
-- assumption baked into this network's setup, not something this
-- module auto-detects, so M.open() returns false on any computer
-- without one there.

local M = {}

local SIDE = "left"
local PW   = 25  -- printed page width in characters
local PH   = 21  -- lines per page before a new page starts

local printer    = nil
local page_lines = {}
local page_num   = 0

function M.open(title)
  printer = peripheral.wrap(SIDE)
  if not printer then
    print("No printer on left!")
    return false
  end

  local ink   = printer.getInkLevel()
  local paper = printer.getPaperLevel()
  print("Printer: ink=" .. ink .. " paper=" .. paper)
  if ink == 0   then print("No ink!");   return false end
  if paper == 0 then print("No paper!"); return false end

  M.title    = title or "Output"
  page_lines = {}
  page_num   = 0
  return true
end

local function flush()
  if #page_lines == 0 then return true end
  if not printer.newPage() then
    print("Out of paper!")
    return false
  end

  page_num = page_num + 1
  printer.setPageTitle(M.title .. " p." .. page_num)
  for i, line in ipairs(page_lines) do
    printer.setCursorPos(1, i)
    printer.write(line:sub(1, PW))
  end
  printer.endPage()
  page_lines = {}
  return true
end

function M.writeLine(line)
  line = line or ""
  print(line)
  table.insert(page_lines, line)
  if #page_lines >= PH then return flush() end
  return true
end

function M.separator()
  return M.writeLine(string.rep("-", PW))
end

function M.close()
  local ok = flush()
  if ok then print("Printed " .. page_num .. " page(s)") end
  return ok
end

return M
