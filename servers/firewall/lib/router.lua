-- router.lua
--
-- decides which internal server a packet goes to, and reshapes
-- it into whatever format that server actually expects. auth
-- packets skip straight there since auth does its own session
-- handling; everything else is a service_request that gets
-- looked up by service name.

local net = require("/lib/network")
local M   = {}

-- goes straight to auth, no service lookup needed
--
-- note: card_verify/card_issue are listed here and validated
-- by validator.lua's schema, but there's no actual handler for
-- them in auth/server.lua right now - looks like a keycard/
-- physical-access feature that got scaffolded but never
-- finished. routing a card_verify packet here would currently
-- just fall through to auth's "unknown packet type" warning.
local AUTH_DIRECT = {
  login           = true,
  logout          = true,
  change_password = true,
  user_create     = true,
  user_delete     = true,
  user_list       = true,
  card_verify     = true,
  card_issue      = true,
}

-- reshapes a validated service_request into the packet format
-- the target server actually expects. mail just unwraps its
-- inner payload as-is; storage has a couple of specific actions
-- it cares about; anything else falls through to a generic
-- passthrough that just strips the request envelope
local function translate(msg)
  local service = msg.service
  local action  = msg.action
  local data     = msg.data or {}
  local role     = msg.validated_role or "guest"

  if service == "mail-server" or service == "mail" then
    local inner = data
    inner.computer_id    = msg.sender_id
    inner.validated_role = role
    inner.validated_user = msg.validated_username
    inner.id             = msg.id
    return inner
  end

  if service == "storage" or service == "master-storage" then
    if action == "query" or action == "storage_query" then
      return {
        type        = "storage_query",
        query       = data.query,
        item_key    = data.item_key,
        amount      = data.amount or 1,
        role        = role,
        computer_id = msg.sender_id,
        id          = msg.id,
        sender_id   = msg.sender_id,
      }
    elseif action == "pull" or action == "storage_pull" then
      return {
        type        = "storage_pull",
        order       = data.order,
        job_id      = data.job_id,
        role        = role,
        computer_id = msg.sender_id,
        id          = msg.id,
        sender_id   = msg.sender_id,
      }
    end
  end

  msg.data           = nil
  msg.validated_role = role
  msg.computer_id    = msg.sender_id
  return msg
end

local SERVICE_MAP = {
  ["mail-server"]    = net.ID.MAIL,
  ["mail"]           = net.ID.MAIL,
  ["master-storage"] = net.ID.STORAGE,
  ["storage"]        = net.ID.STORAGE,
  ["noc-server"]     = net.ID.NOC,
  ["noc"]            = net.ID.NOC,
}

function M.route(msg)
  local t = msg.type

  if AUTH_DIRECT[t] then
    return net.ID.AUTH, msg, nil
  end

  if t == "service_request" then
    local id = SERVICE_MAP[msg.service] or net.getID(msg.service)
    if not id then
      return nil, msg, "Unknown service: " .. tostring(msg.service)
    end
    return id, translate(msg), nil
  end

  return nil, msg, "No route for type: " .. tostring(t)
end

return M
