-- gives the computer a couple seconds before the server script
-- grabs the modem - peripherals aren't always attached the
-- instant a CC computer finishes booting
print("[STARTUP] auth server booting...")
sleep(2)
shell.run("bg", "/auth/server")
print("[STARTUP] auth server running")
