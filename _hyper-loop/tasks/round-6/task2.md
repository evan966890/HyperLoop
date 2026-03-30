## 修复任务: TASK-2
### 上下文
先读 _ctx/ 下所有文件。
### 问题
[P1] Writer 超时默认值与 BDD 规格不符。BDD S006 要求 15 分钟 (900s)，但 `wait_writers` 默认超时为 300s (5min)。调用处 (L626, L851) 均未传超时参数，始终用默认值，导致 Writer 在复杂任务中被过早杀死。
### 相关文件
- scripts/hyper-loop.sh (L198, wait_writers 函数默认值)
  - L198: `local TIMEOUT="${2:-300}"` → 改为 `local TIMEOUT="${2:-900}"`
### 约束
- 只修改 scripts/hyper-loop.sh 中 L198 的默认超时值
- 不改 CSS
- 不改函数签名
### 验收标准
引用 BDD 场景 S006: Writer 15 分钟未写 DONE.json 时才触发超时，DONE.json 被写入 status=timeout
