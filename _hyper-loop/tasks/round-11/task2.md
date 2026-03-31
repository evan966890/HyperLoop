## 修复任务: TASK-2
### 上下文
先读 _ctx/ 下所有文件。

### 问题
[P1] scripts/hyper-loop.sh `cmd_round()` 函数（L673-753）在正常路径（评审通过或拒绝后）不调用 `archive_round()`。

对比 `cmd_loop()` 的同一流程（L1127-1153），每轮结束时正确调用了 `archive_round "$ROUND"` + `cleanup_round "$ROUND"`。但 `cmd_round()` 只调用了 `cleanup_round "$ROUND"`（L746），缺失 `archive_round`。

**影响：**
- 使用 `hyper-loop.sh round N` 命令时，round 数据（git-sha.txt、scores 副本、报告副本）不会被归档到 `_hyper-loop/archive/round-N/`
- S013 连续 5 轮失败回退机制依赖 `archive/round-N/git-sha.txt`，缺失归档导致回退目标不存在
- `cmd_resume_from` 也依赖 archive 数据，round 命令下无法恢复

### 相关文件
- scripts/hyper-loop.sh (L673-753: cmd_round 函数)

### 修复策略

1. 用 grep 搜索 `cmd_round` 函数体，确认所有退出路径：
   ```bash
   grep -n 'cleanup_round\|archive_round\|return' scripts/hyper-loop.sh
   ```

2. 在 `cmd_round()` 中，找到所有调用 `cleanup_round` 的位置，在其**之前**添加 `archive_round "$ROUND"`

3. 确保 cmd_round 中的所有退出路径（正常完成、no-merge、build-fail）都先调用 archive_round 再调用 cleanup_round

4. 对比 cmd_loop 中同样的流程（L1100-1153），确保两个函数的归档/清理逻辑一致

### 约束
- 只修 scripts/hyper-loop.sh 的 cmd_round() 函数（L673-753 区域）
- 不改其他函数
- 修完运行 `bash -n scripts/hyper-loop.sh` 确认语法无误

### 验收标准
- S001: loop 命令和 round 命令都正确归档数据
- S013: round 命令下连续失败回退机制可用（archive/round-N/git-sha.txt 存在）
