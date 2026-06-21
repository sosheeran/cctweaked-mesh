-- addresses.lua
--
-- maps usernames to mail addresses. keyed by username rather
-- than computer_id specifically because a CC:Tweaked terminal
-- can be shared - several different players might log in from
-- the same physical computer over time, and each of them needs
-- their own separate mailbox regardless of which terminal they
-- happened to use.

local M      = {}
local CFG    = "/mail/data/addresses.cfg"
local DOMAIN = "mc-net.red"

function M.load()
  local addresses = {}
  if not fs.exists(CFG) then return addresses end
  local f = fs.open(CFG, "r")
  if not f then return addresses end

  local line = f.readLine()
  while line do
    if not line:match("^#") and line:match("|") then
      local cid, username, display, role = line:match(
        "^%s*(.-)%s*|%s*(.-)%s*|%s*(.-)%s*|%s*(.-)%s*$")
      if username and username ~= "" then
        addresses[username:lower()] = {
          computer_id = tonumber(cid) or 0,
          username    = username,
          display     = display or username,
          role        = role    or "user",
          address     = username .. "@" .. DOMAIN,
        }
      end
    end
    line = f.readLine()
  end
  f.close()
  return addresses
end

function M.save(addresses)
  if not fs.exists("/mail/data") then
    fs.makeDir("/mail/data")
  end
  local f = fs.open(CFG, "w")
  if not f then return false end

  f.writeLine("# computer_id | username | display | role")
  for _, addr in pairs(addresses) do
    f.writeLine(
      tostring(addr.computer_id) .. " | " ..
      (addr.username or "")      .. " | " ..
      (addr.display  or "")      .. " | " ..
      (addr.role     or "user"))
  end
  f.close()
  return true
end

-- called from the login flow each time someone signs in, so the
-- address always reflects whichever computer they most recently
-- logged in from
function M.register(computer_id, username, display, role)
  local addresses = M.load()
  local key     = username:lower()
  local is_new  = not addresses[key]

  addresses[key] = {
    computer_id = computer_id,
    username    = username,
    display     = display or username,
    role        = role    or "user",
    address     = username .. "@" .. DOMAIN,
  }
  M.save(addresses)
  return addresses[key], is_new
end

function M.getByUsername(username)
  if not username then return nil end
  return M.load()[username:lower()]
end

-- this is keyed by username, not computer_id, so finding "the"
-- address for a computer means scanning every entry. if more
-- than one username has ever logged in from this same computer,
-- whichever one pairs() happens to land on first wins here -
-- there's no actual "most recent" tracking, despite what that
-- might sound like. fine for a single-player-per-terminal setup,
-- worth knowing if that assumption ever stops holding
function M.getByID(computer_id)
  for _, addr in pairs(M.load()) do
    if addr.computer_id == computer_id then
      return addr
    end
  end
  return nil
end

function M.getByAddress(address)
  if not address then return nil end
  local username = address:match("^(.-)@")
  if not username then return nil end
  return M.getByUsername(username)
end

function M.getByRole(role)
  local result = {}
  for _, addr in pairs(M.load()) do
    if addr.role == role then
      table.insert(result, addr)
    end
  end
  return result
end

function M.getDomain()
  return DOMAIN
end

return M
