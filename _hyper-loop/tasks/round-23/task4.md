## 修复任务: TASK-4
### 上下文
先读 _ctx/ 下所有文件。
### 问题
[P1] 两个独立 bug：

**Bug A — S013 回退逻辑失效**（行 907-909, 922）：
`BEST_ROUND` 和 `BEST_MEDIAN` 仅在 ACCEPTED 分支内更新。若所有轮次均 REJECTED，`BEST_ROUND` 始终为 0，回退条件 `[[ "$BEST_ROUND" -gt 0 ]]` 永不满足。

BDD S013 要求：回退到得分最高的轮次（不限 ACCEPTED/REJECTED）。

修复方案：在 REJECTED 分支中也追踪最佳中位数。在 else 分支（行 912-913 附近）、以及 BUILD_FAILED 分支之前，当 MEDIAN > BEST_MEDIAN 时同样更新 BEST_ROUND 和 BEST_MEDIAN。

**Bug B — cmd_status 重复定义**（行 697 和行 957）：
两个 `cmd_status()` 函数，第二个覆盖第一个。第一个只输出 tmux windows 和 results.tsv；第二个额外输出最佳轮次信息。

修复方案：删除行 697 的第一个简陋版本，保留行 957 的完整版本。
### 相关文件
- scripts/hyper-loop.sh (行 697-705, 907-913, 957-971)
### 约束
- 只修改 scripts/hyper-loop.sh
- 回退追踪逻辑需同时覆盖 ACCEPTED 和 REJECTED 两个分支
- 不改 CSS
### 验收标准
- 引用 BDD 场景 S013（连续 5 轮失败自动回退）
- 全 REJECTED 场景下 BEST_ROUND 能被正确更新为得分最高的轮次
- `grep -c 'cmd_status()' scripts/hyper-loop.sh` 返回 1（只有一个定义）
- `bash -n scripts/hyper-loop.sh` 通过
