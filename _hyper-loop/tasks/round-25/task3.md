## 修复任务: TASK-3
### 上下文
先读 _ctx/ 下所有文件。
### 问题
[P1] auto_decompose 和 archive_round 中 bdd-specs.md / contract.md 路径缺少 `context/` 前缀

1. auto_decompose 的 decompose prompt（L719-720）引用：
   - `${PROJECT_ROOT}/_hyper-loop/bdd-specs.md`
   - `${PROJECT_ROOT}/_hyper-loop/contract.md`
   应为：
   - `${PROJECT_ROOT}/_hyper-loop/context/bdd-specs.md`
   - `${PROJECT_ROOT}/_hyper-loop/context/contract.md`

2. archive_round（L797）复制：
   - `${PROJECT_ROOT}/_hyper-loop/bdd-specs.md`
   应为：
   - `${PROJECT_ROOT}/_hyper-loop/context/bdd-specs.md`

其他位置（L75-76, L393, L438-439）已正确使用 `context/` 前缀。当前根级存在副本所以不崩溃，但路径不一致。

### 相关文件
- scripts/hyper-loop.sh (L719-720, L797)

### 约束
- 只修 scripts/hyper-loop.sh 中这 3 处路径
- 统一为 `_hyper-loop/context/bdd-specs.md` 和 `_hyper-loop/context/contract.md`
- 不改 CSS

### 验收标准
引用 BDD 场景 S002（auto_decompose 生成任务文件）：
- decompose prompt 中引用的 bdd-specs.md 和 contract.md 路径与 start_agent 中一致（都带 `context/`）
- archive_round 复制正确路径的文件
