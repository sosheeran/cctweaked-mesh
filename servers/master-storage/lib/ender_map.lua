-- ender_map.lua
--
-- which ender chest belongs to which player. storage looks this
-- up whenever it needs to deliver an order - pull the item out of
-- the right storage column, push it into whichever ender chest is
-- mapped to that player's computer ID. managed through
-- storeadmin's ender commands rather than edited by hand.

local M   = {}
local CFG = "/data/ender_map.cfg"

function M.load()
  local map = {}
  if not fs.exists(CFG) then return map end
  local f = fs.open(CFG, "r")
  if not f then return map end

  local line = f.readLine()
  while line do
    if not line:match("^#") and line:match("|") then
      local name, cid, chest = line:match(
        "^%s*(.-)%s*|%s*(.-)%s*|%s*(.-)%s*$")
      if name and cid and chest and name ~= "" and cid ~= "" and chest ~= "" then
        local id = tonumber(cid)
        if id then
          map[id] = { name = name, computer_id = id, chest = chest }
        end
      end
    end
    line = f.readLine()
  end
  f.close()
  return map
end

function M.save(map)
  if not fs.exists("/data") then fs.makeDir("/data") end
  local f = fs.open(CFG, "w")
  if not f then return false end

  f.writeLine("# name | computer_id | ender_chest")
  f.writeLine("# Example: Seth's Terminal | 25 | minecraft:ender chest_0")

  local entries = {}
  for _, entry in pairs(map) do
    table.insert(entries, entry)
  end
  table.sort(entries, function(a, b) return a.computer_id < b.computer_id end)

  for _, entry in ipairs(entries) do
    f.writeLine(entry.name .. " | " .. tostring(entry.computer_id) .. " | " .. entry.chest)
  end
  f.close()
  return true
end

function M.getChest(computer_id)
  local entry = M.load()[computer_id]
  return entry and entry.chest or nil
end

function M.get(computer_id)
  return M.load()[computer_id]
end

function M.set(name, computer_id, chest)
  local map = M.load()
  map[computer_id] = { name = name, computer_id = computer_id, chest = chest }
  return M.save(map)
end

function M.remove(computer_id)
  local map = M.load()
  if not map[computer_id] then return false end
  map[computer_id] = nil
  return M.save(map)
end

function M.isOnline(computer_id)
  local entry = M.get(computer_id)
  if not entry then return false end
  return peripheral.wrap(entry.chest) ~= nil
end

return M
