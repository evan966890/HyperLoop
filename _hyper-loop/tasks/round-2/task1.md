## 修复任务: TASK-1
### 上下文
先读 _ctx/ 下所有文件，特别是 bdd-specs.md 中 S002 场景和 contract.md。

### 问题
[P0] auto_decompose 和 archive_round 中 BDD spec / contract 路径缺少 `context/` 段

auto_decompose (L692-693) 写的是:
- `${PROJECT_ROOT}/_hyper-loop/bdd-specs.md`
- `${PROJECT_ROOT}/_hyper-loop/contract.md`

正确路径应该是:
- `${PROJECT_ROOT}/_hyper-loop/context/bdd-specs.md`
- `${PROJECT_ROOT}/_hyper-loop/context/contract.md`

同样，archive_round (L770) 也写错了:
- `cp "${PROJECT_ROOT}/_hyper-loop/bdd-specs.md"` → 应改为 `_hyper-loop/context/bdd-specs.md`

影响: Claude 拆解器拿到错误路径找不到核心规格文件，拆解质量严重下降，每轮都受影响。归档时 BDD spec 拷贝失败（被 `|| true` 吞掉），archive 不完整。

### 相关文件
- scripts/hyper-loop.sh (L692-694) — auto_decompose 中的路径
- scripts/hyper-loop.sh (L770) — archive_round 中的路径

### 约束
- 只修 scripts/hyper-loop.sh 中的路径字符串
- 不改逻辑结构，不改 CSS
- 搜索全文件确保没有其他遗漏的错误路径

### 验收标准
- S002: auto_decompose 生成任务文件时能正确引用 bdd-specs.md 和 contract.md
- archive_round 能正确拷贝 bdd-specs.md 到归档目录
