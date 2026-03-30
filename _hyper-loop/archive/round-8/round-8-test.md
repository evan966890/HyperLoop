# Round 8 — Tester 报告

测试时间: 2026-03-30
测试方法: bash -n 语法检查 + 逐场景代码审查
语法检查: **PASS** (bash -n 无错误)

---

## BDD 场景逐条验证

| 场景 | 结果 | 说明 |
|------|------|------|
| S001 | **PASS** | `cmd_loop` (L801) 接收 MAX_ROUNDS 参数，输出 "Round N/M"，循环跑满后正常退出，record_result 写 results.tsv |
| S002 | **PASS** | `auto_decompose` (L682) 用 `claude -p` 拆解任务，路径 `${PROJECT_ROOT}/_hyper-loop/context/bdd-specs.md` 正确，fallback 在 L743-764 生成默认 task1.md |
| S003 | **PASS** | `start_writers` (L101) 创建 `/tmp/hyper-loop-worktrees-rN/taskM`，L130 写 `~/.codex/config.toml` trust，L179 在 tmux window 启动 Codex，L136 复制 `_ctx/` |
| S004 | **PASS** | `merge_writers` (L299) 先 `git add -A && git commit` (L338-339)，squash merge 到 integration 分支 (L348)，生成 .patch/.stat (L342-345)，状态输出到 stderr 不污染 stdout 返回值 |
| S005 | **PASS** | `audit_writer_diff` (L242) 检查越界文件，违规返回 `return 1`，merge_writers (L327-330) 跳过审计失败的 Writer |
| S006 | **PASS** | `wait_writers` (L196) 默认超时 900s (15分钟)，超时写 `{"status":"timeout"}` (L224)，merge_writers 检查 status!=done 跳过 (L320) |
| S007 | **PASS** | `run_tester` (L379) 用 `timeout 600 claude -p` 非交互模式运行，10分钟内生成报告，L408-413 空输出时生成默认报告 |
| S008 | **PASS** | `run_reviewers` (L417) 并行启动 3 个 Reviewer（gemini/claude/codex），timeout 300s，EXTRACT_PY 提取 JSON 中的 score 字段，L477-482 fallback 给分 5 |
| S009 | **PASS** | `compute_verdict` (L486) Python 脚本排序后取中位数 (L519)，3 个评分 [5,6,7] → median=6.0，median > prev_median → ACCEPTED，verdict.env 用 key=value 格式 |
| S010 | **PASS** | L523 `veto = any(s < 4.0 for s in scores)`，scores=[3.5,6,7] → veto=True → REJECTED_VETO (L531-532)，record_result 写入 results.tsv |
| S011 | **PASS** | L526-529 检查报告中 "P0" + ("bug"/"fail")，匹配时 REJECTED_TESTER_P0 (L533-534) |
| S012 | **PASS** | record_result (L589) 用 `grep + cut` 安全读取，cmd_round (L651) 和 cmd_loop (L875) 同样用 grep 提取，不 source verdict.env，无 "command not found" 风险 |
| S013 | **PASS** | L900 检查 `consecutive_rejects >= 5 && BEST_ROUND > 0`，从 archive git-sha.txt 恢复代码 (L904-907)，重置 counter=0 (L909) |
| S014 | **PASS** | L830 循环顶部检查 STOP 文件，break 后正常退出 (exit 0)，L832 删除 STOP 文件 |
| S015 | **PASS** | `cleanup_round` (L562) 用 subshell+set +e 容错，L577 删除 worktree，L578 删除分支，L584 `rm -rf ${WORKTREE_BASE}` 删除父目录，L569 关闭 tmux windows |
| S016 | **PASS** | L17-21 依次检查 gtimeout → timeout → 纯 bash fallback (background+sleep+kill)，macOS 兼容 |
| S017 | **PASS** | merge_writers L348 squash merge 失败时 L352-354 执行 merge --abort 并标记 conflict deferred，`((FAILED++)) || true` 不崩溃 |

---

## 发现的 Bug

### P1: archive_round 归档 bdd-specs.md 路径错误 (L773)

```bash
cp "${PROJECT_ROOT}/_hyper-loop/bdd-specs.md" "$ARCHIVE/" 2>/dev/null || true
```

实际路径是 `${PROJECT_ROOT}/_hyper-loop/context/bdd-specs.md`。由于 `|| true` 静默失败，BDD 规格永远不会被归档。

**修复**: 改为 `cp "${PROJECT_ROOT}/_hyper-loop/context/bdd-specs.md" "$ARCHIVE/" 2>/dev/null || true`

### P1: build_app 改变 cwd 未恢复 (L367)

```bash
build_app() {
  local BUILD_DIR="$1"
  cd "$BUILD_DIR"   # ← 改变了 shell 工作目录，函数返回后不恢复
```

后续函数都用绝对路径所以目前不会出错，但这是一个隐患。

**修复**: 用 `(cd "$BUILD_DIR" && eval ...)` subshell 或末尾 `cd "$PROJECT_ROOT"`

### P1: git worktree add 静默失败 (L124)

```bash
git -C "$PROJECT_ROOT" worktree add "$WT" -b "$BRANCH" 2>/dev/null
```

如果前一轮崩溃导致残留分支/worktree，此命令静默失败，Writer 无法启动但不报错。

**修复**: 在 `start_writers` 开头加 `git -C "$PROJECT_ROOT" worktree prune` 并删除同名残留分支

### P1: cmd_status 重复定义 (L673 + L935)

两处定义 `cmd_status()`，第一个 (L673) 是死代码，第二个覆盖它。不影响功能但增加维护混乱。

**修复**: 删除 L673-679 的第一个定义

### P1: 注释与代码不一致 (L476)

注释写 "fallback 给 3 分"，实际 fallback 给 5 分 (L479)。

**修复**: 将注释改为 "fallback 给 5 分"

---

## 总结

- **17 个 BDD 场景全部 PASS**
- **0 个 P0 bug**
- **5 个 P1 bug**（归档路径错误、cwd 泄漏、worktree 残留静默失败、重复函数定义、注释不一致）
