## 修复任务: TASK-2
### 上下文
先读 _ctx/ 下所有文件。
### 问题
[P1] audit_writer_diff 的文件扩展名正则不包含 .sh/.md/.json 等，对本项目（Bash 脚本）的越界修改检测完全失效

`audit_writer_diff()` 在 line 249 使用正则提取 TASK.md 中"相关文件"列出的文件路径：
```
grep -oE '[-a-zA-Z0-9_./ ]+\.(rs|svelte|ts|js|tsx|jsx|css|py|go|html)'
```

该正则缺少 `.sh|.md|.json|.toml|.yaml|.yml|.env` 等扩展名。当 TASK.md 指定 `scripts/hyper-loop.sh` 时，审计器无法识别该路径，导致所有修改都被视为"越界"或审计形同虚设。

### 相关文件
- scripts/hyper-loop.sh (lines 240-260)

### 约束
- 只修 scripts/hyper-loop.sh 中 audit_writer_diff() 函数内的 grep 正则
- 不改其他函数
- 不改 CSS
- 修改范围：lines 240-260

### 验收标准
引用 BDD 场景 S005 (diff 审计拦截越界修改)
- 当 TASK.md 的"相关文件"包含 `.sh` 文件时，审计器能正确识别
- `.md`, `.json`, `.toml`, `.yaml`, `.yml`, `.env` 扩展名也应被识别
- `bash -n scripts/hyper-loop.sh` 语法检查通过
