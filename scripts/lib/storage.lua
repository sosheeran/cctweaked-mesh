-- storage.lua
--
-- the storage index itself - which physical chests hold which
-- item, and how to read stock levels out of them. shared by the
-- storage server, fulfillment, overflow, and storeadmin, so this
-- is the one place the on-disk storage.cfg format is actually
-- understood.

local M = {}

local CFG         = "/data/storage.cfg"
local CHEST_SLOTS = 108  -- iron chest (obsidian tier) slot count

-- damage 0 is the common case and gets no suffix, so a plain
-- "minecraft:iron_ingot" key stays readable instead of always
-- carrying a trailing ":0"
function M.makeKey(name, damage)
  damage = damage or 0
  if damage == 0 then return name end
  return name .. ":" .. tostring(damage)
end

function M.load()
  local store = {}
  local f = fs.open(CFG, "r")
  if not f then return store end

  local line = f.readLine()
  while line do
    if not line:match("^#") and line:match("|") then
      local key, bottom, mid, top, display, mod = line:match(
        "^%s*(.-)%s*|%s*(.-)%s*|%s*(.-)%s*|%s*(.-)%s*|%s*(.-)%s*|%s*(.-)%s*$"
      )
      if key and key ~= "" and bottom and bottom ~= "" then
        store[key] = {
          chest   = bottom,
          mid     = (mid ~= "" and mid) or nil,
          top     = (top ~= "" and top) or nil,
          display = display or key,
          mod     = mod or "unknown",
        }
      end
    end
    line = f.readLine()
  end
  f.close()
  return store
end

function M.save(store)
  if not fs.exists("/data") then fs.makeDir("/data") end
  local f = fs.open(CFG, "w")
  if not f then return false end

  f.writeLine("# key | bottom | mid | top | display | mod")
  local keys = {}
  for k in pairs(store) do table.insert(keys, k) end
  table.sort(keys)

  for _, key in ipairs(keys) do
    local d = store[key]
    f.writeLine(
      key            .. " | " ..
      d.chest        .. " | " ..
      (d.mid or "")  .. " | " ..
      (d.top or "")  .. " | " ..
      d.display      .. " | " ..
      d.mod
    )
  end
  f.close()
  return true
end

-- a storage "column" can be 1-3 chests stacked together (bottom,
-- and once that's full, mid, and once that's full, top). counting
-- the next chest only kicks in once the previous one's slot count
-- reads as fully used (CHEST_SLOTS=108) - this assumes items are
-- generally stacking to their max before spilling into a new
-- slot, which holds in practice for how this network actually
-- fills columns, but it's worth knowing the count is slot-based
-- rather than truly item-based: a chest with 108 mostly-empty
-- stacks would still trigger checking the next chest even though
-- its actual item count is low, and the reverse - fewer than 108
-- slots all sitting at max stack size - would never trigger it
-- even if it's holding thousands of items
function M.getStock(data)
  local function count(name)
    if not name or name == "" then return 0, 0 end
    local c = peripheral.wrap(name)
    if not c then return 0, 0 end

    local n, s = 0, 0
    local ok, items = pcall(c.list)
    if ok and items then
      for _, stack in pairs(items) do
        n = n + stack.count
        s = s + 1
      end
    end
    return n, s
  end

  local bot_n, bot_s = count(data.chest)
  local total = bot_n
  if bot_s >= CHEST_SLOTS then
    local mid_n, mid_s = count(data.mid)
    total = total + mid_n
    if mid_s >= CHEST_SLOTS then
      total = total + count(data.top)
    end
  end

  local overflow = false
  if data.top and data.top ~= "" then
    local _, top_s = count(data.top)
    overflow = top_s >= math.floor(CHEST_SLOTS * 0.75)
  end

  local pct = math.floor(total / (CHEST_SLOTS * 3 * 64) * 100)
  return total, pct, overflow
end

-- max item count assuming every slot in the column fills to a
-- full 64-stack - an upper bound, not a guarantee, since plenty
-- of items don't stack to 64 (buckets, tools, etc)
function M.getCapacity(data)
  local slots = 0
  for _, name in ipairs({ data.chest, data.mid, data.top }) do
    if name and name ~= "" then
      local c = peripheral.wrap(name)
      if c then
        local ok, size = pcall(c.size)
        slots = slots + (ok and size or CHEST_SLOTS)
      end
    end
  end
  return slots * 64
end

return M
