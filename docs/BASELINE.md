# Deployment baseline

Recorded on 2026-11-01 from repository inspection, Nix evaluation, and read-only
SSH inspection of `root@homelab`. Repository base:
`7639c6907f3c873cef15616c614092b7ad5ebb14`.

## Source configurations

- Homelab: `x86_64-linux`, `nixosConfigurations.homelab`.
- VPS: `x86_64-linux`, `homeConfigurations.ubuntu`, Ubuntu with Home Manager.
- Locked stable Nixpkgs: `50ab793786d9de88ee30ec4e4c24fb4236fc2674` (24.11).
- Locked Home Manager: `d5f1f641b289553927b3801580598d200a501863` (24.11).
- Homelab `system.stateVersion`: `25.05`. This is a compatibility setting, not
  evidence that the machine runs NixOS 25.05. Existing documentation claiming
  25.05 does not match the observed release.

Both deployment outputs evaluated successfully before the CI additions. Their
baseline output paths were:

```text
homelab: /nix/store/wy561sqi7cafl3wigf25wqxi7wxqxdsh-nixos-system-homelab-24.11.20250630.50ab793
VPS:     /nix/store/2vfhv752lxj58v7ifbjdzl55pp3yjjzk-home-manager-generation
```

## Observed homelab

- Linux `x86_64`, NixOS `24.11.20250630.50ab793`.
- Active system:
  `/nix/store/7pqar5fbkm9agfb6vjbcc5vsczwjrxgy-nixos-system-homelab-24.11.20250630.50ab793`.
- Rootful Podman with 31 running containers; storage is under
  `/var/lib/containers/storage`.
- The root filesystem reports 5.0 T total, 4.3 T used, 518 G available, and 90%
  use. Values are rounded `df -h` output, not capacity planning measurements.
- `acme-tongatime.us.service` was failed. Its cause and certificate validity were
  not investigated or changed. Several old login session scopes were also failed.

A sanitized local snapshot records container names, image references, image IDs,
mounts, and ports in `artifacts/homelab-containers-2026-11-01.jsonl`. It excludes
container environments and stays ignored by Git. It is a configuration inventory,
not a backup of application data.

## Deployment drift

The active homelab system differs from the output evaluated from this repository.
Examples requiring reconciliation before activation:

- Overleaf, its MongoDB and Redis containers, Quicksilver, and the chess
  application stack are running but are absent from the repository's imports.
- The running Vaultwarden image uses a digest; this repository declares
  `vaultwarden/server:latest`.

Existing core data mounts include `/var/lib/mysql`, `/var/lib/postgres`, and the
Gitea, Immich, Vaultwarden, and media paths recorded in the local inventory.
No ownership, mount, firewall, application, or host configuration was changed.

## VPS verification limit

The local script's `/Users/taylor/.ssh/homelab` key is unavailable. Strict SSH
verification of `129.153.13.212` also lacks a trusted host key, including from the
homelab. Inspection stopped without accepting an unverified host key. The live
VPS architecture, Home Manager generation, firewall, and routes remain unverified.

Identify the authoritative deployed sources, obtain verified VPS access, preserve
the additional applications, and test backup restoration before enabling host
reconciliation. This phase adds repository checks and update PRs only.
