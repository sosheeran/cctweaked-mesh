-- network.lua
--
-- every computer ID and service name in one place, so nothing
-- else in the codebase has to hardcode "ID 4 is storage" - it
-- just asks this module.
--
-- IDs 0-24 are reserved for actual services even if not all of
-- them exist yet (crafting/fluid/farms are still being built out
-- and aren't included in this build - see README). clients start
-- at 25 and just keep incrementing as new ones get placed.

local M = {}

M.ID = {
  LOG        = 0,
  AUTH       = 1,
  FIREWALL   = 2,
  MAIL       = 3,
  STORAGE    = 4,
  CRAFTING   = 5,   -- reserved, not active in this build
  NOC        = 6,
  FLUID      = 7,   -- reserved
  MOB_FARM   = 8,   -- reserved
  TREE_FARM  = 9,   -- reserved
  FOOD_FARM  = 10,  -- reserved
  NUCLEAR    = 11,  -- reserved
  CLIENT_MIN = 25,
}

M.TIMEOUT = 10

local SERVERS = {
  [0]  = {name="log-server",      net="bottom", trusted=true},
  [1]  = {name="auth-server",     net="bottom", trusted=true},
  [2]  = {name="firewall",        net="bottom", trusted=true},
  [3]  = {name="mail-server",     net="bottom", trusted=true},
  [4]  = {name="master-storage",  net="bottom", periph="back", trusted=true},
  [5]  = {name="master-crafting", net="bottom", periph="back", trusted=true},
  [6]  = {name="noc-server",      net="bottom", trusted=true},
  [7]  = {name="fluid-server",    net="bottom", periph="back", trusted=true},
  [8]  = {name="mob-farm",        net="bottom", periph="back", trusted=true},
  [9]  = {name="tree-farm",       net="bottom", periph="back", trusted=true},
  [10] = {name="food-farm",       net="bottom", periph="back", trusted=true},
  [11] = {name="nuclear",         net="bottom", periph="back", trusted=true},
}

function M.getName(id)
  local s = SERVERS[id]
  return s and s.name or ("computer-" .. tostring(id))
end

function M.getID(name)
  for id, s in pairs(SERVERS) do
    if s.name == name then return id end
  end
  return nil
end

-- anything in the 0-24 range is a known service, not a player
-- terminal - used by the firewall to decide what's allowed to
-- skip session validation
function M.isTrusted(id)
  if type(id) ~= "number" then return false end
  return id >= 0 and id <= 24
end

function M.isClient(id)
  return type(id) == "number" and id >= M.ID.CLIENT_MIN
end

function M.myName()
  return M.getName(os.getComputerID())
end

return M
