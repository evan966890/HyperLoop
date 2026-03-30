## 修复任务: TASK-5
### 上下文
先读 _ctx/ 下所有文件。
### 问题
[P1] **cmd_loop 中 grep verdict.env 无 `|| true` 防护，set -e 下可能崩溃**

在 `cmd_loop` 函数 (line ~897-898) 中：
```bash
DECISION=$(grep '^DECISION=' "${TASK_DIR}/verdict.env" | cut -d= -f2)
MEDIAN=$(grep '^MEDIAN=' "${TASK_DIR}/verdict.env" | cut -d= -f2)
```

在 `set -euo pipefail` 模式下，如果 `verdict.env` 异常缺少 `DECISION=` 行，`grep` 返回 exit 1 会导致整个脚本崩溃。需要加 `|| true` 或使用默认值防护。

### 相关文件
- scripts/hyper-loop.sh (cmd_loop 函数，line ~897-898 的 grep verdict.env)
### 约束
- 只修 scripts/hyper-loop.sh
- 为这两行 grep 加防护，建议模式：
  ```bash
  DECISION=$(grep '^DECISION=' "${TASK_DIR}/verdict.env" 2>/dev/null | cut -d= -f2 || echo "REJECTED")
  MEDIAN=$(grep '^MEDIAN=' "${TASK_DIR}/verdict.env" 2>/dev/null | cut -d= -f2 || echo "0.0")
  ```
- 提供合理的默认值（DECISION=REJECTED, MEDIAN=0.0），避免空值引发后续 `unset variable` 错误
- 不改其他函数
### 验收标准
- 当 verdict.env 缺少 DECISION 行时脚本不崩溃
- `bash -n scripts/hyper-loop.sh` PASS
- 引用 BDD 场景 S012（verdict.env 安全读取 — 不会出现 command not found 错误）
