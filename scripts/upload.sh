#!/usr/bin/env bash
# Uploads $WORK_DIR/upload.json to hotpath.rs, authenticated by a GitHub OIDC
# token for the `hotpath.rs` audience. The server's answer is shown whatever
# the status: in the step summary, and on one line in an `::error::`
# annotation when the upload was rejected. On success a `comment.error` means
# the server could not post or update the pull request comment.
set -euo pipefail

upload="$WORK_DIR/upload.json"
response="$WORK_DIR/response.json"

# The rewrite added fields after the benchmark job checked the size: check
# the body actually sent. Never truncated.
# Keep in sync with hotpath::json::cloud_api::MAX_REPORT_BYTES.
max_bytes=5242880
size=$(wc -c < "$upload" | tr -d ' ')
if [ "$size" -gt "$max_bytes" ]; then
  echo "::error::the report is $size bytes, over the 5 MiB ($max_bytes bytes) limit of hotpath.rs; measure fewer functions or split the benchmark"
  exit 1
fi

# `ACTIONS_ID_TOKEN_REQUEST_URL` always carries an `api-version` query, so the
# audience is appended with `&`.
if ! token=$(curl -sS --fail \
  -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" \
  "$ACTIONS_ID_TOKEN_REQUEST_URL&audience=hotpath.rs" | jq -er .value); then
  echo "::error::could not mint the GitHub OIDC token; the relay job needs 'id-token: write'"
  exit 1
fi
echo "::add-mask::$token"

if ! out=$(curl -sS -X POST https://hotpath.rs/api/v1/reports \
  --url-query "benchmark=$BENCHMARK" \
  -H "Authorization: Bearer $token" \
  -H "Content-Type: application/json" \
  --data-binary "@$upload" \
  -o "$response" -w '%{http_code} %header{x-request-id}'); then
  echo "::error::hotpath.rs unreachable"
  exit 1
fi
read -r status request_id <<< "$out"
touch "$response"
# A body that is not JSON is flattened by hand, so neither form can start a
# workflow command on a line of its own.
body=$(jq -c . "$response" 2>/dev/null || head -c 2000 "$response" | tr '\r\n' '  ')
{
  echo "## hotpath.rs $BENCHMARK benchmark"
  echo "HTTP $status, request ${request_id:--}"
  echo '```'; jq . "$response" 2>/dev/null || cat "$response"; echo '```'
} >> "$GITHUB_STEP_SUMMARY"
if [ "$status" != 201 ] && [ "$status" != 200 ]; then
  echo "::error::hotpath.rs rejected the report (HTTP $status): $body"
  exit 1
fi
comment_error=$(jq -r '.comment.error // empty' "$response" 2>/dev/null | tr '\r\n' '  ' || true)
if [ -n "$comment_error" ]; then
  echo "::warning::hotpath.rs comment failed: $comment_error"
fi
