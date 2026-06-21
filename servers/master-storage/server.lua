-- servers/master-storage/server.lua
-- master storage, computer ID 4
-- bottom = wired server network
-- back   = chest peripherals (everything in the actual storage)

local VERSION = 3

local storage     = require("/scripts/lib/storage")
local ender_map   = require("/master-storage/lib/ender_map")
local fulfillment = require("/master-storage/lib/fulfillment")
local overflow    = require("/master-storage/lib/overflow")
local logger      = require("/lib/logger")
local net         = require("/lib/network")

rednet.open("bottom")

local mon = peripheral.find("monitor")
if mon then
  mon.setTextScale(0.5)
  mon.setBackgroundColor(colors.black)
  mon.setTextColor(colors.lime)
  mon.clear()
  mon.setCursorPos(1, 1)
  mon.write("MASTER STORAGE v" .. VERSION)
  mon.setTextColor(colors.white)
end

print("[STORAGE] ID: " .. os.getComputerID())
print("[STORAGE] v" .. VERSION .. " starting...")
logger.audit("master-storage", "Master storage started v" .. VERSION)

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

local function handlePing(sender_id, msg)
  return { type = "pong", from = os.getComputerID(), id = msg.id }
end

local function handleQuery(sender_id, msg)
  local store   = storage.load()
  local results = {}

  if msg.item_key then
    local data = store[msg.item_key]
    if data then
      local ok_s, total, pct = pcall(storage.getStock, data)
      table.insert(results, {
        key     = msg.item_key,
        display = data.display,
        mod     = data.mod,
        total   = ok_s and total or 0,
        pct     = ok_s and pct   or 0,
      })
    end
  else
    local lq = (msg.query or ""):lower()
    for key, data in pairs(store) do
      local match = (lq == "") or
        tostring(data.display):lower():find(lq, 1, true) or
        key:lower():find(lq, 1, true)
      if match then
        table.insert(results, { key = key, display = data.display, mod = data.mod })
      end
    end
    table.sort(results, function(a, b) return tostring(a.display) < tostring(b.display) end)
  end

  return { type = "query_response", results = results, id = msg.id }
end

local function handlePull(sender_id, msg)
  local order       = msg.order or {}
  local computer_id = msg.computer_id or sender_id

  if #order == 0 then
    return { type = "pull_response", success = false, reason = "Empty order", id = msg.id }
  end

  local ok_f, results, total_moved, err =
    pcall(fulfillment.fulfillOrder, order, computer_id, msg.job_id)

  if not ok_f then
    print("[STORAGE] fulfillOrder CRASH: " .. tostring(results))
    return { type = "pull_response", success = false, reason = tostring(results), id = msg.id }
  end

  return {
    type    = "pull_response",
    success = not err,
    moved   = total_moved,
    reason  = err,
    id      = msg.id,
  }
end

-- called by other internal servers (in practice, this would be
-- the crafting server once it exists) asking storage to push
-- specific items somewhere. deliberately ignores whatever
-- dest_chest the caller suggests and always uses storage's own
-- configured send chest instead - storage is the only thing that
-- actually knows which chest the rest of the network expects
-- items to land in, so trusting a caller-supplied destination
-- here would be a good way to silently misroute items the moment
-- any caller got that wrong
local function handleStoragePushRequest(sender_id, msg)
  local items  = msg.items
  local job_id = msg.job_id

  if not items then
    pcall(rednet.send, sender_id, textutils.serialize({
      type = "storage_push_done", job_id = job_id,
      success = false, reason = "No items specified",
    }))
    return nil
  end

  local dest = getConfig().send
  if not dest then
    pcall(rednet.send, sender_id, textutils.serialize({
      type = "storage_push_done", job_id = job_id,
      success = false, reason = "Send chest not configured - run setup",
    }))
    return nil
  end

  local store  = storage.load()
  local pushed = 0
  local failed = {}

  for _, item_req in ipairs(items) do
    local dmg = tonumber(item_req.damage) or 0
    local key = item_req.name .. (dmg > 0 and ":" .. dmg or "")
    local qty = item_req.qty or 1

    local entry = store[key]
    if not entry then
      table.insert(failed, key)
    else
      local moved = 0
      for _, chest_name in ipairs({ entry.chest, entry.mid, entry.top }) do
        if chest_name and chest_name ~= "" and moved < qty then
          local chest = peripheral.wrap(chest_name)
          if chest then
            local ok_l, items_in = pcall(chest.list)
            if ok_l and items_in then
              for slot, stack in pairs(items_in) do
                if moved >= qty then break end
                local take = math.min(stack.count, qty - moved)
                local ok_p, mv = pcall(chest.pushItems, dest, slot, take)
                if ok_p and mv then moved = moved + mv end
              end
            end
          end
        end
      end
      pushed = pushed + moved
      if moved < qty then
        table.insert(failed, key .. " (got " .. moved .. "/" .. qty .. ")")
      end
    end
  end

  pcall(rednet.send, sender_id, textutils.serialize({
    type    = "storage_push_done",
    job_id  = job_id,
    success = #failed == 0,
    pushed  = pushed,
    failed  = failed,
  }))

  return nil
end

-- the other half of the handoff above - once a job's output is
-- sitting in storage's receive chest, pull everything out of it
-- and drop it straight into the requesting player's ender chest
local function handleDeliveryReady(sender_id, msg)
  local computer_id = msg.computer_id
  local item_name   = msg.item_name or "your order"

  local cfg = getConfig()
  if not cfg.receive then return nil end

  local chest_name = ender_map.getChest(computer_id)
  if not chest_name then return nil end

  local recv = peripheral.wrap(cfg.receive)
  if not recv then return nil end

  local ok_l, items = pcall(recv.list)
  local delivered = 0
  if ok_l and items then
    for slot, stack in pairs(items) do
      local ok_p, moved = pcall(recv.pushItems, chest_name, slot, stack.count)
      if ok_p and moved then delivered = delivered + moved end
    end
  end

  logger.audit("master-storage",
    "Delivered " .. delivered .. "x " .. item_name ..
    " to computer " .. tostring(computer_id))

  if delivered > 0 then
    pcall(rednet.send, net.ID.MAIL, textutils.serialize({
      type        = "mail_delivery_notify",
      computer_id = computer_id,
      item        = item_name,
      qty         = delivered,
    }))
  end

  return nil
end

local HANDLERS = {
  ping                  = handlePing,
  storage_query         = handleQuery,
  storage_pull          = handlePull,
  storage_push_request  = handleStoragePushRequest,
  delivery_ready        = handleDeliveryReady,
}

print("[STORAGE] Ready - listening on bottom")

local last_overflow = 0
local OVERFLOW_IV   = 30

while true do
  if os.clock() - last_overflow >= OVERFLOW_IV then
    local ok_ov = pcall(overflow.tick)
    if not ok_ov then
      print("[STORAGE] overflow.tick ERROR")
    end
    last_overflow = os.clock()
  end

  local sender_id, raw = rednet.receive(1)
  if sender_id and raw then
    local ok, msg = pcall(textutils.unserialize, raw)
    if ok and type(msg) == "table" then
      local reply_id = msg._reply_id
      msg._reply_id  = nil

      local handler = HANDLERS[msg.type]
      if handler then
        local ok_h, response = pcall(handler, sender_id, msg)
        if ok_h and response then
          response._reply_id = reply_id
          rednet.send(sender_id, textutils.serialize(response))
        elseif not ok_h then
          print("[STORAGE] CRASH [" .. tostring(msg.type) .. "]: " .. tostring(response))
          logger.error("master-storage",
            "Crash [" .. tostring(msg.type) .. "]: " .. tostring(response))
        end
      else
        logger.warn("master-storage",
          "Unknown pkt: " .. tostring(msg.type) .. " from " .. tostring(sender_id))
      end
    end
  end
end
