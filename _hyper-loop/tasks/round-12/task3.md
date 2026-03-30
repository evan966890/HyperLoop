## 修复任务: TASK-3
### 上下文
先读 _ctx/ 下所有文件。
### 问题
[P1] auto_decompose 和 archive_round 引用错误的 bdd-specs.md / contract.md 路径 + cmd_status() 重复定义

三个路径 bug：
1. `auto_decompose()` line 719: `${PROJECT_ROOT}/_hyper-loop/bdd-specs.md` → 应为 `${PROJECT_ROOT}/_hyper-loop/context/bdd-specs.md`
2. `auto_decompose()` line 720: `${PROJECT_ROOT}/_hyper-loop/contract.md` → 应为 `${PROJECT_ROOT}/_hyper-loop/context/contract.md`
3. `archive_round()` line 797: `${PROJECT_ROOT}/_hyper-loop/bdd-specs.md` → 应为 `${PROJECT_ROOT}/_hyper-loop/context/bdd-specs.md`

一个 P2 代码质量问题：
4. `cmd_status()` 在 line 697 和 line 957 各有一个定义。line 697 是死代码（被 line 957 的定义覆盖）。删除 line 697-703 的第一个 `cmd_status()` 定义。

### 相关文件
- scripts/hyper-loop.sh (lines 695-800)

### 约束
- 只修 scripts/hyper-loop.sh 中 auto_decompose()、archive_round() 的路径引用和删除第一个 cmd_status()
- 不改其他函数
- 不改 CSS
- 修改范围：lines 695-800

### 验收标准
引用 BDD 场景 S002 (auto_decompose 生成任务文件)
- auto_decompose 中 BDD 规格和评估契约路径指向 `_hyper-loop/context/` 下的实际文件
- archive_round 中 bdd-specs.md 路径也已修正
- cmd_status() 只有一个定义（line 957 附近的版本保留）
- `bash -n scripts/hyper-loop.sh` 语法检查通过
