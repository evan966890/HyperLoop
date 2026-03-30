## 修复任务: TASK-2
### 上下文
先读 _ctx/ 下所有文件。

### 问题
[P1] auto_decompose 引用路径不一致

`auto_decompose()` 函数（约 line 757-758）中的 decompose prompt 引用：
- `${PROJECT_ROOT}/_hyper-loop/bdd-specs.md`
- `${PROJECT_ROOT}/_hyper-loop/contract.md`

而 `start_agent()` 和 `run_reviewers()` 引用的是：
- `${PROJECT_ROOT}/_hyper-loop/context/bdd-specs.md`
- `${PROJECT_ROOT}/_hyper-loop/context/contract.md`

当前两个位置都存在文件所以不影响运行，但维护时只更新一处会导致数据分歧。应统一为 `_hyper-loop/context/` 路径。

### 相关文件
- scripts/hyper-loop.sh (auto_decompose 函数，约 line 706-770)

### 约束
- 只修 scripts/hyper-loop.sh 中 `auto_decompose()` 函数内的路径引用
- 将 `_hyper-loop/bdd-specs.md` → `_hyper-loop/context/bdd-specs.md`
- 将 `_hyper-loop/contract.md` → `_hyper-loop/context/contract.md`
- 不改其他函数
- 不改 CSS

### 验收标准
- S002: auto_decompose 生成任务文件时引用的 BDD 和 contract 路径与其他函数一致（均为 `_hyper-loop/context/` 下）
- `bash -n scripts/hyper-loop.sh` 通过
