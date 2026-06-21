-- firewall.lua
-- computer ID 2 - the network's only trust boundary
--
-- back   = wireless modem, this is where every client connects
-- bottom = wired modem, this is where the other internal servers
--          live
--
-- auth packets (login etc) get forwarded straight to auth with
-- no pre-check - auth handles its own validation. everything
-- else (service_request) gets the caller's session checked here
-- first, and only forwarded onward if it's valid. that split
-- matters: a client can't reach storage, mail, or anything else
-- without first proving who they are to this computer.

local router    = require("/fw/lib/router")
local validator = require("/fw/lib/validator")
local ratelimit = require("/fw/lib/ratelimit")
local services  = require("/fw/lib/services")
local logger    = require("/lib/logger")
local net       = require("/lib/network")

local WIRELESS = "back"
local WIRED    = "bottom"
local AUTH_ID  = net.ID.AUTH
local TIMEOUT  = net.TIMEOUT

rednet.open(WIRELESS)
rednet.open(WIRED)

print("[FW] ID: " .. os.getComputerID())
print("[FW] Wireless (clients): " .. WIRELESS)
print("[FW] Wired (servers):    " .. WIRED)
print("[FW] Ready")
logger.audit("firewall", "Firewall started")

local function isBlocked(id)
  local f = fs.open("/fw/data/blocklist.cfg", "r")
  if not f then return false end
  local line = f.readLine()
  while line do
    if tonumber(line:match("^%s*(.-)%s*$")) == id then
      f.close()
      return true
    end
    line = f.readLine()
  end
  f.close()
  return false
end

-- forwards a packet to an internal server and waits for the
-- matching reply.
--
-- the reply_id tag is the important part here: rednet doesn't
-- give any built-in way to say "this response is for that
-- specific request" - if the firewall just listened for the
-- next message from target_id, it could easily grab some
-- unrelated packet that server happened to send around the same
-- time (a log line, a ping reply, whatever) and mistake it for
-- the answer to this request. tagging every forwarded packet
-- with a unique id and only accepting a response carrying that
-- same id back avoids that entirely - basically a poor man's
-- request/response correlation since rednet has no native
-- concept of a "conversation"
local function forward(target_id, msg)
  local reply_id = tostring(os.clock()) .. tostring(math.random(1, 999999))
  msg._reply_id = reply_id
  rednet.send(target_id, textutils.serialize(msg))

  local deadline = os.clock() + TIMEOUT
  while os.clock() < deadline do
    local remaining = deadline - os.clock()
    if remaining <= 0 then break end

    local sender, raw = rednet.receive(math.min(remaining, 0.5))
    if sender == target_id and type(raw) == "string" then
      local ok, resp = pcall(textutils.unserialize, raw)
      if ok and type(resp) == "table" and resp._reply_id == reply_id then
        resp._reply_id = nil
        return resp, nil
      end
    end
  end

  return nil, "Timeout waiting for server " .. target_id
end

-- ------------------------------------------------------------
-- token cache - validating a session means a round trip to auth,
-- so cache a validated token for 30s and skip that round trip on
-- every single follow-up request. cuts a lot of latency on
-- chatty clients (e.g. the storage browser firing several
-- queries in a row) at the cost of a token staying "valid" here
-- for up to 30s after it's actually been revoked elsewhere -
-- acceptable tradeoff for this network
-- ------------------------------------------------------------
local token_cache      = {}
local CACHE_TTL         = 30
local last_cache_clean  = 0

local function cacheGet(token, sender_id)
  local entry = token_cache[token]
  if not entry then return nil end
  if os.clock() - entry.time > CACHE_TTL then
    token_cache[token] = nil
    return nil
  end
  if entry.computer_id ~= sender_id then return nil end
  return entry
end

local function cacheSet(token, sender_id, username, role)
  token_cache[token] = {
    computer_id = sender_id,
    username    = username,
    role        = role,
    time        = os.clock(),
  }
end

local function cacheInvalidate(token)
  token_cache[token] = nil
end

local function cleanCache()
  if os.clock() - last_cache_clean < 60 then return end
  local now = os.clock()
  for t, entry in pairs(token_cache) do
    if now - entry.time > CACHE_TTL then
      token_cache[t] = nil
    end
  end
  last_cache_clean = os.clock()
end

local function validateSession(token, sender_id)
  local cached = cacheGet(token, sender_id)
  if cached then
    return true, cached.username, cached.role, nil
  end

  local req = {
    type       = "validate",
    token      = token,
    computerID = sender_id,
    id         = tostring(os.clock()) .. "v",
  }
  local resp, err = forward(AUTH_ID, req)
  if not resp then
    return false, nil, nil, "Auth unreachable: " .. (err or "timeout")
  end
  if resp.type == "error" then
    return false, nil, nil, resp.reason or "Auth error"
  end
  if resp.type ~= "validate_response" then
    return false, nil, nil, "Unexpected auth response"
  end
  if not resp.valid then
    return false, nil, nil, resp.reason or "Invalid session"
  end

  cacheSet(token, sender_id, resp.username, resp.role)
  return true, resp.username, resp.role, nil
end

local function handlePacket(sender_id, raw)
  if isBlocked(sender_id) then
    logger.security("firewall", "Blocked: " .. sender_id)
    return
  end

  if not ratelimit.check(sender_id) then
    logger.security("firewall", "Rate limited: " .. sender_id)
    rednet.send(sender_id, textutils.serialize({
      type   = "error",
      reason = "Rate limit exceeded",
    }))
    return
  end

  if type(raw) ~= "string" then return end
  local ok, msg = pcall(textutils.unserialize, raw)
  if not ok or type(msg) ~= "table" then
    logger.warn("firewall", "Malformed packet from " .. sender_id)
    return
  end

  local valid, reason = validator.validate(msg)
  if not valid then
    rednet.send(sender_id, textutils.serialize({
      type   = "error",
      reason = "Invalid packet: " .. reason,
      id     = msg.id,
    }))
    return
  end

  msg.sender_id = sender_id

  if msg.type == "service_request" then
    local sess_ok, uname, role, sess_err =
      validateSession(msg.token, sender_id)

    if not sess_ok then
      logger.security("firewall",
        "Session fail from " .. sender_id .. ": " .. tostring(sess_err))
      rednet.send(sender_id, textutils.serialize({
        type   = "error",
        reason = "Session invalid: " .. tostring(sess_err),
        id     = msg.id,
      }))
      return
    end

    msg.validated_role     = role
    msg.validated_username = uname
    logger.network("firewall",
      "Service: " .. msg.service .. "/" .. msg.action ..
      " user=" .. uname .. " role=" .. role)
  else
    if msg.type == "logout" and msg.token then
      cacheInvalidate(msg.token)
    end
    logger.network("firewall", "Auth: " .. msg.type .. " from " .. sender_id)
  end

  local target_id, translated, route_err = router.route(msg)
  if not target_id then
    rednet.send(sender_id, textutils.serialize({
      type   = "error",
      reason = route_err or "No route",
      id     = msg.id,
    }))
    return
  end

  local response, fwd_err = forward(target_id, translated)
  if not response then
    logger.error("firewall",
      "Forward failed to " .. target_id .. ": " .. tostring(fwd_err))
    rednet.send(sender_id, textutils.serialize({
      type   = "error",
      reason = tostring(fwd_err),
      id     = msg.id,
    }))
    return
  end

  rednet.send(sender_id, textutils.serialize(response))
end

-- internal servers talk directly to each other over the wired
-- network and never need to come through here - this loop only
-- actually does work for packets from computer IDs the network
-- doesn't already trust (i.e. clients), with one exception:
-- trusted servers' pings still get answered, since NOC's health
-- check pings every computer ID including this one
while true do
  cleanCache()
  local sender_id, raw = rednet.receive(1)
  if sender_id and raw then
    local ok_parse, msg = pcall(textutils.unserialize, raw)
    if ok_parse and type(msg) == "table" and
       msg.type == "ping" and services.isTrusted(sender_id) then
      rednet.send(sender_id, textutils.serialize({
        type = "pong",
        from = os.getComputerID(),
        ts   = msg.ts,
      }))
    elseif services.isTrusted(sender_id) then
      -- some other trusted-server traffic landed on our modem,
      -- not meant for us specifically - ignore it
    else
      local ok, err = pcall(handlePacket, sender_id, raw)
      if not ok then
        print("[FW] CRASH: " .. tostring(err))
        logger.error("firewall", "Handler crash: " .. tostring(err))
      end
    end
  end
end
