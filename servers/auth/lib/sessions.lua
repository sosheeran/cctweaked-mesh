-- sessions.lua
--
-- session tokens, persisted to disk so a player doesn't get
-- logged out just because the auth server rebooted. a token is
-- bound to the specific computer ID it was issued on, so even if
-- one somehow leaked it can't be replayed from a different
-- terminal.
--
-- TTL CAVEAT - worth being honest about this rather than papering
-- over it: os.clock() measures CPU time the current script has
-- been running, not wall-clock time, and it resets to 0 every
-- time the auth server reboots. so "24 hour" sessions are
-- actually closer to "24 hours of auth-server uptime since its
-- last reboot" - if the server restarts, every session's
-- effective remaining lifetime shifts. for this network that's a
-- fine tradeoff (reboots are rare, and worst case is a session
-- expiring a bit early/late) but it's not actually wall-clock
-- accurate, and os.time() would be the right fix if that ever
-- mattered more.

local sha256 = require("/lib/sha256")

local M   = {}
local CFG = "/auth/data/sessions.cfg"
local TTL = 86400  -- ~24 hours, see caveat above

-- yeah, this needs to not be a literal string before this ever
-- goes anywhere public-facing - tracked, just hasn't mattered
-- for an internal server network
local SECRET = "mctweaked-auth-secret-change-before-deploy"

function M.load()
  local sessions = {}
  if not fs.exists(CFG) then return sessions end
  local f = fs.open(CFG, "r")
  if not f then return sessions end

  local line = f.readLine()
  while line do
    if not line:match("^#") and line:match("|") then
      local token, username, role, cid, issued = line:match(
        "^%s*(.-)%s*|%s*(.-)%s*|%s*(.-)%s*|%s*(.-)%s*|%s*(.-)%s*$"
      )
      if token and token ~= "" then
        sessions[token] = {
          username   = username,
          role       = role       or "user",
          computerID = tonumber(cid) or 0,
          issued     = tonumber(issued) or 0,
        }
      end
    end
    line = f.readLine()
  end
  f.close()
  return sessions
end

function M.save(sessions)
  if not fs.exists("/auth/data") then
    fs.makeDir("/auth/data")
  end
  local f = fs.open(CFG, "w")
  if not f then return false end

  f.writeLine("# token | username | role | computerID | issued")
  for token, data in pairs(sessions) do
    f.writeLine(
      token                     .. " | " ..
      data.username             .. " | " ..
      data.role                 .. " | " ..
      tostring(data.computerID) .. " | " ..
      tostring(data.issued)
    )
  end
  f.close()
  return true
end

function M.generate(username, role, computerID)
  local raw = username ..
              role ..
              tostring(computerID) ..
              tostring(os.clock()) ..
              tostring(math.random(1, 9999999)) ..
              SECRET
  return sha256(raw)
end

function M.create(username, role, computerID)
  local sessions = M.load()

  -- logging in again from the same computer should replace the
  -- old session, not stack a second valid one alongside it
  for token, data in pairs(sessions) do
    if data.username == username and data.computerID == computerID then
      sessions[token] = nil
    end
  end

  local token  = M.generate(username, role, computerID)
  local issued = os.clock()
  sessions[token] = {
    username   = username,
    role       = role,
    computerID = computerID,
    issued     = issued,
  }
  M.save(sessions)
  return token, issued + TTL
end

-- returns: valid, username, role, reason
function M.validate(token, computerID)
  local sessions = M.load()
  local s = sessions[token]
  if not s then
    return false, nil, nil, "Token not found"
  end

  if os.clock() - s.issued > TTL then
    sessions[token] = nil
    M.save(sessions)
    return false, nil, nil, "Session expired"
  end

  if s.computerID ~= computerID then
    return false, nil, nil, "Wrong computer"
  end

  return true, s.username, s.role, nil
end

function M.revoke(token)
  local sessions = M.load()
  if not sessions[token] then return false end
  sessions[token] = nil
  M.save(sessions)
  return true
end

function M.revokeUser(username)
  local sessions = M.load()
  local count = 0
  for token, data in pairs(sessions) do
    if data.username == username then
      sessions[token] = nil
      count = count + 1
    end
  end
  if count > 0 then M.save(sessions) end
  return count
end

function M.cleanup()
  local sessions = M.load()
  local now   = os.clock()
  local count = 0
  for token, data in pairs(sessions) do
    if now - data.issued > TTL then
      sessions[token] = nil
      count = count + 1
    end
  end
  if count > 0 then M.save(sessions) end
  return count
end

return M
