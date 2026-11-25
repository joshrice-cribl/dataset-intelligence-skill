# Dataset Intelligence Skill

A simple agent skill that makes direct Cribl Search API queries Dataset
Intelligence aware, for harnesses that don't use the Cribl MCP server.

## The problem

Dataset Intelligence (DSI) generates a markdown reference file per dataset
(record families, KQL field rules, semantic field mappings). Cribl's built-in
Investigations agent consumes it automatically, but the search API does not:
a harness that composes its own KQL and `POST`s a search job never sees the
DSI file. The context exists, but nothing injects it.

## What this skill does

Teaches the agent a four-step loop:

1. `GET` the DSI reference file for the target dataset
   (`/api/v1/ai/settings/dataset-intelligence/{datasetId}`)
2. Use the markdown as context for composing KQL
3. Fall back to sampling (`dataset=X | limit 100`) when there's no usable DSI,
   optionally triggering a DSI run for next time
4. Run the search via the standard search-jobs API

## Why this improves searches

Without DSI context, an agent querying an unfamiliar dataset is guessing. It
either composes blind KQL (and gets wrong field names, type mismatches, or
empty results) or it burns a search execution on a sampling query, then reasons
over hundreds of raw events to infer the schema. The DSI reference file
replaces that guesswork with a compact, pre-computed schema summary (roughly
6 KB of markdown versus hundreds of KB of raw sample events). Concretely:

- **First-query accuracy.** Each record family in the file ships with a
  ready-made KQL filter (for example, scoping `cribl_internal_logs` to
  `source == ".../access.log"` before touching access-log fields). The agent
  starts from a known-good query instead of discovering the shape by
  trial and error.
- **Fewer failed and wasted searches.** The KQL field rules capture the
  gotchas that break queries: fields that need bracket access
  (`stats["id"]`, not `stats.id`), fields that are numeric rather than
  string, and mixed timestamp formats across record families. Each avoided
  bad query is a search execution, several seconds of latency, and a chunk
  of context window saved.
- **Correct semantic translation.** The semantic field mappings tell the
  agent which real fields mean "user", "action", "status", or "source IP"
  in this dataset, so a question like "show me failed API calls" lands on
  `status == 404` in the access-log family instead of a nonexistent
  `error` field.
- **Heterogeneous datasets become navigable.** Many datasets mix several log
  shapes under one datatype. The file names each family and instructs the
  agent to scope to one family per query, which keeps results precise
  instead of unioned noise.
- **Lower token cost and faster answers.** Injecting one small markdown file
  is cheaper than ingesting sample events, and it is deterministic: every
  run of the harness sees the same schema summary, instead of whatever 100
  events the sampling window happened to return.

In the prod verification of this skill, the generated file for
`cribl_internal_logs` let the agent go straight to a correct aggregation
(`summarize count() by status` scoped to the access-log family) with no
sampling step and no failed queries.

## Install

Copy this directory into your harness's skills location, e.g. for Claude Code:

```bash
cp -r . ~/.claude/skills/cribl-dataset-intelligence-context/
```

Or per-project: `<repo>/.claude/skills/cribl-dataset-intelligence-context/`.

## Contents

- `SKILL.md` - the skill: endpoints, response handling, fallback logic, caveats
- `scripts/get-dsi-context.sh` - helper that fetches the DSI markdown with
  path fallback and clean exit codes (0 = content, 2 = no DSI, 3 = processing)
- `scripts/trigger-dsi.sh` - trigger a one-shot DSI generation on a dataset
- `scripts/test-prod.sh` / `scripts/test-search.sh` - prod smoke tests for the
  DSI endpoint coverage and the search-jobs flow

## Caveat

The DSI endpoint is the internal one the product UI calls. It isn't in the
published API reference and may change when DSI V2 ships.
