## 修复任务: TASK-4
### 上下文
先读 _ctx/ 下所有文件。
### 问题
[P1] archive_round 引用的 bdd-specs.md 路径可能过时

archive_round 函数 line 770 使用 `cp "${PROJECT_ROOT}/_hyper-loop/bdd-specs.md"`，但 `_hyper-loop/context/` 才是标准位置，根目录副本可能与 context/ 下的版本不同步导致归档的 BDD 规格过时。

### 相关文件
- scripts/hyper-loop.sh (line 770, archive_round 函数)

### 约束
- 只修 scripts/hyper-loop.sh 中 archive_round 函数的这一行路径
- 不改 CSS

### 验收标准
- archive_round 归档的 bdd-specs.md 来自 `${PROJECT_ROOT}/_hyper-loop/context/bdd-specs.md`
- 如果 context/ 下不存在则回退到根目录版本（保持 `|| true` 容错）
- 引用 BDD 场景 S001（脚本不崩溃）
