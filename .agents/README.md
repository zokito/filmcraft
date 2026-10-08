# .agents (zokito fork only)

Headless worker sessions for fixes in this fork, adapted from hdb-books `tools/agents/`.
Not for upstream: fix branches start from this commit, so cherry-pick fix commits only.

| File | Purpose |
|---|---|
| `launch.sh <SID>` | worktree `../filmcraft-wt/<SID>`, branch `agents/<SID>`, tmux window `craft:<SID>`, headless `claude -p` (Sonnet) |
| `resume.sh <SID>` | same worktree, `claude -p --continue` |
| `on-exit.sh` | writes `../filmcraft-wt/.state/<SID>.exit.json` |
| `guard.py` | PreToolUse hook: write set, no push to main/upstream, PRs only to zokito/filmcraft, no merge; `--selftest` |
| `roles/implementer.json` | permissions + hook |
| `briefs/<SID>.md`, `writesets/<SID>.txt` | task and allowed paths |

Logs: `../filmcraft-wt/.state/<SID>.stream.jsonl`. Watch: `tmux attach -t craft`.
