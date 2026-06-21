-- servers/mail/server.lua
-- mail server, computer ID 3, bottom modem only
--
-- player-to-player messages, system alerts, admin broadcasts,
-- and address lookups for other servers (storage uses this to
-- find a player's mail address when delivering an order).

local mailbox      = require("/mail/lib/mailbox")
local addresses    = require("/mail/lib/addresses")
local alerts_inbox = require("/mail/lib/alerts_inbox")
local logger       = require("/lib/logger")
local net          = require("/lib/network")

rednet.open("bottom")

print("[MAIL] ID: " .. os.getComputerID())
print("[MAIL] Mail server started")
logger.audit("mail-server", "Mail server started")

local function respond(sender_id, response, reply_id)
  if not response then return end
  response._reply_id = reply_id
  rednet.send(sender_id, textutils.serialize(response))
end

local function handlePing(sender_id, msg)
  rednet.send(sender_id, textutils.serialize({
    type = "pong",
    from = os.getComputerID(),
    ts   = msg.ts,
  }))
  return nil
end

-- called by auth right after a successful login, so a mail
-- address always exists before a player ever opens their inbox
local function handleRegister(sender_id, msg)
  if not net.isTrusted(sender_id) then
    return { type = "register_response", success = false,
             reason = "Unauthorized", id = msg.id }
  end

  local addr, is_new = addresses.register(
    msg.computer_id, msg.username, msg.display, msg.role)

  if is_new then
    logger.audit("mail-server",
      "New address registered: " .. addr.address ..
      " (ID " .. tostring(msg.computer_id) .. ")")
    mailbox.deliver(
      msg.computer_id,
      "system@mc-net.red",
      "Welcome to mc-net.red",
      "Welcome, " .. (msg.display or msg.username) ..
      "!\n\nYour mail address is: " .. addr.address ..
      "\n\nYou can send and receive messages " ..
      "from other players on this network.\n\n" ..
      "- The MC-NET Team")
  end

  return {
    type    = "register_response",
    success = true,
    address = addr.address,
    id      = msg.id,
  }
end

local function handleSend(sender_id, msg)
  local recipient
  if msg.to_computer_id then
    recipient = addresses.getByID(msg.to_computer_id)
  elseif msg.to_address then
    recipient = addresses.getByAddress(msg.to_address)
  end

  if not recipient then
    return {
      type    = "send_response",
      success = false,
      reason  = "Recipient not found: " ..
                tostring(msg.to_address or msg.to_computer_id),
      id      = msg.id,
    }
  end

  -- validated_user comes from the firewall, which already
  -- confirmed the sender's identity at login - using that instead
  -- of just trusting computer_id is what keeps the "from" address
  -- correct if a terminal is ever shared between accounts
  local from_addr = "system@mc-net.red"
  if msg.validated_user and msg.validated_user ~= "" then
    local from = addresses.getByUsername(msg.validated_user)
    if from then from_addr = from.address end
  elseif msg.from_computer_id then
    local from = addresses.getByID(msg.from_computer_id)
    if from then from_addr = from.address end
  elseif msg.from then
    from_addr = msg.from
  end

  local msg_id = mailbox.deliver(
    recipient.computer_id, from_addr,
    msg.subject or "(no subject)", msg.body or "")

  logger.network("mail-server",
    "Mail: " .. from_addr .. " -> " .. recipient.address)

  return {
    type    = "send_response",
    success = true,
    msg_id  = msg_id,
    id      = msg.id,
  }
end

local function handleBroadcast(sender_id, msg)
  if not net.isTrusted(sender_id) then
    return { type = "broadcast_response", success = false,
             reason = "Unauthorized", id = msg.id }
  end

  local count = 0
  for _, addr in ipairs(addresses.getByRole(msg.role or "admin")) do
    mailbox.deliver(
      addr.computer_id, msg.from or "system@mc-net.red",
      msg.subject or "(no subject)", msg.body or "")
    count = count + 1
  end

  return { type = "broadcast_response", success = true, count = count, id = msg.id }
end

local function handleGetInbox(sender_id, msg)
  local cid = msg.computer_id or sender_id
  return {
    type     = "inbox_response",
    messages = mailbox.load(cid),
    unread   = mailbox.unreadCount(cid),
    id       = msg.id,
  }
end

local function handleUnreadCount(sender_id, msg)
  local cid = msg.computer_id or sender_id
  return { type = "unread_response", count = mailbox.unreadCount(cid), id = msg.id }
end

local function handleMarkRead(sender_id, msg)
  local cid = msg.computer_id or sender_id
  if msg.msg_id then
    mailbox.markRead(cid, msg.msg_id)
  else
    mailbox.markAllRead(cid)
  end
  return { type = "mark_read_response", success = true, id = msg.id }
end

local function handleDelete(sender_id, msg)
  local cid = msg.computer_id or sender_id
  return { type = "delete_response", success = mailbox.delete(cid, msg.msg_id), id = msg.id }
end

-- used by other servers (storage, mostly) to look up a player's
-- mail address before sending them a delivery notification
local function handleGetAddress(sender_id, msg)
  if not net.isTrusted(sender_id) then
    return { type = "address_response", success = false,
             reason = "Unauthorized", id = msg.id }
  end

  local addr
  if msg.computer_id then
    addr = addresses.getByID(msg.computer_id)
  elseif msg.username then
    addr = addresses.getByUsername(msg.username)
  elseif msg.address then
    addr = addresses.getByAddress(msg.address)
  end

  if not addr then
    return { type = "address_response", success = false,
             reason = "Address not found", id = msg.id }
  end

  return {
    type        = "address_response",
    success     = true,
    computer_id = addr.computer_id,
    username    = addr.username,
    display     = addr.display,
    address     = addr.address,
    role        = addr.role,
    id          = msg.id,
  }
end

-- storage calls this after it's pushed items into a player's
-- ender chest, so the player gets told to go check it
local function handleDeliveryNotify(sender_id, msg)
  if not net.isTrusted(sender_id) then
    return { type = "delivery_notify_response", success = false,
             reason = "Unauthorized", id = msg.id }
  end

  local cid  = msg.computer_id
  local item = msg.item or "items"
  local qty  = msg.qty  or 0
  local addr = addresses.getByID(cid)
  local name = addr and addr.display or "Player " .. tostring(cid)

  mailbox.deliver(
    cid, "storage@mc-net.red", "Package Delivered",
    "Your order has been delivered!\n\n" ..
    "Item:     " .. item .. "\n" ..
    "Quantity: " .. tostring(qty) .. "\n" ..
    "Time:     " .. os.date() .. "\n\n" ..
    "Check your ender chest to collect.")

  logger.audit("mail-server",
    "Delivery notification sent to " .. tostring(name) ..
    " - " .. tostring(qty) .. "x " .. tostring(item))

  return { type = "delivery_notify_response", success = true, id = msg.id }
end

-- any trusted server can raise an alert. routing priority:
-- a specific computer_id if given, else a specific role if
-- given, else falls back to every admin - so a careless caller
-- that forgets to specify a target still reaches someone rather
-- than silently going nowhere
local function handleSendAlert(sender_id, msg)
  if not net.isTrusted(sender_id) then
    return { type = "alert_response", success = false,
             reason = "Unauthorized", id = msg.id }
  end

  local severity = msg.severity or alerts_inbox.SEVERITY.WARNING
  local source   = msg.source   or net.getName(sender_id)
  local title    = msg.title    or msg.subject or "(alert)"
  local body     = msg.body     or ""

  if msg.to_computer_id then
    alerts_inbox.deliver(msg.to_computer_id, severity, source, title, body)
  elseif msg.to_role then
    for _, addr in ipairs(addresses.getByRole(msg.to_role)) do
      alerts_inbox.deliver(addr.computer_id, severity, source, title, body)
    end
  else
    for _, addr in ipairs(addresses.getByRole("admin")) do
      alerts_inbox.deliver(addr.computer_id, severity, source, title, body)
    end
  end

  logger.network("mail-server",
    "Alert [" .. severity .. "] from " .. source .. ": " .. title)

  return { type = "alert_response", success = true, id = msg.id }
end

local function handleGetAlerts(sender_id, msg)
  local cid = msg.computer_id or sender_id
  return {
    type   = "alerts_response",
    alerts = alerts_inbox.load(cid),
    unread = alerts_inbox.unreadCount(cid),
    id     = msg.id,
  }
end

local function handleAlertsUnread(sender_id, msg)
  local cid = msg.computer_id or sender_id
  return { type = "alerts_unread_response", count = alerts_inbox.unreadCount(cid), id = msg.id }
end

-- one round trip instead of two for the client's main menu,
-- which wants both badge counts at once on every screen refresh
local function handleUnreadAll(sender_id, msg)
  local cid = msg.computer_id or sender_id
  return {
    type         = "unread_all_response",
    mail_unread  = mailbox.unreadCount(cid),
    alert_unread = alerts_inbox.unreadCount(cid),
    id           = msg.id,
  }
end

local function handleAlertMarkRead(sender_id, msg)
  local cid = msg.computer_id or sender_id
  alerts_inbox.markRead(cid, msg.alert_id)
  return { type = "alert_mark_read_response", success = true, id = msg.id }
end

local function handleAlertDelete(sender_id, msg)
  local cid = msg.computer_id or sender_id
  alerts_inbox.delete(cid, msg.alert_id)
  return { type = "alert_delete_response", success = true, id = msg.id }
end

local HANDLERS = {
  ping                  = handlePing,
  mail_register         = handleRegister,
  mail_send             = handleSend,
  mail_broadcast        = handleBroadcast,
  mail_inbox            = handleGetInbox,
  mail_unread           = handleUnreadCount,
  mail_mark_read        = handleMarkRead,
  mail_delete           = handleDelete,
  mail_get_address      = handleGetAddress,
  mail_delivery_notify  = handleDeliveryNotify,
  mail_send_alert       = handleSendAlert,
  mail_get_alerts       = handleGetAlerts,
  mail_alerts_unread    = handleAlertsUnread,
  mail_unread_all       = handleUnreadAll,
  mail_alert_mark_read  = handleAlertMarkRead,
  mail_alert_delete     = handleAlertDelete,
}

while true do
  local sender_id, raw = rednet.receive(1)
  if sender_id and raw then
    local ok, msg = pcall(textutils.unserialize, raw)
    if ok and type(msg) == "table" then
      local reply_id = msg._reply_id
      msg._reply_id  = nil

      local handler = HANDLERS[msg.type]
      if handler then
        local ok_h, response = pcall(handler, sender_id, msg)
        if ok_h then
          respond(sender_id, response, reply_id)
        else
          logger.error("mail-server",
            "Handler crash [" .. tostring(msg.type) .. "]: " .. tostring(response))
          respond(sender_id, {
            type   = "error",
            reason = "Internal server error",
            id     = msg.id,
          }, reply_id)
        end
      else
        logger.warn("mail-server",
          "Unknown packet: " .. tostring(msg.type) .. " from " .. tostring(sender_id))
      end
    end
  end
end
