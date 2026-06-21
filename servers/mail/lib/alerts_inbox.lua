-- alerts_inbox.lua
--
-- system alerts, separate from regular player mail - shows up in
-- its own Alerts screen on the client, closer to an event viewer
-- than an inbox. severity-coded so the client can color them
-- (CRITICAL/WARNING/INFO). same computer_id-keying caveat applies
-- here as in mailbox.lua.

local M    = {}
local BASE = "/mail/data/alerts/"

local MAX_ALERTS = 100  -- alerts get to keep more history than regular mail

M.SEVERITY = {
  CRITICAL = "CRITICAL",
  WARNING  = "WARNING",
  INFO     = "INFO",
}

M.SOURCE = {
  SECURITY = "security",  -- brute force, blocked IDs, etc
  SYSTEM   = "system",    -- a service going up/down
  STORAGE  = "storage",   -- low stock, overflow events
  ACCOUNT  = "account",   -- password changes, logins
}

local function ensureDir()
  if not fs.exists(BASE) then fs.makeDir(BASE) end
end

local function alertPath(computer_id)
  return BASE .. tostring(computer_id) .. ".cfg"
end

function M.load(computer_id)
  local path   = alertPath(computer_id)
  local alerts = {}
  if not fs.exists(path) then return alerts end
  local f = fs.open(path, "r")
  if not f then return alerts end

  local line = f.readLine()
  while line do
    if not line:match("^#") and line:match("|") then
      local id, severity, source, title, body, date, read = line:match(
        "^%s*(.-)%s*|%s*(.-)%s*|%s*(.-)%s*|" ..
        "%s*(.-)%s*|%s*(.-)%s*|%s*(.-)%s*|%s*(.-)%s*$")
      if id and id ~= "" then
        table.insert(alerts, {
          id       = tonumber(id) or 0,
          severity = severity or M.SEVERITY.INFO,
          source   = source   or "system",
          title    = title    or "",
          body     = body     or "",
          date     = date     or "",
          read     = (read == "true"),
        })
      end
    end
    line = f.readLine()
  end
  f.close()

  table.sort(alerts, function(a, b) return a.id > b.id end)
  return alerts
end

function M.save(computer_id, alerts)
  ensureDir()
  local f = fs.open(alertPath(computer_id), "w")
  if not f then return false end

  f.writeLine("# id | severity | source | title | body | date | read")
  for _, alert in ipairs(alerts) do
    local safe_body  = tostring(alert.body):gsub("|", "\\|")
    local safe_title = tostring(alert.title):gsub("|", "\\|")
    f.writeLine(
      tostring(alert.id) .. " | " ..
      alert.severity     .. " | " ..
      alert.source       .. " | " ..
      safe_title         .. " | " ..
      safe_body          .. " | " ..
      alert.date         .. " | " ..
      tostring(alert.read))
  end
  f.close()
  return true
end

local function nextID(alerts)
  local max = 0
  for _, a in ipairs(alerts) do
    if a.id > max then max = a.id end
  end
  return max + 1
end

function M.deliver(computer_id, severity, source, title, body)
  ensureDir()
  local alerts = M.load(computer_id)

  table.insert(alerts, 1, {
    id       = nextID(alerts),
    severity = severity or M.SEVERITY.INFO,
    source   = source   or "system",
    title    = title    or "(no title)",
    body     = body     or "",
    date     = os.date(),
    read     = false,
  })

  while #alerts > MAX_ALERTS do
    table.remove(alerts, #alerts)
  end

  M.save(computer_id, alerts)
end

function M.markRead(computer_id, alert_id)
  local alerts = M.load(computer_id)
  for _, a in ipairs(alerts) do
    if a.id == alert_id then
      a.read = true
      M.save(computer_id, alerts)
      return true
    end
  end
  return false
end

function M.delete(computer_id, alert_id)
  local alerts = M.load(computer_id)
  for i, a in ipairs(alerts) do
    if a.id == alert_id then
      table.remove(alerts, i)
      M.save(computer_id, alerts)
      return true
    end
  end
  return false
end

function M.unreadCount(computer_id)
  local count = 0
  for _, a in ipairs(M.load(computer_id)) do
    if not a.read then count = count + 1 end
  end
  return count
end

return M
