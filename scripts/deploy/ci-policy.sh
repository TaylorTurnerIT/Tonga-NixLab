#!/usr/bin/env bash

workflow_candidates() {
  jq -r --arg sha "$1" '
    (.workflow_runs // [])[] |
    select(.head_sha == $sha and .head_branch == "master" and
      .event == "push" and .path == ".github/workflows/ci.yml" and
      .name == "Infrastructure CI" and .status == "completed" and
      .conclusion == "success") |
    [.id, .run_attempt] | @tsv
  '
}

all_jobs_succeeded() {
  jq -e '
    (.total_count | type == "number") and
    (.jobs | type == "array") and
    (.total_count == (.jobs | length)) and
    (.total_count > 0) and
    ([.jobs[] | select(.status != "completed" or .conclusion != "success")] | length == 0)
  ' >/dev/null
}
