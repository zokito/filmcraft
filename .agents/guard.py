#!/usr/bin/env python3
"""PreToolUse guard for craft workers (adapted from hdb-books tools/agents/guard.py).

Hook mode: reads the hook JSON on stdin, exits 2 with a reason on stderr to block, 0 to allow.
`guard.py --selftest` checks every blocked and allowed case.
Environment: CRAFT_SESSION, CRAFT_WRITESET_FILE (one glob per line), CRAFT_REPO (zokito/<name>),
CLAUDE_PROJECT_DIR.
"""
import fnmatch
import json
import os
import re
import sys

EDIT_TOOLS = {"Edit", "Write", "MultiEdit", "NotebookEdit"}
GIT_PUSH_RE = re.compile(r"\bgit\s+(?:-C\s+\S+\s+)?push\b(?P<rest>.*)")
GIT_BRANCH_DEL_RE = re.compile(r"\bgit\s+branch\s+.*(?:-D\b|-d\b|--delete\b)")
PR_CREATE_RE = re.compile(r"\bgh\s+pr\s+create\b(?P<rest>.*)")
PR_MERGE_RE = re.compile(r"\bgh\s+pr\s+merge\b")
UPSTREAM_RE = re.compile(r"\bstorytold/")


def _rel(path, env):
    root = (env.get("CLAUDE_PROJECT_DIR") or os.getcwd()).rstrip("/")
    p = path if os.path.isabs(path) else os.path.abspath(path)
    return p[len(root) + 1:] if p.startswith(root + "/") else p


def in_writeset(rel, patterns):
    for pat in (p.strip() for p in patterns):
        if not pat or pat.startswith("#"):
            continue
        if pat.endswith("/**"):
            if rel.startswith(pat[:-3] + "/"):
                return True
        elif fnmatch.fnmatchcase(rel, pat):
            return True
    return False


def check(event, env):
    """Return a reason string to block, or None to allow."""
    tool = event.get("tool_name", "")
    inp = event.get("tool_input") or {}
    if tool == "Bash":
        cmd = str(inp.get("command") or "")
        m = GIT_PUSH_RE.search(cmd)
        if m:
            rest = m.group("rest")
            if re.search(r"(\s|:)(main|master)\b", rest):
                return "git push to main (PRs only)"
            if re.search(r"(\s--force\b|\s-f\b|\s--force-with-lease\b|\s\+\S)", rest):
                return "git force push"
            if re.search(r"(\s--delete\b|\s-d\b|\s:\S+)", rest) or "upstream" in rest:
                return "git push branch delete or push to upstream"
        if GIT_BRANCH_DEL_RE.search(cmd):
            return "git branch delete"
        m = PR_CREATE_RE.search(cmd)
        if m:
            repo = env.get("CRAFT_REPO", "")
            if not repo or f"-R {repo}" not in m.group("rest") and f"--repo {repo}" not in m.group("rest"):
                return f"gh pr create must target the fork: -R {repo or 'zokito/<name>'}"
        if PR_MERGE_RE.search(cmd):
            return "gh pr merge is owner only"
        if UPSTREAM_RE.search(cmd) and re.search(r"\bgh\s+(pr|issue|api|repo)\b", cmd):
            return "no GitHub operations against storytold (fork only)"
        if re.search(r"\brm\s+-[a-zA-Z]*r[a-zA-Z]*f|\brm\s+-[a-zA-Z]*f[a-zA-Z]*r", cmd):
            return "rm -rf"
    if tool in EDIT_TOOLS:
        ws = env.get("CRAFT_WRITESET_FILE")
        if not ws:
            return "CRAFT_WRITESET_FILE not set"
        try:
            with open(ws, encoding="utf-8") as f:
                patterns = f.read().splitlines()
        except OSError:
            return f"write set file {ws} unreadable"
        rel = _rel(str(inp.get("file_path") or inp.get("notebook_path") or ""), env)
        if rel.startswith(".agents/") or not in_writeset(rel, patterns):
            return f"`{rel}` outside the write set of {env.get('CRAFT_SESSION', '?')}"
    return None


def selftest():
    ws = "/tmp/craft-guard-selftest-ws.txt"
    with open(ws, "w", encoding="utf-8") as f:
        f.write("crates/fonts/**\napps/x-cli/tests/cli.rs\n")
    env = {"CRAFT_SESSION": "C-1", "CRAFT_WRITESET_FILE": ws, "CRAFT_REPO": "zokito/x",
           "CLAUDE_PROJECT_DIR": "/repo"}
    bash = lambda c: {"tool_name": "Bash", "tool_input": {"command": c}}
    edit = lambda p: {"tool_name": "Edit", "tool_input": {"file_path": p}}
    blocked = [bash("git push origin main"), bash("git push -f origin agents/C-1"),
               bash("git push upstream agents/C-1"), bash("gh pr create --base main"),
               bash("gh pr create -R storytold/x --base main"), bash("gh pr merge 1"),
               bash("git branch -D main"), bash("rm -rf target"),
               edit("/repo/Cargo.toml"), edit("/repo/.agents/briefs/C-1.md"), edit("/elsewhere/a.rs")]
    allowed = [bash("git push -u origin agents/C-1"), bash("cargo test -p x-fonts"),
               bash("gh pr create -R zokito/x --base main --head agents/C-1"),
               edit("/repo/crates/fonts/src/stroke.rs"), edit("/repo/apps/x-cli/tests/cli.rs")]
    bad = [e for e in blocked if check(e, env) is None] + [e for e in allowed if check(e, env)]
    os.remove(ws)
    for e in bad:
        print("selftest FAIL", json.dumps(e), check(e, env))
    print(f"selftest {'ok' if not bad else 'FAILED'}: {len(blocked)} blocked, {len(allowed)} allowed")
    return 1 if bad else 0


if __name__ == "__main__":
    if sys.argv[1:] == ["--selftest"]:
        sys.exit(selftest())
    reason = check(json.load(sys.stdin), os.environ)
    if reason:
        print(f"craft guard: {reason}", file=sys.stderr)
        sys.exit(2)
    sys.exit(0)
