# Round 9 — Tester Report

Tested: `scripts/hyper-loop.sh` (966 lines)
Syntax: `bash -n` PASS
Date: 2026-03-30

## BDD Scenario Results

| ID | Result | Reason |
|----|--------|--------|
| S001 | PASS | `cmd_loop` accepts MAX_ROUNDS (default 999), loops via `while [[ "$ROUND" -le "$MAX_ROUNDS" ]]`, `record_result` appends to results.tsv each round |
| S002 | PASS | `auto_decompose` (line 682) uses `claude -p -` pipe mode, generates tasks to `$TASK_DIR`, fallback at line 743 creates default task1.md if claude fails |
| S003 | PASS | `start_writers` (line 101) creates worktree via `git worktree add`, adds trust to `~/.codex/config.toml`, copies `_ctx/`, starts codex in tmux window |
| S004 | PASS | `merge_writers` (line 299) does `git add -A && git commit` in worktree (line 338-339), squash merge to integration branch (line 348), generates .patch/.stat files. All echo to stderr, only integration path to stdout |
| S005 | PASS | `audit_writer_diff` (line 242) extracts allowed files from TASK.md "### 相关文件", compares with `git diff --name-only`, allows DONE.json/WRITER_INIT.md/_ctx/*/TASK.md, returns 1 on violations |
| S006 | PASS | `wait_writers` (line 196) default timeout 900s (15 min), writes `{"status":"timeout"}` to DONE.json on expiry (line 224), merge_writers skips non-done status |
| S007 | PASS | `run_tester` (line 379) uses `timeout 600 claude -p -`, generates default empty report on failure (line 411-413), no crash path |
| S008 | PASS | `run_reviewers` (line 417) runs 3 reviewers in parallel `(...)&` (gemini + claude + codex), `EXTRACT_PY` extracts JSON, fallback score=5 on missing/empty files (line 477-482) |
| S009 | PASS | `compute_verdict` Python (line 512-557): median calculation correct, ACCEPTED when median > prev_median, verdict.env written with safe format, read back via grep+cut (no source) |
| S010 | PASS | Python line 523: `veto = any(s < 4.0 for s in scores)`, line 531: yields REJECTED_VETO, recorded to results.tsv |
| S011 | PASS | Python lines 525-529: checks `"P0" in text and ("bug" in text.lower() or "fail" in text.lower())`, line 533: yields REJECTED_TESTER_P0 |
| S012 | PASS | verdict.env read via `grep '^DECISION=' \| cut -d= -f2` at lines 597, 651, 875 — never sourced, immune to "command not found" errors |
| S013 | PASS | Line 900: triggers when `CONSECUTIVE_REJECTS >= 5 && BEST_ROUND > 0`, reads git-sha.txt from archive, checkouts, resets counter to 0 |
| S014 | PASS | Line 830-834: checks `$STOP_FILE` at loop top before any work, deletes file, `break` exits loop normally (exit 0) |
| S015 | PASS | `cleanup_round` (line 563): removes worktrees + branches in subshell with `set +e`, kills tmux windows, `rm -rf "${WORKTREE_BASE}"` removes parent dir |
| S016 | PASS | Lines 17-21: prefers `gtimeout`, falls back to custom bash `timeout()` if neither exists. All script timeout calls use plain integer seconds |
| S017 | PASS | Line 348-356: first writer squash-merges OK, conflicting writer triggers `merge --abort` + "deferred" log, `((FAILED++)) || true` prevents set -e crash |

**Overall: 17/17 PASS**

---

## Bugs Found

### P1-1: `build_app` changes global cwd (line 367)

`cd "$BUILD_DIR"` changes the shell's working directory to the integration worktree. After `cleanup_round` removes that worktree, the process cwd becomes a deleted directory. All subsequent code uses absolute paths so it works today, but any future relative path usage would fail silently.

**Fix:** `(cd "$BUILD_DIR" && eval ...)` in subshell, or `pushd/popd`.

### P1-2: `PREV_MEDIAN` empty string crashes `compute_verdict` (lines 624, 849)

If results.tsv exists but is empty (0 bytes), `tail -1 | cut -f2` returns "" with exit 0 (`|| echo 0` never fires). Python `float("")` raises ValueError, crashing the script under `set -e`.

**Fix:** Add `PREV_MEDIAN=${PREV_MEDIAN:-0}` after the assignment, or check `-s` instead of `-f`.

### P1-3: `archive_round` wrong path for bdd-specs.md (line 773)

```bash
cp "${PROJECT_ROOT}/_hyper-loop/bdd-specs.md" "$ARCHIVE/"   # WRONG
```

Should be `${PROJECT_ROOT}/_hyper-loop/context/bdd-specs.md`. All other references in the script use `context/bdd-specs.md`. This copy silently fails every round (`|| true` suppresses).

### P1-4: `cmd_status` defined twice (lines 673 and 935)

First definition (line 673-679) is dead code overwritten by the second (line 935-947). Remove line 673-679.
