"""Check committed SOPS documents without decrypting or printing their values."""

import json
from pathlib import Path
import subprocess


def encrypted_leaves(value):
    if isinstance(value, dict):
        return all(encrypted_leaves(item) for item in value.values())
    if isinstance(value, list):
        return all(encrypted_leaves(item) for item in value)
    return isinstance(value, str) and value.startswith("ENC[AES256_GCM,")


for path in (Path("secrets/secrets.yaml"), Path("secrets/dns_creds.json")):
    document = json.loads(subprocess.run(
        ["yq", "-o=json", str(path)], check=True, text=True, capture_output=True
    ).stdout)
    if not isinstance(document, dict):
        raise SystemExit(f"{path}: expected a SOPS object")
    metadata = document.get("sops", {})
    if not isinstance(metadata, dict) or not metadata.get("age") or not metadata.get("mac"):
        raise SystemExit(f"{path}: missing SOPS age metadata or MAC")
    payload = {key: value for key, value in document.items() if key != "sops"}
    if not payload or not encrypted_leaves(payload):
        raise SystemExit(f"{path}: payload contains an unencrypted value")
    print(f"{path}: encrypted payload and SOPS metadata present")
