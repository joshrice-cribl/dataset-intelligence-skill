#!/usr/bin/env bash
# Prod smoke test for the dataset-intelligence skill flow.
# Reads CRIBL_CLIENT_ID / CRIBL_CLIENT_SECRET / CRIBL_CLOUD_URL from the environment.
# Never prints tokens or secrets.
set -uo pipefail

BASE="${CRIBL_CLOUD_URL:?}"
echo "== Target: $BASE"

# --- Step 0: OAuth token ---
TOKEN=$(curl -s -X POST https://login.cribl.cloud/oauth/token \
  -H "Content-Type: application/json" \
  -d "{\"grant_type\":\"client_credentials\",\"client_id\":\"$CRIBL_CLIENT_ID\",\"client_secret\":\"$CRIBL_CLIENT_SECRET\",\"audience\":\"https://api.cribl.cloud\"}" \
  | python3 -c 'import json,sys; print(json.load(sys.stdin).get("access_token",""))')
if [ -z "$TOKEN" ]; then echo "FAIL: could not obtain OAuth token"; exit 1; fi
echo "OK: obtained bearer token (length ${#TOKEN})"
AUTH="Authorization: Bearer $TOKEN"

# --- Step 1: list datasets ---
echo
echo "== Step 1: list Search datasets"
DS_JSON=$(curl -s -H "$AUTH" "$BASE/api/v1/m/default_search/search/datasets")
echo "$DS_JSON" | python3 -c '
import json,sys
try:
    body = json.load(sys.stdin)
except Exception as e:
    print("FAIL: non-JSON response:", e); sys.exit(1)
items = body.get("items", [])
print(f"OK: {len(items)} datasets")
for d in items[:40]:
    print("  -", d.get("id"), "| type:", d.get("type"))
' || echo "$DS_JSON" | head -c 400

# --- Step 2: probe DSI endpoint for each dataset ---
echo
echo "== Step 2: GET dataset-intelligence for each dataset (unscoped path first)"
IDS=$(echo "$DS_JSON" | python3 -c 'import json,sys; [print(d["id"]) for d in json.load(sys.stdin).get("items",[])]')
for id in $IDS; do
  for path in "$BASE/api/v1/ai/settings/dataset-intelligence/$id" \
              "$BASE/api/v1/m/default_search/ai/settings/dataset-intelligence/$id"; do
    resp=$(curl -s -w '\n%{http_code}' -H "$AUTH" "$path")
    code="${resp##*$'\n'}"; body="${resp%$'\n'*}"
    if [ "$code" = "403" ] || [ "$code" = "405" ]; then continue; fi
    summary=$(printf '%s' "$body" | python3 -c '
import json,sys
try:
    b=json.load(sys.stdin)
    print(f"status={b.get(\"status\")} contentLen={len(b.get(\"content\") or \"\")} generatedAt={b.get(\"generatedAt\")}")
except Exception:
    print("(non-JSON body)", sys.stdin.read()[:80] if False else "")' 2>/dev/null)
    scope=$([ "${path#*/m/}" != "$path" ] && echo scoped || echo unscoped)
    printf "  %-45s HTTP %s (%s) %s\n" "$id" "$code" "$scope" "$summary"
    break
  done
done
