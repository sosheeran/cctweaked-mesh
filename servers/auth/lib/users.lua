-- users.lua
--
-- user accounts, password verification, basic CRUD. accounts are
-- stored in a pipe-delimited cfg file rather than JSON - this
-- predates JSON support being added elsewhere in the network and
-- it's never been worth migrating since it works fine.
--
-- password handling: the client hashes the raw password with
-- sha256 before it ever leaves the terminal (so plaintext never
-- crosses the network), then this server hashes that again with
-- a per-user random salt before storing it. worth being clear
-- about what this does and doesn't protect against - it stops
-- plaintext passwords sitting on disk or in transit, and salting
-- defeats precomputed rainbow-table attacks against the stored
-- hashes. it is NOT a substitute for a proper slow KDF like
-- bcrypt/argon2 - sha256 is fast, which is exactly what you don't
-- want for password hashing against brute force. fine for what
-- this network actually needs to defend against, worth knowing
-- the limitation if this pattern got reused somewhere with higher
-- stakes.

local sha256 = require("/lib/sha256")

local M   = {}
local CFG = "/auth/data/users.cfg"

function M.load()
  local users = {}
  if not fs.exists(CFG) then return users end
  local f = fs.open(CFG, "r")
  if not f then return users end

  local line = f.readLine()
  while line do
    if not line:match("^#") and line:match("|") then
      local username, hash, salt, role, display = line:match(
        "^%s*(.-)%s*|%s*(.-)%s*|%s*(.-)%s*|%s*(.-)%s*|%s*(.-)%s*$"
      )
      if username and username ~= "" and hash and hash ~= "" then
        users[username] = {
          hash    = hash,
          salt    = salt    or "",
          role    = role    or "user",
          display = display or username,
        }
      end
    end
    line = f.readLine()
  end
  f.close()
  return users
end

function M.save(users)
  if not fs.exists("/auth/data") then
    fs.makeDir("/auth/data")
  end
  local f = fs.open(CFG, "w")
  if not f then return false end

  f.writeLine("# username | hash | salt | role | display")
  for username, data in pairs(users) do
    f.writeLine(
      username     .. " | " ..
      data.hash    .. " | " ..
      data.salt    .. " | " ..
      data.role    .. " | " ..
      data.display
    )
  end
  f.close()
  return true
end

function M.exists()
  if not fs.exists(CFG) then return false end
  return next(M.load()) ~= nil
end

function M.generateSalt()
  local chars = "abcdefghijklmnopqrstuvwxyz" ..
                "ABCDEFGHIJKLMNOPQRSTUVWXYZ" ..
                "0123456789"
  local salt = ""
  for i = 1, 32 do
    local idx = math.random(1, #chars)
    salt = salt .. chars:sub(idx, idx)
  end
  return salt
end

function M.hashPassword(prehash, salt)
  return sha256(prehash .. salt)
end

-- prehash is sha256(raw password) - already hashed once on the
-- client side before it reaches here
function M.verify(username, prehash)
  local users = M.load()
  local user  = users[username]
  if not user then
    return false, "Invalid username or password"
  end

  local computed = M.hashPassword(prehash, user.salt)
  if computed ~= user.hash then
    return false, "Invalid username or password"
  end
  return true, user
end

function M.create(username, prehash, role, display)
  local users = M.load()
  if users[username] then
    return false, "User already exists: " .. username
  end

  local salt = M.generateSalt()
  users[username] = {
    hash    = M.hashPassword(prehash, salt),
    salt    = salt,
    role    = role    or "user",
    display = display or username,
  }
  M.save(users)
  return true, nil
end

function M.delete(username)
  local users = M.load()
  if not users[username] then
    return false, "User not found: " .. username
  end
  users[username] = nil
  M.save(users)
  return true, nil
end

function M.changePassword(username, prehash)
  local users = M.load()
  if not users[username] then
    return false, "User not found: " .. username
  end
  local salt = M.generateSalt()
  users[username].hash = M.hashPassword(prehash, salt)
  users[username].salt = salt
  M.save(users)
  return true, nil
end

function M.changeRole(username, newRole)
  local users = M.load()
  if not users[username] then
    return false, "User not found: " .. username
  end
  users[username].role = newRole
  M.save(users)
  return true, nil
end

function M.changeDisplay(username, newDisplay)
  local users = M.load()
  if not users[username] then
    return false, "User not found: " .. username
  end
  users[username].display = newDisplay
  M.save(users)
  return true, nil
end

return M
