## 修复任务: TASK-1
### 上下文
先读 _ctx/ 下所有文件。

### 问题
[P1] `auto_decompose` 函数中引用了错误路径：line 719 的 `_hyper-loop/bdd-specs.md` 和 line 720 的 `_hyper-loop/contract.md`，正确路径应为 `_hyper-loop/context/bdd-specs.md` 和 `_hyper-loop/context/contract.md`。这导致 Claude 拆解任务时读不到 BDD spec 和 contract，是 18 轮连续 REJECTED_VETO 的根因之一。

### 相关文件
- scripts/hyper-loop.sh (line 715-756, auto_decompose 函数内的 DECOMPOSE_PROMPT heredoc)

### 约束
- 只修 scripts/hyper-loop.sh
- 只改 auto_decompose 函数中 heredoc 内的两个路径引用
- 不改其他函数

### 验收标准
引用 BDD 场景 S002: auto_decompose 生成任务文件
- `_hyper-loop/context/bdd-specs.md` 和 `_hyper-loop/context/contract.md` 路径正确
- bash -n scripts/hyper-loop.sh 通过
