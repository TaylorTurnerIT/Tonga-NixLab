# Repository checks and dependency updates

Changes target `master` through a pull request. The required `Required CI` check
passes only when repository checks and both Linux deployment builds succeed.
GitHub-hosted Linux runners receive no production credentials. Workflows never
run the deployment scripts or activate a host configuration.

## Local checks

Run the configuration checks on Linux:

```sh
nix flake check --no-update-lock-file --print-build-logs
nix build --no-link --no-update-lock-file .#nixosConfigurations.homelab.config.system.build.toplevel
nix build --no-link --no-update-lock-file .#homeConfigurations.ubuntu.activationPackage
```

On Apple Silicon, the repository check is available locally. Linux builds and
the Linux Caddy checks run in GitHub Actions:

```sh
nix build --no-link --no-update-lock-file .#checks.aarch64-darwin.repository
```

`nix develop` provides the tools from the existing lock file. The checks cover
Nix and shell syntax, workflow syntax, encrypted SOPS payloads, and DNSControl
configuration. They neither decrypt secrets nor contact Cloudflare.

Linux checks validate the generated homelab and VPS Caddy configurations with
their configured Caddy packages. The homelab check supplies a temporary test
certificate and omits the runtime-generated Foundry routes import. Those dynamic
routes, real certificates, networking, and application behavior require host
checks. A successful Nix build does not test OCI image availability or migrations.

Existing shell scripts have lint debt. CI requires their syntax to pass; it does
not suppress failures from the Nix builds or Caddy validation.

## Renovate

The Renovate GitHub App must have access to this repository. The owner confirmed
that access during setup. `renovate.json` controls repository updates:

- Nix inputs and `flake.lock` maintenance.
- GitHub Actions commit pins and release updates.
- The `Containerfile` base image.
- Remote OCI images in Nix, including the Pterodactyl image variables.
- The Caddy Layer 4 plugin and the Renovate CLI used in CI.

New update PRs are scheduled before 07:00 on weekdays in `America/Chicago`, with
two concurrent PRs. Weekly lock maintenance runs before 07:00 on Monday. Major
updates require approval in the Dependency Dashboard before a PR is opened.
Automatic merging is disabled. An update PR cannot activate production.

OCI updates include digest pins. Immich server and machine-learning updates are
grouped. Database major updates remain separate. Local images such as
`localhost/odysseus` and `foundry-portal` are excluded because no remote registry
source is declared. Moving these builds to pinned, reproducible sources is a
later prerequisite for automatic deployment.

Caddy plugin PRs need the corresponding `withPlugins` hash regenerated before
merging. Renovate proposes the version; it does not repair that Nix hash. The
Linux build and Caddy validation must pass after the hash is updated.

The deployment container still installs tools from unpinned flake references.
Converting those commands to locked flake packages belongs to the later deployer
migration. CI does not build or execute that container in this phase.

CI validates the Renovate schema and runs a local extraction-only dry run. This
checks dependency discovery without opening PRs or requiring a bot token. The
Dependency Dashboard and real update PRs establish that the installed app is
processing the repository. Review its configuration warnings after activation.

## Repository settings

Protect `master` with strict `Required CI`, pull requests, conversation resolution,
and no force pushes or branch deletion. Apply the rules to administrators too.
Automatic deployment and automatic merge remain disabled during this phase.

## NixOS homelab pull deployment

The NixOS homelab pull deployment is implemented and disabled by default.
Enable `services.tongaAutoDeploy.enable` in `configuration.nix` only after
reviewing the current host baseline and the recovery behavior below. The
polling timer is enabled only when this option is true. The rollback timer is
always enabled and does nothing when no deployment is pending. This keeps the
recovery path independent of network access. This change does not run
deployment, SSH, or host commands.

The root poller reads the current `master` SHA, then accepts only a completed,
successful `Infrastructure CI` workflow run for that exact SHA. It checks the
workflow path, push event, master branch, run attempt, and every job result.
The GitHub jobs API total must match the returned job count. A check with the
right name alone does not qualify. The poller fetches the exact commit and
rechecks both master and CI before building and immediately before activation.
If either check fails or master moves, it exits without activation.

The homelab builds the `nixosConfigurations.homelab` system locally before
activation. Before switching, the service records the prior system generation
and a five-minute health deadline under `/var/lib/tonga-auto-deploy`. A
separate system timer checks Caddy's service and local admin API. If activation
fails or health checks fail, it restores the recorded generation. The state
and enabled timer survive network loss and reboot. The watchdog does not need
GitHub or SSH. It checks local Caddy availability, not DNS, TLS, or every
application.

The host needs outbound HTTPS access to GitHub and the Nix build cache. No new
credentials, inbound ports, DNS records, or live changes are part of this
implementation. Existing manual deployment scripts remain unchanged.

Before enabling automatic activation, reconcile every difference recorded in
[the baseline](BASELINE.md). Do not replace the running configuration with this
older repository snapshot merely because CI passes.
