-- noc.lua
-- console tool for the NOC server
--
-- usage:
--   noc alerts
--   noc ack <id>
--   noc remove <id>
--   noc clear
--   noc status

local alerts = require("/noc/lib/alerts")
local net    = require("/lib/network")

local LEVEL_COLOR = {
  INFO     = colors.white,
  WARN     = colors.yellow,
  ERROR    = colors.red,
  CRITICAL = colors.red,
}

local function setColor(c)
  if term.isColor and term.isColor() then
    term.setTextColor(c)
  end
end
local function reset() setColor(colors.white) end

local function cmdAlerts()
  local list = alerts.getSorted()
  if #list == 0 then
    setColor(colors.green)
    print("No active alerts.")
    reset()
    return
  end

  print(string.format("%-4s %-8s %-16s %-4s %s",
    "ID", "LEVEL", "SOURCE", "ACK", "MESSAGE"))
  print(string.rep("-", 60))

  for _, alert in ipairs(list) do
    local color = LEVEL_COLOR[alert.level] or colors.white
    if alert.acked then color = colors.lightGray end
    setColor(color)
    print(string.format("%-4d %-8s %-16s %-4s %s",
      alert.id,
      tostring(alert.level):sub(1, 7),
      tostring(alert.source):sub(1, 15),
      alert.acked and "yes" or "no",
      tostring(alert.message):sub(1, 30)))
    reset()
  end

  print("")
  print("Total: " .. #list .. "  Unacked: " .. alerts.getUnackedCount())
end

local function cmdAck(id_str)
  if not id_str then print("Usage: noc ack <id>"); return end
  local id = tonumber(id_str)
  if not id then print("Invalid ID"); return end

  if alerts.ack(id) then
    setColor(colors.green)
    print("Alert " .. id .. " acknowledged")
    reset()
  else
    print("Alert " .. id .. " not found")
  end
end

local function cmdRemove(id_str)
  if not id_str then print("Usage: noc remove <id>"); return end
  local id = tonumber(id_str)
  if not id then print("Invalid ID"); return end

  if alerts.remove(id) then
    setColor(colors.green)
    print("Alert " .. id .. " removed")
    reset()
  else
    print("Alert " .. id .. " not found")
  end
end

local function cmdClear()
  print("Cleared " .. alerts.clearAcked() .. " acknowledged alerts")
end

local function cmdStatus()
  print("=== NOC STATUS ===")
  print("Time:    " .. os.date())
  local uptime = math.floor(os.clock())
  local up_h   = math.floor(uptime / 3600)
  local up_m   = math.floor(uptime / 60) % 60
  print(string.format("Uptime:  %dh %02dm", up_h, up_m))
  print("Alerts:  " .. #alerts.getSorted() ..
        " (" .. alerts.getUnackedCount() .. " unacked)")
end

local function help()
  print("noc alerts         list all alerts")
  print("noc ack <id>       acknowledge alert")
  print("noc remove <id>    delete alert")
  print("noc clear          remove all acked alerts")
  print("noc status         system overview")
end

local args = { ... }
local cmd  = args[1]

if     not cmd or cmd == "help" then help()
elseif cmd == "alerts" then cmdAlerts()
elseif cmd == "ack"    then cmdAck(args[2])
elseif cmd == "remove" then cmdRemove(args[2])
elseif cmd == "clear"  then cmdClear()
elseif cmd == "status" then cmdStatus()
else   print("Unknown: " .. cmd); help()
end
