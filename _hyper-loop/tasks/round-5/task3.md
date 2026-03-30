## 修复任务: TASK-3
### 上下文
先读 _ctx/ 下所有文件。
### 问题
[P1] 两个独立的路径/变量 bug：

1. `archive_round` 中 bdd-specs.md 路径错误（line 770）：写的是 `${PROJECT_ROOT}/_hyper-loop/bdd-specs.md`，实际文件在 `${PROJECT_ROOT}/_hyper-loop/context/bdd-specs.md`。cp 因 `|| true` 静默失败，归档缺少 BDD 规格文件。

2. `auto_decompose` 的 heredoc 中 `\$f` 变量转义错误（line 704）：在非引号 heredoc 的 `$(...)` 命令替换中，`\$f` 被转义为字面量 `$f`，for 循环变量不生效。Claude 拆解时看不到上一轮具体评分内容。
### 相关文件
- scripts/hyper-loop.sh (line 770: archive_round 中 cp bdd-specs.md)
- scripts/hyper-loop.sh (line 703-705: auto_decompose heredoc 中的 for 循环)
### 约束
- 只修 scripts/hyper-loop.sh
- 不改 CSS
- bug 1: 将 `_hyper-loop/bdd-specs.md` 改为 `_hyper-loop/context/bdd-specs.md`
- bug 2: 将 `\$f` 改为 `$f`（heredoc 中 `$(...)` 内的 `$` 由子 shell 处理，不需要转义）
### 验收标准
引用 BDD 场景 S002: auto_decompose 的拆解 prompt 包含上一轮评分内容
归档目录包含 bdd-specs.md 文件
