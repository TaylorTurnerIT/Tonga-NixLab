"""Require dependency discovery by the real Renovate CLI, not just valid regexes."""

import json
from pathlib import Path
import sys

records = [json.loads(line) for line in Path(sys.argv[1]).read_text().splitlines()]
if any(record.get("level", 0) >= 50 for record in records):
    raise SystemExit("Renovate extraction logged an error; inspect the CLI output")
reports = [record["packageFiles"] for record in records if "packageFiles" in record]
if len(reports) != 1:
    raise SystemExit("Expected one Renovate dependency extraction report")

expected = {
    "dockerfile": {"nixos/nix"},
    "github-actions": {"actions/checkout", "cachix/install-nix-action", "actions/setup-node"},
    "nix": {"nixpkgs", "nixpkgs-unstable", "home-manager", "disko", "sops-nix"},
    "regex": {
        "ghcr.io/pterodactyl/panel", "ghcr.io/pterodactyl/wings", "mariadb", "redis",
        "postgres", "renovate", "mholt/caddy-l4", "ghcr.io/immich-app/postgres",
    },
}
for manager, required in expected.items():
    deps = [dep for file in reports[0].get(manager, []) for dep in file["deps"]]
    missing = required - {dep["depName"] for dep in deps}
    if missing:
        raise SystemExit(f"{manager}: missing dependencies: {', '.join(sorted(missing))}")
    print(f"{manager}: discovered {len(deps)} dependencies; required coverage passed")

image_deps = [dep for file in reports[0]["regex"] for dep in file["deps"]
              if dep["depName"] == "ghcr.io/immich-app/postgres"]
if not image_deps or not all(dep.get("currentDigest", "").startswith("sha256:") for dep in image_deps):
    raise SystemExit("Existing OCI digest was not extracted")
