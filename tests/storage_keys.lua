-- storage_keys.lua
-- dumps every key currently in storage.cfg to the monitor, with
-- paging since the full list usually doesn't fit on one screen.
-- quick way to sanity-check what discover actually mapped.

local mon = peripheral.find("monitor")
if not mon then print("No monitor found"); return end

mon.setTextScale(0.5)
local W, H = mon.getSize()

local function monClear()
  mon.setBackgroundColor(colors.black)
  mon.setTextColor(colors.white)
  mon.clear()
  mon.setCursorPos(1,1)
end

local function mprint(y, text, col)
  mon.setCursorPos(1, y)
  mon.setTextColor(col or colors.white)
  mon.write(tostring(text):sub(1, W))
  mon.setTextColor(colors.white)
end

-- Load all keys
if not fs.exists("/data/storage.cfg") then
  monClear()
  mprint(1, "No storage.cfg found!", colors.red)
  return
end

local keys = {}
local f = fs.open("/data/storage.cfg", "r")
local line = f.readLine()
while line do
  if not line:match("^#") and line:match("|") then
    local key = line:match("^%s*(.-)%s*|")
    if key and key ~= "" then
      table.insert(keys, key)
    end
  end
  line = f.readLine()
end
f.close()

-- Paginate - leave 1 row for footer
local page_size = H - 1
local total     = #keys
local page      = 1
local total_pages = math.ceil(total / page_size)

local function drawPage(p)
  monClear()
  local start = (p - 1) * page_size + 1
  local finish = math.min(start + page_size - 1, total)
  for i = start, finish do
    local key = keys[i]
    local col = colors.white
    if key:find("thermalfoundation") then col = colors.yellow
    elseif key:find("minecraft")       then col = colors.cyan
    elseif key:find("enderio")         then col = colors.lime
    elseif key:find("extrautils")      then col = colors.orange
    elseif key:find("thaumcraft")      then col = colors.purple
    end
    mprint(i - start + 1, key, col)
  end
  -- Footer
  mprint(H, string.format("Page %d/%d | %d items | Enter=next Q=quit",
    p, total_pages, total), colors.lightGray)
end

drawPage(page)
print("Showing on monitor. Press Enter to page, Q to quit.")

while true do
  local _, key = os.pullEvent("key")
  if key == keys.enter or key == keys.space then
    page = page + 1
    if page > total_pages then page = 1 end
    drawPage(page)
  elseif key == keys.q then
    monClear()
    mprint(1, "Done.", colors.gray)
    break
  end
end
