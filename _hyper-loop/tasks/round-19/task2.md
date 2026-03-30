## 修复任务: TASK-2
### 上下文
先读 _ctx/ 下所有文件。

### 问题
[P2] `archive_round` 函数 line 797 引用了错误路径 `_hyper-loop/bdd-specs.md`，正确路径应为 `_hyper-loop/context/bdd-specs.md`。虽然因 `|| true` 不会崩溃，但归档缺少 bdd-specs.md 文件。

### 相关文件
- scripts/hyper-loop.sh (line 792-804, archive_round 函数)

### 约束
- 只修 scripts/hyper-loop.sh
- 只改 archive_round 函数中的路径引用
- 不改其他函数

### 验收标准
引用 BDD 场景 S002 (路径一致性)
- 归档时正确复制 `_hyper-loop/context/bdd-specs.md`
- bash -n scripts/hyper-loop.sh 通过
