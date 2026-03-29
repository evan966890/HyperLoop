## 修复任务: TASK-4
### 上下文
先读 _ctx/ 下所有文件。

### 问题
[P1] Reviewer 降级提取逻辑（第 478-500 行）不够健壮，是导致 Round 1 全 0.0 分的可能原因之一。

三个具体问题：
1. `tmux capture-pane -t "hyper-loop:${NAME}" -p -S -` — 如果 Reviewer 窗口已因超时被关闭或崩溃，
   pane 不存在，`capture-pane` 失败，`|| true` 吞掉错误，生成空文件，导致 score=0。
   应在 capture 前检查窗口是否存在。

2. `-S -` 只捕获从窗口创建到当前的可见输出，如果输出超过 tmux scrollback buffer（默认 2000 行），
   早期的 JSON 可能已被丢失。应使用 `-S -5000` 确保足够的回滚。

3. 当所有 3 个 reviewer 都失败时，全部降级为 `{"score":0}`，
   触发 `REJECTED_VETO`（score < 4.0），循环永远无法进步。
   应在全部降级时记录显眼的警告日志，帮助诊断。

### 相关文件
- scripts/hyper-loop.sh (第 478-500 行, `run_reviewers` 降级提取)

### 约束
- 只修 `run_reviewers` 函数中的降级提取部分（第 478-500 行）
- 不改 Reviewer 启动逻辑（第 450-463 行）
- 不改 CSS

### 验收标准
- S008: 降级提取更健壮，在窗口不存在时不产生空文件
- S008: capture-pane 使用更大的 scrollback 范围
- 全部降级时输出 WARNING 级别日志
