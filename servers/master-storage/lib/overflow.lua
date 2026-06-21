-- overflow.lua
--
-- three-tier system for keeping storage columns from filling up
-- completely:
--
--   tier 1 - full scan, every 2 minutes. checks every column,
--            voids anything at 95%+ immediately, and adds
--            anything at 85%+ to a priority watch list
--
--   tier 2 - priority watch, every 30 seconds. only checks the
--            (usually small) set of columns already flagged by
--            tier 1, so it's cheap enough to run often
--
--   tier 3 - manual void via storeadmin's `void <item> <pct>`,
--            for whenever an admin wants to force it outside the
--            automatic schedule

local storage = require("/scripts/lib/storage")
local logger  = require("/lib/logger")
local net     = require("/lib/network")

-- maps a base ingredient to the alloy recipes it feeds into, so
-- that instead of just voiding excess copper/tin/etc, overflow
-- could in principle redirect it into making an alloy first.
--
-- NOTE: checkAlloyOpportunity below, which is the only thing that
-- reads this table, is never actually called anywhere in this
-- file or anywhere else in the repo - it's dead code right now.
-- the intent was clearly to wire it into checkAndVoid as a "can
-- this be alloyed instead of voided" check before falling back to
-- voiding, but that depends on the crafting server actually being
-- able to receive and execute an alloy job, and crafting isn't
-- part of this build (see fulfillment.lua's header note for the
-- same underlying reason). leaving this in rather than deleting
-- it since it documents what the overflow system was designed to
-- eventually do.
local ALLOY_USES = {
  ["thermalfoundation:material:128"] = {  -- copper
    recipes = {
      { output = "thermalfoundation:material:163",  -- bronze
        others = { "thermalfoundation:material:129" } },  -- tin
      { output = "thermalfoundation:material:164",  -- constantan
        others = { "thermalfoundation:material:133" } },  -- nickel
      { output = "thermalfoundation:material:165",  -- signalum
        others = { "thermalfoundation:material:130", "minecraft:redstone" } },
    },
  },
  ["thermalfoundation:material:129"] = {  -- tin
    recipes = {
      { output = "thermalfoundation:material:163",
        others = { "thermalfoundation:material:128" } },
      { output = "thermalfoundation:material:166",  -- lumium
        others = { "thermalfoundation:material:130", "minecraft:glowstone_dust" } },
    },
  },
  ["thermalfoundation:material:130"] = {  -- silver
    recipes = {
      { output = "thermalfoundation:material:161",  -- electrum
        others = { "minecraft:gold_ingot" } },
      { output = "thermalfoundation:material:165",
        others = { "thermalfoundation:material:128", "minecraft:redstone" } },
      { output = "thermalfoundation:material:166",
        others = { "thermalfoundation:material:129", "minecraft:glowstone_dust" } },
    },
  },
  ["thermalfoundation:material:133"] = {  -- nickel
    recipes = {
      { output = "thermalfoundation:material:162",  -- invar
        others = { "minecraft:iron_ingot" } },
      { output = "thermalfoundation:material:164",
        others = { "thermalfoundation:material:128" } },
    },
  },
  ["minecraft:iron_ingot"] = {
    recipes = {
      { output = "thermalfoundation:material:162",
        others = { "thermalfoundation:material:133" } },
    },
  },
  ["minecraft:gold_ingot"] = {
    recipes = {
      { output = "thermalfoundation:material:161",
        others = { "thermalfoundation:material:130" } },
    },
  },
}

-- checks whether item_key has an alloy it could feed into, and
-- whether conditions are right to do that (other ingredients have
-- enough stock, the alloy output isn't already nearly full).
-- see the dead-code note above ALLOY_USES - nothing calls this
-- right now.
local function checkAlloyOpportunity(item_key, store)
  local uses = ALLOY_USES[item_key]
  if not uses then return false, nil end

  for _, recipe in ipairs(uses.recipes) do
    local ingredients_ok = true
    for _, other_key in ipairs(recipe.others) do
      local other_data = store[other_key]
      if not other_data then
        ingredients_ok = false
        break
      end
      local ok_s, _, pct = pcall(storage.getStock, other_data)
      if not ok_s or not pct or pct < 30 then
        ingredients_ok = false
        break
      end
    end

    if ingredients_ok then
      local alloy_ok   = true
      local alloy_data = store[recipe.output]
      if alloy_data then
        local ok_a, _, alloy_pct = pcall(storage.getStock, alloy_data)
        if ok_a and alloy_pct and alloy_pct >= 80 then
          alloy_ok = false
        end
      end
      if alloy_ok then
        return true, recipe
      end
    end
  end

  return false, nil
end

local M = {}

local PRIORITY_FILE   = "/data/priority_watch.cfg"
local FULL_SCAN_IV    = 120
local PRIORITY_IV     = 30
local WATCH_THRESHOLD = 85
local VOID_THRESHOLD  = 95
local VOID_TARGET     = 80
local PRIORITY_CLEAR  = 75

local last_full_scan = -(FULL_SCAN_IV)  -- so the first scan runs soon after boot
local last_priority   = 0

local function loadPriority()
  local list = {}
  if not fs.exists(PRIORITY_FILE) then return list end
  local f = fs.open(PRIORITY_FILE, "r")
  if not f then return list end

  local line = f.readLine()
  while line do
    line = line:match("^%s*(.-)%s*$")
    if line ~= "" and not line:match("^#") then
      list[line] = true
    end
    line = f.readLine()
  end
  f.close()
  return list
end

local function savePriority(list)
  if not fs.exists("/data") then fs.makeDir("/data") end
  local f = fs.open(PRIORITY_FILE, "w")
  if not f then return end

  f.writeLine("# Priority watch list - auto managed")
  for key in pairs(list) do
    f.writeLine(key)
  end
  f.close()
end

local function voidFromColumn(data, target_pct, trash_name)
  if not trash_name or trash_name == "" then
    logger.warn("master-storage", "No trash configured - cannot void " .. tostring(data.display))
    return 0, "No trash configured"
  end

  local trash = peripheral.wrap(trash_name)
  if not trash then
    return 0, "Trash offline: " .. trash_name
  end

  local ok_s, total = pcall(storage.getStock, data)
  if not ok_s or not total then return 0, "Cannot read stock" end

  local capacity = storage.getCapacity(data)
  if not capacity or capacity == 0 then
    return 0, "Cannot read capacity"
  end

  local target_count = math.floor(capacity * target_pct / 100)
  local to_void       = math.max(0, total - target_count)
  if to_void == 0 then return 0, nil end

  local voided = 0
  for _, chest_name in ipairs({ data.chest, data.mid, data.top }) do
    if chest_name and chest_name ~= "" and voided < to_void then
      local chest = peripheral.wrap(chest_name)
      if chest then
        local ok_list, items = pcall(chest.list)
        if ok_list and items then
          for slot, stack in pairs(items) do
            if voided >= to_void then break end
            local amount = math.min(stack.count, to_void - voided)
            local ok_push, moved = pcall(chest.pushItems, trash_name, slot, amount)
            if ok_push and moved then voided = voided + moved end
          end
        end
      end
    end
  end

  return voided, nil
end

local function getConfig()
  local cfg = {}
  if not fs.exists("/data/config.cfg") then return cfg end
  local f = fs.open("/data/config.cfg", "r")
  if not f then return cfg end

  local line = f.readLine()
  while line do
    if not line:match("^#") and line:match("=") then
      local k, v = line:match("^%s*(.-)%s*=%s*(.-)%s*$")
      if k and v then
        cfg[k:match("^%s*(.-)%s*$")] = v:match("^%s*(.-)%s*$")
      end
    end
    line = f.readLine()
  end
  f.close()
  return cfg
end

local function notifyAdmins(title, body)
  pcall(rednet.send, net.ID.MAIL, textutils.serialize({
    type     = "mail_send_alert",
    severity = "WARNING",
    source   = "master-storage",
    title    = title,
    body     = body,
    to_role  = "admin",
  }))
end

local function checkAndVoid(key, data, cfg)
  local ok_s, total, pct = pcall(storage.getStock, data)
  if not ok_s or not pct then return nil, false end

  if pct >= VOID_THRESHOLD then
    local voided, err = voidFromColumn(data, VOID_TARGET, cfg.trash)
    if voided > 0 then
      local msg = string.format("Auto-voided %d x %s (%.0f%% -> ~%d%%)",
        voided, data.display, pct, VOID_TARGET)
      logger.warn("master-storage", msg)
      notifyAdmins("Overflow: " .. data.display,
        msg .. "\n\nColumn was at " .. string.format("%.0f%%", pct) .. " capacity.")

      local ok2, _, new_pct = pcall(storage.getStock, data)
      return ok2 and new_pct or pct, true
    elseif err then
      logger.error("master-storage", "Void failed for " .. data.display .. ": " .. err)
    end
  end

  return pct, false
end

local function runFullScan()
  local store    = storage.load()
  local cfg      = getConfig()
  local priority = loadPriority()
  local changed  = false

  local near_full = {}

  for key, data in pairs(store) do
    local pct, _ = checkAndVoid(key, data, cfg)
    if pct then
      if pct >= WATCH_THRESHOLD then
        if not priority[key] then
          priority[key] = true
          changed = true
          table.insert(near_full, data.display)
        end
      elseif pct < PRIORITY_CLEAR and priority[key] then
        priority[key] = nil
        changed = true
      end
    end
  end

  if changed then savePriority(priority) end

  if #near_full > 0 then
    logger.warn("master-storage",
      "Near full (>=" .. WATCH_THRESHOLD .. "%): " .. table.concat(near_full, ", "))
  end

  local count = 0
  for _ in pairs(priority) do count = count + 1 end
  if count > 0 then
    logger.info("master-storage", "Priority watch: " .. count .. " items")
  end
end

local function runPriorityScan()
  local priority = loadPriority()
  if not next(priority) then return end

  local store   = storage.load()
  local cfg     = getConfig()
  local changed = false

  for key in pairs(priority) do
    local data = store[key]
    if data then
      local pct = checkAndVoid(key, data, cfg)
      if pct and pct < PRIORITY_CLEAR then
        priority[key] = nil
        changed = true
        logger.info("master-storage",
          data.display .. " cleared priority watch (" .. string.format("%.0f%%", pct) .. ")")
      end
    else
      priority[key] = nil
      changed = true
    end
  end

  if changed then savePriority(priority) end
end

function M.manualVoid(name_query, target_pct)
  local store = storage.load()
  local cfg   = getConfig()

  if not cfg.trash or cfg.trash == "" then
    return false, "No trash configured in config.cfg"
  end

  target_pct = math.max(0, math.min(100, tonumber(target_pct) or 50))

  local lq      = name_query:lower()
  local matches = {}
  for key, data in pairs(store) do
    if tostring(data.display):lower():find(lq, 1, true) or key:lower():find(lq, 1, true) then
      table.insert(matches, { key = key, data = data })
    end
  end

  if #matches == 0 then
    return false, "No items found matching: " .. name_query
  end
  if #matches > 1 then
    local names = {}
    for _, m in ipairs(matches) do table.insert(names, m.data.display) end
    return false, "Ambiguous - matches: " .. table.concat(names, ", ")
  end

  local item = matches[1]
  local ok_s, total, pct = pcall(storage.getStock, item.data)
  if not ok_s then
    return false, "Cannot read stock for " .. item.data.display
  end
  if pct <= target_pct then
    return false, string.format("%s is already at %.0f%% (target: %d%%)",
      item.data.display, pct, target_pct)
  end

  local voided, err = voidFromColumn(item.data, target_pct, cfg.trash)
  if err then return false, err end

  local msg = string.format("Manual void: %d x %s (%.0f%% -> %d%%)",
    voided, item.data.display, pct, target_pct)
  logger.audit("master-storage", msg)

  return true, msg, voided
end

-- called from the storage server's main loop every tick - cheap
-- to call constantly since it just checks elapsed time and bails
-- out immediately if neither tier is due yet
function M.tick()
  local now = os.clock()

  if now - last_full_scan >= FULL_SCAN_IV then
    pcall(runFullScan)
    last_full_scan = now
  elseif now - last_priority >= PRIORITY_IV then
    pcall(runPriorityScan)
    last_priority = now
  end
end

return M
