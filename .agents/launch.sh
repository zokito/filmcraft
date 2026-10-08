#!/usr/bin/env bash
# Launch one worker session in its own worktree and tmux window.
# Adapted from hdb-books tools/agents/launch.sh. This directory exists only in the zokito fork.
# usage: .agents/launch.sh <SID> [role]        e.g. .agents/launch.sh C-1
# Prerequisites: tmux, claude, gh logged in as zokito, a free slot (max 4 workers), >= 50 GB free.
# A headless claude run is killed after 600 s of waiting for background subagents unless
# CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS=0; resume with .agents/resume.sh.
set -euo pipefail
SID="${1:?session id, e.g. C-1}"; ROLE="${2:-implementer}"
REPO="$(git -C "$(dirname "${BASH_SOURCE[0]}")/.." rev-parse --show-toplevel)"
NAME="$(basename "$REPO")"
WT="${CRAFT_WT_ROOT:-$REPO-wt}/$SID"
STATE="${CRAFT_WT_ROOT:-$REPO-wt}/.state"
BRANCH="agents/$SID"
MODEL="${CRAFT_MODEL:-claude-sonnet-5}"
TSESS="${CRAFT_TMUX:-craft}"
BRIEF=".agents/briefs/$SID.md"
WS=".agents/writesets/$SID.txt"
for f in ".agents/roles/$ROLE.json" "$BRIEF" "$WS"; do
  [ -f "$REPO/$f" ] || { echo "missing $f" >&2; exit 1; }
done
running=$(tmux list-windows -a -F '#W' 2>/dev/null | grep -cE '^[A-Z]-[0-9]+$' || true)
[ "$running" -lt 4 ] || { echo "4 workers already running; wait for a free slot" >&2; exit 1; }
free_gb=$(df -g "$REPO" | awk 'NR==2 {print $4}')
[ "$free_gb" -ge 50 ] || { echo "only ${free_gb} GB free (< 50): stop, clean first" >&2; exit 1; }
git -C "$REPO" fetch -q origin main
git -C "$REPO" worktree add -B "$BRANCH" "$WT" origin/main
mkdir -p "$STATE"
tmux has-session -t "$TSESS" 2>/dev/null || tmux new-session -d -s "$TSESS" -n main
PROMPT="You are worker $SID for $NAME (the zokito fork of storytold/$NAME).
Read $BRIEF fully; it is your task. Write only inside the paths in $WS (the guard hook refuses others).
Commit on branch $BRANCH, push it to origin (github.com/zokito/$NAME) and open one PR with
gh pr create -R zokito/$NAME --base main --head $BRANCH. Never open a PR against storytold, never merge.
You run headless: ending your turn ends the process. Run every cargo build/test/xtask in the
FOREGROUND (Bash timeout 600000 ms, output to /tmp/craft-$SID/<name>.log, print only the tail);
never use run_in_background and never stop to wait for a notification.
Stop when every Done-when in the brief has a verbatim proof in the PR body."
tmux new-window -d -t "$TSESS" -n "$SID" -c "$WT" \
  "CRAFT_SESSION=$SID CRAFT_ROLE=$ROLE CRAFT_WRITESET_FILE=$WT/$WS CRAFT_REPO=zokito/$NAME CLAUDE_PROJECT_DIR=$WT \
   CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS=0 \
   claude -p \"$PROMPT\" \
     --model $MODEL \
     --settings .agents/roles/$ROLE.json \
     --permission-mode acceptEdits \
     --output-format stream-json --verbose \
     > $STATE/$SID.stream.jsonl 2> $STATE/$SID.err; \
   .agents/on-exit.sh $SID \$? $STATE"
echo "launched $SID ($ROLE, $MODEL) in $WT on $BRANCH; tmux: $TSESS:$SID; log: $STATE/$SID.stream.jsonl"
