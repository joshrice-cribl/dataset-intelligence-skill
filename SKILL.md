---
name: cribl-dataset-intelligence-context
description: Fetch the Dataset Intelligence (DSI) markdown reference file for a Cribl Search dataset via the REST API and use it as context before composing and running KQL — for harnesses that call the Cribl API directly without the Cribl MCP server. Use when querying Cribl Search datasets via API, when asked to "search a Cribl dataset", "compose KQL for a dataset", or "get dataset intelligence context".
---

# Cribl Dataset Intelligence Context (no MCP server)

## Why this skill exists

Dataset Intelligence (DSI) generates a markdown reference file describing a
dataset's record families, field-access rules, and semantic field mappings.
Cribl's own server-side Investigations agent consumes it automatically — but a
**raw search API call does not**. The search engine is DSI-unaware: if you
compose KQL yourself and `POST` a search job, the DSI file is never consulted
and never returned.

So, before composing KQL against a dataset, this skill fetches the DSI
markdown yourself and uses it as context. That is the entire trick.

```
1. GET the DSI reference file for the dataset   ──►  markdown (or 404)
2. Read it: record families, field rules, mappings
3. Compose KQL informed by that context
4. POST the search job and fetch results
```

## Prerequisites

- A Cribl.Cloud (or on-prem Leader) base URL, e.g.
  `https://main-<org-id>.cribl.cloud`
- A bearer token with Search access and read access to the dataset
- The dataset ID you intend to query

## Step 1 — Fetch the DSI reference file

```bash
# Unscoped path — verified against Cribl.Cloud prod (Nov 2025):
curl -s -H "Authorization: Bearer $CRIBL_TOKEN" \
  "$CRIBL_BASE_URL/api/v1/ai/settings/dataset-intelligence/$DATASET_ID"

# Fallback (group-scoped) for deployments that route AI settings per group:
curl -s -H "Authorization: Bearer $CRIBL_TOKEN" \
  "$CRIBL_BASE_URL/api/v1/m/default_search/ai/settings/dataset-intelligence/$DATASET_ID"
```

A `404` only means "DSI never run" when the body is the handler's JSON error
(`{"error":"Dataset intelligence not found"}`). An HTML `Cannot GET` 404 means
the route doesn't exist at that path — try the other path.

Or use the bundled helper, which handles both paths and the status cases:

```bash
./scripts/get-dsi-context.sh <dataset-id>
```

**Response shape** (undocumented/internal endpoint — same call the product UI
makes; subject to change with DSI V2):

```json
{
  "status": "complete | partial | processing | failed",
  "generatedAt": 1763500000000,
  "content": "# <markdown reference file>..."
}
```

**Interpret the result:**

| Result | Meaning | What to do |
|---|---|---|
| `200`, `status: complete`, non-empty `content` | DSI is populated | Use `content` as context (Step 2) |
| `200`, `status: partial` | Usable but incomplete | Use it, note the gap |
| `200` but `content` empty | DSI ran against an empty dataset ("false coverage") | Treat as no DSI — sample instead |
| `404` with JSON error body | DSI never run on this dataset | Treat as no DSI — sample instead |
| `404` with HTML `Cannot GET` body | Wrong path for this deployment | Try the other path variant |
| `status: processing` | Generation in flight (~2–3 min) | Don't wait; sample, or retry later |
| `403` | Token lacks dataset read access | Surface the permission error — never fail silently |

## Step 2 — Use the markdown as context

The `content` field is a structured markdown document. Read it before writing
any KQL. It contains, in order:

- **Overview** — what the dataset holds, including heterogeneous structure
- **Record families** — one entry per distinct log type, each with a
  **ready-made KQL filter** scoped to that source. Prefer these filters as
  your starting point instead of guessing.
- **KQL field rules** — dataset-specific gotchas: fields needing
  bracket-quoting (`['field.with.dots']`), numeric-vs-string types, nested
  access patterns. Apply these verbatim.
- **Semantic field mappings** — which actual fields mean user / action /
  status / timestamp. Use these to translate the question into field names.

Generated files may also include **Starter Queries** and an **Investigation
Playbook** section with ready-to-run KQL. Starter queries begin with the
`cribl` command (`cribl dataset=...`) — keep that prefix when submitting via
the API, as the Search API guide instructs (a bare `dataset=...` also executes,
but the prefixed form is the documented contract).

Inject the full markdown into the model's context, then compose the query.

## Step 3 — Fallback when there is no DSI content

If Step 1 returned no usable content, do what Cribl's own investigation agent
does: sample the dataset first, then compose.

```
cribl dataset="<dataset-id>" | limit 100
```

Run that as a search (Step 4), inspect the field shapes from the results, and
compose the real query from what you observed. Never compose blind KQL against
a dataset you have neither DSI context nor samples for.

Optionally, trigger DSI generation for next time (one-shot, async, ~2–3 min):

```bash
curl -s -X POST -H "Authorization: Bearer $CRIBL_TOKEN" \
  "$CRIBL_BASE_URL/api/v1/ai/settings/dataset-intelligence/$DATASET_ID"
```

## Step 4 — Run the search

```bash
# Create the search job. Per the Search API guide, begin the query with the
# `cribl` operator. (Double quotes so $DATASET_ID expands; inner quotes escaped.)
curl -s -X POST -H "Authorization: Bearer $CRIBL_TOKEN" \
  -H "Content-Type: application/json" \
  "$CRIBL_BASE_URL/api/v1/m/default_search/search/jobs" \
  -d "{\"query\": \"cribl dataset=\\\"$DATASET_ID\\\" | limit 100\", \"earliest\": \"-24h\", \"latest\": \"now\"}"

# Returns {"items":[{"id":"<job-id>", ...}]} — poll the documented status
# endpoint until status is "completed":
curl -s -H "Authorization: Bearer $CRIBL_TOKEN" \
  "$CRIBL_BASE_URL/api/v1/m/default_search/search/jobs/<job-id>/status"

# Then fetch results (paginate with limit/offset):
curl -s -H "Authorization: Bearer $CRIBL_TOKEN" \
  "$CRIBL_BASE_URL/api/v1/m/default_search/search/jobs/<job-id>/results?limit=100&offset=0"
```

Results come back as **NDJSON**: the first line is a header object
(`totalEventCount`, `isFinished`, ...) and each following line is one event.

Verified against prod (Nov 2025): the query also executes without the `cribl`
prefix, and `GET .../search/jobs/<job-id>` also returns the `status` field —
but prefer the documented forms above.

KQL quick rules (the DSI field rules override these where they conflict):
`==` not `=`; `or` not `||`; `summarize total=count() by field` (no `as`);
`timestats span=1h count()` (span before the aggregation); bracket-quote
dotted fields.

## Caveats

- The DSI endpoint is **internal/undocumented** — it is what the product UI
  calls, not part of the published API reference. Pin your integration tests
  to it and expect change when DSI V2 lands.
- DSI samples ~1,000 events at generation time; results go stale as new,
  different-shaped data arrives, and they never refresh on their own. Check
  `generatedAt` and treat old files on fast-changing datasets with suspicion.
- DSI exists only for **log** datasets, not `metrics` datasets.
- An empty-`content` "complete" run is the classic trap (Lakehouse datasets
  scanned before data flowed in). Always check `content`, not just `status`.
- The DSI endpoint returns the same JSON 404 for a **nonexistent dataset** as
  for "never run" — it does not validate the dataset ID. Confirm the dataset
  exists (via the datasets list) before concluding DSI was simply never run.
