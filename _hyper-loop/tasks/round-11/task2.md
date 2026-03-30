## 修复任务: TASK-2
### 上下文
先读 _ctx/ 下所有文件。
### 问题
[P1] auto_decompose 和 archive_round 引用了错误的 bdd-specs.md / contract.md 路径。

1. auto_decompose (约719-720行) 的 decompose prompt 中写的:
   - `${PROJECT_ROOT}/_hyper-loop/bdd-specs.md`
   - `${PROJECT_ROOT}/_hyper-loop/contract.md`
   实际路径应为:
   - `${PROJECT_ROOT}/_hyper-loop/context/bdd-specs.md`
   - `${PROJECT_ROOT}/_hyper-loop/context/contract.md`

2. archive_round (约797行):
   - `cp "${PROJECT_ROOT}/_hyper-loop/bdd-specs.md" "$ARCHIVE/"`
   实际路径应为:
   - `cp "${PROJECT_ROOT}/_hyper-loop/context/bdd-specs.md" "$ARCHIVE/"`

这导致 Claude decomposer 无法找到 BDD 规格和评估契约，任务拆解质量下降。归档时也无法正确复制规格文件。

### 相关文件
- scripts/hyper-loop.sh (719-720行: decompose prompt 中的路径引用; 797行: archive_round 中的 cp 路径)

### 约束
- 只修 scripts/hyper-loop.sh 中对 bdd-specs.md 和 contract.md 的路径引用
- 所有引用都加上 `context/` 子目录前缀
- 不改 CSS，不新建文件

### 验收标准
引用 BDD 场景 S002: auto_decompose 能正确读取 BDD 规格并生成高质量任务文件
