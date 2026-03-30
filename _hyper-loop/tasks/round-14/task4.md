## 修复任务: TASK-4
### 上下文
先读 _ctx/ 下所有文件。

### 问题
[P1] 工作区 scripts/hyper-loop.sh 被 `script` 命令意外覆盖为 1 行垃圾内容

当前工作目录中的 `scripts/hyper-loop.sh` 内容为：
```
Script started on Mon Mar 30 04:15:42 2026
```
只有 2 行，原始 987 行代码丢失。git HEAD 中的版本是正确的。
这意味着后续轮次如果基于工作目录（而非 git HEAD）构建会失败。

### 修复方案
从 git HEAD 恢复工作目录中的 `scripts/hyper-loop.sh`：
```bash
git checkout HEAD -- scripts/hyper-loop.sh
```

### 相关文件
- scripts/hyper-loop.sh (整个文件)

### 约束
- 只恢复 scripts/hyper-loop.sh 从 git HEAD
- 不改其他文件
- 不改 CSS
- 恢复后文件应与 `git show HEAD:scripts/hyper-loop.sh` 完全一致

### 验收标准
- `wc -l scripts/hyper-loop.sh` 返回 987（与 HEAD 一致）
- `bash -n scripts/hyper-loop.sh` 通过
- `git diff HEAD -- scripts/hyper-loop.sh` 无输出（与 HEAD 完全一致）
