## 修复任务: TASK-1
### 上下文
先读 _ctx/ 下所有文件。

### 问题
[P0] Reviewer 管道完全失效 — 12 轮全部得 0.0 分

根因：`run_reviewers()` 中的评审请求文件是 3 个 Reviewer 共用的，里面写的是
`把 JSON 写入文件 ${SCORES_DIR}/你的角色名.json`，但 Reviewer Agent 不知道自己叫什么名字
（reviewer-a / reviewer-b / reviewer-c），导致无法写出正确文件名。
脚本等待的是 `reviewer-a.json` 等具体文件，等不到就走降级提取，提取也失败就写 `score:0`。

修复方案：为每个 Reviewer 生成**独立的**评审请求文件，明确写出输出路径如
`${SCORES_DIR}/reviewer-a.json`，而不是共用一个含歧义的请求文件。

### 相关文件
- scripts/hyper-loop.sh (行 428-510, run_reviewers 函数)

### 约束
- 只修 `run_reviewers()` 函数
- 保持 3 个 Reviewer 并行启动的结构不变
- 不改 CSS
- 不改其他函数

### 验收标准
- 每个 Reviewer 收到的请求中包含其**精确的**输出文件路径（如 `${SCORES_DIR}/reviewer-a.json`）
- `bash -n scripts/hyper-loop.sh` 语法通过
- 引用 BDD 场景 S008（3 Reviewer 启动并产出评分）、S009（和议计算正确）
