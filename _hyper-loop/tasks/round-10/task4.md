## 修复任务: TASK-4
### 上下文
先读 _ctx/ 下所有文件。
### 问题
[P1] 三个独立小修复：

1. **archive_round 路径错误**（line 773）：`cp "${PROJECT_ROOT}/_hyper-loop/bdd-specs.md"` 应为 `cp "${PROJECT_ROOT}/_hyper-loop/context/bdd-specs.md"`。当前 `|| true` 掩盖了每轮复制失败。

2. **cmd_status 重复定义**（line 673-679）：第一个 `cmd_status`（line 673）是死代码，被第二个定义（line 935）覆盖。删除 line 673-679。

3. **audit_writer_diff 白名单缺 .sh 扩展名**（line 249）：正则 `\.(rs|svelte|ts|js|tsx|jsx|css|py|go|html)` 不包含 `.sh`，导致当任务目标是 shell 脚本时审计被跳过，BDD S005 在自举场景下失效。

### 相关文件
- scripts/hyper-loop.sh (773, 673-679, 249)

### 修复方向
1. 把 `_hyper-loop/bdd-specs.md` → `_hyper-loop/context/bdd-specs.md`
2. 删除 line 673-679 的第一个 `cmd_status` 函数
3. 在扩展名正则中加入 `sh|bash|zsh`：`\.(rs|svelte|ts|js|tsx|jsx|css|py|go|html|sh|bash|zsh)`

### 约束
- 只修 scripts/hyper-loop.sh
- 不改 CSS
- 三个修复互不影响，但都在同一个文件

### 验收标准
引用 BDD 场景 S005（diff 审计拦截越界修改）+ 通用代码质量：
- archive_round 能正确复制 bdd-specs.md 到归档目录
- cmd_status 只有一个定义，无死代码
- 当任务目标是 .sh 文件时，audit_writer_diff 能正确提取白名单并进行审计
