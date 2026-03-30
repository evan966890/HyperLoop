## 修复任务: TASK-2
### 上下文
先读 _ctx/ 下所有文件。
### 问题
[P0] auto_decompose() 引用错误的文件路径导致 S002 FAIL

`auto_decompose()` 函数（约第 719-720 行）的分解 prompt 中引用了：
- `${PROJECT_ROOT}/_hyper-loop/bdd-specs.md`
- `${PROJECT_ROOT}/_hyper-loop/contract.md`

但这两个文件的实际路径是：
- `${PROJECT_ROOT}/_hyper-loop/context/bdd-specs.md`
- `${PROJECT_ROOT}/_hyper-loop/context/contract.md`

这导致 Claude 在拆解任务时无法读取 BDD 规格和评估契约，生成的任务质量低下。这是连续 14 轮全部 0 分 REJECTED_VETO 的根因。

### 相关文件
- scripts/hyper-loop.sh (auto_decompose 函数, 约第 710-760 行)

### 约束
- 只修改 scripts/hyper-loop.sh 中 auto_decompose() 函数内的路径引用
- 将 `_hyper-loop/bdd-specs.md` 改为 `_hyper-loop/context/bdd-specs.md`
- 将 `_hyper-loop/contract.md` 改为 `_hyper-loop/context/contract.md`
- 不改动函数逻辑，只改路径字符串

### 验收标准
引用 BDD 场景 S002: auto_decompose 被调用时能正确读取 bdd-specs.md 和 contract.md，生成的 task*.md 文件包含"修复任务"和"相关文件"段落
