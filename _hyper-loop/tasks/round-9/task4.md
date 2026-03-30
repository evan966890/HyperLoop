## 修复任务: TASK-4
### 上下文
先读 _ctx/ 下所有文件。

### 问题
[P1] 4 个小问题合并修复，都是代码卫生问题：

**4a. cleanup_round 残留分支未完全删除**
line 600-606: 只遍历 `${WORKTREE_BASE}/task*` 和 `integration` 目录来获取分支名。如果 worktree 目录已被删除（如 merge 后自动清理），循环获取不到分支名，残留分支不会被清理。
修复：在现有逻辑之后，加一行 `git branch | grep "hyper-loop/r${ROUND}-" | xargs git branch -D` 兜底。

**4b. cmd_status 重复定义**
line 697-703 和 line 957-969 各定义了一个 `cmd_status`，后者覆盖前者。前者是死代码。
修复：删除 line 697-703 的第一个定义。

**4c. auto_decompose 路径不一致**
line 719-720 引用 `_hyper-loop/bdd-specs.md` 和 `_hyper-loop/contract.md`，但这些文件的规范位置是 `_hyper-loop/context/bdd-specs.md` 和 `_hyper-loop/context/contract.md`（与 Writer `_ctx/` 上下文包一致）。
修复：加上 `context/` 路径前缀。

**4d. audit_writer_diff 正则缺 .sh 扩展名**
line 249: `grep -oE '[-a-zA-Z0-9_./ ]+\.(rs|svelte|ts|js|tsx|jsx|css|py|go|html)'` 不包含 `.sh`，导致修改 shell 脚本的任务无法被正确审计。
修复：在扩展名列表中加入 `sh|bash|md|json|toml`。

### 相关文件
- scripts/hyper-loop.sh (line 589-609 cleanup_round; line 697-703 第一个 cmd_status; line 716-721 auto_decompose; line 248-250 audit regex)

### 约束
- 只修 scripts/hyper-loop.sh
- 每个子问题的修改不超过 5 行
- 保持 subshell + `set +e` 容错结构
- 不改 CSS

### 验收标准
引用 BDD 场景 S015（worktree 清理）和 S002（auto_decompose 生成任务文件）和 S005（diff 审计）
- cleanup_round 执行后无 `hyper-loop/rN-*` 残留分支
- 脚本中只有一个 `cmd_status` 定义
- auto_decompose prompt 中的文件路径指向 `_hyper-loop/context/` 下的实际文件
- audit regex 能匹配 `.sh` 文件路径
- `bash -n scripts/hyper-loop.sh` 语法检查通过
