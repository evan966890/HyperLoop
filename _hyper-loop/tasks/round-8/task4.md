## 修复任务: TASK-4
### 上下文
先读 _ctx/ 下所有文件。
### 问题
[P1] cmd_status 函数重复定义 + Reviewer fallback 注释不一致

两处独立问题：

1. `cmd_status` 在 line 673-679 和 line 935-947 各定义一次，后者覆盖前者。line 673-679 是死代码，应删除以消除维护混淆。

2. line 476 注释写 "fallback 给 3 分"，但 line 479 实际 JSON 给 `"score":5`（中立分）。注释与代码不一致误导维护者。

### 相关文件
- scripts/hyper-loop.sh (line 673-679，第一个 cmd_status 定义)
- scripts/hyper-loop.sh (line 476，reviewer fallback 注释)

### 约束
- 只修 scripts/hyper-loop.sh
- 删除 line 673-679 的重复 cmd_status
- 修正 line 476 注释为 "fallback 给 5 分（中立分）"
- 不改 CSS

### 验收标准
引用 BDD 场景 S008: Reviewer fallback 逻辑正确，代码中无死代码、无误导注释
