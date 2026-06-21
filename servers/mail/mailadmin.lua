-- mailadmin.lua
-- console tool for the mail server, physical access only
--
-- usage:
--   mailadmin list
--   mailadmin send <address> <subject> <body>
--   mailadmin inbox <computer_id>
--   mailadmin delete <computer_id> <msg_id>
--
-- (a "chest" subcommand shows up referenced elsewhere from an
-- earlier design pass but was never actually implemented here -
-- not currently a real command)

local mailbox   = require("/mail/lib/mailbox")
local addresses = require("/mail/lib/addresses")

local function setColor(c)
  if term.isColor and term.isColor() then
    term.setTextColor(c)
  end
end
local function reset() setColor(colors.white) end

local function cmdList()
  local all = addresses.load()
  if not next(all) then print("No addresses."); return end

  print(string.format("%-6s %-24s %-8s %s", "CID", "ADDRESS", "ROLE", "DISPLAY"))
  print(string.rep("-", 55))

  local list = {}
  for _, addr in pairs(all) do
    table.insert(list, addr)
  end
  table.sort(list, function(a, b) return a.computer_id < b.computer_id end)

  for _, addr in ipairs(list) do
    print(string.format("%-6d %-24s %-8s %s",
      addr.computer_id, addr.address:sub(1, 23), addr.role, addr.display))
  end
end

local function cmdSend(address, subject, body)
  if not address or not subject then
    print("Usage: mailadmin send <address> <subject> <body>")
    return
  end
  local addr = addresses.getByAddress(address)
  if not addr then
    print("Address not found: " .. address)
    return
  end

  mailbox.deliver(addr.computer_id, "admin@mc-net.red", subject, body or "")
  setColor(colors.green)
  print("Sent to " .. address)
  reset()
end

local function cmdInbox(cid_str)
  if not cid_str then
    print("Usage: mailadmin inbox <computer_id>")
    return
  end
  local cid = tonumber(cid_str)
  if not cid then print("Invalid ID"); return end

  local addr = addresses.getByID(cid)
  local msgs = mailbox.load(cid)
  if #msgs == 0 then
    print("Inbox empty for ID " .. cid)
    return
  end

  print("Inbox: " .. (addr and addr.address or cid) .. " (" .. #msgs .. " messages)")
  print(string.rep("-", 50))
  for _, msg in ipairs(msgs) do
    local read_tag = msg.read and " " or "*"
    setColor(msg.read and colors.lightGray or colors.white)
    print(string.format("[%s] #%-4d %-20s %s",
      read_tag, msg.id, msg.from:sub(1, 19), msg.subject:sub(1, 25)))
    reset()
  end
end

local function cmdDelete(cid_str, msg_id_str)
  if not cid_str or not msg_id_str then
    print("Usage: mailadmin delete <computer_id> <msg_id>")
    return
  end
  local cid, msg_id = tonumber(cid_str), tonumber(msg_id_str)
  if not cid or not msg_id then
    print("Invalid arguments")
    return
  end

  if mailbox.delete(cid, msg_id) then
    setColor(colors.green)
    print("Deleted message " .. msg_id)
    reset()
  else
    print("Message not found")
  end
end

local function help()
  print("mailadmin list")
  print("mailadmin send <address> <subject> <body>")
  print("mailadmin inbox <cid>")
  print("mailadmin delete <cid> <msg_id>")
end

local args = { ... }
local cmd  = args[1]

if     not cmd or cmd == "help" then help()
elseif cmd == "list"   then cmdList()
elseif cmd == "send"   then cmdSend(args[2], args[3], args[4])
elseif cmd == "inbox"  then cmdInbox(args[2])
elseif cmd == "delete" then cmdDelete(args[2], args[3])
else   print("Unknown: " .. cmd); help()
end
