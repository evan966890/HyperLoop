## 修复任务: TASK-4
### 上下文
先读 _ctx/ 下所有文件。

### 问题
[P1] 两个独立的代码质量问题：

1. **cmd_status 函数重复定义**（line ~697 和 ~957）：第一个简单版本是死代码，被第二个（更完整、含"最佳轮次"显示）覆盖。应删除第一个。

2. **Tester 超时消息不一致**（line ~421）：消息说"Tester 未在 10 分钟内完成"但实际超时是 900s = 15 分钟（line ~407）。应改为 15 分钟。

### 相关文件
- scripts/hyper-loop.sh（line 697-703: 第一个 cmd_status 定义需删除；line 421: 超时消息需修正）

### 修复方案
1. 删除约 line 697-703 的第一个 `cmd_status` 函数：
   ```bash
   # 删除这段：
   cmd_status() {
     echo "tmux windows:"
     tmux list-windows -t hyper-loop 2>/dev/null || echo "  (no session)"
     echo ""
     echo "results.tsv:"
     cat "${PROJECT_ROOT:-.}/_hyper-loop/results.tsv" 2>/dev/null || echo "  (empty)"
   }
   ```

2. 将 line ~421 的超时消息从：
   ```
   echo "Tester 未在 10 分钟内完成。需要人工验证。" >> "$REPORT_FILE"
   ```
   改为：
   ```
   echo "Tester 未在 15 分钟内完成。需要人工验证。" >> "$REPORT_FILE"
   ```

### 约束
- 只修 scripts/hyper-loop.sh 中上述两处
- 不改其他函数逻辑

### 验收标准
引用 BDD 场景 S007（Tester 超时消息应与实际超时匹配）和 S001（代码无死代码重复定义）
