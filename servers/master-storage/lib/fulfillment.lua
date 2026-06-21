-- fulfillment.lua
--
-- pulls requested items out of storage and delivers them to a
-- player's ender chest. handles two cases: items already sitting
-- in storage as-is (pulled straight from a column), and items
-- that only exist in a compressed block form and need
-- decompressing first.
--
-- IMPORTANT LIMITATION IN THIS BUILD: the decomp path below sends
-- a decomp_job request to the crafting server (net.ID.CRAFTING)
-- and waits up to 10 seconds for it to respond. crafting isn't
-- part of this stable build (see README - it's being redesigned
-- separately), so that computer ID never exists, the request
-- always times out, and any order that needs decompression always
-- falls through to a "decomp_pending"/"partial" result rather
-- than ever actually completing. direct in-storage items are
-- unaffected and fulfill normally - this only matters for items
-- that only exist as compressed blocks right now.

local storage   = require("/scripts/lib/storage")
local ender_map = require("/master-storage/lib/ender_map")
local logger    = require("/lib/logger")
local net       = require("/lib/network")

local M = {}

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

-- which compressed block decompresses into which item, and how
-- many come out per block. loaded lazily and cached since this
-- never changes at runtime
local decomp_map = nil
local function getDecompMap()
  if decomp_map then return decomp_map end
  decomp_map = {}

  local vanilla = {
    ["minecraft:iron_block"]     = { output = "minecraft:iron_ingot", qty = 9 },
    ["minecraft:gold_block"]     = { output = "minecraft:gold_ingot", qty = 9 },
    ["minecraft:diamond_block"]  = { output = "minecraft:diamond",    qty = 9 },
    ["minecraft:emerald_block"]  = { output = "minecraft:emerald",    qty = 9 },
    ["minecraft:coal_block"]     = { output = "minecraft:coal",       qty = 9 },
    ["minecraft:redstone_block"] = { output = "minecraft:redstone",   qty = 9 },
    ["minecraft:lapis_block"]    = { output = "minecraft:dye:4",      qty = 9 },
    ["minecraft:quartz_block"]   = { output = "minecraft:quartz",     qty = 4 },
  }
  local tf_metals = {
    ["thermalfoundation:storage"]   = { output = "thermalfoundation:material:320", qty = 9 },
    ["thermalfoundation:storage:1"] = { output = "thermalfoundation:material:321", qty = 9 },
    ["thermalfoundation:storage:2"] = { output = "thermalfoundation:material:322", qty = 9 },
    ["thermalfoundation:storage:3"] = { output = "thermalfoundation:material:323", qty = 9 },
    ["thermalfoundation:storage:4"] = { output = "thermalfoundation:material:324", qty = 9 },
    ["thermalfoundation:storage:5"] = { output = "thermalfoundation:material:325", qty = 9 },
    ["thermalfoundation:storage:6"] = { output = "thermalfoundation:material:326", qty = 9 },
    ["thermalfoundation:storage:7"] = { output = "thermalfoundation:material:327", qty = 9 },
  }
  local tf_alloys = {
    ["thermalfoundation:storage_alloy"]   = { output = "thermalfoundation:material:160", qty = 9 },
    ["thermalfoundation:storage_alloy:1"] = { output = "thermalfoundation:material:161", qty = 9 },
    ["thermalfoundation:storage_alloy:2"] = { output = "thermalfoundation:material:162", qty = 9 },
    ["thermalfoundation:storage_alloy:3"] = { output = "thermalfoundation:material:163", qty = 9 },
    ["thermalfoundation:storage_alloy:4"] = { output = "thermalfoundation:material:164", qty = 9 },
    ["thermalfoundation:storage_alloy:5"] = { output = "thermalfoundation:material:165", qty = 9 },
    ["thermalfoundation:storage_alloy:6"] = { output = "thermalfoundation:material:166", qty = 9 },
    ["thermalfoundation:storage_alloy:7"] = { output = "thermalfoundation:material:167", qty = 9 },
  }
  local bop_gems = {
    ["biomesoplenty:gem_block"]   = { output = "biomesoplenty:gem",   qty = 9 },
    ["biomesoplenty:gem_block:1"] = { output = "biomesoplenty:gem:1", qty = 9 },
    ["biomesoplenty:gem_block:2"] = { output = "biomesoplenty:gem:2", qty = 9 },
    ["biomesoplenty:gem_block:6"] = { output = "biomesoplenty:gem:6", qty = 9 },
  }
  local xu2 = {
    ["extrautils2:compressedcobblestone:2"] = { output = "minecraft:cobblestone", qty = 729 },
    ["extrautils2:compressedgravel:1"]      = { output = "minecraft:gravel",      qty = 81 },
    ["extrautils2:compressedgravel"]        = { output = "minecraft:gravel",      qty = 9 },
    ["extrautils2:compresseddirt"]          = { output = "minecraft:dirt",        qty = 9 },
  }

  for k, v in pairs(vanilla)   do decomp_map[k] = v end
  for k, v in pairs(tf_metals) do decomp_map[k] = v end
  for k, v in pairs(tf_alloys) do decomp_map[k] = v end
  for k, v in pairs(bop_gems)  do decomp_map[k] = v end
  for k, v in pairs(xu2)       do decomp_map[k] = v end

  return decomp_map
end

local function findStorageBlock(item_id)
  for block_id, entry in pairs(getDecompMap()) do
    if entry.output == item_id then
      return block_id, entry.qty
    end
  end
  return nil, nil
end

local function pullFromChest(chest_name, buffer_name, qty)
  local chest  = peripheral.wrap(chest_name)
  local buffer = peripheral.wrap(buffer_name)
  if not chest or not buffer then return 0 end

  local moved = 0
  local ok_list, items = pcall(chest.list)
  if not ok_list or not items then return 0 end

  for slot, stack in pairs(items) do
    if moved >= qty then break end
    local to_move = math.min(stack.count, qty - moved)
    local ok_push, n = pcall(chest.pushItems, buffer_name, slot, to_move)
    if ok_push and n then moved = moved + n end
  end

  return moved
end

-- a storage "column" is up to 3 chests stacked together (bottom/
-- mid/top) treated as one logical slot for an item type - pulls
-- whatever's needed from however many of the three are actually
-- populated
local function pullFromColumn(store_entry, dest_name, qty)
  local moved = 0
  for _, chest_name in ipairs({ store_entry.chest, store_entry.mid, store_entry.top }) do
    if chest_name and chest_name ~= "" and moved < qty then
      moved = moved + pullFromChest(chest_name, dest_name, qty - moved)
    end
  end
  return moved
end

-- called by the storage server whenever a client requests items.
-- dest_override exists so other internal callers (the crafting
-- server, when it exists) can redirect delivery to a staging
-- chest instead of a player's ender chest
function M.fulfillOrder(order, computer_id, job_id, dest_override)
  local cfg    = getConfig()
  local buffer = cfg.send  -- decomp staging chest only

  local player_chest = dest_override or ender_map.getChest(computer_id)
  local store = storage.load()

  if not buffer then
    return nil, 0, "Buffer ender chest not configured - run setup"
  end

  local results     = {}
  local total_moved = 0

  for _, item_req in ipairs(order) do
    local item_id = item_req.item_key or item_req.item_id
    local qty     = item_req.qty or item_req.amount or 1
    local result  = {
      item_id   = item_id,
      requested = qty,
      moved     = 0,
      method    = "none",
      status    = "failed",
    }

    local store_entry = store[item_id]
    if store_entry then
      -- already in storage as-is - pull straight to the player,
      -- no intermediate staging needed
      local dest  = player_chest or buffer
      local moved = pullFromColumn(store_entry, dest, qty)
      result.moved  = moved
      result.method = "direct"
      result.status = moved >= qty and "fulfilled" or
                      moved > 0   and "partial"   or "failed"
      total_moved = total_moved + moved
    else
      -- not in storage directly - see if it can come from
      -- decompressing a block we do have (see file header note
      -- on why this path doesn't currently complete)
      local block_id, qty_per_block = findStorageBlock(item_id)
      if block_id and store[block_id] then
        local blocks_needed = math.ceil(qty / qty_per_block)
        local blocks_moved  = pullFromColumn(store[block_id], buffer, blocks_needed)

        if blocks_moved > 0 then
          local job_resp
          pcall(function()
            local req_id = tostring(os.clock()) .. tostring(math.random(1, 99999))
            rednet.send(net.ID.CRAFTING, textutils.serialize({
              type        = "decomp_job",
              block_id    = block_id,
              block_count = blocks_moved,
              item_id     = item_id,
              item_qty    = qty,
              buffer      = buffer,
              job_id      = job_id,
              id          = req_id,
            }))
            local deadline = os.clock() + 10
            while os.clock() < deadline do
              local sender, raw = rednet.receive(0.5)
              if sender == net.ID.CRAFTING and raw then
                local ok_r, resp = pcall(textutils.unserialize, raw)
                if ok_r and type(resp) == "table" and resp.id == req_id then
                  job_resp = resp
                  break
                end
              end
            end
          end)

          if job_resp and job_resp.success then
            result.moved  = job_resp.items_produced or qty
            result.method = "decomp"
            result.status = "fulfilled"
          else
            result.moved  = blocks_moved * qty_per_block
            result.method = "decomp_pending"
            result.status = "partial"
          end
          total_moved = total_moved + result.moved
        end
      end
    end

    table.insert(results, result)
    logger.info("master-storage",
      "Order item: " .. tostring(item_id) .. " x" .. tostring(qty) ..
      " -> " .. tostring(result.moved) .. " (" .. result.status .. ")")
  end

  if total_moved > 0 then
    if player_chest then
      local ender = peripheral.wrap(player_chest)
      if ender then
        pcall(rednet.send, net.ID.MAIL, textutils.serialize({
          type        = "mail_delivery_notify",
          computer_id = computer_id,
          item        = #order == 1 and
                        (order[1].item_key or order[1].item_id) or
                        "your order",
          qty         = total_moved,
        }))
      else
        logger.warn("master-storage",
          "Ender chest offline for computer " .. tostring(computer_id))
      end
    else
      logger.warn("master-storage",
        "No ender chest mapped for computer " .. tostring(computer_id))
    end
  end

  return results, total_moved
end

return M
