# /logs — Analisar Logs do Projeto com Subagente

You have been invoked with the `/logs` command. Your job is to spawn one or more subagents to read, parse, and analyze the project's logs. The goal is a diagnosis: what happened, what's wrong, what's the probable cause.

## Instructions

1. **Locate the logs**: Before spawning anything, do a quick recon to find where logs live. Check common locations:
   - `logs/` or `log/` directory
   - Any `*.log` files in the project root or subdirectories
   - Docker logs: `docker compose logs --tail=500` or `docker logs <container>`
   - Application output redirected to files
   - `journalctl` if running as a systemd service
   - `/var/log/` if applicable
   - If the user specified a log source or path, use that directly

2. **Assess scope and spawn**: Based on the volume and variety of logs found:
   - **1 subagent**: Single log source or small volume — one subagent handles everything
   - **2 subagents**: Multiple log sources (e.g., app logs + database logs) — each subagent owns a source
   - **3 subagents**: Large volume or multiple services — divide by service, time window, or severity

3. **Subagent mission**: Each subagent must:
   - Read the assigned logs using bash (cat, tail, grep) and Read tool
   - Parse both structured JSON logs and plain text logs
   - Identify and categorize findings:
     - **CRITICAL / ERROR**: failures, crashes, unhandled exceptions
     - **WARNING**: recoverable issues, deprecations, approaching limits
     - **Retry patterns**: repeated attempts at the same operation, backoff sequences
     - **Slow operations**: entries with elapsed_ms, timeout warnings, query duration
     - **Anomalies**: sudden spikes, gaps in logging, unexpected event sequences
   - For each finding, capture: event name, severity, count, time range, the actual log message, and relevant contextual fields
   - NOT modify any files — strictly read-only

4. **Consolidate and report**: After subagents return, synthesize a single analysis report.

## Report Format

```
SUMMARY
One or two sentences on the overall state of the system based on log evidence.

ERRORS
- [count]x event_name (first: timestamp, last: timestamp)
  Message: the actual error message
  Context: relevant fields (request_id, user_id, etc.)
  Probable cause: what likely triggered this

WARNINGS
- [count]x event_name (first: timestamp, last: timestamp)
  Message: the warning message
  Risk: what could happen if ignored

PATTERNS
- Description of any notable pattern (retry storms, cascading failures,
  periodic errors, performance degradation over time, correlated events)

TIMELINE
If relevant, a chronological reconstruction of what happened:
  HH:MM:SS - event A
  HH:MM:SS - event B triggered by A
  HH:MM:SS - cascade begins

RECOMMENDED ACTIONS
1. Concrete next step to investigate or fix issue #1
2. Concrete next step for issue #2
...
```

## Rules

- All subagents are READ-ONLY — no file modifications, no restarts, no config changes
- The analysis is factual and evidence-based — cite specific log entries, not assumptions
- No emojis anywhere in the output
- No speculation without evidence — if the cause is unclear, say "cause unclear, needs further investigation" and suggest what to check
- If no logs are found anywhere, report that clearly and suggest how to enable or locate logging for the project's stack
- Prefer recent logs over old ones — if logs are large, focus on the last N lines or the most recent time window
- Group related errors — don't list the same error 50 times, show it once with count and time range
- If the user mentioned a specific issue or symptom, prioritize findings related to that
