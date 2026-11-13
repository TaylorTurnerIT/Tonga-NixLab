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
