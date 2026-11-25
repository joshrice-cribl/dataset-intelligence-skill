#!/usr/bin/env bash
# Prod test of Step 4 of the skill: create a search job and fetch results.
# Read/query only — no DSI trigger, no config changes.
set -uo pipefail
BASE="${CRIBL_CLOUD_URL:?}"
DS="${1:-cribl_internal_logs}"

TOKEN=$(curl -s -X POST https://login.cribl.cloud/oauth/token \
  -H "Content-Type: application/json" \
  -d "{\"grant_type\":\"client_credentials\",\"client_id\":\"$CRIBL_CLIENT_ID\",\"client_secret\":\"$CRIBL_CLIENT_SECRET\",\"audience\":\"https://api.cribl.cloud\"}" \
  | python3 -c 'import json,sys; print(json.load(sys.stdin).get("access_token",""))')
[ -n "$TOKEN" ] || { echo "FAIL: no token"; exit 1; }
AUTH="Authorization: Bearer $TOKEN"
echo "OK: token acquired"

echo
echo "== Create search job: dataset=\"$DS\" | limit 5"
JOB=$(curl -s -X POST -H "$AUTH" -H "Content-Type: application/json" \
  "$BASE/api/v1/m/default_search/search/jobs" \
  -d "{\"query\":\"dataset=\\\"$DS\\\" | limit 5\",\"earliest\":\"-1h\",\"latest\":\"now\"}")
echo "$JOB" | head -c 600; echo
JOB_ID=$(echo "$JOB" | python3 -c 'import json,sys
try:
    b=json.load(sys.stdin)
    items=b.get("items") or ([b] if b.get("id") else [])
    print(items[0]["id"] if items else "")
except Exception: print("")')
if [ -z "$JOB_ID" ]; then echo "FAIL: no job id"; exit 1; fi
echo "OK: job id = $JOB_ID"

echo
echo "== Poll job status"
for i in $(seq 1 12); do
  sleep 5
  ST=$(curl -s -H "$AUTH" "$BASE/api/v1/m/default_search/search/jobs/$JOB_ID" \
    | python3 -c 'import json,sys
b=json.load(sys.stdin); it=(b.get("items") or [b])[0]
print(it.get("status",""))' 2>/dev/null)
  echo "  poll $i: status=$ST"
  [ "$ST" = "completed" ] && break
  [ "$ST" = "failed" ] && { echo "FAIL: search job failed"; exit 1; }
done

echo
echo "== Fetch results"
RES=$(curl -s -H "$AUTH" "$BASE/api/v1/m/default_search/search/jobs/$JOB_ID/results?limit=5")
echo "$RES" | python3 -c 'import json,sys
raw=sys.stdin.read()
try:
    b=json.loads(raw)
    items=b.get("items", b if isinstance(b,list) else [])
    print(f"OK: results JSON, {len(items)} events")
    for e in items[:2]: print("  keys:", sorted(list(e))[:10])
except Exception:
    lines=[l for l in raw.splitlines() if l.strip()]
    print(f"OK: results NDJSON, {len(lines)} lines")
    for l in lines[:2]:
        try: print("  keys:", sorted(list(json.loads(l)))[:10])
        except Exception: print("  raw:", l[:120])'
