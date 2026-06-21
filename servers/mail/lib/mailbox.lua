-- mailbox.lua
--
-- per-player inbox storage, one cfg file per computer ID, capped
-- at 25 messages (oldest gets dropped once full).
--
-- worth flagging a real inconsistency rather than pretending it
-- isn't there: addresses.lua keys mail addresses by USERNAME
-- specifically because a terminal can be shared between players -
-- but this file keys the actual inbox storage by COMPUTER_ID, not
-- username. in practice that means if two different usernames
-- ever logged into the same physical terminal, they'd currently
-- be reading and writing the same inbox file. fine as long as
-- "one player per terminal" holds in practice, which it has so
-- far on this server, but it's a real gap between the two
-- modules' assumptions and would need fixing (keying this by
-- username like addresses.lua does) before that assumption could
-- safely be relaxed.

local M        = {}
local BASE     = "/mail/data/inbox/"
local MAX_MSGS = 25

local function ensureDir(path)
  if not fs.exists(path) then fs.makeDir(path) end
end

local function inboxPath(computer_id)
  return BASE .. tostring(computer_id) .. ".cfg"
end

function M.load(computer_id)
  local path = inboxPath(computer_id)
  local msgs = {}
  if not fs.exists(path) then return msgs end
  local f = fs.open(path, "r")
  if not f then return msgs end

  local line = f.readLine()
  while line do
    if not line:match("^#") and line:match("|") then
      local id, from, subject, body, date, read = line:match(
        "^%s*(.-)%s*|%s*(.-)%s*|%s*(.-)%s*|" ..
        "%s*(.-)%s*|%s*(.-)%s*|%s*(.-)%s*$")
      if id and id ~= "" then
        table.insert(msgs, {
          id      = tonumber(id) or 0,
          from    = from    or "",
          subject = subject or "",
          body    = body    or "",
          date    = date    or "",
          read    = (read == "true"),
        })
      end
    end
    line = f.readLine()
  end
  f.close()

  table.sort(msgs, function(a, b) return a.id > b.id end)
  return msgs
end

function M.save(computer_id, msgs)
  ensureDir(BASE)
  local f = fs.open(inboxPath(computer_id), "w")
  if not f then return false end

  f.writeLine("# id | from | subject | body | date | read")
  for _, msg in ipairs(msgs) do
    -- subject/body are free text from the player and could
    -- contain a literal "|", which would otherwise corrupt the
    -- pipe-delimited row on the next load
    local safe_sub  = tostring(msg.subject):gsub("|", "\\|")
    local safe_body = tostring(msg.body):gsub("|", "\\|")
    f.writeLine(
      tostring(msg.id)   .. " | " ..
      (msg.from or "")   .. " | " ..
      safe_sub           .. " | " ..
      safe_body          .. " | " ..
      (msg.date or "")   .. " | " ..
      tostring(msg.read))
  end
  f.close()
  return true
end

local function nextID(msgs)
  local max = 0
  for _, msg in ipairs(msgs) do
    if msg.id > max then max = msg.id end
  end
  return max + 1
end

function M.deliver(computer_id, from, subject, body)
  ensureDir(BASE)
  local msgs = M.load(computer_id)

  local msg = {
    id      = nextID(msgs),
    from    = from    or "system@mc-net.red",
    subject = subject or "(no subject)",
    body    = body    or "",
    date    = os.date(),
    read    = false,
  }
  table.insert(msgs, 1, msg)

  while #msgs > MAX_MSGS do
    table.remove(msgs, #msgs)
  end

  M.save(computer_id, msgs)
  return msg.id
end

function M.markRead(computer_id, msg_id)
  local msgs = M.load(computer_id)
  for _, msg in ipairs(msgs) do
    if msg.id == msg_id then
      msg.read = true
      M.save(computer_id, msgs)
      return true
    end
  end
  return false
end

function M.markAllRead(computer_id)
  local msgs = M.load(computer_id)
  for _, msg in ipairs(msgs) do
    msg.read = true
  end
  M.save(computer_id, msgs)
end

function M.delete(computer_id, msg_id)
  local msgs = M.load(computer_id)
  for i, msg in ipairs(msgs) do
    if msg.id == msg_id then
      table.remove(msgs, i)
      M.save(computer_id, msgs)
      return true
    end
  end
  return false
end

function M.unreadCount(computer_id)
  local count = 0
  for _, msg in ipairs(M.load(computer_id)) do
    if not msg.read then count = count + 1 end
  end
  return count
end

function M.get(computer_id, msg_id)
  for _, msg in ipairs(M.load(computer_id)) do
    if msg.id == msg_id then return msg end
  end
  return nil
end

return M
