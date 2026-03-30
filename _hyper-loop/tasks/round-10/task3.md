## 修复任务: TASK-3
### 上下文
先读 _ctx/ 下所有文件。

### 问题
[P1-003] cmd_loop 中 verdict.env 读取行缩进不一致

第 897-898 行的 DECISION 和 MEDIAN grep 赋值缩进为 2 空格，但所在代码块（while > if/else 内部）
的上下文缩进为 6 空格。功能不受影响但可读性差，增加维护风险。

```
      # 安全读取 verdict.env（不 source，用 grep 提取）
  DECISION=$(grep '^DECISION=' ...   ← 2 空格（应为 6 空格）
  MEDIAN=$(grep '^MEDIAN=' ...       ← 2 空格（应为 6 空格）

      if [[ "$DECISION" == ...       ← 6 空格（正确）
```

### 相关文件
- scripts/hyper-loop.sh (第 897-898 行)

### 约束
- 只改 scripts/hyper-loop.sh 第 897-898 行的前导空格
- 将 2 空格缩进改为 6 空格，与上下文（第 896 行注释、第 900 行 if）对齐
- 不改代码逻辑、不改 CSS

### 验收标准
- 第 897-898 行缩进与第 896 行和第 900 行一致（6 空格）
- `bash -n scripts/hyper-loop.sh` 语法检查通过
- 引用 BDD 场景 S012: verdict.env 安全读取行为不变
