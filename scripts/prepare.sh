#!/usr/bin/env bash
# Stamps the downloaded report with the pull request found by find-pr.sh and
# writes the body to upload as $WORK_DIR/upload.json. The artifact was written
# by pull request code: it is read as data only, never executed.
set -euo pipefail

# Keep in sync with upload.sh. The raw file may be pretty-printed and shrink
# when compacted, so it gets headroom; this bound only stops a huge artifact
# from being fed to jq.
max_raw_bytes=$((4 * 5242880))

artifact_dir=$(cd -P "$WORK_DIR/artifact" && pwd -P)
report_path="$artifact_dir/$REPORT_FILE"
if [ -L "$report_path" ] || [ ! -f "$report_path" ]; then
  echo "::error::the artifact has no regular file '$REPORT_FILE'; check the report_file input and the path the benchmark job uploaded"
  exit 1
fi
# A directory inside the artifact must not lead outside of it.
report_dir=$(cd -P "$(dirname "$report_path")" && pwd -P)
case "$report_dir/" in
  "$artifact_dir"/*) ;;
  *)
    echo "::error::'$REPORT_FILE' resolves outside the artifact"
    exit 1
    ;;
esac

size=$(wc -c < "$report_path" | tr -d ' ')
if [ "$size" -gt "$max_raw_bytes" ]; then
  echo "::error::the report file is $size bytes, far over the 5 MiB (5242880 bytes) limit of hotpath.rs; measure fewer functions or split the benchmark"
  exit 1
fi

# The event is stamped, not trusted: the relay's token is a `workflow_run`
# one, which the server accepts only for a `pull_request` report. The pull
# request fields come from the lookup. Every other key of `meta` is kept,
# `policy` included. Compact, the form the benchmark job's size check measured.
if ! jq -c --arg source_root "$SOURCE_ROOT" --slurpfile pr "$WORK_DIR/pr.json" '
  if type != "object" then error("the report is not a JSON object") else . end
  | .meta.source_root = $source_root
  | .meta.ci.event = "pull_request"
  | .meta.git.base_sha = $pr[0].base.sha
  | .meta.ci.pull_request += {
      number: $pr[0].number,
      base_ref: $pr[0].base.ref,
      head_ref: $pr[0].head.ref,
      head_sha: $pr[0].head.sha
    }' "$report_path" > "$WORK_DIR/upload.json" 2> "$WORK_DIR/jq.err"; then
  # Flattened, so the message cannot start a workflow command on its own line.
  echo "::error::'$REPORT_FILE' is not a hotpath JSON report: $(head -c 500 "$WORK_DIR/jq.err" | tr '\r\n' '  ')"
  exit 1
fi
