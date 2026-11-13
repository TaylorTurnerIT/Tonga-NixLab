#!/usr/bin/env bash
set -euo pipefail

repo="${TONGA_REPOSITORY:-https://github.com/TaylorTurnerIT/Tonga-NixLab.git}"
api="${TONGA_GITHUB_API:-https://api.github.com/repos/TaylorTurnerIT/Tonga-NixLab}"
state="${TONGA_DEPLOY_STATE:-/var/lib/tonga-auto-deploy}"
health_seconds="${TONGA_HEALTH_SECONDS:-300}"
mkdir -p "$state"
exec 9>"$state/deploy.lock"
flock -n 9 || exit 0
[[ ! -e "$state/pending" ]] || exit 0

request() { curl --fail --silent --show-error --location "$1"; }
master_sha() { request "$api/commits/master" | jq -er '.sha | select(test("^[0-9a-f]{40}$"))'; }

# A run is trusted only when this exact workflow attempt and every listed job succeeded.
qualified_run() {
  local sha="$1" runs run_id attempt jobs
  runs="$(request "$api/actions/workflows/ci.yml/runs?head_sha=$sha&event=push&per_page=100")" || return 1
  while IFS=$'\t' read -r run_id attempt; do
    [[ -n "$run_id" && -n "$attempt" ]] || continue
    jobs="$(request "$api/actions/runs/$run_id/attempts/$attempt/jobs?per_page=100")" || continue
    if printf '%s' "$jobs" | all_jobs_succeeded; then
      return 0
    fi
  done < <(printf '%s' "$runs" | workflow_candidates "$sha")
  return 1
}

rollback() {
  local previous
  [[ -s "$state/previous-system" ]] || return 1
  previous="$(cat "$state/previous-system")"
  [[ -x "$previous/bin/switch-to-configuration" ]] || return 1
  nix-env --profile /nix/var/nix/profiles/system --set "$previous"
  "$previous/bin/switch-to-configuration" switch
  rm -f "$state/pending" "$state/previous-system" "$state/deadline"
  sync
}

sha="$(master_sha)" || exit 1
qualified_run "$sha" || exit 0
[[ "$(cat "$state/deployed-sha" 2>/dev/null || true)" != "$sha" ]] || exit 0
checkout="$(mktemp -d "$state/source.XXXXXX")"
cleanup() {
  local result=$?
  if (( result != 0 )) && [[ -e "$state/pending" ]]; then
    rollback || echo "Automatic rollback failed; durable rollback timer will retry." >&2
  fi
  rm -rf "$checkout"
  return "$result"
}
trap cleanup EXIT
git -C "$checkout" init -q
git -C "$checkout" remote add origin "$repo"
git -C "$checkout" fetch --quiet --depth=1 origin "$sha"
git -C "$checkout" checkout --quiet --detach FETCH_HEAD
[[ "$(git -C "$checkout" rev-parse HEAD)" == "$sha" ]] || exit 1
[[ "$(master_sha)" == "$sha" ]] || exit 0
qualified_run "$sha" || exit 0

system="$(nix build --no-link --print-out-paths --no-update-lock-file "$checkout#nixosConfigurations.homelab.config.system.build.toplevel")"
[[ -x "$system/bin/switch-to-configuration" ]] || exit 1
[[ "$(master_sha)" == "$sha" ]] || exit 0
qualified_run "$sha" || exit 0
[[ ! -e "$state/pending" ]] || exit 0

previous="$(readlink -f /nix/var/nix/profiles/system)"
[[ -x "$previous/bin/switch-to-configuration" ]] || exit 1
printf '%s\n' "$previous" > "$state/previous-system.tmp"
printf '%s\n' "$(( $(date +%s) + health_seconds ))" > "$state/deadline.tmp"
mv "$state/previous-system.tmp" "$state/previous-system"
mv "$state/deadline.tmp" "$state/deadline"
: > "$state/pending.tmp"
mv "$state/pending.tmp" "$state/pending"
sync
systemctl start tonga-auto-deploy-rollback.timer
if [[ "$(master_sha)" != "$sha" ]] || ! qualified_run "$sha"; then
  rm -f "$state/pending" "$state/previous-system" "$state/deadline"
  sync
  exit 0
fi
[[ "$(master_sha)" == "$sha" ]] || {
  rm -f "$state/pending" "$state/previous-system" "$state/deadline"
  sync
  exit 0
}

activation_failed=0
if ! nix-env --profile /nix/var/nix/profiles/system --set "$system" ||
   ! "$system/bin/switch-to-configuration" switch; then
  activation_failed=1
fi
if (( activation_failed )); then
  rollback || echo "Automatic rollback failed; durable rollback timer will retry." >&2
  exit 1
fi
printf '%s\n' "$sha" > "$state/deployed-sha.tmp"
mv "$state/deployed-sha.tmp" "$state/deployed-sha"
sync
