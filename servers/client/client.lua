-- client.lua
-- the actual terminal program a player runs once logged in.
-- back modem = wireless, connects to the firewall - this is the
-- only thing the firewall is meant to ever talk to directly on
-- that side of the network.

local session = require("/client/lib/session")
local net     = require("/lib/network")

local W, H = term.getSize()

-- small drawing helpers shared by every screen below
local function clear()
  term.setBackgroundColor(colors.black)
  term.setTextColor(colors.white)
  term.clear()
  term.setCursorPos(1, 1)
end

local function setColor(fg, bg)
  if fg then term.setTextColor(fg) end
  if bg then term.setBackgroundColor(bg) end
end

local function resetColor()
  term.setTextColor(colors.white)
  term.setBackgroundColor(colors.black)
end

local function centerPrint(text, y, fg, bg)
  setColor(fg or colors.white, bg or colors.black)
  local x = math.floor((W - #text) / 2) + 1
  term.setCursorPos(x, y)
  term.write(text)
  resetColor()
end

local function header(title)
  term.setCursorPos(1, 1)
  setColor(colors.black, colors.cyan)
  term.clearLine()
  local time_str = os.date("%H:%M")
  local left     = " " .. title
  local right    = time_str .. " "
  local pad      = W - #left - #right
  term.write(left .. string.rep(" ", math.max(0,pad)) .. right)
  resetColor()
end

local function footer(text)
  term.setCursorPos(1, H)
  setColor(colors.black, colors.gray)
  term.clearLine()
  term.write(" " .. text:sub(1, W-1))
  resetColor()
end

local function statusMsg(text, color)
  term.setCursorPos(1, H-1)
  term.clearLine()
  setColor(color or colors.yellow)
  term.write(" " .. text)
  resetColor()
end

-- ============================================================
-- LOGIN SCREEN
-- ============================================================
local function loginScreen()
  while true do
    clear()
    setColor(colors.cyan)
    centerPrint("╔══════════════════════╗", 4)
    centerPrint("║    MC-NET TERMINAL   ║", 5)
    centerPrint("╚══════════════════════╝", 6)
    resetColor()
    centerPrint("mc-net.red", 7, colors.lightGray)

    term.setCursorPos(1, 10)
    setColor(colors.yellow)
    io.write("  Username: ")
    resetColor()
    local user = read()

    if user and user ~= "" then
      setColor(colors.yellow)
      io.write("  Password: ")
      resetColor()
      local pass = read("*")
      print("")
      statusMsg("Connecting...", colors.yellow)
      local ok, err = session.login(user, pass)
      if ok then return true end
      statusMsg("Failed: " .. tostring(err), colors.red)
      sleep(1.5)
    end
  end
end

-- mail screen - pulls the inbox once on entry and works off
-- that local copy while browsing, rather than re-querying the
-- mail server on every keypress. mark-read state is batched up
-- and only sent when the player actually leaves the screen
local function mailScreen()
  statusMsg("Loading inbox...", colors.yellow)
  local resp = session.mailRequest("mail_inbox",
    {computer_id=session.getCID()})
  local msgs = (resp and resp.messages) or {}

  local sel      = 1
  local reading  = nil
  local to_read  = {}  -- ids to mark read on exit

  local function drawInbox()
    clear()
    header("MAIL  " .. session.getDisplay())
    if #msgs == 0 then
      centerPrint("Inbox empty", 10, colors.lightGray)
    else
      local visible = H - 3
      local start   = math.max(1, sel - math.floor(visible/2))
      local finish  = math.min(#msgs, start + visible - 1)
      for i = start, finish do
        local msg    = msgs[i]
        local y      = i - start + 2
        local is_sel = (i == sel)
        term.setCursorPos(1, y)
        if is_sel then
          setColor(colors.black, colors.cyan)
        elseif not msg.read then
          setColor(colors.white, colors.black)
        else
          setColor(colors.lightGray, colors.black)
        end
        local mark = msg.read and "  " or " *"
        local from = tostring(msg.from):sub(1,18)
        local subj = tostring(msg.subject):sub(1, W-22)
        term.clearLine()
        term.write(string.format("%s %-18s %s",
          mark, from, subj):sub(1,W))
        resetColor()
      end
    end
    footer("[Ent]Read [C]ompose [D]el [R]efresh [Q]uit")
  end

  local function drawMessage(msg)
    clear()
    header("READ MAIL")
    setColor(colors.cyan)
    term.setCursorPos(1,2)
    print(" From:    " .. tostring(msg.from):sub(1,W-10))
    print(" Date:    " .. tostring(msg.date):sub(1,W-10))
    print(" Subject: " .. tostring(msg.subject):sub(1,W-10))
    resetColor()
    term.setCursorPos(1,5)
    print(string.rep("-",W))
    local y = 6
    for line in (tostring(msg.body).."\n"):gmatch("([^\n]*)\n") do
      while #line > 0 do
        term.setCursorPos(1, y)
        term.write(" " .. line:sub(1, W-2))
        line = line:sub(W-1)
        y = y + 1
        if y >= H-1 then break end
      end
      if y >= H-1 then break end
    end
    footer("[D]elete  [B]ack")
  end

  while true do
    if reading then
      drawMessage(reading)
      local _, key = os.pullEvent("key")
      if key == keys.d then
        session.mailRequest("mail_delete", {
          computer_id = session.getCID(),
          msg_id      = reading.id,
        })
        -- Remove from local list
        for i, m in ipairs(msgs) do
          if m.id == reading.id then
            table.remove(msgs, i); break
          end
        end
        if sel > #msgs then sel = math.max(1,#msgs) end
        reading = nil
      elseif key == keys.b then
        reading = nil
      end
    else
      drawInbox()
      local _, key = os.pullEvent("key")
      if key == keys.q then
        -- Batch mark all read on exit
        if #to_read > 0 then
          session.mailRequest("mail_mark_read", {
            computer_id = session.getCID(),
          })
        end
        return
      elseif key == keys.up and sel > 1 then
        sel = sel - 1
      elseif key == keys.down and sel < #msgs then
        sel = sel + 1
      elseif key == keys.r then
        statusMsg("Refreshing...", colors.yellow)
        local r2 = session.mailRequest("mail_inbox",
          {computer_id=session.getCID()})
        msgs = (r2 and r2.messages) or {}
        sel  = 1
      elseif key == keys.enter and #msgs > 0 then
        reading = msgs[sel]
        if not reading.read then
          reading.read = true  -- optimistic local update
          table.insert(to_read, reading.id)
        end
      elseif key == keys.d and #msgs > 0 then
        local msg = msgs[sel]
        session.mailRequest("mail_delete", {
          computer_id = session.getCID(),
          msg_id      = msg.id,
        })
        table.remove(msgs, sel)
        if sel > #msgs then sel = math.max(1,#msgs) end
      elseif key == keys.c then
        -- Compose
        clear()
        header("COMPOSE")
        term.setCursorPos(1,3)
        setColor(colors.yellow); io.write("  To:      "); resetColor()
        local to = read()
        setColor(colors.yellow); io.write("  Subject: "); resetColor()
        local subj = read()
        print("  Body (blank line to send):")
        local lines = {}
        repeat
          io.write("  ")
          local line = read()
          if line ~= "" then table.insert(lines, line) end
        until line == ""
        statusMsg("Sending...", colors.yellow)
        local sr = session.mailRequest("mail_send", {
          to_address       = to,
          from_computer_id = session.getCID(),
          subject          = subj,
          body             = table.concat(lines, "\n"),
        })
        if sr and sr.success then
          statusMsg("Sent!", colors.green)
        else
          statusMsg("Failed: " ..
            tostring(sr and sr.reason or "timeout"),
            colors.red)
        end
        sleep(1)
      end
    end
  end
end

-- alerts screen - same caching approach as mail
local function alertsScreen()
  local SCOL = {
    CRITICAL=colors.red,
    WARNING=colors.yellow,
    INFO=colors.white,
  }

  statusMsg("Loading alerts...", colors.yellow)
  local resp    = session.mailRequest("mail_get_alerts",
    {computer_id=session.getCID()})
  local alerts  = (resp and resp.alerts) or {}
  local sel     = 1
  local reading = nil

  local function drawList()
    clear()
    header("ALERTS  " .. session.getDisplay())
    if #alerts == 0 then
      centerPrint("No alerts", 10, colors.green)
    else
      local visible = H - 3
      local start   = math.max(1, sel - math.floor(visible/2))
      local finish  = math.min(#alerts, start + visible - 1)
      for i = start, finish do
        local a      = alerts[i]
        local y      = i - start + 2
        local is_sel = (i == sel)
        local col    = SCOL[a.severity] or colors.white
        if a.read then col = colors.lightGray end
        term.setCursorPos(1, y)
        if is_sel then
          setColor(colors.black, colors.cyan)
        else
          setColor(col, colors.black)
        end
        local mark  = a.read and "  " or " !"
        local sev   = "[" .. tostring(a.severity):sub(1,4) .. "]"
        local title = tostring(a.title):sub(1, W-12)
        term.clearLine()
        term.write(string.format("%s %-6s %s",
          mark, sev, title):sub(1,W))
        resetColor()
      end
    end
    footer("[Ent]Read [D]el [R]efresh [Q]uit")
  end

  local function drawAlert(a)
    clear()
    header("ALERT")
    local col = SCOL[a.severity] or colors.white
    term.setCursorPos(1,2)
    setColor(col)
    print(" [" .. tostring(a.severity) .. "] " ..
          tostring(a.title):sub(1,W-15))
    resetColor()
    print(" Source: " .. tostring(a.source))
    print(" Date:   " .. tostring(a.date))
    print(string.rep("-",W))
    for line in (tostring(a.body).."\n"):gmatch("([^\n]*)\n") do
      print(" " .. line:sub(1,W-2))
    end
    footer("[D]elete  [B]ack")
  end

  while true do
    if reading then
      drawAlert(reading)
      local _, key = os.pullEvent("key")
      if key == keys.d then
        session.mailRequest("mail_alert_delete", {
          computer_id = session.getCID(),
          alert_id    = reading.id,
        })
        for i, a in ipairs(alerts) do
          if a.id == reading.id then
            table.remove(alerts, i); break
          end
        end
        if sel > #alerts then sel = math.max(1,#alerts) end
        reading = nil
      elseif key == keys.b then
        reading = nil
      end
    else
      drawList()
      local _, key = os.pullEvent("key")
      if key == keys.q then
        return
      elseif key == keys.up and sel > 1 then
        sel = sel - 1
      elseif key == keys.down and sel < #alerts then
        sel = sel + 1
      elseif key == keys.r then
        statusMsg("Refreshing...", colors.yellow)
        local r2 = session.mailRequest("mail_get_alerts",
          {computer_id=session.getCID()})
        alerts = (r2 and r2.alerts) or {}
        sel    = 1
      elseif key == keys.enter and #alerts > 0 then
        reading = alerts[sel]
        if not reading.read then
          reading.read = true
          session.mailRequest("mail_alert_mark_read", {
            computer_id = session.getCID(),
            alert_id    = reading.id,
          })
        end
      elseif key == keys.d and #alerts > 0 then
        local a = alerts[sel]
        session.mailRequest("mail_alert_delete", {
          computer_id = session.getCID(),
          alert_id    = a.id,
        })
        table.remove(alerts, sel)
        if sel > #alerts then sel = math.max(1,#alerts) end
      end
    end
  end
end

-- ============================================================
-- STORAGE SCREEN
-- search and request items from master storage. note: only the
-- direct-from-storage path actually completes right now (see
-- fulfillment.lua's header note on why decomp-based items don't)
-- ============================================================
local function storageScreen()
  -- All items cached locally on first load
  -- Filtering is instant client-side, no network per keypress
  local all_items  = nil  -- nil = not loaded yet
  local filtered   = {}
  local sel        = 1
  local query      = ""
  local status_txt = "Press any key to load storage..."
  local status_col = colors.lightGray

  -- Load ALL items once from master storage
  local function loadAll()
    status_txt = "Loading storage..."
    status_col = colors.yellow
    -- Draw immediately so user sees feedback
    clear()
    header("STORAGE  " .. session.getDisplay())
    statusMsg(status_txt, status_col)
    footer("[Type]Filter  [Enter]Request  [Q]uit")

    local resp, err = session.storageRequest("storage_query", {
      query = "",  -- empty = return all
    })
    if resp and resp.results then
      all_items  = resp.results
      status_txt = tostring(#all_items) .. " items loaded"
      status_col = colors.white
      filtered   = all_items
    else
      all_items  = {}
      status_txt = "Failed to load: " ..
                   tostring(err or "timeout")
      status_col = colors.red
    end
    sel = 1
  end

  -- Filter locally - instant, no network
  local function applyFilter(q)
    if not all_items then return end
    if q == "" then
      filtered = all_items
    else
      local lq = q:lower()
      filtered = {}
      for _, item in ipairs(all_items) do
        local name = tostring(item.display):lower()
        local key  = tostring(item.key):lower()
        if name:find(lq, 1, true) or
           key:find(lq, 1, true) then
          table.insert(filtered, item)
        end
      end
    end
    sel = math.min(sel, math.max(1, #filtered))
  end

  local function doRequest(item, qty)
    status_txt = "Requesting..."
    status_col = colors.yellow
    local resp, err = session.storageRequest("storage_pull", {
      order       = {{item_key=item.key, qty=qty}},
      computer_id = session.getCID(),
    })
    if resp and resp.success then
      status_txt = "Sent! Check ender chest"
      status_col = colors.green
    else
      status_txt = "Failed: " ..
        tostring(err or (resp and resp.reason) or "timeout")
      status_col = colors.red
    end
  end

  -- Load on first open
  loadAll()
  applyFilter("")

  while true do
    clear()
    header("STORAGE  " .. session.getDisplay())

    -- Search bar
    term.setCursorPos(1, 2)
    setColor(colors.yellow)
    io.write(" Filter: ")
    resetColor()
    term.write(query .. "_")

    -- Results list
    if #filtered == 0 then
      if query ~= "" then
        centerPrint("No matches for: " .. query, 10,
                    colors.lightGray)
      else
        centerPrint("Storage empty", 10, colors.lightGray)
      end
    else
      local visible = H - 5
      local start   = math.max(1, sel - math.floor(visible/2))
      local finish  = math.min(#filtered, start + visible - 1)
      for i = start, finish do
        local item = filtered[i]
        local y    = i - start + 3
        term.setCursorPos(1, y)
        if i == sel then
          setColor(colors.black, colors.cyan)
        else
          local pct = item.pct or 0
          if pct >= 90 then setColor(colors.red)
          elseif pct >= 75 then setColor(colors.yellow)
          else resetColor() end
        end
        local pct_str = string.format("%3d%%", item.pct or 0)
        local qty_str = tostring(item.total or 0)
        local name    = tostring(item.display):sub(1, W-14)
        local padded  = name .. string.rep(" ", W-14-#name)
        term.clearLine()
        term.write(string.format(" %s %6s %s",
          padded, qty_str, pct_str))
        resetColor()
      end
    end

    if status_txt ~= "" then
      statusMsg(status_txt, status_col)
    end
    footer("[Type]Filter  [Enter]Request  [R]efresh  [Q]uit")

    local evt, param = os.pullEvent()

    if evt == "char" then
      query = query .. param
      applyFilter(query)
      sel   = 1

    elseif evt == "key" then
      local key = param
      if key == keys.q then
        return
      elseif key == keys.backspace then
        if #query > 0 then
          query = query:sub(1, -2)
          applyFilter(query)
          sel   = 1
        end
      elseif key == keys.up and sel > 1 then
        sel = sel - 1
      elseif key == keys.down and sel < #filtered then
        sel = sel + 1
      elseif key == keys.r then
        loadAll()
        applyFilter(query)
      elseif key == keys.enter and #filtered > 0 then
        local item = filtered[sel]
        -- Fetch real stock count for this item
        statusMsg("Checking stock...", colors.yellow)
        local stock_resp, _ = session.storageRequest(
          "storage_query", {item_key = item.key})
        local stock_item = stock_resp and
                           stock_resp.results and
                           stock_resp.results[1]
        clear()
        header("REQUEST ITEM")
        term.setCursorPos(1, 5)
        print("  Item:  " .. tostring(item.display))
        if stock_item then
          print("  Stock: " .. tostring(stock_item.total) ..
                " (" .. tostring(stock_item.pct) .. "%)")
        else
          print("  Stock: unknown")
        end
        print("")
        setColor(colors.yellow)
        io.write("  Quantity [1]: ")
        resetColor()
        local qty_str = read()
        local qty = tonumber(qty_str) or 1
        doRequest(item, qty)
        sleep(1.5)
        -- Refresh list after request
        loadAll()
        applyFilter(query)
      end
    end
  end
end

-- main menu - unread counts for mail/alerts are cached locally
-- and only refreshed after coming back from a screen that could
-- have changed them, rather than polling on every frame
local function mainMenu()
  local mail_unread   = 0
  local alert_unread  = 0
  local needs_refresh = true

  local function refreshCounts()
    local resp = session.mailRequest("mail_unread_all",
      {computer_id=session.getCID()})
    if resp then
      mail_unread  = resp.mail_unread  or 0
      alert_unread = resp.alert_unread or 0
    end
    needs_refresh = false
  end

  while true do
    if needs_refresh then
      -- Show menu immediately, refresh in background
      -- by drawing first then fetching
      refreshCounts()
    end

    clear()
    header("MC-NET  " .. os.date("%H:%M:%S"))

    term.setCursorPos(1,3)
    setColor(colors.cyan)
    print("  " .. session.getDisplay())
    setColor(colors.lightGray)
    print("  " .. session.getRole():upper() ..
          "  |  " .. os.date())
    resetColor()

    term.setCursorPos(1,7)
    print("  ┌──────────────────────────┐")

    -- Mail badge
    local mbadge = mail_unread > 0 and
                   " (" .. mail_unread .. ")" or ""
    setColor(colors.white)
    print("  │  [M] Mail" .. mbadge)

    -- Alerts badge
    local abadge = alert_unread > 0 and
                   " (" .. alert_unread .. ")" or ""
    if alert_unread > 0 then setColor(colors.red) end
    print("  │  [A] Alerts" .. abadge)
    resetColor()

    print("  │  [S] Storage")
    print("  │")
    print("  │  [L] Logout")
    print("  └──────────────────────────┘")

    footer("mc-net.red  |  ID:" .. session.getCID())

    local _, key = os.pullEvent("key")
    if key == keys.m then
      mailScreen()
      needs_refresh = true
    elseif key == keys.a then
      alertsScreen()
      needs_refresh = true
    elseif key == keys.s then
      storageScreen()
    elseif key == keys.l then
      statusMsg("Logging out...", colors.yellow)
      session.logout()
      return
    end
  end
end

-- entry point
if not rednet.isOpen("back") then
  pcall(rednet.open, "back")
end

while true do
  loginScreen()
  if session.isLoggedIn() then
    mainMenu()
  end
end
