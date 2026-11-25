#!/usr/bin/env bash
# Trigger a one-shot Dataset Intelligence generation on one dataset.
# This is the exact call the product UI's "Enable Dataset Intelligence" button
# makes. It does not create, modify, or delete the dataset or its data.
set -uo pipefail
BASE="${CRIBL_CLOUD_URL:?}"
DS="${1:?usage: trigger-dsi.sh <dataset-id>}"

TOKEN=$(curl -s -X POST https://login.cribl.cloud/oauth/token \
  -H "Content-Type: application/json" \
  -d "{\"grant_type\":\"client_credentials\",\"client_id\":\"$CRIBL_CLIENT_ID\",\"client_secret\":\"$CRIBL_CLIENT_SECRET\",\"audience\":\"https://api.cribl.cloud\"}" \
  | python3 -c 'import json,sys; print(json.load(sys.stdin).get("access_token",""))')
[ -n "$TOKEN" ] || { echo "FAIL: no token"; exit 1; }

curl -s -w '\nHTTP %{http_code}\n' -X POST -H "Authorization: Bearer $TOKEN" \
  "$BASE/api/v1/ai/settings/dataset-intelligence/$DS" | head -c 500
