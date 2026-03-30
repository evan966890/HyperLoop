## 修复任务: TASK-3
### 上下文
先读 _ctx/ 下所有文件。
### 问题
[P1] 两个独立的代码质量问题：

**3a) cmd_status() 函数重复定义**
`cmd_status()` 在 L670 和 L930 各定义了一次。Bash 静默使用最后一个定义，L670 版本是死代码且缺少"最佳轮次"信息。重复定义增加维护混乱，Reviewer 会扣分。

**3b) archive_round 归档路径不够健壮**
L770 `cp "${PROJECT_ROOT}/_hyper-loop/bdd-specs.md"` 虽然当前有效（文件存在于根级），但 bdd-specs.md 的规范位置是 `_hyper-loop/context/bdd-specs.md`（Writer 的 _ctx/ 也是从 context/ 复制的）。如果根级副本被删除，归档会静默失败。
### 相关文件
- scripts/hyper-loop.sh (L670-676, 第一个 cmd_status 定义 — 删除)
- scripts/hyper-loop.sh (L930-942, 第二个 cmd_status 定义 — 保留)
- scripts/hyper-loop.sh (L770, archive_round 的 bdd-specs.md 复制路径)
### 修复方案
1. 删除 L670-676 的第一个 `cmd_status()` 定义（含空行），保留 L930 的完整版本
2. 将 L770 改为优先从 context/ 复制，fallback 到根级：
```bash
cp "${PROJECT_ROOT}/_hyper-loop/context/bdd-specs.md" "$ARCHIVE/" 2>/dev/null || \
  cp "${PROJECT_ROOT}/_hyper-loop/bdd-specs.md" "$ARCHIVE/" 2>/dev/null || true
```
### 约束
- 只修改 scripts/hyper-loop.sh 中的 cmd_status (删除第一个) 和 archive_round (修改路径)
- 不改其他函数
- 不改 CSS
### 验收标准
引用 BDD 场景 S001 (脚本整体不崩溃): bash -n 语法检查通过，cmd_status 只有一个定义且包含最佳轮次信息
