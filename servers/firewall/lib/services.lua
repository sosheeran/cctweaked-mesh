-- services.lua
--
-- thin wrapper around network.lua, scoped to what the firewall
-- specifically needs (look up an ID, check if something's
-- trusted). exists mostly so firewall.lua talks to "services"
-- conceptually rather than reaching into the shared network
-- module directly - if the firewall ever needed its own
-- service-lookup rules that differ from the rest of the network,
-- this is the file that would change.

local net = require("/lib/network")
local M   = {}

function M.getID(name)
  return net.getID(name)
end

function M.isTrusted(computer_id)
  return net.isTrusted(computer_id)
end

return M
