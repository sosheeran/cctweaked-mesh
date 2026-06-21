-- install.lua
--
-- single installer for the whole network. run this on any
-- computer and it figures out which service belongs on that ID
-- and pulls down exactly the files that service needs.
--
-- wget https://raw.githubusercontent.com/sosheeran/cctweaked-mesh/main/install.lua install && install

local REPO = "https://raw.githubusercontent.com/sosheeran/cctweaked-mesh/main/"
local ID   = os.getComputerID()

-- every computer gets these three regardless of what service it
-- ends up running
local SHARED = {
  {"shared/lib/sha256.lua",  "/lib/sha256.lua"},
  {"shared/lib/logger.lua",  "/lib/logger.lua"},
  {"shared/lib/network.lua", "/lib/network.lua"},
}

-- one entry per service, keyed by the computer ID it's meant to
-- run on. IDs 5/7-11 are reserved for crafting/fluid/farms - see
-- README, those aren't part of this build yet
local SERVERS = {

  [0] = {
    name    = "log-server",
    dirs    = {"/lib", "/data", "/log", "/log/lib", "/log/data"},
    files   = {
      {"servers/log/server.lua",         "/log/server.lua"},
      {"servers/log/startup.lua",        "/log/startup.lua"},
      {"servers/log/lib/logfile.lua",    "/log/lib/logfile.lua"},
      {"servers/log/lib/logmonitor.lua", "/log/lib/logmonitor.lua"},
      {"scripts/lib/monitor.lua",        "/scripts/lib/monitor.lua"},
    },
    startup = 'shell.run("bg", "/log/startup")',
  },

  [1] = {
    name    = "auth-server",
    dirs    = {"/lib", "/data", "/auth", "/auth/lib", "/auth/data"},
    files   = {
      {"servers/auth/server.lua",       "/auth/server.lua"},
      {"servers/auth/startup.lua",      "/auth/startup.lua"},
      {"servers/auth/useradmin.lua",    "/useradmin.lua"},
      {"servers/auth/lib/users.lua",    "/auth/lib/users.lua"},
      {"servers/auth/lib/sessions.lua", "/auth/lib/sessions.lua"},
      {"servers/auth/lib/roles.lua",    "/auth/lib/roles.lua"},
    },
    startup = 'shell.run("bg", "/auth/startup")',
  },

  [2] = {
    name    = "firewall",
    dirs    = {"/lib", "/data", "/fw", "/fw/lib", "/fw/data"},
    files   = {
      {"servers/firewall/firewall.lua",      "/fw/firewall.lua"},
      {"servers/firewall/startup.lua",       "/fw/startup.lua"},
      {"servers/firewall/lib/services.lua",  "/fw/lib/services.lua"},
      {"servers/firewall/lib/validator.lua", "/fw/lib/validator.lua"},
      {"servers/firewall/lib/ratelimit.lua", "/fw/lib/ratelimit.lua"},
      {"servers/firewall/lib/router.lua",    "/fw/lib/router.lua"},
    },
    data    = {
      {"servers/firewall/data/blocklist.cfg", "/fw/data/blocklist.cfg"},
    },
    startup = 'shell.run("bg", "/fw/startup")',
  },

  [3] = {
    name    = "mail-server",
    dirs    = {"/lib", "/data", "/mail", "/mail/lib",
               "/mail/data", "/mail/data/inbox"},
    files   = {
      {"servers/mail/server.lua",           "/mail/server.lua"},
      {"servers/mail/startup.lua",          "/mail/startup.lua"},
      {"servers/mail/mailadmin.lua",        "/mailadmin.lua"},
      {"servers/mail/lib/mailbox.lua",      "/mail/lib/mailbox.lua"},
      {"servers/mail/lib/alerts_inbox.lua", "/mail/lib/alerts_inbox.lua"},
      {"servers/mail/lib/addresses.lua",    "/mail/lib/addresses.lua"},
    },
    startup = 'shell.run("bg", "/mail/startup")',
  },

  [4] = {
    name    = "master-storage",
    dirs    = {"/lib", "/data", "/scripts", "/scripts/lib",
               "/master-storage", "/master-storage/lib"},
    files   = {
      {"scripts/setup.lua",                            "/setup.lua"},
      {"scripts/discover.lua",                         "/discover.lua"},
      {"scripts/debug_storage.lua",                    "/debug_storage.lua"},
      {"scripts/storage_log.lua",                      "/storage_log.lua"},
      {"scripts/health.lua",                           "/health.lua"},
      {"scripts/column_edit.lua",                      "/column_edit.lua"},
      {"scripts/lib/storage.lua",                      "/scripts/lib/storage.lua"},
      {"scripts/lib/printer.lua",                      "/scripts/lib/printer.lua"},
      {"scripts/lib/monitor.lua",                      "/scripts/lib/monitor.lua"},
      {"servers/master-storage/server.lua",            "/master-storage/server.lua"},
      {"servers/master-storage/startup.lua",           "/master-storage/startup.lua"},
      {"servers/master-storage/storeadmin.lua",        "/storeadmin.lua"},
      {"servers/master-storage/lib/ender_map.lua",     "/master-storage/lib/ender_map.lua"},
      {"servers/master-storage/lib/fulfillment.lua",   "/master-storage/lib/fulfillment.lua"},
      {"servers/master-storage/lib/overflow.lua",      "/master-storage/lib/overflow.lua"},
    },
    data    = {
      {"servers/master-storage/data/bash_routes.cfg",  "/data/bash_routes.cfg"},
    },
    startup = 'shell.run("bg", "/master-storage/startup")',
  },

  [6] = {
    name    = "noc-server",
    dirs    = {"/lib", "/data", "/noc", "/noc/lib",
               "/noc/data", "/scripts/lib"},
    files   = {
      {"servers/noc/server.lua",         "/noc/server.lua"},
      {"servers/noc/startup.lua",        "/noc/startup.lua"},
      {"servers/noc/noc.lua",            "/noc.lua"},
      {"servers/noc/lib/alerts.lua",     "/noc/lib/alerts.lua"},
      {"servers/noc/lib/nocmonitor.lua", "/noc/lib/nocmonitor.lua"},
      {"scripts/lib/monitor.lua",        "/scripts/lib/monitor.lua"},
      {"scripts/lib/printer.lua",        "/scripts/lib/printer.lua"},
    },
    startup = 'shell.run("bg", "/noc/startup")',
  },

}

-- anything ID 25 and up isn't a fixed service, it's a player
-- terminal - same client install regardless of which exact ID
-- it landed on
local CLIENT = {
  name    = "client",
  dirs    = {"/lib", "/data", "/client", "/client/lib"},
  files   = {
    {"servers/client/client.lua",      "/client/client.lua"},
    {"servers/client/startup.lua",     "/client/startup.lua"},
    {"servers/client/lib/session.lua", "/client/lib/session.lua"},
  },
  startup = 'shell.run("/client/startup")',
}

local function wget(src, dest)
  if fs.exists(dest) then fs.delete(dest) end
  local url = REPO .. src
  local ok, result = pcall(http.get, url)
  if not ok or not result then
    print("  ! FAILED: " .. src)
    return false
  end
  local body = result.readAll()
  result.close()
  if not body or #body == 0 then
    print("  ! EMPTY: " .. src)
    return false
  end
  local f = fs.open(dest, "w")
  if not f then
    print("  ! CANT WRITE: " .. dest)
    return false
  end
  f.write(body)
  f.close()
  print("  + " .. dest)
  return true
end

local function mkdirs(dirs)
  for _, d in ipairs(dirs) do
    if not fs.exists(d) then
      fs.makeDir(d)
      print("  mkdir " .. d)
    end
  end
end

local function installCfg(cfg)
  mkdirs(cfg.dirs)

  local ok_count, fail_count = 0, 0

  print("Shared libs...")
  for _, f in ipairs(SHARED) do
    if wget(f[1], f[2]) then
      ok_count = ok_count + 1
    else
      -- if a shared lib fails to download, nothing downstream is
      -- going to work right anyway - bail out instead of limping
      -- along with half the network stack missing
      fail_count = fail_count + 1
      print("  CRITICAL: shared lib failed")
      return false
    end
  end

  print(cfg.name .. " files...")
  for _, f in ipairs(cfg.files or {}) do
    if wget(f[1], f[2]) then
      ok_count = ok_count + 1
    else
      fail_count = fail_count + 1
      print("  Check file exists in repo: " .. f[1])
    end
  end

  -- data files are config/state, not code - if one's already on
  -- disk from a previous install, leave it alone rather than
  -- clobbering whatever's already been configured
  for _, f in ipairs(cfg.data or {}) do
    if fs.exists(f[2]) then
      print("  = " .. f[2] .. " (kept)")
      ok_count = ok_count + 1
    else
      if wget(f[1], f[2]) then
        ok_count = ok_count + 1
      else
        fail_count = fail_count + 1
      end
    end
  end

  if cfg.startup then
    local sf = fs.open("/startup.lua", "w")
    sf.writeLine(cfg.startup)
    sf.close()
    print("  + /startup.lua")
  end

  print("")
  print("===========================")
  print("Installed: " .. ok_count)
  if fail_count > 0 then
    print("Failed:    " .. fail_count)
  else
    print("All OK - run: reboot")
  end

  return fail_count == 0
end

-- figure out what belongs on this computer ID and go install it
local cfg = SERVERS[ID]
if not cfg and ID >= 25 then cfg = CLIENT end

if not cfg then
  print("No config for ID " .. ID)
  print("")
  print("Server IDs:")
  print("  0  log-server")
  print("  1  auth-server")
  print("  2  firewall")
  print("  3  mail-server")
  print("  4  master-storage")
  print("  6  noc-server")
  print("  25+ client")
  print("")
  print("(crafting/fluid/farms not yet stable - omitted)")
  return
end

print("=== MC-TWEAKED: " .. cfg.name ..
      " (ID " .. ID .. ") ===")
print("")
installCfg(cfg)
