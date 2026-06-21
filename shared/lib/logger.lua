-- logger.lua
--
-- Every service calls this instead of print() so logs end up
-- on the log server (id 0) instead of scattered across whatever
-- terminal happens to be open. Tried a version of this that
-- batched events into a buffer and flushed on a timer - not
-- worth the complexity for what this network actually needs.
-- Sends immediately, one event = one packet. If the log server
-- is down for a second the event just doesn't make it - that's
-- an acceptable tradeoff here, this isn't meant to be durable.

local M = {}

local LOG_SERVER_ID = 0
local MODEM = "bottom"

local function send(category, level, source, msg)
  -- other scripts can call logger functions before they've
  -- opened their own modem, so just make sure it's open here too
  if not rednet.isOpen(MODEM) then
    pcall(rednet.open, MODEM)
  end

  -- wrapped in pcall on purpose - a service should never crash
  -- because logging failed. that'd be a pretty bad trade.
  pcall(rednet.send, LOG_SERVER_ID, textutils.serialize({
    type     = "log",
    category = category,
    level    = level,
    source   = source,
    message  = tostring(msg),
    ts       = os.date(),
  }))
end

-- falls back to a generic computer-N name if network.lua isn't
-- available for some reason, so logging still works in a half
-- broken state
local function myName()
  local ok, net = pcall(require, "/lib/network")
  if ok and net then
    return net.myName()
  end
  return "computer-" .. os.getComputerID()
end

-- every level below supports two call styles:
--   logger.info("master-storage", "send chest offline")
--   logger.info("send chest offline")   -- source inferred
-- if msg is missing, the single arg becomes the message and
-- source gets filled in automatically

function M.info(source, msg)
  if not msg then msg, source = source, myName() end
  send("audit", "INFO", source, msg)
end

function M.warn(source, msg)
  if not msg then msg, source = source, myName() end
  send("audit", "WARN", source, msg)
end

function M.error(source, msg)
  if not msg then msg, source = source, myName() end
  send("errors", "ERROR", source, msg)
end

function M.critical(source, msg)
  if not msg then msg, source = source, myName() end
  send("errors", "CRITICAL", source, msg)
end

function M.security(source, msg)
  if not msg then msg, source = source, myName() end
  send("security", "SEC", source, msg)
end

function M.audit(source, msg)
  if not msg then msg, source = source, myName() end
  send("audit", "AUDIT", source, msg)
end

function M.network(source, msg)
  if not msg then msg, source = source, myName() end
  send("network", "NET", source, msg)
end

function M.system(source, msg)
  if not msg then msg, source = source, myName() end
  send("system", "INFO", source, msg)
end

return M
