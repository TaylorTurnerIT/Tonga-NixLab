#!/usr/bin/env bash
set -euo pipefail
source scripts/deploy/ci-policy.sh

sha=0123456789012345678901234567890123456789
run='{"workflow_runs":[{"id":1,"run_attempt":2,"head_sha":"0123456789012345678901234567890123456789","head_branch":"master","event":"push","path":".github/workflows/ci.yml","name":"Infrastructure CI","status":"completed","conclusion":"success"}]}'
[[ "$(printf '%s' "$run" | workflow_candidates "$sha")" == $'1\t2' ]]

for invalid_run in \
  '{"workflow_runs":[{"id":1,"run_attempt":1,"head_sha":"other","head_branch":"master","event":"push","path":".github/workflows/ci.yml","name":"Infrastructure CI","status":"completed","conclusion":"success"}]}' \
  '{"workflow_runs":[{"id":1,"run_attempt":1,"head_sha":"0123456789012345678901234567890123456789","head_branch":"master","event":"push","path":".github/workflows/ci.yml","name":"Other workflow","status":"completed","conclusion":"success"}]}' \
  '{"workflow_runs":[{"id":1,"run_attempt":1,"head_sha":"0123456789012345678901234567890123456789","head_branch":"master","event":"pull_request","path":".github/workflows/ci.yml","name":"Infrastructure CI","status":"completed","conclusion":"success"}]}' \
  '{"workflow_runs":[{"id":1,"run_attempt":1,"head_sha":"0123456789012345678901234567890123456789","head_branch":"master","event":"push","path":".github/workflows/other.yml","name":"Infrastructure CI","status":"completed","conclusion":"success"}]}' \
  '{"workflow_runs":[{"id":1,"run_attempt":1,"head_sha":"0123456789012345678901234567890123456789","head_branch":"master","event":"push","path":".github/workflows/ci.yml","name":"Infrastructure CI","status":"in_progress","conclusion":null}]}' \
  '{"check_runs":[{"name":"Required CI","status":"completed","conclusion":"success"}]}'
do
  [[ -z "$(printf '%s' "$invalid_run" | workflow_candidates "$sha")" ]]
done

# Exercise recovery with mocked host commands. Holding the deployment lock
# models a stalled activation while proving the watchdog uses an independent lock.
test_root="$(mktemp -d)"
trap 'rm -rf "$test_root"' EXIT
mkdir -p "$test_root/bin" "$test_root/state" "$test_root/previous/bin"
printf '%s\n' "$test_root/previous" > "$test_root/state/previous-system"
printf '0\n' > "$test_root/state/deadline"
printf 'candidate\n' > "$test_root/state/candidate-sha"
printf 'candidate\n' > "$test_root/state/deployed-sha"
: > "$test_root/state/pending"
cat > "$test_root/bin/systemctl" <<'MOCK'
#!/usr/bin/env bash
[[ "$1" == stop ]] && exit 0
exit 1
MOCK
cat > "$test_root/bin/nix-env" <<'MOCK'
#!/usr/bin/env bash
[[ "${MOCK_FAIL_ROLLBACK:-0}" == 0 ]]
MOCK
cat > "$test_root/bin/timeout" <<'MOCK'
#!/usr/bin/env bash
while [[ "$1" == --kill-after=* ]]; do shift; done
[[ "$1" =~ ^[0-9]+(s|m)?$ ]] && shift
exec "$@"
MOCK
cat > "$test_root/bin/flock" <<'MOCK'
#!/usr/bin/env bash
exit 0
MOCK
cat > "$test_root/previous/bin/switch-to-configuration" <<'MOCK'
#!/usr/bin/env bash
exit 0
MOCK
chmod +x "$test_root/bin/"* "$test_root/previous/bin/switch-to-configuration"
printf 'stalled activation holds this deployment lock\n' > "$test_root/state/deploy.lock"
exec 8>"$test_root/state/deploy.lock"
PATH="$test_root/bin:$PATH" TONGA_DEPLOY_STATE="$test_root/state" bash scripts/deploy/rollback-watchdog.sh
[[ ! -e "$test_root/state/pending" && ! -e "$test_root/state/deployed-sha" ]]
exec 8>&-

# A failed rollback keeps durable state so the next timer tick can retry.
: > "$test_root/state/pending"
printf '%s\n' "$test_root/previous" > "$test_root/state/previous-system"
printf '0\n' > "$test_root/state/deadline"
printf 'candidate\n' > "$test_root/state/candidate-sha"
printf 'candidate\n' > "$test_root/state/deployed-sha"
if PATH="$test_root/bin:$PATH" MOCK_FAIL_ROLLBACK=1 TONGA_DEPLOY_STATE="$test_root/state" bash scripts/deploy/rollback-watchdog.sh 2>"$test_root/rollback-failed.log"; then
  echo "Unexpectedly accepted failed rollback" >&2
  exit 1
fi
[[ -e "$test_root/state/pending" && -s "$test_root/state/previous-system" ]]
PATH="$test_root/bin:$PATH" TONGA_DEPLOY_STATE="$test_root/state" bash scripts/deploy/rollback-watchdog.sh
[[ ! -e "$test_root/state/pending" && ! -e "$test_root/state/deployed-sha" ]]

# Healthy state clears only after its deadline. The timer remains boot-enabled
# when polling is disabled, and its recovery check runs without GitHub access.
cat > "$test_root/bin/systemctl" <<'MOCK'
#!/usr/bin/env bash
[[ "$1" == stop ]] && exit 0
exit 0
MOCK
cat > "$test_root/bin/curl" <<'MOCK'
#!/usr/bin/env bash
exit 0
MOCK
cat > "$test_root/bin/tailscale" <<'MOCK'
#!/usr/bin/env bash
printf '{"BackendState":"Running","Health":[]}\n'
MOCK
cat > "$test_root/bin/jq" <<'MOCK'
#!/usr/bin/env bash
cat >/dev/null
MOCK
chmod +x "$test_root/bin/"*
printf '%s\n' "$test_root/previous" > "$test_root/state/previous-system"
: > "$test_root/state/pending"
printf 'candidate\n' > "$test_root/state/candidate-sha"
printf '%s\n' "$(( $(date +%s) + 3600 ))" > "$test_root/state/deadline"
PATH="$test_root/bin:$PATH" TONGA_DEPLOY_STATE="$test_root/state" bash scripts/deploy/rollback-watchdog.sh
[[ -e "$test_root/state/pending" ]]
printf '0\n' > "$test_root/state/deadline"
PATH="$test_root/bin:$PATH" TONGA_DEPLOY_STATE="$test_root/state" bash scripts/deploy/rollback-watchdog.sh
[[ ! -e "$test_root/state/pending" ]]
grep -q 'services.tongaAutoDeploy.enable = false' configuration.nix
grep -q 'wantedBy = lib.optionals cfg.enable' nix/auto-deploy.nix
grep -q 'OnBootSec = "20s"' nix/auto-deploy.nix

printf '%s' '{"total_count":4,"jobs":[{"status":"completed","conclusion":"success"},{"status":"completed","conclusion":"success"},{"status":"completed","conclusion":"success"},{"status":"completed","conclusion":"success"}]}' | all_jobs_succeeded
for invalid_jobs in \
  '{"total_count":0,"jobs":[]}' \
  '{"total_count":4,"jobs":[{"status":"completed","conclusion":"success"},{"status":"completed","conclusion":"success"},{"status":"completed","conclusion":"success"}]}' \
  '{"total_count":2,"jobs":[{"status":"completed","conclusion":"success"},{"status":"in_progress","conclusion":null}]}' \
  '{"total_count":1,"jobs":[{"status":"completed","conclusion":"failure"}]}' \
  '{"total_count":1,"jobs":[{"status":"completed","conclusion":"skipped"}]}' \
  '{"jobs":[{"status":"completed","conclusion":"success"}]}'
do
  if printf '%s' "$invalid_jobs" | all_jobs_succeeded; then
    echo "Unexpectedly accepted incomplete or unsuccessful workflow jobs" >&2
    exit 1
  fi
done
