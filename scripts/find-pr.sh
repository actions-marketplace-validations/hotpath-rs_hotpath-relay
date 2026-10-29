#!/usr/bin/env bash
# Checks the inputs and the triggering run, then finds the open pull request
# the benchmark run belongs to. Writes `dir` (a fresh scratch directory) and,
# when there is a report to relay, `number` to $GITHUB_OUTPUT. Exits 0 without
# `number` when there is nothing to relay, so the remaining steps skip.
set -euo pipefail

for cmd in gh jq curl; do
  if ! command -v "$cmd" > /dev/null; then
    echo "::error::hotpath-relay needs '$cmd' on the runner; use ubuntu-latest or install it"
    exit 1
  fi
done

# Inputs arrive through the environment, never interpolated into this text.
if ! [[ "$BENCHMARK" =~ ^[A-Za-z0-9._-]{1,64}$ ]]; then
  echo "::error::the benchmark input must be 1-64 characters from [A-Za-z0-9._-]; check the workflow name lookup if it is computed"
  exit 1
fi
if [ -z "$ARTIFACT_NAME" ]; then
  # An empty name would make download-artifact fetch every artifact of the run.
  echo "::error::the artifact_name input must not be empty"
  exit 1
fi
if [ -z "$REPORT_FILE" ]; then
  echo "::error::the report_file input must not be empty"
  exit 1
fi
# Both paths are joined under a directory: relative, without `..`.
check_relative() {
  case "$2" in
    /* | .. | ../* | */.. | */../* | *\\* | *[[:cntrl:]]*)
      echo "::error::the $1 input must be a relative path without '..' segments, backslashes or control characters"
      exit 1
      ;;
  esac
}
check_relative report_file "$REPORT_FILE"
check_relative source_root "$SOURCE_ROOT"

if [ "${GITHUB_EVENT_NAME:-}" != workflow_run ]; then
  echo "::error::hotpath-relay must run in a workflow triggered by 'on: workflow_run', not '${GITHUB_EVENT_NAME:-}'"
  exit 1
fi

# The run's fields come from the event file GitHub wrote, read as data.
run_event=$(jq -r '.workflow_run.event // empty' "$GITHUB_EVENT_PATH")
conclusion=$(jq -r '.workflow_run.conclusion // empty' "$GITHUB_EVENT_PATH")
if [ "$run_event" != pull_request ]; then
  echo "::notice::the benchmark run was triggered by '$run_event', not pull_request, nothing to relay"
  exit 0
fi
if [ "$conclusion" != success ]; then
  echo "::notice::the benchmark run concluded '$conclusion', not success, nothing to relay"
  exit 0
fi

# A composite action cannot grant permissions: the calling job must.
if [ -z "${ACTIONS_ID_TOKEN_REQUEST_URL:-}" ] || [ -z "${ACTIONS_ID_TOKEN_REQUEST_TOKEN:-}" ]; then
  echo "::error::no OIDC token available: grant the relay job 'id-token: write' (and 'actions: read', 'pull-requests: read')"
  exit 1
fi

HEAD_SHA=$(jq -r '.workflow_run.head_sha // empty' "$GITHUB_EVENT_PATH")
head_owner=$(jq -r '.workflow_run.head_repository.owner.login // empty' "$GITHUB_EVENT_PATH")
head_branch=$(jq -r '.workflow_run.head_branch // empty' "$GITHUB_EVENT_PATH")
if [ -z "$HEAD_SHA" ] || [ -z "$head_owner" ] || [ -z "$head_branch" ]; then
  echo "::notice::the benchmark run has no head repository or branch (deleted fork?), nothing to relay"
  exit 0
fi
export HEAD_SHA

dir=$(mktemp -d "${RUNNER_TEMP:-/tmp}/hotpath-relay.XXXXXX")
echo "dir=$dir" >> "$GITHUB_OUTPUT"

# The report is written by pull request code, so nothing in it says which
# pull request it belongs to: a report claiming another number would replace
# that pull request's comment. The run's head commit is set by GitHub, and the
# open pull request whose head is that commit is the one. None when the branch
# has moved on since: the run of the newer commit relays its own report.
gh api -X GET "repos/$GITHUB_REPOSITORY/pulls" -f state=open -f head="$head_owner:$head_branch" \
  --jq 'map(select(.head.sha == env.HEAD_SHA)) | first // empty' > "$dir/pr.json"
if [ ! -s "$dir/pr.json" ]; then
  echo "::notice::no open pull request has head $HEAD_SHA, nothing to relay"
  exit 0
fi
number=$(jq -er '.number | select(type == "number")' "$dir/pr.json")
echo "number=$number" >> "$GITHUB_OUTPUT"
