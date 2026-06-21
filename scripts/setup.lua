-- setup.lua
-- one-time interactive setup for the storage server: assigns the
-- receive/send/bash ender chests and groups whatever obsidian
-- chests are left into columns of 3 (bottom/mid/top).
--
-- usage: setup
--
-- note: the receive/send chests are described below as talking
-- to "the crafting server" - that's the intended design, but
-- crafting isn't part of this build yet (see README), so for now
-- those two chests just won't have anything actually feeding
-- them or pulling from them. direct storage requests don't need
-- them at all.

local W = term.getSize()

local function header(title)
  term.setTextColor(colors.yellow)
  print(string.rep("=", W))
  print("  " .. title)
  print(string.rep("=", W))
  term.setTextColor(colors.white)
end

local function ok(msg)
  term.setTextColor(colors.green)
  print("[OK] " .. msg)
  term.setTextColor(colors.white)
end

local function warn(msg)
  term.setTextColor(colors.yellow)
  print("[WARN] " .. msg)
  term.setTextColor(colors.white)
end

-- Scan obsidian chests - just list by number, no content check
local function scanObsidian()
  local chests = {}
  for _, name in ipairs(peripheral.getNames()) do
    if name:find("ironchest_obsidian") then
      local num = tonumber(name:match("_(%d+)$"))
      if num then
        table.insert(chests, {name=name, num=num})
      end
    end
  end
  table.sort(chests, function(a,b) return a.num < b.num end)
  return chests
end

-- Scan ender chests
local function scanEnder()
  local chests = {}
  for _, name in ipairs(peripheral.getNames()) do
    if name:match("^minecraft:ender chest_") then
      local num = tonumber(
        name:match("minecraft:ender chest_(%d+)")) or 0
      table.insert(chests, {name=name, num=num})
    end
  end
  table.sort(chests, function(a,b) return a.num < b.num end)
  return chests
end

local function displayObsidian(chests, excluded)
  excluded = excluded or {}
  print(string.format("  %-5s %s", "NUM", "NAME"))
  print("  " .. string.rep("-", 45))
  for _, c in ipairs(chests) do
    if not excluded[c.name] then
      print(string.format("  %-5d %s", c.num, c.name))
    end
  end
end

local function displayEnder(chests, excluded)
  excluded = excluded or {}
  print(string.format("  %-5s %s", "NUM", "NAME"))
  print("  " .. string.rep("-", 45))
  for _, e in ipairs(chests) do
    if not excluded[e.name] then
      print(string.format("  %-5d %s", e.num, e.name))
    end
  end
end

local function pickEnder(chests, label, excluded)
  excluded = excluded or {}
  io.write(label .. " number: ")
  local num  = tonumber(io.read())
  local name = "minecraft:ender chest_" .. tostring(num)
  for _, e in ipairs(chests) do
    if e.name == name and not excluded[name] then
      return e
    end
  end
  warn("Not found, try again")
  return pickEnder(chests, label, excluded)
end

local function saveConfig(receive, send, bash, trash, columns)
  if not fs.exists("/data") then fs.makeDir("/data") end
  local f = fs.open("/data/config.cfg", "w")
  f.writeLine("# Master storage configuration")
  f.writeLine("receive = " .. receive)
  f.writeLine("send    = " .. send)
  f.writeLine("bash    = " .. bash)
  if trash and trash ~= "" then
    f.writeLine("trash   = " .. trash)
  end
  f.close()

  local g = fs.open("/data/columns.cfg", "w")
  g.writeLine("# Storage columns")
  g.writeLine("# bottom | mid | top")
  for _, col in ipairs(columns) do
    g.writeLine(col.bottom .. " | " ..
                col.mid    .. " | " ..
                col.top)
  end
  g.close()
end

-- main
term.clear()
term.setCursorPos(1,1)
header("MASTER STORAGE SETUP")
print("")

local obs    = scanObsidian()
local enders = scanEnder()
local excl   = {}

print("Found " .. #obs .. " obsidian chests")
print("Found " .. #enders .. " ender chests")
print("")

-- STEP 1: RECEIVE ENDER CHEST
header("STEP 1: RECEIVE ENDER CHEST")
print("Items arrive here from crafting server (not in this build yet).")
print("")
displayEnder(enders, excl)
print("")
local recv = pickEnder(enders, "Receive", excl)
excl[recv.name] = true
ok("Receive: " .. recv.name)

-- STEP 2: SEND ENDER CHEST
print("")
header("STEP 2: SEND ENDER CHEST")
print("Items leave here to crafting server (not in this build yet).")
print("")
displayEnder(enders, excl)
print("")
local send = pickEnder(enders, "Send", excl)
excl[send.name] = true
ok("Send: " .. send.name)

-- STEP 3: BASH ENDER CHEST
print("")
header("STEP 3: BASH ENDER CHEST")
print("Overflow and leftovers go here.")
print("Linked to all condenser machines.")
print("")
displayEnder(enders, excl)
print("")
local bash = pickEnder(enders, "Bash", excl)
excl[bash.name] = true
ok("Bash: " .. bash.name)

-- STEP 4: TRASH (optional)
print("")
header("STEP 4: TRASH PERIPHERAL (optional)")
print("Items to void get pushed here.")
print("Leave blank to skip.")
print("")
io.write("Trash peripheral name (or blank): ")
local trash = io.read()
if trash == "" then trash = nil end
if trash then ok("Trash: " .. trash) end

-- STEP 5: COLUMN GROUPING
print("")
header("STEP 5: STORAGE COLUMNS")
print("Remaining obsidian chests grouped into")
print("columns of 3 (bottom, mid, top).")
print("")

local remaining = {}
for _, c in ipairs(obs) do
  if not excl[c.name] then
    table.insert(remaining, c)
  end
end

print("Obsidian chests available: " .. #remaining)
if #remaining % 3 ~= 0 then
  warn(#remaining .. " chests - not divisible by 3")
end
print("")
displayObsidian(remaining, {})
print("")
print("Chests will be grouped in number order:")
print("  Col 1: chests 0,1,2  Col 2: chests 3,4,5 etc")
print("")
io.write("Confirm grouping? (y/n): ")
local confirm = io.read()
if confirm ~= "y" then
  print("Aborted. Re-run setup when ready.")
  return
end

local columns = {}
local i = 1
while i <= #remaining do
  table.insert(columns, {
    bottom = remaining[i]   and remaining[i].name   or "",
    mid    = remaining[i+1] and remaining[i+1].name or "",
    top    = remaining[i+2] and remaining[i+2].name or "",
  })
  i = i + 3
end

ok(#columns .. " columns created")

-- SAVE
saveConfig(recv.name, send.name, bash.name, trash, columns)
print("")
ok("Saved config.cfg and columns.cfg")
print("")
print("Config saved:")
print("  Receive: " .. recv.name)
print("  Send:    " .. send.name)
print("  Bash:    " .. bash.name)
print("")
print("Run 'discover' to map items to columns.")
print("Then 'reboot' to start storage server.")
