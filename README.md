# Dataset Intelligence Skill

A simple agent skill that makes direct Cribl Search API queries **Dataset
Intelligence–aware** — for harnesses that don't use the Cribl MCP server.

## The problem

Dataset Intelligence (DSI) generates a markdown reference file per dataset
(record families, KQL field rules, semantic field mappings). Cribl's built-in
Investigations agent consumes it automatically, but the **search API does
not**: a harness that composes its own KQL and `POST`s a search job never sees
the DSI file. The context exists — nothing injects it.

## What this skill does

Teaches the agent a four-step loop:

1. `GET` the DSI reference file for the target dataset
   (`/api/v1/m/{group}/ai/settings/dataset-intelligence/{datasetId}`)
2. Use the markdown as context for composing KQL
3. Fall back to sampling (`dataset=X | limit 100`) when there's no usable DSI,
   optionally triggering a DSI run for next time
4. Run the search via the standard search-jobs API

## Install

Copy this directory into your harness's skills location, e.g. for Claude Code:

```bash
cp -r . ~/.claude/skills/cribl-dataset-intelligence-context/
```

Or per-project: `<repo>/.claude/skills/cribl-dataset-intelligence-context/`.

## Contents

- `SKILL.md` — the skill: endpoints, response handling, fallback logic, caveats
- `scripts/get-dsi-context.sh` — helper that fetches the DSI markdown with
  path fallback and clean exit codes (0 = content, 2 = no DSI, 3 = processing)

## Caveat

The DSI endpoint is the internal one the product UI calls — it isn't in the
published API reference and may change when DSI V2 ships.
