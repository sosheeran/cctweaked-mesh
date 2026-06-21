-- servers/noc/server.lua
-- network operations center, computer ID 6, bottom modem only
--
-- pings every other service once a minute and raises an alert
-- (logged + mailed to admins) the moment one stops answering, and
-- another when it comes back. also the place alerts from any
-- other trusted server land and get tracked until acknowledged.

local alerts     = require("/noc/lib/alerts")
local nocmonitor = require("/noc/lib/nocmonitor")
local logger     = require("/lib/logger")
local net        = require("/lib/network")

local PING_IV   = 60
local RENDER_IV = 5

rednet.open("bottom")

print("[NOC] ID: " .. os.getComputerID())
print("[NOC] " .. os.date())

local has_monitor = nocmonitor.open()
if has_monitor then
  nocmonitor.render()
  print("[NOC] Monitor active")
end

logger.audit("noc-server", "NOC server started - " .. os.date())

local function notifyAdmins(subject, body)
  pcall(rednet.send, net.ID.MAIL, textutils.serialize({
    type    = "mail_broadcast",
    role    = "admin",
    subject = subject,
    body    = body,
    from    = "noc-server",
  }))
end

local last_ping   = -60
local was_offline = {}

-- pinging every service has to match what's actually in this
-- build - crafting/fluid (5/7) used to be here but were dropped
-- when this network was trimmed down to working services only,
-- otherwise this would alert "offline" on something that was
-- never running in the first place
local function pingServers()
  local server_ids = { 0, 1, 2, 3, 4, 6 }
  local my_id = os.getComputerID()

  -- fire every ping up front rather than ping-wait-ping-wait one
  -- at a time, then sit in a single collection window listening
  -- for whatever pongs come back. one 5-second window covers all
  -- of them instead of N sequential round trips, so a full sweep
  -- of the network takes roughly 5s total regardless of how many
  -- services there are, not 5s times the service count
  for _, id in ipairs(server_ids) do
    if id ~= my_id then
      rednet.send(id, textutils.serialize({
        type = "ping",
        from = my_id,
        ts   = os.clock(),
      }))
    end
  end

  local responded = {}
  local deadline   = os.clock() + 5
  while os.clock() < deadline do
    local sender, raw = rednet.receive(0.5)
    if sender and raw then
      local ok, msg = pcall(textutils.unserialize, raw)
      if ok and type(msg) == "table" and msg.type == "pong" then
        responded[sender] = true
      end
    end
  end

  for _, id in ipairs(server_ids) do
    if id ~= my_id then
      local online = responded[id] == true
      local name   = net.getName(id)
      nocmonitor.updateStatus(id, online)

      if not online and not was_offline[id] then
        was_offline[id] = true
        local msg = name .. " (ID " .. id .. ") is OFFLINE"
        alerts.create("ERROR", "noc-server", msg, os.date())
        logger.error("noc-server", msg)
        notifyAdmins("SERVER OFFLINE: " .. name, name .. " has gone offline.")
        print("[NOC] OFFLINE: " .. name)
      elseif online and was_offline[id] then
        was_offline[id] = false
        local msg = name .. " (ID " .. id .. ") is back ONLINE"
        alerts.create("INFO", "noc-server", msg, os.date())
        logger.audit("noc-server", msg)
        notifyAdmins("SERVER ONLINE: " .. name, name .. " is back online.")
        print("[NOC] ONLINE: " .. name)
      end
    end
  end
end

nocmonitor.updateStatus(os.getComputerID(), true)

local function handlePing(sender_id, msg)
  rednet.send(sender_id, textutils.serialize({
    type = "pong",
    from = os.getComputerID(),
    ts   = msg.ts,
  }))
end

local function handleAlert(sender_id, msg)
  if not net.isTrusted(sender_id) then return end
  alerts.create(
    msg.level or "WARN",
    msg.source or net.getName(sender_id),
    msg.message or "",
    os.date())
end

local function handleAlertAck(sender_id, msg)
  if not net.isTrusted(sender_id) then return end
  alerts.ack(msg.alert_id)
end

local function handleAlertRemove(sender_id, msg)
  if not net.isTrusted(sender_id) then return end
  alerts.remove(msg.alert_id)
end

local function handleStatusRequest(sender_id, msg)
  rednet.send(sender_id, textutils.serialize({
    type        = "status_response",
    time        = os.date(),
    alert_count = alerts.getUnackedCount(),
    id          = msg.id,
  }))
end

local HANDLERS = {
  ping           = handlePing,
  alert          = handleAlert,
  alert_ack      = handleAlertAck,
  alert_remove   = handleAlertRemove,
  status_request = handleStatusRequest,
}

local last_render = os.clock()

while true do
  if os.clock() - last_ping >= PING_IV then
    pingServers()
    last_ping = os.clock()
  end

  if os.clock() - last_render >= RENDER_IV then
    if has_monitor then nocmonitor.render() end
    last_render = os.clock()
  end

  local sender_id, raw = rednet.receive(1)
  if sender_id and raw then
    local ok, msg = pcall(textutils.unserialize, raw)
    if ok and type(msg) == "table" then
      local handler = HANDLERS[msg.type]
      if handler then
        local ok_h, err = pcall(handler, sender_id, msg)
        if not ok_h then
          logger.error("noc-server",
            "Handler crash [" .. tostring(msg.type) .. "]: " .. tostring(err))
        end
      end
    end
  end
end
