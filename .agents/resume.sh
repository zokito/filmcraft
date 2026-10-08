#!/usr/bin/env bash
# Resume a worker whose headless run ended (same worktree, claude -p --continue).
# usage: .agents/resume.sh <SID> [role] [prompt]
set -euo pipefail
SID="${1:?session id}"; ROLE="${2:-implementer}"
PROMPT="${3:-Continue your task from .agents/briefs/$SID.md. Stop when every Done-when has a verbatim proof in the PR body.}"
REPO="$(git -C "$(dirname "${BASH_SOURCE[0]}")/.." rev-parse --show-toplevel)"
# When run from inside a worktree, the main checkout is the common dir's parent.
MAIN="$(dirname "$(git -C "$REPO" rev-parse --path-format=absolute --git-common-dir)")"
NAME="$(basename "$MAIN")"
WT="${CRAFT_WT_ROOT:-$MAIN-wt}/$SID"
STATE="${CRAFT_WT_ROOT:-$MAIN-wt}/.state"
MODEL="${CRAFT_MODEL:-claude-sonnet-5}"
TSESS="${CRAFT_TMUX:-craft}"
[ -d "$WT" ] || { echo "no worktree $WT" >&2; exit 1; }
tmux has-session -t "$TSESS" 2>/dev/null || tmux new-session -d -s "$TSESS" -n main
tmux new-window -d -t "$TSESS" -n "$SID" -c "$WT" \
  "CRAFT_SESSION=$SID CRAFT_ROLE=$ROLE CRAFT_WRITESET_FILE=$WT/.agents/writesets/$SID.txt CRAFT_REPO=zokito/$NAME CLAUDE_PROJECT_DIR=$WT \
   CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS=0 \
   claude -p --continue \"$PROMPT\" \
     --model $MODEL \
     --settings .agents/roles/$ROLE.json \
     --permission-mode acceptEdits \
     --output-format stream-json --verbose \
     >> $STATE/$SID.stream.jsonl 2>> $STATE/$SID.err; \
   .agents/on-exit.sh $SID \$? $STATE"
echo "resumed $SID in $WT; tmux: $TSESS:$SID"
