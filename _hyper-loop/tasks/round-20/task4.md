## 修复任务: TASK-4
### 上下文
先读 _ctx/ 下所有文件。

### 问题
[P1] `start_agent()` 注入消息中的 bdd-specs.md 和 contract.md 路径使用 `_hyper-loop/context/` 前缀，但 `auto_decompose()` 的 prompt 使用 `_hyper-loop/` 前缀（无 context/）。虽然文件在两个位置都存在且内容相同，但路径不一致会导致：
1. 如果某天只更新了其中一个位置的文件，agent 间看到的规格不同
2. 代码可读性差：两处引用同一文件用了不同路径

应统一为 `_hyper-loop/context/` 路径（这是 `start_agent` 已使用的规范路径，且 context/ 是所有上下文文件的标准目录）。

### 相关文件
- scripts/hyper-loop.sh (`auto_decompose` 函数中的 prompt 模板，约第 719-720 行)
  - `${PROJECT_ROOT}/_hyper-loop/bdd-specs.md` → `${PROJECT_ROOT}/_hyper-loop/context/bdd-specs.md`
  - `${PROJECT_ROOT}/_hyper-loop/contract.md` → `${PROJECT_ROOT}/_hyper-loop/context/contract.md`

### 约束
- 只修 scripts/hyper-loop.sh
- 只改 `auto_decompose` 函数中 prompt 模板里的两个路径
- 不改其他函数

### 验收标准
引用 BDD 场景 S002: auto_decompose 生成任务文件
- decompose prompt 中 bdd-specs.md 和 contract.md 的路径统一为 `_hyper-loop/context/` 前缀
- Claude -p 能正确读取到这两个文件
