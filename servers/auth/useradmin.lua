-- useradmin.lua
--
-- console-only user management for the auth server. anything in
-- here can create/promote/demote admin accounts, which is exactly
-- why it's console-only and not exposed to clients at all -
-- physical access to the auth computer is the boundary.
--
-- usage:
--   useradmin list
--   useradmin add <username> <role>
--   useradmin del <username>
--   useradmin passwd <username>
--   useradmin role <username> <role>
--   useradmin display <username> <name>

local sha256 = require("/lib/sha256")
local users  = require("/auth/lib/users")
local logger = require("/lib/logger")

local VALID_ROLES = { admin = true, user = true, guest = true }

local function confirm(prompt)
  io.write(prompt .. " (yes/no): ")
  local r = io.read()
  if not r then return false end
  return r:lower() == "yes" or r:lower() == "y"
end

local function cmdList()
  local all = users.load()
  if not next(all) then print("No users."); return end

  print(string.format("%-20s %-8s %s", "USERNAME", "ROLE", "DISPLAY"))
  print(string.rep("-", 52))

  local list = {}
  for uname, data in pairs(all) do
    table.insert(list, { u = uname, d = data })
  end

  -- admins first, then users, then guests - just easier to scan
  -- than alphabetical when you're trying to spot who has elevated
  -- access
  table.sort(list, function(a, b)
    if a.d.role ~= b.d.role then
      local order = { admin = 1, user = 2, guest = 3 }
      return (order[a.d.role] or 9) < (order[b.d.role] or 9)
    end
    return a.u < b.u
  end)

  for _, v in ipairs(list) do
    print(string.format("%-20s %-8s %s", v.u, v.d.role, v.d.display))
  end
end

local function cmdAdd(username, role)
  if not username or username == "" then
    print("Usage: useradmin add <username> <role>")
    return
  end
  role = role or "user"
  if not VALID_ROLES[role] then
    print("Invalid role. Use: admin, user, guest")
    return
  end
  if users.load()[username] then
    print("User already exists: " .. username)
    return
  end

  if role == "admin" then
    print("WARNING: Creating admin account.")
    if not confirm("Are you sure?") then
      print("Cancelled.")
      return
    end
  end

  io.write("Display name (blank = " .. username .. "): ")
  local display = io.read()
  if not display or display == "" then display = username end

  io.write("Password: ")
  local pw = read("*")
  if not pw or pw == "" then
    print("Password cannot be empty.")
    return
  end
  io.write("Confirm: ")
  local pw2 = read("*")
  if pw ~= pw2 then
    print("Passwords do not match.")
    return
  end

  local ok, err = users.create(username, sha256(pw), role, display)
  if ok then
    print("Created: " .. username .. " [" .. role .. "]")
    logger.audit("auth-server",
      "Console: user created " .. username .. " [" .. role .. "]")
  else
    print("Error: " .. tostring(err))
  end
end

local function cmdDel(username)
  if not username then
    print("Usage: useradmin del <username>")
    return
  end
  local all = users.load()
  if not all[username] then
    print("Not found: " .. username)
    return
  end

  print("Delete: " .. username .. " [" .. all[username].role .. "]")
  if not confirm("Are you sure?") then
    print("Cancelled.")
    return
  end

  local ok, err = users.delete(username)
  if ok then
    print("Deleted: " .. username)
    logger.audit("auth-server", "Console: user deleted " .. username)
  else
    print("Error: " .. tostring(err))
  end
end

local function cmdPasswd(username)
  if not username then
    print("Usage: useradmin passwd <username>")
    return
  end
  if not users.load()[username] then
    print("Not found: " .. username)
    return
  end

  io.write("New password: ")
  local pw = read("*")
  if not pw or pw == "" then
    print("Password cannot be empty.")
    return
  end
  io.write("Confirm: ")
  local pw2 = read("*")
  if pw ~= pw2 then
    print("Passwords do not match.")
    return
  end

  local ok, err = users.changePassword(username, sha256(pw))
  if ok then
    print("Password changed: " .. username)
    logger.audit("auth-server", "Console: password changed for " .. username)
  else
    print("Error: " .. tostring(err))
  end
end

local function cmdRole(username, newRole)
  if not username or not newRole then
    print("Usage: useradmin role <username> <role>")
    return
  end
  if not VALID_ROLES[newRole] then
    print("Invalid role. Use: admin, user, guest")
    return
  end
  if not users.load()[username] then
    print("Not found: " .. username)
    return
  end

  if newRole == "admin" then
    print("WARNING: Promoting to admin.")
    if not confirm("Are you sure?") then
      print("Cancelled.")
      return
    end
  end

  local ok, err = users.changeRole(username, newRole)
  if ok then
    print(username .. " is now [" .. newRole .. "]")
    logger.audit("auth-server",
      "Console: role changed " .. username .. " -> " .. newRole)
  else
    print("Error: " .. tostring(err))
  end
end

local function cmdDisplay(username, newDisplay)
  if not username or not newDisplay then
    print("Usage: useradmin display <username> <name>")
    return
  end
  local ok, err = users.changeDisplay(username, newDisplay)
  if ok then
    print(username .. " display -> " .. newDisplay)
  else
    print("Error: " .. tostring(err))
  end
end

local function help()
  print("useradmin list")
  print("useradmin add <user> <role>")
  print("useradmin del <user>")
  print("useradmin passwd <user>")
  print("useradmin role <user> <role>")
  print("useradmin display <user> <name>")
  print("Roles: admin, user, guest")
end

local args = { ... }
local cmd  = args[1]

if     not cmd or cmd == "help" then help()
elseif cmd == "list"            then cmdList()
elseif cmd == "add"             then cmdAdd(args[2], args[3])
elseif cmd == "del"             then cmdDel(args[2])
elseif cmd == "passwd"          then cmdPasswd(args[2])
elseif cmd == "role"            then cmdRole(args[2], args[3])
elseif cmd == "display"         then cmdDisplay(args[2], args[3])
else   print("Unknown: " .. cmd); help()
end
