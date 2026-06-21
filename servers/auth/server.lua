-- servers/auth/server.lua
-- auth server, computer ID 1, bottom modem only
--
-- handles login/logout/session validation, password changes,
-- and admin user management. on first boot, if there are no
-- accounts at all yet, it walks through creating the domain
-- admin right here on the console rather than over the network -
-- that account never touches rednet during creation.

local users    = require("/auth/lib/users")
local sessions = require("/auth/lib/sessions")
local roles    = require("/auth/lib/roles")
local sha256   = require("/lib/sha256")
local logger   = require("/lib/logger")
local net      = require("/lib/network")

local MODEM      = "bottom"
local CLEANUP_IV = 3600  -- sweep expired sessions once an hour

rednet.open(MODEM)

print("[AUTH] ID: " .. os.getComputerID())

local function bootstrap()
  if users.exists() then return end

  print("")
  print("=== FIRST RUN: DOMAIN ADMIN SETUP ===")
  print("No users found. Create domain admin account.")
  print("")

  local username, password, display

  repeat
    io.write("Admin username: ")
    username = io.read()
    if not username or username == "" then
      print("Username cannot be empty")
      username = nil
    end
  until username

  io.write("Display name (blank = " .. username .. "): ")
  display = io.read()
  if not display or display == "" then display = username end

  repeat
    io.write("Password: ")
    password = read("*")
    if not password or password == "" then
      print("Password cannot be empty")
      password = nil
    end
  until password

  io.write("Confirm password: ")
  local confirm = read("*")
  if password ~= confirm then
    print("Passwords do not match. Restart to try again.")
    return
  end

  -- hash the same way a client would before sending it over
  -- rednet, so the admin account is created consistently with
  -- how every other account gets created
  local prehash = sha256(password)
  local ok, err = users.create(username, prehash, "admin", display)

  if ok then
    print("")
    print("[AUTH] Domain admin created: " .. username)
    logger.audit("auth-server",
      "Bootstrap: domain admin created - " .. username)
  else
    print("[AUTH] ERROR: " .. tostring(err))
  end

  print("======================================")
  print("")
end

bootstrap()
print("[AUTH] Server started")
logger.audit("auth-server", "Auth server started")

-- ------------------------------------------------------------
-- brute force protection - five bad attempts from the same
-- computer ID locks it out for five minutes
-- ------------------------------------------------------------
local failed     = {}
local LOCK_COUNT = 5
local LOCK_SECS  = 300

local function isLockedOut(cid)
  local a = failed[cid]
  if not a then return false end
  if a.count < LOCK_COUNT then return false end
  if os.clock() - a.time > LOCK_SECS then
    failed[cid] = nil
    return false
  end
  return true
end

local function recordFail(cid, username)
  if not failed[cid] then
    failed[cid] = { count = 0, time = os.clock() }
  end
  failed[cid].count = failed[cid].count + 1
  failed[cid].time  = os.clock()
  if failed[cid].count >= LOCK_COUNT then
    logger.security("auth-server",
      "BRUTE FORCE from computer " .. cid ..
      " username=" .. tostring(username))
  end
end

local function clearFail(cid)
  failed[cid] = nil
end

-- the firewall correlates responses back to the original caller
-- by reply_id, so it always has to ride along on the way out -
-- handlers that don't need to answer anything (ping) just return
-- nil and this quietly does nothing
local function respond(sender_id, response, reply_id)
  if not response then return end
  response._reply_id = reply_id
  rednet.send(sender_id, textutils.serialize(response))
end

local function handleLogin(msg, sender_id)
  local cid = msg.computerID or sender_id

  if isLockedOut(cid) then
    logger.security("auth-server",
      "Login blocked - locked out: computer " .. cid)
    return {
      type    = "login_response",
      success = false,
      reason  = "Too many failed attempts. Try again later.",
      id      = msg.id,
    }
  end

  local ok, user = users.verify(msg.username, msg.password)
  if not ok then
    recordFail(cid, msg.username)
    logger.security("auth-server",
      "Failed login: '" .. tostring(msg.username) ..
      "' from computer " .. cid)
    return {
      type    = "login_response",
      success = false,
      reason  = user,  -- error message lives here on failure
      id      = msg.id,
    }
  end

  clearFail(cid)
  local token, expiry = sessions.create(msg.username, user.role, cid)
  logger.audit("auth-server",
    "Login: " .. msg.username ..
    " [" .. user.role .. "]" ..
    " computer=" .. cid)

  -- mail server needs to know this computer ID maps to this
  -- username so it has somewhere to deliver mail - fire and
  -- forget, login shouldn't fail just because mail is briefly down
  pcall(rednet.send, net.ID.MAIL, textutils.serialize({
    type        = "mail_register",
    computer_id = cid,
    username    = msg.username,
    display     = user.display,
    role        = user.role,
  }))

  return {
    type    = "login_response",
    success = true,
    token   = token,
    role    = user.role,
    display = user.display,
    expiry  = expiry,
    id      = msg.id,
  }
end

local function handleValidate(msg, sender_id)
  local cid = msg.computerID or sender_id
  local valid, username, role, reason =
    sessions.validate(msg.token, cid)

  if not valid then
    return {
      type   = "validate_response",
      valid  = false,
      reason = reason,
      id     = msg.id,
    }
  end

  local permitted = true
  if msg.permission then
    permitted = roles.hasPermission(role, msg.permission)
  end

  return {
    type      = "validate_response",
    valid     = true,
    username  = username,
    role      = role,
    permitted = permitted,
    limit     = roles.getLimit(role),
    id        = msg.id,
  }
end

local function handleLogout(msg, sender_id)
  local revoked = sessions.revoke(msg.token)
  if revoked then
    logger.audit("auth-server", "Logout from computer " .. sender_id)
  end
  return {
    type    = "logout_response",
    success = revoked,
    id      = msg.id,
  }
end

local function handleChangePassword(msg, sender_id)
  local valid, caller, caller_role =
    sessions.validate(msg.token, sender_id)
  if not valid then
    return {
      type    = "passwd_response",
      success = false,
      reason  = "Invalid session",
      id      = msg.id,
    }
  end

  local tuser = users.load()[msg.target_username]
  if not tuser then
    return {
      type    = "passwd_response",
      success = false,
      reason  = "User not found",
      id      = msg.id,
    }
  end

  -- rules: admins can reset user/guest passwords, but not each
  -- other's - that's console-only, intentionally, so a compromised
  -- admin session can't escalate to every other admin account.
  -- everyone else can only ever touch their own password.
  if caller_role == "admin" then
    if tuser.role == "admin" and caller ~= msg.target_username then
      logger.security("auth-server",
        "Admin " .. caller ..
        " tried to change admin password for " ..
        msg.target_username)
      return {
        type    = "passwd_response",
        success = false,
        reason  = "Cannot change admin passwords from client. Use console.",
        id      = msg.id,
      }
    end
  elseif msg.target_username ~= caller then
    logger.security("auth-server",
      caller .. " tried to change password for " ..
      msg.target_username)
    return {
      type    = "passwd_response",
      success = false,
      reason  = "You can only change your own password",
      id      = msg.id,
    }
  end

  local ok, err = users.changePassword(msg.target_username, msg.new_password)
  if not ok then
    return {
      type    = "passwd_response",
      success = false,
      reason  = tostring(err),
      id      = msg.id,
    }
  end

  -- old sessions were tied to the old password's identity in
  -- spirit if not literally - force a fresh login after a
  -- password change rather than leave a stale session valid
  sessions.revokeUser(msg.target_username)
  logger.audit("auth-server",
    "Password changed: " .. msg.target_username .. " by " .. caller)
  return {
    type    = "passwd_response",
    success = true,
    id      = msg.id,
  }
end

local function handleUserCreate(msg, sender_id)
  local valid, caller, caller_role =
    sessions.validate(msg.token, sender_id)
  if not valid or caller_role ~= "admin" then
    return {
      type    = "user_create_response",
      success = false,
      reason  = "Admin session required",
      id      = msg.id,
    }
  end

  if msg.role == "admin" then
    logger.security("auth-server",
      "Admin " .. caller ..
      " tried to create admin account via client")
    return {
      type    = "user_create_response",
      success = false,
      reason  = "Cannot create admin accounts from client. Use console.",
      id      = msg.id,
    }
  end

  local ok, err = users.create(msg.username, msg.password, msg.role, msg.display)
  if not ok then
    return {
      type    = "user_create_response",
      success = false,
      reason  = tostring(err),
      id      = msg.id,
    }
  end

  logger.audit("auth-server",
    "User created: " .. msg.username ..
    " [" .. (msg.role or "user") .. "]" ..
    " by " .. caller)
  return {
    type    = "user_create_response",
    success = true,
    id      = msg.id,
  }
end

local function handleUserDelete(msg, sender_id)
  local valid, caller, caller_role =
    sessions.validate(msg.token, sender_id)
  if not valid or caller_role ~= "admin" then
    return {
      type    = "user_delete_response",
      success = false,
      reason  = "Admin session required",
      id      = msg.id,
    }
  end

  local tuser = users.load()[msg.target_username]
  if not tuser then
    return {
      type    = "user_delete_response",
      success = false,
      reason  = "User not found",
      id      = msg.id,
    }
  end

  if tuser.role == "admin" then
    logger.security("auth-server",
      "Admin " .. caller ..
      " tried to delete admin " .. msg.target_username)
    return {
      type    = "user_delete_response",
      success = false,
      reason  = "Cannot delete admin accounts from client. Use console.",
      id      = msg.id,
    }
  end

  sessions.revokeUser(msg.target_username)
  local ok, err = users.delete(msg.target_username)
  if not ok then
    return {
      type    = "user_delete_response",
      success = false,
      reason  = tostring(err),
      id      = msg.id,
    }
  end

  logger.audit("auth-server",
    "User deleted: " .. msg.target_username .. " by " .. caller)
  return {
    type    = "user_delete_response",
    success = true,
    id      = msg.id,
  }
end

local function handleUserList(msg, sender_id)
  local valid, _, caller_role = sessions.validate(msg.token, sender_id)
  if not valid or caller_role ~= "admin" then
    return {
      type    = "user_list_response",
      success = false,
      reason  = "Admin session required",
      id      = msg.id,
    }
  end

  local list = {}
  for uname, data in pairs(users.load()) do
    table.insert(list, {
      username = uname,
      display  = data.display,
      role     = data.role,
    })
  end

  return {
    type    = "user_list_response",
    success = true,
    users   = list,
    id      = msg.id,
  }
end

local function handlePing(msg, sender_id)
  rednet.send(sender_id, textutils.serialize({
    type = "pong",
    from = os.getComputerID(),
    ts   = msg.ts,
  }))
  return nil
end

local HANDLERS = {
  login           = handleLogin,
  logout          = handleLogout,
  validate        = handleValidate,
  change_password = handleChangePassword,
  user_create     = handleUserCreate,
  user_delete     = handleUserDelete,
  user_list       = handleUserList,
  ping            = handlePing,
}

local last_cleanup = os.clock()

while true do
  if os.clock() - last_cleanup > CLEANUP_IV then
    local n = sessions.cleanup()
    if n > 0 then
      logger.info("auth-server", "Cleaned " .. n .. " expired sessions")
    end
    last_cleanup = os.clock()
  end

  local sender_id, raw = rednet.receive(1)
  if sender_id and raw then
    local ok, msg = pcall(textutils.unserialize, raw)
    if ok and type(msg) == "table" then
      local reply_id = msg._reply_id
      msg._reply_id  = nil

      local handler = HANDLERS[msg.type]
      if handler then
        local ok_h, response = pcall(handler, msg, sender_id)
        if ok_h then
          respond(sender_id, response, reply_id)
        else
          logger.error("auth-server",
            "Handler crash [" .. tostring(msg.type) .. "]: " ..
            tostring(response))
          respond(sender_id, {
            type   = "error",
            reason = "Internal server error",
            id     = msg.id,
          }, reply_id)
        end
      else
        logger.warn("auth-server",
          "Unknown packet type: " .. tostring(msg.type) ..
          " from " .. sender_id)
      end
    end
  end
end
