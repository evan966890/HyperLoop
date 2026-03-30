## 修复任务: TASK-2
### 上下文
先读 _ctx/ 下所有文件。

### 问题
[P0] `_hyper-loop/context/hyper-loop.sh` 是 v5.3 旧版本，而 `scripts/hyper-loop.sh` 已是 v5.4。
关键差异：
1. Writer 超时：context 版 900s vs scripts 版 300s
2. wait_writers 的 grep 管道：context 版缺少 `set +e` 防崩保护
3. Tester/Reviewer：context 版是交互 tmux 模式，scripts 版是非交互 `-p` 管道模式
4. cleanup_round：context 版缺少 subshell+set+e 保护
5. record_result：context 版用危险的 `source verdict.env`，scripts 版用安全的 grep

Writer 在 worktree 中工作时读 `_ctx/hyper-loop.sh`（即 context 副本）来理解项目。如果看到旧代码，可能基于错误理解做修改。

### 相关文件
- _hyper-loop/context/hyper-loop.sh (整个文件需要同步)

### 修复方案
用 `scripts/hyper-loop.sh` 的内容覆盖 `_hyper-loop/context/hyper-loop.sh`，确保两者一致。

### 约束
- 只修 _hyper-loop/context/hyper-loop.sh
- 内容应与 scripts/hyper-loop.sh 完全一致
- 不改 CSS

### 验收标准
引用 BDD 场景 S003: _ctx/ 目录被复制到 worktree（Writer 看到正确的代码）
验证：`diff scripts/hyper-loop.sh _hyper-loop/context/hyper-loop.sh` 无差异
