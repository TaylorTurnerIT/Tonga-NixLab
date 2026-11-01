#!/usr/bin/env bash
set -euo pipefail

# Gluetun can receive a new incoming port after reconnecting to Proton VPN.
forwarded_port=$(podman exec gluetun cat /tmp/gluetun/forwarded_port)
if [[ ! "$forwarded_port" =~ ^[0-9]+$ ]] || (( forwarded_port < 1024 || forwarded_port > 65535 )); then
  echo 'Gluetun did not report a valid forwarded port.' >&2
  exit 1
fi

# This request stays inside qBittorrent's network namespace. Its existing
# localhost authentication bypass applies, so no credentials are required.
podman exec -i qbittorrent python3 - "$forwarded_port" <<'PY'
import json
import sys
import urllib.parse
import urllib.request

port = int(sys.argv[1])
base = "http://127.0.0.1:8080/api/v2/"

def preferences():
    with urllib.request.urlopen(base + "app/preferences", timeout=10) as response:
        return json.load(response)

before = preferences()
if before["listen_port"] != port or before["random_port"]:
    payload = urllib.parse.urlencode({"json": json.dumps({
        "listen_port": port,
        "random_port": False,
    })}).encode()
    request = urllib.request.Request(base + "app/setPreferences", data=payload)
    with urllib.request.urlopen(request, timeout=10) as response:
        response.read()
    after = preferences()
    if after["listen_port"] != port or after["random_port"]:
        raise RuntimeError("qBittorrent did not apply the forwarded port")
    print(f"qBittorrent incoming port changed from {before['listen_port']} to {port}.")
PY
