# Round 10 — Tester Report

**syntax check**: `bash -n scripts/hyper-loop.sh` PASS (no errors)

---

## BDD Scenario Results

| ID | Result | Reason |
|----|--------|--------|
| S001 | PASS | `cmd_loop` (L801) accepts max_rounds, outputs "LOOP: Round N/M", loops until max then exits, `record_result` appends results.tsv each round |
| S002 | PASS | `auto_decompose` (L682) creates TASK_DIR, uses claude -p to generate task*.md; L743 fallback generates default task1.md if count=0 |
| S003 | PASS | `start_writers` (L101) creates worktree (L124), writes ~/.codex/config.toml trust (L130-133), starts codex in tmux (L179-182), copies _ctx/ (L136) |
| S004 | **FAIL** | `merge_writers` L338 `git add -A` commits DONE.json/TASK.md into writer branch; second+ writer squash merge conflicts on these files (P0-1) |
| S005 | PASS | `audit_writer_diff` (L242) detects out-of-scope files, returns non-zero (L292), merge_writers L327-330 skips that writer |
| S006 | PASS | `wait_writers` (L196) defaults to 900s=15min (L198), writes `{"status":"timeout"}` (L224), writer skipped by merge_writers |
| S007 | PASS | `run_tester` (L379) uses `claude -p` pipe mode, timeout 600s within 15min, empty output generates fallback report (L412). Note: BDD says tmux, code uses pipe — functionally equivalent |
| S008 | PASS | `run_reviewers` (L417) runs 3 parallel subshells (L454-471), timeout 300s within 10min, generates reviewer-{a,b,c}.json with "score" field, fallback score 5 (L479). Note: pipe mode not tmux; no pane extraction, uses fallback instead |
| S009 | PASS | `compute_verdict` (L486) Python correctly computes median (L519), ACCEPTED when median > prev_median (L538), verdict.env format safe (L550-556) |
| S010 | PASS | L523 `any(s < 4.0 for s in scores)` detects veto, L531 returns REJECTED_VETO |
| S011 | PASS | L525-529 checks report for "P0" + ("bug"/"fail"), L533 returns REJECTED_TESTER_P0 |
| S012 | PASS | All verdict.env reads use grep+cut (L597, L651, L875), never source, no "command not found" errors |
| S013 | PASS | L900 detects 5 consecutive rejects, L904 reads archive git-sha.txt, L906 checkout rollback, L909 resets counter |
| S014 | PASS | L830-833 checks STOP file at loop top, deletes it, breaks — clean exit |
| S015 | PASS | `cleanup_round` (L563) removes worktrees (L577), deletes branches (L578), rm -rf parent dir (L584), kills tmux windows (L569-571) |
| S016 | PASS | L17-21 checks gtimeout first, falls back to custom timeout function — no command not found |
| S017 | **FAIL** | Conflict handling logic correct (L352-354 merge --abort + deferred), but P0-1 bug causes ALL 2nd+ writers to always conflict on metadata files |

**Score: 15/17 PASS, 2 FAIL** (both caused by same P0-1 root cause)

---

## P0 Bugs

### P0-1: HyperLoop metadata files cause mandatory merge conflicts for 2nd+ writers

**Location**: `merge_writers()` L338 `git add -A` + L348 `git merge --squash`

**Problem**: `start_writers` copies TASK.md (L137) and generates WRITER_INIT.md (L140) into each worktree. Writers create DONE.json. `git add -A` (L338) commits ALL these files into the writer branch. After the first writer is squash-merged into the integration branch, subsequent writers' squash merges conflict on DONE.json and TASK.md (different content per writer), entering the `else` branch (L352) and marked "conflict, deferred".

**Impact**: **Only 1 writer's changes merge per round.** The other 3-4 writers' work is completely wasted. This is the core efficiency bottleneck of the loop.

**Reproduction**: Any round with >= 2 writers triggers this deterministically.

**Fix**: Remove metadata files before committing writer changes:
```bash
# Before git add -A (insert at L337)
rm -f "${WT}/DONE.json" "${WT}/WRITER_INIT.md" "${WT}/TASK.md"
rm -rf "${WT}/_ctx"
git -C "$WT" add -A 2>/dev/null
```

---

## P1 Bugs

### P1-1: archive_round copies bdd-specs.md from wrong path

**Location**: L773 `cp "${PROJECT_ROOT}/_hyper-loop/bdd-specs.md"`

**Problem**: File is at `_hyper-loop/context/bdd-specs.md`. The `|| true` silently fails; archives never contain BDD specs.

### P1-2: cmd_status defined twice

**Location**: L673-679 (first) and L935-947 (second)

**Problem**: Second definition overwrites first. L673-679 is dead code.

### P1-3: PREV_MEDIAN empty string causes Python crash

**Location**: L625, L850 `PREV_MEDIAN=$(tail -1 ... | cut -f2 || echo 0)`

**Problem**: If results.tsv exists but is empty, tail+cut return empty string (exit 0), so `|| echo 0` never fires. Empty string passed to Python `float("")` throws ValueError; under `set -e` the script exits.

**Fix**: Add default: `PREV_MEDIAN="${PREV_MEDIAN:-0}"`

### P1-4: Build failure path skips archive_round

**Location**: `cmd_loop` L858-866

**Problem**: On build failure, only record_result + cleanup_round are called — archive_round is skipped. Round data (git-sha, scores) is lost, and S013 rollback mechanism lacks that round's git-sha.txt.
