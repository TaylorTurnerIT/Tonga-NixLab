#!/usr/bin/env bash
set -euo pipefail

state="${TONGA_DEPLOY_STATE:-/var/lib/tonga-auto-deploy}"
[[ -e "$state/pending" ]] || exit 0
exec 9>"$state/deploy.lock"
flock -n 9 || exit 0
[[ -e "$state/pending" ]] || exit 0

healthy() {
  systemctl is-active --quiet caddy.service &&
    curl --fail --silent --show-error --max-time 5 http://127.0.0.1:2019/config/ >/dev/null
}

if healthy; then
  if (( $(date +%s) >= $(cat "$state/deadline") )); then
    rm -f "$state/pending" "$state/previous-system" "$state/deadline"
    sync
  fi
  exit 0
fi

previous="$(cat "$state/previous-system")"
if [[ -x "$previous/bin/switch-to-configuration" ]]; then
  nix-env --profile /nix/var/nix/profiles/system --set "$previous"
  "$previous/bin/switch-to-configuration" switch
  rm -f "$state/pending" "$state/previous-system" "$state/deadline"
  sync
  exit 0
fi
echo "Previous NixOS system generation is unavailable; rollback remains pending." >&2
exit 1
