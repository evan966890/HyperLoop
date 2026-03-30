## 修复任务: TASK-1
### 上下文
先读 _ctx/ 下所有文件。

### 问题
[P0] Reviewer 评审请求不含具体输出文件路径 — 13 轮全部 0.0 分的根因

`run_reviewers()` 生成一个共用 `REVIEW_REQ` 文件，指示 Reviewer "把 JSON 写入文件 ${SCORES_DIR}/你的角色名.json"。
但 Reviewer Agent 不知道自己叫 reviewer-a / reviewer-b / reviewer-c，所以无法写入正确路径。
→ 等待超时 → 降级提取也失败 → 全部 score=0 → REJECTED_VETO → 循环永远无法成功。

这是 13 轮连续 REJECTED_VETO 的唯一根因。

### 修复方案
将 `run_reviewers()` 改为：为每个 Reviewer 生成独立的评审请求文件，用确切路径替换"你的角色名"。

具体：
1. 将生成 `REVIEW_REQ` 的代码块移到 `for ENTRY in "${REVIEWERS[@]}"` 循环内部
2. 每个 Reviewer 使用独立的文件 `/tmp/hyper-loop-review-${NAME}-r${ROUND}.md`
3. 将 `"把 JSON 写入文件 ${SCORES_DIR}/你的角色名.json"` 改为 `"把 JSON 写入文件 ${SCORES_DIR}/${NAME}.json"`
4. `tmux load-buffer` 加载的是该 Reviewer 独立的评审请求文件

### 相关文件
- scripts/hyper-loop.sh (run_reviewers 函数，约 line 440-510)

### 约束
- 只修 scripts/hyper-loop.sh 中的 `run_reviewers()` 函数
- 不改其他函数
- 不改 CSS
- 评审请求的其他内容（契约路径、BDD 路径、diff stat 等）保持不变
- 三个 Reviewer 的 CLI 和启动逻辑不变

### 验收标准
- S008: 3 个 Reviewer 启动后各自收到的评审请求文件包含 **确切** 的输出路径（`reviewer-a.json`、`reviewer-b.json`、`reviewer-c.json`），而非"你的角色名.json"
- `bash -n scripts/hyper-loop.sh` 通过
