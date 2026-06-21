-- session.lua
--
-- everything a client needs for talking to the network: login
-- state, and a couple of request helpers. login/logout and every
-- service_request go through the firewall, which is the network's
-- only trust boundary - nothing here talks to an internal server
-- directly.
--
-- NOTE: mailDirect() below is dead code. the comment that used to
-- sit on this file claimed mail requests skip the firewall for
-- speed, but M.mailRequest actually goes through serviceRequest
-- like everything else, and mailDirect is never called anywhere.
-- given the whole point of routing everything through the
-- firewall is having one place that validates sessions, a real
-- bypass-the-firewall path for mail would have been a meaningful
-- security hole if it had ever actually been wired up - leaving
-- the function here since deleting it loses the history, but it
-- should stay unused.

local M      = {}
local sha256 = require("/lib/sha256")
local net    = require("/lib/network")

local MODEM_WIRELESS = "back"    -- faces the firewall
local MODEM_WIRED    = "bottom"  -- faces the internal network
local TIMEOUT         = 10        -- storage queries can take a while

local token, username, display, role
local cid = os.getComputerID()

local function ensureModems()
  if not rednet.isOpen(MODEM_WIRELESS) then
    pcall(rednet.open, MODEM_WIRELESS)
  end
  -- not every client has a wired modem in a test setup, so this
  -- one's allowed to silently fail
  pcall(rednet.open, MODEM_WIRED)
end

local function request(server_id, packet)
  ensureModems()
  local req_id = tostring(os.clock()) .. tostring(math.random(1, 99999))
  packet.id = req_id

  rednet.send(server_id, textutils.serialize(packet))

  local deadline = os.clock() + TIMEOUT
  while os.clock() < deadline do
    local sender, raw = rednet.receive(math.min(deadline - os.clock(), 0.5))
    if sender == server_id and type(raw) == "string" then
      local ok, resp = pcall(textutils.unserialize, raw)
      if ok and type(resp) == "table" and resp.id == req_id then
        return resp, nil
      end
    end
  end
  return nil, "Timeout"
end

local function fwRequest(packet)
  return request(net.ID.FIREWALL, packet)
end

-- see file header - this is unused
local function mailDirect(packet)
  packet.computer_id = cid
  if token then packet.token = token end
  return request(net.ID.MAIL, packet)
end

function M.login(user, pass)
  local resp, err = fwRequest({
    type       = "login",
    username   = user,
    password   = sha256(pass),
    computerID = cid,
  })
  if not resp then return false, err end
  if not resp.success then
    return false, resp.reason or "Login failed"
  end

  token    = resp.token
  username = user
  display  = resp.display
  role     = resp.role
  return true, nil
end

function M.logout()
  if not token then return end
  fwRequest({ type = "logout", token = token })
  token, username, display, role = nil, nil, nil, nil
end

function M.isLoggedIn()  return token ~= nil end
function M.getToken()    return token end
function M.getUsername() return username end
function M.getDisplay()  return display end
function M.getRole()     return role end
function M.getCID()      return cid end

-- every authenticated request gets wrapped in a service_request
-- envelope and sent to the firewall, which validates the session
-- and forwards it on to whichever internal server actually
-- handles it
local function serviceRequest(service, msg_type, data)
  if not token then return nil, "Not logged in" end

  local req_id = tostring(os.clock()) .. tostring(math.random(1, 99999))
  local inner  = data or {}
  inner.type        = msg_type
  inner.computer_id = cid

  local packet = {
    type    = "service_request",
    token   = token,
    service = service,
    action  = msg_type,
    data    = inner,
    id      = req_id,
  }

  ensureModems()
  rednet.send(net.ID.FIREWALL, textutils.serialize(packet))

  local deadline = os.clock() + TIMEOUT
  while os.clock() < deadline do
    local sender, raw = rednet.receive(math.min(deadline - os.clock(), 0.5))
    if sender == net.ID.FIREWALL and type(raw) == "string" then
      local ok, resp = pcall(textutils.unserialize, raw)
      if ok and type(resp) == "table" and resp.id == req_id then
        return resp, nil
      end
    end
  end
  return nil, "Timeout"
end

function M.mailRequest(msg_type, data)
  return serviceRequest("mail-server", msg_type, data)
end

function M.storageRequest(msg_type, data)
  return serviceRequest("master-storage", msg_type, data)
end

return M
