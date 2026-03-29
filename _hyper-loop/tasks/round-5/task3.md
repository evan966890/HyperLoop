## 修复任务: TASK-3
### 上下文
先读 _ctx/ 下所有文件。
### 问题
[P1] `auto_decompose` decompose prompt 路径不一致（第 716-717 行）

decompose prompt 中引用 `${PROJECT_ROOT}/_hyper-loop/bdd-specs.md` 和 `${PROJECT_ROOT}/_hyper-loop/contract.md`（无 `context/` 前缀），而项目中的规范位置是 `_hyper-loop/context/bdd-specs.md`。目前两个路径都有对应文件所以不崩溃，但路径不一致会导致将来清理时 break。

### 相关文件
- scripts/hyper-loop.sh (第 716-718 行，auto_decompose 函数内的路径引用)

### 修复方案
检查项目中 bdd-specs.md 和 contract.md 的实际位置。如果它们在 `_hyper-loop/` 根目录下（非 context/ 子目录），则路径本身是正确的，只需确保一致性。如果规范位置是 `_hyper-loop/context/`，则修改为带 `context/` 前缀的路径。

### 约束
- 只修 scripts/hyper-loop.sh
- 不改 CSS
- 不移动或重命名任何文件

### 验收标准
引用 BDD 场景 S002：auto_decompose 生成任务文件 — 确保 decompose prompt 引用的路径与实际文件位置一致
