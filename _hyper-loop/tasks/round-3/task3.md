## 修复任务: TASK-3
### 上下文
先读 _ctx/ 下所有文件。
### 问题
[P2] context/hyper-loop.sh 与 scripts/hyper-loop.sh 同步：确保 context/ 下的副本也反映 P0/P1 修复

`_hyper-loop/context/hyper-loop.sh` 是供 Agent（Tester/Reviewer）阅读的参考副本。如果 task1 和 task2 只修了 `scripts/hyper-loop.sh`，context/ 下的副本仍然包含旧的错误路径和 LOOP: 前缀，会导致 Agent 阅读到过时的代码。

需要将 task1 和 task2 的同等修复应用到 context 副本：
1. line 381: TESTER_INIT.MD 路径加 `templates/`
2. line 457: REVIEWER_INIT.MD 路径加 `templates/`
3. line 849: 去掉 `LOOP: ` 前缀

### 相关文件
- _hyper-loop/context/hyper-loop.sh (line 381, 457, 849)

### 约束
- 只改 `_hyper-loop/context/hyper-loop.sh` 中上述三处
- 修改内容必须与 task1 和 task2 对 scripts/hyper-loop.sh 的修改一致
- 不改 CSS

### 验收标准
- 引用 BDD 场景 S007: context 副本中 TESTER_INIT.MD 路径正确
- 引用 BDD 场景 S008: context 副本中 REVIEWER_INIT.MD 路径正确
- 引用 BDD 场景 S001: context 副本中输出格式为 `Round N/M`
- `bash -n _hyper-loop/context/hyper-loop.sh` 通过
