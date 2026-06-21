-- servers/log/server.lua
-- log server, computer ID 0, bottom modem only
--
-- every other service ships its logger.lua calls here instead of
-- writing to its own local file. stores entries by category,
-- shows recent activity on a monitor if one's attached, and pages
-- anything ERROR/CRITICAL/SEC straight to NOC so it surfaces as
-- an alert rather than just sitting quietly in a log file.

local logfile    = require("/log/lib/logfile")
local logmonitor = require("/log/lib/logmonitor")
local net        = require("/lib/network")

local NOC_ID    = net.ID.NOC
local RENDER_IV = 5  -- re-render the monitor at most every 5s

rednet.open("bottom")

print("[LOG] ID: " .. os.getComputerID())
print("[LOG] Log server started")

local has_monitor = logmonitor.open()
if has_monitor then
  logmonitor.render()
  print("[LOG] Monitor active")
else
  print("[LOG] No monitor found")
end

logfile.append({
  category = "system",
  level    = "INFO",
  source   = "log-server",
  message  = "Log server started",
  ts       = os.date(),
})

local function notifyNOC(entry)
  pcall(rednet.send, NOC_ID, textutils.serialize({
    type    = "alert",
    level   = entry.level,
    source  = entry.source,
    message = entry.message,
    ts      = entry.ts,
  }))
end

local function handleLog(sender_id, msg)
  if not net.isTrusted(sender_id) then return end
  if type(msg) ~= "table" or not msg.message then return end

  msg.category = msg.category or "system"
  msg.level    = msg.level    or "INFO"
  msg.source   = msg.source   or net.getName(sender_id)
  msg.ts       = msg.ts       or os.time()

  logfile.append(msg)

  local formatted = logfile.format(msg)
  local color = colors.white
  if msg.level == "ERROR" or msg.level == "CRITICAL" then color = colors.red
  elseif msg.level == "WARN"  then color = colors.yellow
  elseif msg.level == "SEC"   then color = colors.orange
  elseif msg.level == "AUDIT" then color = colors.cyan
  elseif msg.level == "NET"   then color = colors.lightBlue
  end
  term.setTextColor(color)
  print(formatted:sub(1, term.getSize()))
  term.setTextColor(colors.white)

  if msg.level == "ERROR" or msg.level == "CRITICAL" or msg.level == "SEC" then
    notifyNOC(msg)
  end
end

local function handleQuery(sender_id, msg)
  if not net.isTrusted(sender_id) then return nil end

  local category = msg.category or "system"
  local entries   = logfile.tail(category, msg.tail or 20)

  return {
    type     = "log_response",
    category = category,
    entries  = entries,
    count    = #entries,
    id       = msg.id,
  }
end

local function handleCritical(sender_id, msg)
  if not net.isTrusted(sender_id) then return nil end

  if msg.action == "list" then
    return { type = "critical_response", entries = logfile.getCritical(), id = msg.id }
  elseif msg.action == "delete" and msg.index then
    logfile.deleteCritical(msg.index)
    return { type = "critical_response", success = true, id = msg.id }
  elseif msg.action == "clear" then
    logfile.clearCritical()
    return { type = "critical_response", success = true, id = msg.id }
  end

  return nil
end

local function handlePing(sender_id, msg)
  rednet.send(sender_id, textutils.serialize({
    type = "pong",
    from = os.getComputerID(),
    ts   = msg.ts,
  }))
end

local last_render = os.clock()

while true do
  if os.clock() - last_render > RENDER_IV then
    if has_monitor then logmonitor.render() end
    last_render = os.clock()
  end

  local sender_id, raw = rednet.receive(1)
  if sender_id and raw then
    local ok, msg = pcall(textutils.unserialize, raw)
    if ok and type(msg) == "table" then
      local response = nil

      if msg.type == "log" then
        handleLog(sender_id, msg)
        -- a new entry just landed - re-render now instead of
        -- waiting up to RENDER_IV seconds to show it
        if has_monitor then
          logmonitor.render()
          last_render = os.clock()
        end
      elseif msg.type == "log_query" then
        response = handleQuery(sender_id, msg)
      elseif msg.type == "log_critical" then
        response = handleCritical(sender_id, msg)
      elseif msg.type == "ping" then
        handlePing(sender_id, msg)
      end

      if response then
        rednet.send(sender_id, textutils.serialize(response))
      end
    end
  end
end
