# CLI 工具验证参考 (2026-03-30 实测)

## 核心原则
**不在 shell 里传文本。每个 agent 都能读文件。把文件路径给它，让它自己读。**

上下文文件统一放在 `_hyper-loop/context/` 下，prompt 只需说"先读那个目录"。

---

## Claude Code CLI (v2.1.87)

### stdin 管道行为（实测）
```bash
# -p 无参数 + stdin → 读取 stdin 作为 prompt（OK）
echo "say hi" | claude --dangerously-skip-permissions -p
# 输出: Hi!

# -p "" + stdin → 同上效果（OK）
echo "say hi" | claude --dangerously-skip-permissions -p ""
# 输出: Hi!

# -p "arg" + stdin → 两者都处理！prompt 和 stdin 都会被传入
echo "say hi" | claude --dangerously-skip-permissions -p "say ok"
# 输出: ok\nhi  (两个都执行了)

# -p - + stdin → "-" 被当成 prompt 的字面值参数，但 stdin 也会传入（OK）
echo "say hi" | claude --dangerously-skip-permissions -p -
# 输出: Hi!
```

### 关键参数
| 参数 | 用途 | 实测 |
|------|------|------|
| `-p` / `--print` | 非交互模式，输出后退出 | OK |
| `--dangerously-skip-permissions` | 跳过所有权限检查 | OK |
| `--add-dir DIR` | 额外允许访问的目录 | OK，实测 `--add-dir /tmp` 正常 |
| `--system-prompt "..."` | 自定义系统提示 | 存在，见 help |
| `--append-system-prompt "..."` | 追加到默认系统提示 | 存在，见 help |
| `--output-format json\|stream-json` | 输出格式 | 存在（仅 --print 模式） |
| `--model MODEL` | 指定模型 | 存在 |
| `-w` / `--worktree [name]` | 自动创建 git worktree | 存在 |
| `--tmux` | 自动创建 tmux 会话（需 --worktree） | 存在 |
| `-c` / `--continue` | 续上一次对话 | 存在 |
| `-n NAME` | 会话命名 | 存在 |
| `--max-budget-usd N` | API 费用上限（仅 --print） | 存在 |
| `--allowedTools "T1 T2"` | 限制可用工具 | 存在 |
| `--effort low\|medium\|high\|max` | 推理强度 | 存在 |
| `--bare` | 最小模式，跳过 hooks/LSP/插件等 | 存在 |

### 不存在的参数
- ~~`-C DIR`~~ → 用 `--add-dir DIR` 代替
- ~~`exec` 子命令~~ → 用 `-p` 实现非交互

### HyperLoop 推荐用法
```bash
# Writer（非交互任务）
claude --dangerously-skip-permissions --add-dir "$PROJECT_ROOT" \
  -p "先读 _hyper-loop/context/ 下所有 .md 了解背景，然后读 TASK.md 执行"

# Reviewer（非交互评审 + JSON 输出）
claude --dangerously-skip-permissions --add-dir "$PROJECT_ROOT" \
  -p "评审当前代码..." --output-format json

# 带 worktree 的常驻 Writer
claude --dangerously-skip-permissions -w "task-name" --tmux \
  --add-dir "$PROJECT_ROOT" "先读 _hyper-loop/context/WRITER_INIT.md"
```

---

## Gemini CLI (v0.35.3)

### stdin 管道行为（实测）
```bash
# -p "" + stdin → 读取 stdin 作为 prompt（OK，推荐用法）
echo "say hi" | gemini -y -p ""
# 输出: Hello! How can I help you...

# -p (无参数) + stdin → 报错！-p 必须带参数
echo "say hi" | gemini -y -p
# 输出: Not enough arguments following: p

# -p "非空" + stdin → 挂起/超时！（严重陷阱）
echo "say hi" | gemini -y -p "say ok"
# 结果: 超时（30秒无响应）

# -p - + stdin → 挂起/超时！("-" 被当字面值，行为异常)
echo "say hi" | gemini -y -p -
# 结果: 超时（30秒无响应）

# -p "非空" 无 stdin → 正常但较慢
gemini -y -p "respond with only the word OK"
# 输出: OK（但启动慢，多次打印 YOLO mode 信息）
```

### 关键参数
| 参数 | 用途 | 实测 |
|------|------|------|
| `-p "..."` | 非交互模式（必须带参数） | OK，但注意 stdin 陷阱 |
| `-y` / `--yolo` | 自动批准所有操作 | OK |
| `--approval-mode yolo` | 等效于 `-y` | OK，实测正常 |
| `--include-directories DIR` | 额外工作目录 | OK，实测 `--include-directories /tmp` 正常 |
| `-o json\|stream-json\|text` | 输出格式 | 存在 |
| `-m MODEL` | 指定模型 | 存在 |
| `-i "..."` | 交互模式带初始 prompt | 存在 |
| `-r latest` | 恢复最近会话 | 存在 |
| `-s` / `--sandbox` | 启用沙箱 | 存在 |

### 不存在的参数
- ~~`--add-dir`~~ → 报错 `Unknown arguments: add-dir, addDir`，用 `--include-directories` 代替
- ~~`--system-prompt`~~ → 在 prompt 中说明角色
- ~~`--dangerously-skip-permissions`~~ → 用 `-y` / `--yolo`

### 严重注意事项
1. **`-p` 必须带参数**，不能裸用 `-p`
2. **stdin + 非空 `-p` 参数 = 挂起**，只能用 `-p ""` 配合 stdin
3. **正确的管道模式**: `echo "prompt" | gemini -y -p ""`（空字符串）

### HyperLoop 推荐用法
```bash
# Reviewer（管道输入 prompt）
echo "$REVIEW_PROMPT" | gemini -y \
  --include-directories "$PROJECT_ROOT" -p "" -o json

# Reviewer（直接 prompt，无 stdin）
gemini -y --include-directories "$PROJECT_ROOT" \
  -p "先读 _hyper-loop/context/REVIEWER_INIT.md 然后评审代码" -o json
```

---

## Codex CLI (v0.117.0, codex-cli)

### stdin 管道行为（实测）
```bash
# exec + prompt 参数 → 非交互执行（推荐）
codex exec "say hi back"
# 输出: 正常响应

# exec + stdin (用 - 占位符) → 从 stdin 读取 prompt
echo "say hi" | codex exec -
# 输出: 正常响应（- 表示从 stdin 读取）

# exec + 直接管道(prompt 参数) → stdin 被忽略，只用参数
echo "say hi" | codex exec "say ok"
# 输出: 只处理 "say ok"，stdin 被忽略
```

### 关键参数（顶层 + exec 子命令共有）
| 参数 | 用途 | 实测 |
|------|------|------|
| `exec` / `e` | 非交互子命令，完成后退出 | OK |
| `-C DIR` / `--cd DIR` | 指定工作目录（必须是 git 仓库） | OK，实测 `-C $GIT_REPO` 正常 |
| `--full-auto` | `-a on-request` + `--sandbox workspace-write` 组合 | OK |
| `-a never` | 从不弹审批 | OK |
| `--dangerously-bypass-approvals-and-sandbox` | 跳过一切审批和沙箱 | OK，实测 sandbox 显示 `danger-full-access` |
| `--add-dir DIR` | 额外可写目录 | OK，实测正常 |
| `-s read-only\|workspace-write\|danger-full-access` | 沙箱策略 | 存在 |
| `-m MODEL` | 指定模型（默认 gpt-5.4） | 存在 |
| `-i FILE` | 附带图片 | 存在 |
| `--skip-git-repo-check` | 允许在非 git 目录运行 | 存在（exec 子命令） |
| `--json` | JSONL 输出（exec 子命令） | 存在 |
| `-o FILE` / `--output-last-message FILE` | 最后消息写入文件（exec） | 存在 |
| `review` 子命令 | 非交互代码评审 | 存在 |

### exec 子命令特有参数
| 参数 | 用途 |
|------|------|
| `--ephemeral` | 不持久化会话文件 |
| `--output-schema FILE` | JSON Schema 约束输出格式 |
| `--color always\|never\|auto` | 输出颜色控制 |

### 不存在的参数
- ~~`--system-prompt`~~ → prompt 里直接写角色说明
- ~~`--file`~~ → 用 `-C` + prompt 里引用文件路径

### 注意事项
1. **`-C DIR` 目标必须是 git 仓库**，否则报 `Not inside a trusted directory`，需加 `--skip-git-repo-check`
2. **`exec` 默认 sandbox 是 `read-only`**，写文件需 `--full-auto` 或 `-s workspace-write`
3. **`-` 占位符**: `codex exec -` 表示从 stdin 读取 prompt

### HyperLoop 推荐用法
```bash
# Writer（非交互任务，可写沙箱）
codex exec --full-auto -C "$WORKTREE_PATH" \
  "先读 _hyper-loop/context/ 下所有 .md 了解背景，然后读 TASK.md 执行"

# Writer（无沙箱限制）
codex exec --dangerously-bypass-approvals-and-sandbox -C "$WORKTREE_PATH" \
  "先读 TASK.md 然后修复"

# Reviewer（非交互评审）
codex exec -C "$PROJECT_ROOT" --json \
  "评审当前代码，输出 JSON 格式评分"

# stdin 管道模式
echo "$TASK_PROMPT" | codex exec --full-auto -C "$WORKTREE_PATH" -
```

---

## 三工具对比速查

| 功能 | Claude Code | Gemini | Codex |
|------|------------|--------|-------|
| **非交互标志** | `-p` | `-p "..."` | `exec` 子命令 |
| **自动批准** | `--dangerously-skip-permissions` | `-y` / `--yolo` | `--full-auto` 或 `--dangerously-bypass-approvals-and-sandbox` |
| **工作目录** | `--add-dir DIR` | `--include-directories DIR` | `-C DIR` + `--add-dir DIR` |
| **stdin 语法** | `echo X \| claude -p` | `echo X \| gemini -y -p ""` | `echo X \| codex exec -` |
| **输出格式** | `--output-format json` | `-o json` | `--json` (JSONL) |
| **模型选择** | `--model M` | `-m M` | `-m M` |
| **系统提示** | `--system-prompt "..."` | 不支持（写在 prompt 中） | 不支持（写在 prompt 中） |

### stdin 陷阱总结
| 工具 | `echo X \| tool -p` | `echo X \| tool -p ""` | `echo X \| tool -p "arg"` |
|------|---------------------|------------------------|--------------------------|
| Claude | OK (读 stdin) | OK (读 stdin) | 两者都处理 |
| Gemini | 报错 (缺参数) | OK (读 stdin) | 挂起/超时! |
| Codex | N/A (用 exec) | N/A | N/A (用 `exec -`) |
