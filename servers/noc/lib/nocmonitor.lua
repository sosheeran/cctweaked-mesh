-- nocmonitor.lua
--
-- NOC's monitor: a status grid of every service this network
-- actually runs, current time, and a feed of active alerts below
-- that.

local alerts = require("/noc/lib/alerts")
local net    = require("/lib/network")

local M     = {}
local mon   = nil
local mon_w = 51
local mon_h = 19
local SCALE = 0.5

local server_status = {}

function M.open()
  mon = peripheral.find("monitor")
  if not mon then return false end
  pcall(mon.setTextScale, SCALE)
  pcall(mon.setBackgroundColor, colors.black)
  local ok, w, h = pcall(mon.getSize)
  if ok then mon_w = w; mon_h = h end
  return true
end

function M.updateStatus(server_id, online)
  server_status[server_id] = {
    online    = online,
    last_ping = os.clock(),
  }
end

function M.render()
  if not mon then M.open() end
  if not mon then return false end

  local old = term.redirect(mon)
  term.setBackgroundColor(colors.black)
  term.clear()

  local y = 1

  local time_str = os.date("%H:%M:%S")
  term.setCursorPos(1, y)
  term.setBackgroundColor(colors.gray)
  term.setTextColor(colors.yellow)
  local title = " NOC  " .. time_str .. " "
  term.write(title .. string.rep(" ", math.max(0, mon_w - #title)))
  term.setBackgroundColor(colors.black)
  y = y + 1

  term.setCursorPos(1, y)
  term.setTextColor(colors.lightGray)
  term.write(string.rep("-", mon_w))
  y = y + 1

  -- this list has to match the ping list in server.lua - if it
  -- shows a service that isn't actually being pinged, that slot
  -- just sits red/"DN" forever since nothing ever calls
  -- updateStatus for it. crafting/fluid (IDs 5/7) used to be
  -- here but aren't part of this build yet, so they're left off.
  local server_ids = { 0, 1, 2, 3, 4, 6 }
  local cols  = 2
  local col_w = math.floor(mon_w / cols)

  for i, id in ipairs(server_ids) do
    local name   = net.getName(id):sub(1, col_w - 5)
    local status = server_status[id]
    local online = status and status.online or false
    local color  = online and colors.green or colors.red
    local tag    = online and " OK " or " DN "
    local col    = (i - 1) % cols
    local row    = math.floor((i - 1) / cols)
    local x      = col * col_w + 1

    term.setCursorPos(x, y + row)
    term.setTextColor(color)
    term.write(tag)
    term.setTextColor(online and colors.white or colors.red)
    term.write(name)
  end

  y = y + math.ceil(#server_ids / cols) + 1

  term.setCursorPos(1, y)
  term.setTextColor(colors.lightGray)
  term.write(string.rep("-", mon_w))
  y = y + 1

  local alert_list = alerts.getSorted()
  local unacked     = alerts.getUnackedCount()

  if #alert_list == 0 then
    term.setCursorPos(1, y)
    term.setTextColor(colors.green)
    term.write(" No active alerts")
    y = y + 1
  else
    term.setCursorPos(1, y)
    term.setTextColor(unacked > 0 and colors.red or colors.yellow)
    term.write(string.format(" ALERTS: %d (%d unacked)", #alert_list, unacked))
    y = y + 1

    local lines_left = mon_h - y - 1
    local start = math.max(1, #alert_list - lines_left + 1)

    for i = start, #alert_list do
      if y > mon_h - 1 then break end
      local alert = alert_list[i]
      local color = colors.yellow
      if alert.level == "ERROR" or alert.level == "CRITICAL" then color = colors.red end
      if alert.acked then color = colors.lightGray end

      local ack_tag = alert.acked and "~" or "!"
      local line = string.format(" %s[%s] %s: %s",
        ack_tag, alert.level:sub(1, 4), alert.source:sub(1, 10), alert.message)

      term.setCursorPos(1, y)
      term.setTextColor(color)
      if #line > mon_w then line = line:sub(1, mon_w) end
      term.write(line)
      y = y + 1
    end
  end

  term.setCursorPos(1, mon_h)
  term.setTextColor(colors.lightGray)
  local uptime = math.floor(os.clock())
  local up_h   = math.floor(uptime / 3600)
  local up_m   = math.floor(uptime / 60) % 60
  local status = string.format(" UP %dh%02dm  ALERTS:%d", up_h, up_m, #alert_list)
  term.write(status:sub(1, mon_w))

  term.setTextColor(colors.white)
  term.redirect(old)
  return true
end

return M
