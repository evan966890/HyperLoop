## 修复任务: TASK-3
### 上下文
先读 _ctx/ 下所有文件。

### 问题
[P2] scripts/hyper-loop.sh 中 `start_agent()`（L59-92）和 `kill_agent()`（L95-98）两个函数是死代码——定义了但从未被调用。

验证方法：
```bash
grep -n 'start_agent\|kill_agent' scripts/hyper-loop.sh
```
只会看到函数定义，没有任何调用点。

**背景：** 这两个函数是早期版本用 tmux window 启动 Writer/Tester/Reviewer 的遗留代码。当前实现已改为：
- Writer: 后台 subshell + `codex exec`（L227-234）
- Tester: 非交互 `claude -p` 管道模式（L449-451）
- Reviewer: 并行 subshell + 管道模式（L504-524）

保留死代码增加维护负担（约 40 行），且可能误导代码审查者认为这些函数在使用中。

### 相关文件
- scripts/hyper-loop.sh (L59-98: start_agent 和 kill_agent 两个函数)

### 修复策略

1. 先用 grep 确认 `start_agent` 和 `kill_agent` 确实无任何调用：
   ```bash
   grep -c 'start_agent\|kill_agent' scripts/hyper-loop.sh
   ```
   应只有函数定义处的匹配

2. 确认没有其他文件引用这两个函数：
   ```bash
   grep -rn 'start_agent\|kill_agent' scripts/ _hyper-loop/
   ```

3. 删除 `start_agent()` 函数（L59-92）和 `kill_agent()` 函数（L95-98）的完整定义

4. 保留上方的 `ensure_session()` 函数（L53-57）和下方注释 `# ── Writer 管理 ──` + `start_writers()` 函数（L100+），不动

### 约束
- 只修 scripts/hyper-loop.sh 的 L59-98 区域
- 不改其他函数
- 修完运行 `bash -n scripts/hyper-loop.sh` 确认语法无误

### 验收标准
- bash -n 语法检查通过
- 脚本功能不受影响（所有 BDD 场景不变）
- 代码行数减少约 40 行，可读性提升
