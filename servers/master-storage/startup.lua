-- storage needs the back modem (chests) up before server.lua
-- starts polling them, hence the same boot delay as everything
-- else on this network
print("[STARTUP] master-storage booting...")
sleep(2)
shell.run("bg", "/master-storage/server")
print("[STARTUP] master-storage running")
