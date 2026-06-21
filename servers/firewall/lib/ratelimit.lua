-- ratelimit.lua
--
-- per-computer-ID rate limiting, 30 requests per 60-second
-- window. this is a fixed window, not a true sliding window -
-- the window resets to a fresh count the moment it expires
-- rather than smoothly rolling. that means a client could
-- technically send 30 requests right at the tail end of one
-- window and another 30 right at the start of the next, getting
-- up to 60 through in a much shorter span than 60 seconds. for
-- what this is actually defending against (a misbehaving client
-- hammering the network, not a serious DoS adversary) that
-- boundary case hasn't mattered enough to justify a proper
-- sliding-window or token-bucket implementation.

local M       = {}
local windows = {}
local MAX     = 30
local WINDOW  = 60

function M.check(id)
  local now = os.clock()
  local w   = windows[id]

  if not w or now - w.start > WINDOW then
    windows[id] = { count = 1, start = now }
    return true
  end

  if w.count >= MAX then return false end
  w.count = w.count + 1
  return true
end

function M.reset(id)
  windows[id] = nil
end

return M
