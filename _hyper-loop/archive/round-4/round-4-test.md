# Round 4 Tester Report

构建验证: `bash -n scripts/hyper-loop.sh` — **PASS** (语法无错误)

## BDD 场景逐条检查

| 场景 | 结果 | 原因 |
|------|------|------|
| S001 | PASS | `cmd_loop` 接受轮次参数，输出 "Round N/M"，循环跑满后正常退出，每轮调用 `record_result` 写 results.tsv |
| S002 | PASS | `auto_decompose` 用 claude -p 非交互拆解，失败时降级生成 task1.md (line 740-759)，每个文件含"修复任务"和"相关文件"段落 |
| S003 | PASS | `start_writers` 创建 worktree (line 124)，写 config.toml trust (line 130-133)，复制 _ctx/ (line 136)，codex 在 tmux window 启动 (line 179-182) |
| S004 | **FAIL** | `merge_writers` 函数在 stdout 混合了状态输出 (echo "合并 Writer 产出...") 和返回值 (echo "$INTEGRATION_WT")。`INTEGRATION_WT=$(merge_writers "$ROUND")` 捕获全部 stdout（多行文本），导致 `build_app "$INTEGRATION_WT"` 中 `cd "$BUILD_DIR"` 必然失败。**P0 bug — 每轮都会因"构建失败"而被拒绝** |
| S005 | PASS | `audit_writer_diff` 提取允许文件列表，比对实际修改，越界时 return 1，caller 跳过合并 (line 327-330) |
| S006 | PASS | `wait_writers` 超时后写 `{"status":"timeout"}` 到 DONE.json (line 224)，status != "done" 在 merge 时被标记 failed (line 320-324) |
| S007 | PASS | `run_tester` 用 `claude -p` 管道模式运行，timeout 600s，无输出时生成空报告 (line 411-413)。注: BDD 说 "tmux 中启动" 但实现改为非交互管道模式，功能等价 |
| S008 | PASS | 3 个 Reviewer 并行后台运行 (gemini/claude/codex)，JSON 提取通过 python3，超时或无输出 fallback 给 5 分 (line 477-482)。注: BDD 说 "tmux 中启动" 但实现改为管道模式 |
| S009 | PASS | python3 正确计算中位数 (line 519)，median > prev_median 时 ACCEPTED (line 538)，verdict.env 用标准 key=value 格式写入 |
| S010 | PASS | `any(s < 4.0 for s in scores)` 触发 REJECTED_VETO (line 523,531-532)，通过 record_result 记录到 results.tsv |
| S011 | PASS | 检查 report 中 "P0" + ("bug"/"fail") 触发 REJECTED_TESTER_P0 (line 526-529,533-534) |
| S012 | PASS | `record_result` 和 `cmd_loop` 均用 `grep + cut` 安全读取 verdict.env (line 594-596, 872-873)，不 source，不会出现 "command not found" |
| S013 | PASS | `CONSECUTIVE_REJECTS >= 5` 且 `BEST_ROUND > 0` 时从 archive 读 git-sha 回退 (line 897-907)，重置 consecutive_rejects=0 |
| S014 | PASS | 检测 STOP 文件后 break 退出循环，删除 STOP 文件 (line 827-830)，脚本正常结束 |
| S015 | **FAIL** | `cleanup_round` 通过 `git worktree remove` 删除各子目录，但未删除父目录 `/tmp/hyper-loop-worktrees-rN/`（空目录残留）。BDD 要求该目录不存在。**P1 bug** |
| S016 | PASS | 脚本开头检测 gtimeout / timeout，缺失时自定义 fallback 函数 (line 17-21) |
| S017 | PASS | squash merge 冲突时执行 `merge --abort`，标记 deferred，脚本不崩溃 (line 353-355) |

**统计: 15 PASS / 2 FAIL**

## Bug 列表

### P0

**BUG-P0-1: `merge_writers` stdout 污染导致每轮构建必然失败**
- 位置: `scripts/hyper-loop.sh` line 309-361 + line 628-629 + line 853-854
- 问题: `merge_writers` 函数在 stdout 输出了状态信息 ("合并 Writer 产出...", "✓ taskN merged", "合并完成: ...") 和返回路径 (`echo "$INTEGRATION_WT"`)。调用方用 `INTEGRATION_WT=$(merge_writers "$ROUND")` 捕获 stdout，得到多行文本而非纯路径。后续 `build_app "$INTEGRATION_WT"` 中 `cd "$BUILD_DIR"` 因路径无效必然失败。
- 影响: 每一轮都会走 "构建失败" 分支，Tester/Reviewer 永远不会运行，所有轮次 DECISION=BUILD_FAILED
- 修复建议: 将 `merge_writers` 中的状态 echo 重定向到 stderr (`>&2`)，仅保留最后一行 `echo "$INTEGRATION_WT"` 输出到 stdout

### P1

**BUG-P1-1: worktree 父目录未清理**
- 位置: `cleanup_round` line 563-583
- 问题: 只删子目录 (task*, integration)，未 `rm -rf "$WORKTREE_BASE"` 删除父目录
- 影响: `/tmp/hyper-loop-worktrees-rN/` 空目录残留，S015 fail
- 修复: 在 cleanup_round 末尾加 `rm -rf "${WORKTREE_BASE}" 2>/dev/null`

**BUG-P1-2: `archive_round` bdd-specs 路径错误**
- 位置: line 770
- 问题: `cp "${PROJECT_ROOT}/_hyper-loop/bdd-specs.md"` — 实际文件在 `_hyper-loop/context/bdd-specs.md`
- 影响: 归档中缺少 BDD 规格文件 (cp 静默失败因 `|| true`)
- 修复: 改为 `${PROJECT_ROOT}/_hyper-loop/context/bdd-specs.md`

**BUG-P1-3: `auto_decompose` heredoc 变量转义错误**
- 位置: line 703-705
- 问题: `\$f` 在非引号 heredoc 的 `$(...)` 命令替换中被转义为字面量 `$f`，导致 for 循环变量不生效。上一轮评分内容不会出现在拆解 prompt 中
- 影响: Claude 拆解时看不到上一轮具体评分，降低任务拆解质量
- 修复: 将 `\$f` 改为 `$f`（heredoc 中 `$(...)` 内的 `$` 由子 shell 处理，不需要转义）

**BUG-P1-4: `cmd_status` 重复定义**
- 位置: line 670-676 和 line 932-943
- 问题: 函数定义了两次，第二个覆盖第一个。第一个定义是死代码
- 影响: 无功能影响但代码混乱
- 修复: 删除 line 670-676 的第一个定义
