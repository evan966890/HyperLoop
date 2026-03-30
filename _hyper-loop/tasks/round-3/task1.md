## 修复任务: TASK-1
### 上下文
先读 _ctx/ 下所有文件。
### 问题
[P0] auto_decompose 函数中 BDD 规格和评估契约的路径缺少 `context/` 子目录，导致 Claude 无法读取正确的 BDD 规格，任务拆解质量严重退化。

- L692: `${PROJECT_ROOT}/_hyper-loop/bdd-specs.md` 应为 `${PROJECT_ROOT}/_hyper-loop/context/bdd-specs.md`
- L693: `${PROJECT_ROOT}/_hyper-loop/contract.md` 应为 `${PROJECT_ROOT}/_hyper-loop/context/contract.md`

### 相关文件
- scripts/hyper-loop.sh (L688-694)

### 约束
- 只修改 scripts/hyper-loop.sh 中 auto_decompose 的 heredoc prompt 部分
- 不改动函数逻辑和其他代码
- 修改后 `bash -n scripts/hyper-loop.sh` 必须通过

### 验收标准
引用 BDD 场景 S002: auto_decompose 被调用时能正确引用 `_hyper-loop/context/bdd-specs.md` 和 `_hyper-loop/context/contract.md`
