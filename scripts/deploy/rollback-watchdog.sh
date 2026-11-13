#!/usr/bin/env bash
set -euo pipefail

state="${TONGA_DEPLOY_STATE:-/var/lib/tonga-auto-deploy}"
[[ -e "$state/pending" ]] || exit 0
exec 9>"$state/rollback.lock"
flock -n 9 || exit 0
[[ -e "$state/pending" ]] || exit 0

healthy() {
  local tailscale
  active() { timeout --kill-after=1s 5s systemctl is-active --quiet "$1"; }
  active caddy.service &&
    active tailscaled.service &&
    active podman.socket &&
    active docker.service &&
    active sshd.service &&
    timeout --kill-after=2s 8s curl --connect-timeout 2 --max-time 5 --fail --silent http://127.0.0.1:2019/config/ >/dev/null &&
    tailscale="$(timeout --kill-after=2s 8s tailscale status --json)" &&
    printf '%s' "$tailscale" | jq -e '.BackendState == "Running" and ((.Health // []) | length == 0)' >/dev/null
}

if healthy; then
  if (( $(date +%s) >= $(cat "$state/deadline") )); then
    rm -f "$state/pending" "$state/previous-system" "$state/deadline"
    sync
  fi
  exit 0
fi

previous="$(cat "$state/previous-system" 2>/dev/null || true)"
if [[ -x "$previous/bin/switch-to-configuration" ]]; then
  # Stop a stuck activation first. systemd bounds the stop and kills its cgroup.
  timeout --kill-after=5s 35s systemctl stop tonga-auto-deploy.service || true
  if timeout --kill-after=5s 60s nix-env --profile /nix/var/nix/profiles/system --set "$previous" &&
     timeout --kill-after=10s 90s "$previous/bin/switch-to-configuration" switch; then
    candidate="$(cat "$state/candidate-sha" 2>/dev/null || true)"
    if [[ -n "$candidate" && "$(cat "$state/deployed-sha" 2>/dev/null || true)" == "$candidate" ]]; then
      rm -f "$state/deployed-sha"
    fi
    rm -f "$state/pending" "$state/previous-system" "$state/previous-system-root" "$state/deadline" "$state/candidate-sha"
    sync
    exit 0
  fi
  echo "Automatic rollback failed; durable state remains for retry." >&2
  exit 1
fi
echo "Previous NixOS system generation is unavailable; rollback remains pending." >&2
exit 1
