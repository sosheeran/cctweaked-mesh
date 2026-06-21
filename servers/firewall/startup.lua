print("[STARTUP] firewall booting...")
sleep(2)
shell.run("bg", "/fw/firewall")
print("[STARTUP] firewall up, listening")
