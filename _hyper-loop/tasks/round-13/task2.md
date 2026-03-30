## 修复任务: TASK-2
### 上下文
先读 _ctx/ 下所有文件。

### 问题
[P0] Reviewer CLI 可用性未检查 — gemini/codex 可能未安装

`run_reviewers()` 硬编码了 3 个 CLI：
```
"reviewer-a:gemini --yolo"
"reviewer-b:claude --dangerously-skip-permissions"
"reviewer-c:codex --full-auto"
```
如果 `gemini` 或 `codex` 未安装，tmux 窗口启动后直接报错退出，
Agent 无法运行，评分文件不会生成，降级提取也失败。

修复方案：在 `run_reviewers()` 开始时检查每个 CLI 是否可用，
不可用的 Reviewer 降级使用 `claude --dangerously-skip-permissions`。
确保至少有 1 个 CLI 可用，否则报错退出。

### 相关文件
- scripts/hyper-loop.sh (行 453-466, REVIEWERS 数组及启动循环)

### 约束
- 只修 `run_reviewers()` 函数中 REVIEWERS 数组的构建逻辑
- 保持 3 个 Reviewer 的结构（不减少为 1 个）
- 不改 CSS
- 不改其他函数

### 验收标准
- 当 `gemini` 不存在时，reviewer-a 降级使用 `claude --dangerously-skip-permissions`
- 当 `codex` 不存在时，reviewer-c 降级使用 `claude --dangerously-skip-permissions`
- 至少 1 个 CLI 可用时脚本不崩溃
- `bash -n scripts/hyper-loop.sh` 语法通过
- 引用 BDD 场景 S008（3 Reviewer 启动并产出评分）
