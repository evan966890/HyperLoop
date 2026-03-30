## 修复任务: TASK-4
### 上下文
先读 _ctx/ 下所有文件。
### 问题
[P1] Tester 超时消息不一致。Line 404 等待日志说"最多 15 分钟"，但 Line 421 空报告消息说"Tester 未在 10 分钟内完成"。实际超时阈值为 900s = 15 分钟。

### 相关文件
- scripts/hyper-loop.sh (Line 421: 超时消息中的 "10 分钟" 应改为 "15 分钟")

### 约束
- 只修改 Line 421 的字符串 "10 分钟" → "15 分钟"
- 不改动超时逻辑（900s）本身
- 不改动其他任何代码

### 验收标准
- grep "10 分钟" scripts/hyper-loop.sh 无匹配
- grep "15 分钟" scripts/hyper-loop.sh 至少匹配 2 处（等待消息 + 超时消息）
- `bash -n scripts/hyper-loop.sh` PASS
- 引用 BDD 场景 S007（Tester 启动并生成报告，超时时生成空报告而非崩溃）
