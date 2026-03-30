## 修复任务: TASK-4
### 上下文
先读 _ctx/ 下所有文件。
### 问题
[P1-3 + P2-1 + P2-2] 三处独立小缺陷打包修复

**P1-3: cmd_status 重复定义**
L673-679 定义了第一个 `cmd_status()`（功能简陋），L935-947 定义了第二个（多了"最佳轮次"显示）。Bash 使用最后一个定义，第一个是死代码。
修复：删除 L673-679 的第一个定义。

**P2-1: archive_round 复制 bdd-specs.md 路径错误**
L773: `cp "${PROJECT_ROOT}/_hyper-loop/bdd-specs.md"` 指向不存在的路径。
实际文件在 `${PROJECT_ROOT}/_hyper-loop/context/bdd-specs.md`。
虽然 `|| true` 让它静默失败，但 archive 永远缺少 BDD 规格副本。
修复：改为 `${PROJECT_ROOT}/_hyper-loop/context/bdd-specs.md`。

**P2-2: build_app 改变全局 CWD**
L367: `cd "$BUILD_DIR"` 改变了主进程工作目录。cleanup_round 删除 worktree 后，主进程站在已删除目录中。当前全用绝对路径没崩溃，但脆弱。
修复：将 build_app 函数体包裹在 subshell `( ... )` 中隔离 CWD。

### 相关文件
- scripts/hyper-loop.sh (L673-679, 第一个 cmd_status 定义 — 删除)
- scripts/hyper-loop.sh (L773, archive_round 内 bdd-specs.md 路径)
- scripts/hyper-loop.sh (L363-375, build_app 函数)

### 约束
- 只修上述三处，不改其他逻辑
- build_app 改用 subshell 后，函数返回值（exit code）语义不变
- 不改 CSS

### 验收标准
1. 引用 BDD S001: `bash -n` 语法检查通过，`grep -c 'cmd_status()' scripts/hyper-loop.sh` 输出 1
2. archive 目录包含正确路径的 bdd-specs.md 副本
3. build_app 执行后主进程 CWD 不变
