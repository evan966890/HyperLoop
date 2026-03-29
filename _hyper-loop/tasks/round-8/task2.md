## 修复任务: TASK-2
### 上下文
先读 _hyper-loop/context/ 下所有文件，确认 bdd-specs.md 和 contract.md 的实际位置。
### 问题
[P1] auto_decompose 和 archive_round 中 bdd-specs.md / contract.md 路径缺少 `context/` 前缀。

具体：
- `scripts/hyper-loop.sh:716` 引用 `${PROJECT_ROOT}/_hyper-loop/bdd-specs.md`，实际在 `_hyper-loop/context/bdd-specs.md`
- `scripts/hyper-loop.sh:717` 引用 `${PROJECT_ROOT}/_hyper-loop/contract.md`，实际在 `_hyper-loop/context/contract.md`
- `scripts/hyper-loop.sh:794` 引用 `${PROJECT_ROOT}/_hyper-loop/bdd-specs.md`，同样缺少 `context/`

注意：顶层 `_hyper-loop/bdd-specs.md` 和 `_hyper-loop/contract.md` 也存在（可能是旧副本），但 context/ 下的版本是权威来源，auto_decompose 的提示词应指向 context/ 版本以保持一致。

### 相关文件
- scripts/hyper-loop.sh (行 716-718, auto_decompose 函数的提示词)
- scripts/hyper-loop.sh (行 794, archive_round 函数的 cp 命令)

### 约束
- 只修改 scripts/hyper-loop.sh
- 只改路径字符串，不改逻辑
- 不改 CSS

### 验收标准
- S002: auto_decompose 生成任务文件时能正确读取 BDD spec 和 contract，提升拆解质量
