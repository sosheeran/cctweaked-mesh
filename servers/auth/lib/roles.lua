-- roles.lua
--
-- what each role is actually allowed to do, plus a rough per-role
-- storage request limit (guests get capped hard, admins don't).
-- three roles: guest, user, admin.

local M = {}

local PERMISSIONS = {
  guest = {
    "storage.query",
    "storage.request",
    "terminal.use",
  },
  user = {
    "storage.query",
    "storage.request",
    "storage.discover",
    "terminal.use",
    "noc.view",
    "mail.send",
    "mail.receive",
  },
  admin = {
    "storage.query",
    "storage.request",
    "storage.discover",
    "storage.modify",
    "terminal.use",
    "noc.view",
    "noc.manage",
    "user.manage",
    "room.access",
    "alert.resolve",
    "server.manage",
    "mail.send",
    "mail.receive",
    "mail.manage",
    "log.view",
    "log.manage",
  },
}

local LIMITS = {
  guest = 64,
  user  = 1000,
  admin = math.huge,
}

-- linear scan through the role's permission list - fine here,
-- each role only has a handful of permission strings, not worth
-- a lookup table for this size
function M.hasPermission(role, perm)
  local perms = PERMISSIONS[role]
  if not perms then return false end
  for _, p in ipairs(perms) do
    if p == perm then return true end
  end
  return false
end

function M.getLimit(role)
  return LIMITS[role] or LIMITS.guest
end

function M.isValid(role)
  return PERMISSIONS[role] ~= nil
end

return M
