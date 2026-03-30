## 修复任务: TASK-3
### 上下文
先读 _ctx/ 下所有文件。
### 问题
[P1] diff 审计正则表达式缺少 .sh 扩展名，导致审计对本项目（Bash 脚本项目）形同虚设。

audit_writer_diff (约249行) 的文件扩展名正则:
```
grep -oE '[-a-zA-Z0-9_./ ]+\.(rs|svelte|ts|js|tsx|jsx|css|py|go|html)'
```
缺少 `.sh`、`.md`、`.json`、`.toml`、`.yaml`、`.yml`、`.env` 等常见扩展名。

对于本项目的主要修改文件 `hyper-loop.sh`，正则永远匹配不到，`ALLOWED_FILES` 始终为空，函数走进 "跳过审计" 分支直接返回 0，使得越界修改检测完全失效。

### 相关文件
- scripts/hyper-loop.sh (249行: audit_writer_diff 函数中的 grep -oE 正则表达式)

### 约束
- 只修 scripts/hyper-loop.sh 中 audit_writer_diff 的正则表达式
- 在扩展名列表中添加: sh|md|json|toml|yaml|yml|env|cfg|conf|txt
- 不改 CSS，不新建文件

### 验收标准
引用 BDD 场景 S005: diff 审计能正确识别 .sh 文件并拦截越界修改
