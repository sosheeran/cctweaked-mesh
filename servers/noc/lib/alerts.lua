-- alerts.lua
--
-- alert storage for NOC - create/list/acknowledge/resolve, all
-- persisted to disk so an admin can come back later and still see
-- what fired while they were away.

local M       = {}
local CFG     = "/noc/data/alerts.cfg"
local next_id = 1

M.LEVELS = {
  INFO     = "INFO",
  WARN     = "WARN",
  ERROR    = "ERROR",
  CRITICAL = "CRITICAL",
}

local function ensureDir()
  if not fs.exists("/noc/data") then
    fs.makeDir("/noc/data")
  end
end

-- worth noting: M.load() bumps next_id based on whatever's
-- already on disk, and M.create() reads, allocates, then writes
-- back. that pattern would be a real race if multiple callers
-- could run it concurrently - but CC:Tweaked scripts execute
-- cooperatively (one coroutine, no real threads), so there's
-- never an actual interleaving where two create() calls could
-- both read the same next_id before either writes. fine here,
-- would need real locking if this pattern got reused somewhere
-- with actual concurrent writers.
function M.load()
  local alerts = {}
  if not fs.exists(CFG) then return alerts end
  local f = fs.open(CFG, "r")
  if not f then return alerts end

  local line = f.readLine()
  while line do
    if not line:match("^#") and line:match("|") then
      local id, level, source, message, ts, acked = line:match(
        "^%s*(.-)%s*|%s*(.-)%s*|%s*(.-)%s*|" ..
        "%s*(.-)%s*|%s*(.-)%s*|%s*(.-)%s*$")
      if id and id ~= "" then
        local aid = tonumber(id)
        alerts[aid] = {
          id      = aid,
          level   = level,
          source  = source,
          message = message,
          ts      = tonumber(ts) or 0,
          acked   = (acked == "true"),
        }
        if aid >= next_id then next_id = aid + 1 end
      end
    end
    line = f.readLine()
  end
  f.close()
  return alerts
end

function M.save(alerts)
  ensureDir()
  local f = fs.open(CFG, "w")
  if not f then return false end

  f.writeLine("# id | level | source | message | date | acked")
  for id, alert in pairs(alerts) do
    f.writeLine(
      tostring(alert.id)    .. " | " ..
      (alert.level   or "") .. " | " ..
      (alert.source  or "") .. " | " ..
      (alert.message or "") .. " | " ..
      tostring(alert.ts)    .. " | " ..
      tostring(alert.acked)
    )
  end
  f.close()
  return true
end

function M.create(level, source, message, date_str)
  local alerts = M.load()
  local id     = next_id
  next_id      = next_id + 1

  alerts[id] = {
    id      = id,
    level   = level    or "WARN",
    source  = source   or "unknown",
    message = message  or "",
    ts      = date_str or os.date(),
    acked   = false,
  }
  M.save(alerts)
  return id
end

function M.ack(id)
  local alerts = M.load()
  if not alerts[id] then return false end
  alerts[id].acked = true
  M.save(alerts)
  return true
end

function M.remove(id)
  local alerts = M.load()
  if not alerts[id] then return false end
  alerts[id] = nil
  M.save(alerts)
  return true
end

function M.clearAcked()
  local alerts = M.load()
  local count  = 0
  for id, alert in pairs(alerts) do
    if alert.acked then
      alerts[id] = nil
      count = count + 1
    end
  end
  M.save(alerts)
  return count
end

function M.getUnackedCount()
  local count = 0
  for _, alert in pairs(M.load()) do
    if not alert.acked then count = count + 1 end
  end
  return count
end

function M.getSorted()
  local list = {}
  for _, alert in pairs(M.load()) do
    table.insert(list, alert)
  end
  table.sort(list, function(a, b) return a.ts < b.ts end)
  return list
end

return M
