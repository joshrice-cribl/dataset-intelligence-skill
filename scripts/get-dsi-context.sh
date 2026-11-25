#!/usr/bin/env bash
# Fetch the Dataset Intelligence markdown reference file for a Cribl Search dataset.
#
# Usage:   CRIBL_BASE_URL=https://main-<org>.cribl.cloud CRIBL_TOKEN=<token> \
#            ./get-dsi-context.sh <dataset-id> [group]
#
# Prints the markdown content to stdout on success.
# Exit codes: 0 = content printed, 2 = no DSI (never run or empty), 3 = still processing, 1 = error.
set -euo pipefail

DATASET_ID="${1:?usage: get-dsi-context.sh <dataset-id> [group]}"
GROUP="${2:-default_search}"
: "${CRIBL_BASE_URL:?set CRIBL_BASE_URL, e.g. https://main-<org-id>.cribl.cloud}"
: "${CRIBL_TOKEN:?set CRIBL_TOKEN to a bearer token with Search access}"

fetch() {
  curl -s -w '\n%{http_code}' -H "Authorization: Bearer $CRIBL_TOKEN" "$1"
}

# Unscoped path first (verified real on Cribl.Cloud), group-scoped fallback.
# A 404 only means "DSI never run" when the body is the handler's JSON error;
# an HTML "Cannot GET" 404 means the route doesn't exist there — try the next path.
for path in \
  "$CRIBL_BASE_URL/api/v1/ai/settings/dataset-intelligence/$DATASET_ID" \
  "$CRIBL_BASE_URL/api/v1/m/$GROUP/ai/settings/dataset-intelligence/$DATASET_ID"; do

  response="$(fetch "$path")"
  code="${response##*$'\n'}"
  body="${response%$'\n'*}"

  case "$code" in
    404)
      if printf '%s' "$body" | python3 -c 'import json,sys; json.load(sys.stdin)' 2>/dev/null; then
        echo "no-dsi: Dataset Intelligence has never been run on '$DATASET_ID'" >&2; exit 2
      fi
      continue ;;  # HTML 404 = route not here; try the fallback path
    403|405) continue ;;  # try the fallback path
    200) ;;
    *) echo "error: GET $path returned HTTP $code" >&2; exit 1 ;;
  esac

  status="$(printf '%s' "$body" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("status",""))')"
  content="$(printf '%s' "$body" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("content",""))')"

  if [ "$status" = "processing" ]; then
    echo "processing: DSI generation is in flight (~2-3 min); retry later or sample the dataset" >&2
    exit 3
  fi
  if [ -z "$content" ]; then
    echo "no-dsi: DSI status is '$status' but content is empty (likely scanned while dataset was empty)" >&2
    exit 2
  fi

  [ "$status" = "partial" ] && echo "note: DSI status is 'partial' - reference file may be incomplete" >&2
  printf '%s\n' "$content"
  exit 0
done

echo "error: all endpoint paths were rejected (check token permissions and group name)" >&2
exit 1
