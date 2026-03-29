## 修复任务: TASK-5
### 上下文
先读 _ctx/ 下所有文件。
### 问题
[P1-3] `auto_decompose` 路径不一致（第 716-717 行）

decompose prompt 中引用 `_hyper-loop/bdd-specs.md`（无 `context/` 前缀），而项目其他位置统一使用 `_hyper-loop/context/bdd-specs.md`。当前两个路径都存在文件所以不崩溃，但如果将来清理冗余文件会 break。

应统一为 `_hyper-loop/bdd-specs.md`（此为实际被 auto_decompose 和 contract 使用的路径）。检查是否有冗余副本需清理。

### 相关文件
- scripts/hyper-loop.sh (行 716-717)
- _hyper-loop/bdd-specs.md
- _hyper-loop/context/bdd-specs.md (如存在，为冗余副本)

### 约束
- 只修 scripts/hyper-loop.sh 中的路径引用
- 不删除任何文件（避免破坏其他引用）
- 确保 auto_decompose 中 BDD 和 contract 路径与实际文件位置一致

### 验收标准
引用 BDD 场景 S002: auto_decompose 生成的 prompt 中文件路径可被正确读取
- `grep 'bdd-specs\|contract' scripts/hyper-loop.sh` 中所有路径指向存在的文件
