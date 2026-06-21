-- storeadmin.lua
-- console tool for the storage server - ender chest mappings,
-- bash routing rules, and manual voiding. run directly on the
-- storage computer.
--
-- usage:
--   storeadmin ender list
--   storeadmin ender add <name> <cid> <chest>
--   storeadmin ender remove <cid>
--   storeadmin ender test <cid>
--   storeadmin bash list
--   storeadmin bash add <item_id> <dest> [reason]
--   storeadmin bash remove <item_id>
--   storeadmin bash generate
--   storeadmin bash test
--   storeadmin void <item> <target_%>

local ender_map = require("/master-storage/lib/ender_map")

local function setColor(c)
  if term.isColor and term.isColor() then
    term.setTextColor(c)
  end
end
local function reset() setColor(colors.white) end
local function ok(m)  setColor(colors.green);  print("[OK] "  ..m); reset() end
local function err(m) setColor(colors.red);    print("[ERR] " ..m); reset() end
local function warn(m)setColor(colors.yellow); print("[WARN] "..m); reset() end

-- bash routing rules, stored straight in this file (no
-- separate bash_router module)
local BASH_CFG = "/data/bash_routes.cfg"

local function loadRoutes()
  local routes = {}
  if not fs.exists(BASH_CFG) then return routes end
  local f = fs.open(BASH_CFG, "r")
  if not f then return routes end
  local line = f.readLine()
  while line do
    if not line:match("^#") and line:match("|") then
      local item_id, dest, reason = line:match(
        "^%s*(.-)%s*|%s*(.-)%s*|%s*(.-)%s*$")
      if item_id and item_id ~= "" then
        routes[item_id] = {destination=dest, reason=reason or ""}
      end
    end
    line = f.readLine()
  end
  f.close()
  return routes
end

local function saveRoutes(routes)
  if not fs.exists("/data") then fs.makeDir("/data") end
  local f = fs.open(BASH_CFG, "w")
  if not f then return false end
  f.writeLine("# item_id | destination | reason")
  local list = {}
  for id, data in pairs(routes) do
    table.insert(list, {id=id, data=data})
  end
  table.sort(list, function(a,b) return a.id < b.id end)
  for _, e in ipairs(list) do
    f.writeLine(e.id .. " | " .. e.data.destination ..
      " | " .. (e.data.reason or ""))
  end
  f.close()
  return true
end

-- ender chest commands
local function enderList()
  local map = ender_map.load()
  if not next(map) then
    print("No ender mappings. Use: storeadmin ender add")
    return
  end
  print(string.format("%-4s %-28s %-32s %s",
    "CID","NAME","CHEST","STATUS"))
  print(string.rep("-",70))
  local list = {}
  for _, e in pairs(map) do table.insert(list, e) end
  table.sort(list, function(a,b)
    return a.computer_id < b.computer_id end)
  for _, e in ipairs(list) do
    local online = peripheral.wrap(e.chest) ~= nil
    setColor(online and colors.white or colors.red)
    print(string.format("%-4d %-28s %-32s %s",
      e.computer_id, e.name:sub(1,27),
      e.chest:sub(1,31),
      online and "online" or "OFFLINE"))
    reset()
  end
end

local function enderAdd(args_table, name, cid_str)
  if not name or not cid_str then
    print("Usage: storeadmin ender add <name> <cid> <chest>")
    print('Example: storeadmin ender add "Seth" 25 "minecraft:ender chest_0"')
    return
  end
  local cid = tonumber(cid_str)
  if not cid then err("Invalid computer ID"); return end
  -- chest names like "minecraft:ender chest_0" have a literal
  -- space in the actual peripheral name, which the shell splits
  -- into separate args - rejoin everything from arg 5 onward and
  -- strip a wrapping quote pair if the caller used one
  local chest_parts = {}
  for i = 5, #args_table do
    table.insert(chest_parts, args_table[i])
  end
  local chest = table.concat(chest_parts, " ")
  chest = chest:match('^"(.-)"$') or
          chest:match("^'(.-)'$") or chest
  if chest == "" then err("Missing chest name"); return end
  if not peripheral.wrap(chest) then
    warn("Chest not visible: " .. chest)
    warn("Saving anyway")
  end
  ender_map.set(name, cid, chest)
  ok("Mapped: [" .. cid .. "] " .. name .. " → " .. chest)
end

local function enderRemove(cid_str)
  if not cid_str then
    print("Usage: storeadmin ender remove <cid>"); return
  end
  local cid = tonumber(cid_str)
  if not cid then err("Invalid ID"); return end
  if ender_map.remove(cid) then
    ok("Removed mapping for " .. cid)
  else
    err("Not found: " .. cid)
  end
end

local function enderTest(cid_str)
  if not cid_str then
    print("Usage: storeadmin ender test <cid>"); return
  end
  local cid   = tonumber(cid_str)
  local entry = ender_map.get(cid)
  if not entry then err("No mapping for " .. tostring(cid)); return end
  print("Computer: " .. cid)
  print("Name:     " .. entry.name)
  print("Chest:    " .. entry.chest)
  local p = peripheral.wrap(entry.chest)
  if p then
    ok("Chest online")
    local ok_s, size = pcall(p.size)
    local ok_l, items = pcall(p.list)
    local used = 0
    if ok_l and items then
      for _ in pairs(items) do used=used+1 end
    end
    if ok_s then
      print(string.format("Slots: %d/%d used", used, size))
    end
  else
    err("Chest OFFLINE")
  end
end

-- bash routing commands
local function bashList()
  local routes = loadRoutes()
  if not next(routes) then
    print("No bash routes. Use: storeadmin bash add")
    print("Or: storeadmin bash generate")
    return
  end
  print(string.format("%-50s %-20s %s",
    "ITEM ID","DESTINATION","REASON"))
  print(string.rep("-",80))
  local list = {}
  for id, data in pairs(routes) do
    table.insert(list, {id=id, data=data})
  end
  table.sort(list, function(a,b) return a.id < b.id end)
  for _, e in ipairs(list) do
    local col = colors.white
    if e.data.destination == "void" then col = colors.red
    elseif e.data.destination:find("storage") then col = colors.cyan
    elseif e.data.destination:find("mob") then col = colors.lime
    end
    setColor(col)
    print(string.format("%-50s %-20s %s",
      e.id:sub(1,49),
      e.data.destination,
      (e.data.reason or ""):sub(1,20)))
    reset()
  end
  local n = 0; for _ in pairs(routes) do n=n+1 end
  print("\nTotal: " .. n)
end

local function bashAdd(item_id, dest, reason)
  if not item_id or not dest then
    print("Usage: storeadmin bash add <item_id> <dest> [reason]")
    print("Destinations: storage_condenser, mob_farm, void")
    return
  end
  local routes = loadRoutes()
  routes[item_id] = {destination=dest, reason=reason or ""}
  saveRoutes(routes)
  ok("Route: " .. item_id .. " → " .. dest)
end

local function bashRemove(item_id)
  if not item_id then
    print("Usage: storeadmin bash remove <item_id>"); return
  end
  local routes = loadRoutes()
  if not routes[item_id] then
    err("No route for: " .. item_id); return
  end
  routes[item_id] = nil
  saveRoutes(routes)
  ok("Removed: " .. item_id)
end

local function bashTest()
  local cfg = {}
  if fs.exists("/data/config.cfg") then
    local f = fs.open("/data/config.cfg","r")
    if f then
      local line = f.readLine()
      while line do
        if not line:match("^#") and line:match("=") then
          local k,v = line:match("^%s*(.-)%s*=%s*(.-)%s*$")
          if k and v then cfg[k]=v end
        end
        line = f.readLine()
      end
      f.close()
    end
  end
  if not cfg.bash then err("Bash not in config.cfg"); return end
  local bash = peripheral.wrap(cfg.bash)
  if not bash then err("Bash chest offline: "..cfg.bash); return end
  local ok_l, items = pcall(bash.list)
  if not ok_l or not items or not next(items) then
    print("Bash chest is empty"); return
  end
  local routes = loadRoutes()
  local counts = {}
  for _, stack in pairs(items) do
    local k = stack.name .. (stack.damage and
      (stack.damage > 0 and ":"..stack.damage or "") or "")
    counts[k] = (counts[k] or 0) + stack.count
  end
  print(string.format("%-42s %-6s %s","ITEM","COUNT","ROUTE TO"))
  print(string.rep("-",65))
  for id, count in pairs(counts) do
    local dest = routes[id] and routes[id].destination
    local base = id:match("^(.-):%d+$")
    if not dest and base then
      dest = routes[base] and routes[base].destination
    end
    local col = dest and colors.white or colors.yellow
    setColor(col)
    print(string.format("%-42s %-6d %s",
      id:sub(1,41), count,
      dest or "UNKNOWN"))
    reset()
  end
end

local function bashGenerate()
  local storage_lib = require("/scripts/lib/storage")
  local store = storage_lib.load()
  if not next(store) then
    err("storage.cfg empty - run discover first"); return
  end
  local routes = loadRoutes()
  local added = 0
  local STORED = {}
  for key in pairs(store) do STORED[key] = true end
  local block_to_outputs = {
    ["minecraft:iron_block"]    = {"minecraft:iron_ingot","minecraft:iron_nugget"},
    ["minecraft:gold_block"]    = {"minecraft:gold_ingot","minecraft:gold_nugget"},
    ["minecraft:diamond_block"] = {"minecraft:diamond"},
    ["minecraft:emerald_block"] = {"minecraft:emerald"},
    ["minecraft:coal_block"]    = {"minecraft:coal"},
    ["minecraft:redstone_block"]= {"minecraft:redstone"},
    ["minecraft:lapis_block"]   = {"minecraft:dye:4"},
    ["minecraft:quartz_block"]  = {"minecraft:quartz"},
    ["minecraft:glowstone"]     = {"minecraft:glowstone_dust"},
    ["thermalfoundation:storage"]  = {"thermalfoundation:material:128","thermalfoundation:material:352"},
    ["thermalfoundation:storage:1"]= {"thermalfoundation:material:129","thermalfoundation:material:353"},
    ["thermalfoundation:storage:2"]= {"thermalfoundation:material:130","thermalfoundation:material:354"},
    ["thermalfoundation:storage:3"]= {"thermalfoundation:material:131","thermalfoundation:material:355"},
    ["thermalfoundation:storage:4"]= {"thermalfoundation:material:132"},
    ["thermalfoundation:storage:5"]= {"thermalfoundation:material:133","thermalfoundation:material:357"},
    ["thermalfoundation:storage:6"]= {"thermalfoundation:material:134","thermalfoundation:material:358"},
    ["thermalfoundation:storage:7"]= {"thermalfoundation:material:135"},
    ["biomesoplenty:gem_block:1"]= {"biomesoplenty:gem:1"},
    ["biomesoplenty:gem_block:2"]= {"biomesoplenty:gem:2"},
    ["biomesoplenty:gem_block:6"]= {"biomesoplenty:gem:6"},
    ["extrautils2:compressedcobblestone:2"]={"minecraft:cobblestone"},
    ["extrautils2:compressedgravel:1"]={"minecraft:gravel"},
  }
  for block_id, outputs in pairs(block_to_outputs) do
    if STORED[block_id] then
      for _, out_id in ipairs(outputs) do
        if not routes[out_id] then
          routes[out_id] = {
            destination = "storage_condenser",
            reason = "auto: from "..
              (block_id:match(":(.-)$") or block_id)
          }
          added = added + 1
          setColor(colors.green)
          print("+ " .. out_id .. " → storage_condenser")
          reset()
        end
      end
    end
  end
  saveRoutes(routes)
  print("")
  ok("Generated " .. added .. " routes")
end

-- manual void command
local function cmdVoid(name_query, target_str)
  if not name_query then
    print("Usage: storeadmin void <item_name> <target_%>")
    print("Example: storeadmin void andesite 38")
    return
  end
  -- Load overflow lazily to avoid require at top level
  local ok_req, overflow = pcall(require, "/master-storage/lib/overflow")
  if not ok_req then
    err("overflow lib not available: " ..
      tostring(overflow)); return
  end
  local target = tonumber(target_str) or 50
  print(string.format("Voiding '%s' to %d%%...",
    name_query, target))
  local ok_v, msg, count = overflow.manualVoid(
    name_query, target)
  if ok_v then
    ok(tostring(msg))
  else
    err(tostring(msg))
  end
end

-- help text
local function help()
  print("storeadmin ender list")
  print('storeadmin ender add "<name>" <cid> "<chest>"')
  print("storeadmin ender remove <cid>")
  print("storeadmin ender test <cid>")
  print("")
  print("storeadmin bash list")
  print("storeadmin bash add <item_id> <dest> [reason]")
  print("storeadmin bash remove <item_id>")
  print("storeadmin bash generate")
  print("storeadmin bash test")
  print("")
  print("storeadmin void <item> <target_%>")
end

-- argument dispatch
local args = {...}
local cmd1 = args[1]
local cmd2 = args[2]

if not cmd1 or cmd1 == "help" then
  help()
elseif cmd1 == "ender" then
  if     not cmd2 or cmd2 == "list" then enderList()
  elseif cmd2 == "add"    then enderAdd(args, args[3], args[4])
  elseif cmd2 == "remove" then enderRemove(args[3])
  elseif cmd2 == "test"   then enderTest(args[3])
  else print("Unknown: storeadmin ender "..cmd2); help()
  end
elseif cmd1 == "bash" then
  if     not cmd2 or cmd2 == "list" then bashList()
  elseif cmd2 == "add"      then bashAdd(args[3], args[4], args[5])
  elseif cmd2 == "remove"   then bashRemove(args[3])
  elseif cmd2 == "generate" then bashGenerate()
  elseif cmd2 == "test"     then bashTest()
  else print("Unknown: storeadmin bash "..cmd2); help()
  end
elseif cmd1 == "void" then
  cmdVoid(args[2], args[3])
else
  print("Unknown: "..cmd1); help()
end
