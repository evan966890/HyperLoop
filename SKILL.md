---
name: hyper-loop
description: "Multi-agent self-improving loop with full context injection. Codex CLI writes code in worktrees (up to 50 parallel tmux panes), Gemini CLI reviews with full BMAD docs, Claude orchestrates. Prevents self-inflation through separation of concerns."
tools: Read, Edit, Write, Bash, Glob, Grep, Agent, AskUserQuestion
---

# HyperLoop v4 — 全上下文多 Agent 自改进循环

## 血的教训

> v2: 同一个 Agent 自写自审 → 30 轮 CSS 自嗨
> v3: 角色分离了但 Codex 没上下文 → 写出来的代码不符合设计
> **v4: 每个 Agent 都必须拿到完整上下文才能工作**

---

## 架构

```
┌──────────────────────────────────────────────────────────┐
│ ORCHESTRATOR (Claude Code 主会话)                          │
│ 职责：对齐→拆任务→分发→收集→对比→决策                       │
│ 禁止：写业务代码、自己给最终分                               │
├──────────────────────────────────────────────────────────┤
│ WRITERS (Codex CLI × N · 每个在独立 worktree + tmux pane) │
│ 最多 50 个并行 pane，每个 pane = 1 个 worktree = 1 个任务  │
│ 每个 Writer 启动时注入：BMAD 全套文档 + 评估契约 + CLAUDE.md │
│ 进程常驻，不是一次性命令                                     │
├──────────────────────────────────────────────────────────┤
│ REVIEWERS (Gemini CLI × M · tmux pane)                    │
│ 每个 Reviewer 启动时注入：PRD + 架构文档 + 设计文档 + 契约   │
│ 进程常驻，接受多轮评审请求                                   │
└──────────────────────────────────────────────────────────┘

最终分 = min(Claude, Gemini)，差异 > 2 分须用户裁决
```

---

## 初始化文档模板

三份模板在 `~/.claude/skills/hyper-loop/templates/` 下：

| 文件 | 给谁 | 包含什么 |
|------|------|---------|
| `WRITER_INIT.md` | Codex Writer | 角色定义 + 项目概览 + 编码规范 + 架构 + PRD 摘要 + 设计摘要 + 契约 + 任务 |
| `REVIEWER_INIT.md` | Gemini Reviewer | 角色定义 + PRD **全文** + 设计 **全文** + 架构 + 评分规则 + JSON 输出格式 |
| `ORCHESTRATOR_CHECKLIST.md` | Claude 自己 | 项目配置 + tmux 会话清单 + 每轮检查清单 + 紧急停止条件 |

Phase 0 时用 `{{placeholder}}` 替换为实际内容生成最终版本。

---

## Phase 0: 目标对齐 + 上下文准备

### Step A: 项目配置收集

```markdown
## 项目配置
- 项目类型：[Tauri / Next.js / SvelteKit / 其他]
- 项目根目录：[绝对路径]
- 构建命令 / 启动命令 / 缓存清理 / 构建验证
- App 窗口名（Peekaboo 用）
- 测试模式：[packaged-app / dev-server]
```

确认后立刻写入 `_hyper-loop/project-config.env`，后续所有模板渲染只读这个锁定文件：

```bash
mkdir -p _hyper-loop

cat > _hyper-loop/project-config.env <<'EOF'
PROJECT_NAME="项目目录名"
PROJECT_ROOT="/absolute/path/to/project"
PROJECT_TYPE="Tauri"
BUILD_CMD="pnpm build"
LAUNCH_CMD="pnpm tauri dev"
CACHE_CLEAN="rm -rf node_modules/.vite dist target"
BUILD_VERIFY="pnpm tauri build && strings src-tauri/target/release/bundle/macos/*.app/Contents/MacOS/* | rg '目标字符串'"
WINDOW_NAME="Peekaboo 可见的窗口名"
TEST_MODE="packaged-app"
TECH_STACK="Tauri v2 + Svelte 5 + Rust + TypeScript"
EOF
```

### Step B: 问用户三个问题

Q1: 试用什么？ Q2: 什么算成功？ Q3: 最担心什么？

### Step C: 收集 BMAD 全套文档，构建上下文包

**这是 v4 的核心改进。** 在分发任何任务之前，先构建一个「上下文包」：

```bash
# 收集所有 BMAD 编码前文档
CONTEXT_DIR="_hyper-loop/context"
mkdir -p "$CONTEXT_DIR"

# 1. CLAUDE.md（项目编码规范）
cp CLAUDE.md "$CONTEXT_DIR/" 2>/dev/null

# 2. PRD（产品需求文档）
find _bmad-output/planning-artifacts -type f \( -iname "*prd*" \) 2>/dev/null | sort | head -3 | while read -r f; do
  cp "$f" "$CONTEXT_DIR/"
done

# 3. 架构文档
find _bmad-output/planning-artifacts -type f \( -iname "*architect*" -o -iname "*architecture*" \) 2>/dev/null | sort | head -3 | while read -r f; do
  cp "$f" "$CONTEXT_DIR/"
done

# 4. 设计文档（用户指定路径）
find docs/design -maxdepth 1 -type f -name "*.md" 2>/dev/null | sort | while read -r f; do
  cp "$f" "$CONTEXT_DIR/"
done

# 5. UX 设计文档
find _bmad-output/planning-artifacts -type f \( -iname "*ux*" -o -iname "*design*" \) 2>/dev/null | sort | head -3 | while read -r f; do
  cp "$f" "$CONTEXT_DIR/"
done

# 6. Sprint 计划
find _bmad-output/implementation-artifacts -type f -iname "*sprint*" 2>/dev/null | sort | head -1 | while read -r f; do
  cp "$f" "$CONTEXT_DIR/"
done

# 7. 评估契约（Phase 0 生成后放这里）
# 8. 功能检查清单（Phase 0 生成后放这里）
```

### Step D: 读取设计文档，生成功能检查清单

从上下文包中的设计文档提取功能点，生成 `_hyper-loop/checklist.md`。

### Step E: 生成评估契约

写入 `_hyper-loop/contract.md`，同时复制到 `_hyper-loop/context/contract.md`。

### Step F: 渲染初始化模板（一次定义，后续复用）

```bash
set -a
. _hyper-loop/project-config.env
set +a

TEMPLATE_DIR="$HOME/.claude/skills/hyper-loop/templates"
mkdir -p _hyper-loop/context _hyper-loop/tasks _hyper-loop/logs

PRD_FILE=$(find _hyper-loop/context -maxdepth 1 -type f -iname "*prd*" | sort | head -1)
ARCH_FILE=$(find _hyper-loop/context -maxdepth 1 -type f \( -iname "*architect*" -o -iname "*architecture*" \) | sort | head -1)
DESIGN_FILE=$(find _hyper-loop/context -maxdepth 1 -type f -iname "*design*" | sort | head -1)
UX_FILE=$(find _hyper-loop/context -maxdepth 1 -type f -iname "*ux*" | sort | head -1)
CLAUDE_FILE="_hyper-loop/context/CLAUDE.md"
[ -n "$DESIGN_FILE" ] || DESIGN_FILE="$UX_FILE"

export DIR_STRUCTURE="$(find "$PROJECT_ROOT" -maxdepth 2 -type d | sort | head -40)"
export CODING_RULES="$(sed -n '/^## .*代码.*规则/,/^## /p' "$CLAUDE_FILE" 2>/dev/null)"
export ARCHITECTURE="$(cat "$ARCH_FILE" 2>/dev/null)"
export PRD_FULL="$(cat "$PRD_FILE" 2>/dev/null)"
export PRD_SUMMARY="$(head -100 "$PRD_FILE" 2>/dev/null)"
export DESIGN_FULL="$(cat "$DESIGN_FILE" 2>/dev/null)"
export DESIGN_SUMMARY="$(head -100 "$DESIGN_FILE" 2>/dev/null)"
export UX_SPEC="$(cat "$UX_FILE" 2>/dev/null)"
export CONTRACT="$(cat _hyper-loop/contract.md)"
export CHECKLIST="$(cat _hyper-loop/checklist.md)"
[ -n "$CODING_RULES" ] || export CODING_RULES="$(cat "$CLAUDE_FILE" 2>/dev/null)"
[ -n "$ARCHITECTURE" ] || export ARCHITECTURE="$(sed -n '/^## .*架构/,/^## /p' "$CLAUDE_FILE" 2>/dev/null)"

render_template() {
  python3 - "$1" "$2" <<'PY'
from pathlib import Path
import os
import re
import sys

template_path, output_path = sys.argv[1:3]
text = Path(template_path).read_text()
for key, value in os.environ.items():
    if re.fullmatch(r"[A-Z0-9_]+", key):
        text = text.replace(f"{{{{{key}}}}}", value)
missing = sorted(set(re.findall(r"{{([A-Z0-9_]+)}}", text)))
if missing:
    raise SystemExit(f"模板仍有未填充占位符: {missing}")
Path(output_path).write_text(text)
PY
}

render_template "$TEMPLATE_DIR/REVIEWER_INIT.md" "_hyper-loop/context/REVIEWER_INIT.md"
render_template "$TEMPLATE_DIR/ORCHESTRATOR_CHECKLIST.md" "_hyper-loop/context/ORCHESTRATOR_CHECKLIST.md"

# WRITER_INIT.md 依赖每个子任务的 WORKTREE_PATH 和 TASK_DESCRIPTION，
# 必须在 Phase 1 为每个 task 单独渲染，不能在这里预生成。
```

### Step G: 初始化 tmux（无人值守模式）

**所有子进程必须开启 bypass 模式，否则会卡在审批弹窗上：**

```bash
LOG_DIR="$PROJECT_ROOT/_hyper-loop/logs/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$LOG_DIR"

# 创建 tmux 会话
tmux new-session -d -s hyper-loop -n orchestrator
tmux pipe-pane -o -t hyper-loop:orchestrator "cat >> '$LOG_DIR/orchestrator.log'"

# --- Gemini Reviewer（常驻，yolo 模式）---
tmux new-window -t hyper-loop -n reviewer
tmux pipe-pane -o -t hyper-loop:reviewer "cat >> '$LOG_DIR/gemini-reviewer.log'"
tmux send-keys -t hyper-loop:reviewer "cd $PROJECT_ROOT && gemini --yolo" Enter
sleep 2
tmux load-buffer -b reviewer-init "$PROJECT_ROOT/_hyper-loop/context/REVIEWER_INIT.md"
tmux paste-buffer -d -r -b reviewer-init -t hyper-loop:reviewer
tmux send-keys -t hyper-loop:reviewer Enter

# --- Claude 子进程（如需额外 Claude 评审）---
# claude --dangerously-skip-permissions -p "$(cat _hyper-loop/context/ORCHESTRATOR_CHECKLIST.md)"
```

**Writer (Codex) 启动模板（Phase 1 按需创建）：**

```bash
# 每个 Writer 在独立 worktree + tmux window 中启动
tmux new-window -t hyper-loop -n "w-task${N}"
tmux pipe-pane -o -t "hyper-loop:w-task${N}" "cat >> '$LOG_DIR/codex-writer-r${ROUND}-task${N}.log'"
tmux send-keys -t "hyper-loop:w-task${N}" "cd ${WORKTREE_PATH} && codex --full-auto" Enter
sleep 2
tmux load-buffer -b "writer-init-r${ROUND}-task${N}" "${WORKTREE_PATH}/WRITER_INIT.md"
tmux paste-buffer -d -r -b "writer-init-r${ROUND}-task${N}" -t "hyper-loop:w-task${N}"
tmux send-keys -t "hyper-loop:w-task${N}" Enter
```

### CLI 无人值守标志速查

| CLI | 标志 | 效果 |
|-----|------|------|
| **Claude Code** | `--dangerously-skip-permissions` | 跳过所有工具审批 |
| **Codex CLI** | `--full-auto` | 沙箱内自动执行（安全）|
| | `--dangerously-bypass-approvals-and-sandbox` | 跳过审批+沙箱（完全自主） |
| **Gemini CLI** | `--yolo` 或 `-y` | 自动批准所有操作 |

**规则**：
- Codex Writer 默认用 `--full-auto`（沙箱保护）
- 如果任务需要写文件到 worktree 外（如 Rust cargo），用 `--dangerously-bypass-approvals-and-sandbox`
- Gemini Reviewer 始终用 `--yolo`（它只读不写）
- Claude 子进程（如有）用 `--dangerously-skip-permissions`

### 已验证的 CLI / tmux 事实

- `codex --help` 没有 `--file`；HyperLoop 的实际做法是先启动 `codex --full-auto`，再用 `tmux load-buffer/paste-buffer` 把 `WRITER_INIT.md` 作为第一条消息送进去。
- `gemini --help` 没有 `--system-prompt`；HyperLoop 同样先启动 `gemini --yolo`，再用 `tmux load-buffer/paste-buffer` 注入 `REVIEWER_INIT.md`。
- `tmux pipe-pane` 正确语法是 `tmux pipe-pane [-IOo] [-t target-pane] [shell-command]`；不带 `-I/-O` 时默认把 pane 输出送进 `shell-command`。
- `tmux capture-pane` 默认只抓当前可见区域；要抓整段可访问历史，用 `-S -`。抓取上限受 pane 的 `history-limit` 限制，不受 `buffer-limit` 影响。当前机器 `history-limit=50000`，`buffer-limit=50` 只限制自动命名 paste buffer 的数量；显式命名的 buffer（例如 `reviewer-init`）不受这个 50 的淘汰规则影响。

Writer pane 在 Phase 1 按需创建（每个任务一个 worktree + pane）。

用户确认配置、契约、检查清单后锁定。

---

## Phase 1: 棘轮循环

**前置检查**：轮次/分数/元改进触发条件。

### Step 1: 问题拆解

Claude 分析当前问题清单，拆解为**独立子任务**（最多 50 个）：

```markdown
## Round N 任务拆解
### 修复目标：P0 — Gateway 不启动 + 扫描重复

拆解为独立子任务：
1. [TASK-N-1] Gateway 进程启动逻辑 → daemon/src/gateway.rs
2. [TASK-N-2] 扫描路径去重 → tauri-app/src-tauri/src/lib.rs
3. [TASK-N-3] Guardian 面板状态显示 → GuardianPanel.svelte

依赖关系：1→3（3 依赖 1 的状态枚举），2 独立
并行组：{1,2} 先跑，3 等 1 完成后跑
```

**拆解规则**：
- 同一个 P0/P1 可以拆成多个子任务并行修
- 但不同优先级的不混：有 P0 子任务就不创建 P2 子任务
- 每个子任务必须指定具体文件和行号范围
- 有依赖关系的标注清楚，按拓扑序执行

### Step 2: 为每个子任务创建 Worktree + Writer Pane

```bash
set -a
. _hyper-loop/project-config.env
set +a

# 为每个独立子任务创建 worktree
WORKTREE_BASE="/tmp/hyper-loop-worktrees"
ROUND_TASK_DIR="$PROJECT_ROOT/_hyper-loop/tasks/round-${ROUND}"
mkdir -p "$WORKTREE_BASE" "$ROUND_TASK_DIR"

# TASK-N-1: Gateway 修复
TASK_FILE="$ROUND_TASK_DIR/task1.md"
WORKTREE_PATH="$WORKTREE_BASE/task1"
BRANCH="hyper-loop/r${ROUND}-task1-gateway"
git worktree add "$WORKTREE_PATH" -b "$BRANCH"

# 写任务文件（包含完整上下文引用）
cat > "$TASK_FILE" << 'TASK'
## 修复任务: TASK-N-1 Gateway 进程启动

### 上下文
请先阅读 _hyper-loop-context/ 目录下的所有文档，特别是：
- CLAUDE.md（编码规范）
- PRD 中关于守护台的章节
- 架构文档中 daemon 部分
- contract.md（评估契约）

### 问题
[P0] Gateway 进程不启动。daemon 启动后不自动拉起 OpenClaw Gateway。

### 相关文件
- daemon/src/gateway.rs (line 45-120)
- daemon/src/main.rs (line 200-230)

### 期望行为（摘自设计文档）
"daemon 启动后自动检测 OpenClaw 安装状态，如已安装则拉起 Gateway 进程..."

### 当前行为
Guardian 面板显示"异常"，无具体原因。Gateway 进程未启动。

### 约束
- 只修 Gateway 启动逻辑
- 不改 CSS
- 不重构不相关代码
- Tauri invoke 参数必须 camelCase
TASK

# 渲染当前 task 专属的 WRITER_INIT.md（复用 Phase 0 的 render_template）
export WORKTREE_PATH
export TASK_DESCRIPTION="$(cat "$TASK_FILE")"
render_template "$TEMPLATE_DIR/WRITER_INIT.md" "$WORKTREE_PATH/WRITER_INIT.md"

# 复制上下文包到 worktree（让 Codex 能读到）
cp -r _hyper-loop/context "$WORKTREE_PATH/_hyper-loop-context"

# 创建 tmux pane 并启动常驻 Codex 进程
tmux new-window -t hyper-loop -n "w-task1"
tmux pipe-pane -o -t hyper-loop:w-task1 "cat >> '$LOG_DIR/codex-writer-r${ROUND}-task1.log'"

# 启动 Codex 常驻交互模式（bypass 模式，不卡审批）
# Tauri 项目需要写 Rust 文件，必须用完全 bypass
tmux send-keys -t hyper-loop:w-task1 \
  "cd $WORKTREE_PATH && codex --dangerously-bypass-approvals-and-sandbox" Enter
sleep 2
tmux load-buffer -b "writer-init-r${ROUND}-task1" "$WORKTREE_PATH/WRITER_INIT.md"
tmux paste-buffer -d -r -b "writer-init-r${ROUND}-task1" -t hyper-loop:w-task1
tmux send-keys -t hyper-loop:w-task1 Enter
```

**对每个独立子任务重复上述步骤**（并行的一起创建）。
如果是 `--resume`，先重新加载 `_hyper-loop/project-config.env` 并重新定义 `render_template` / `TEMPLATE_DIR` / `LOG_DIR`，再继续本步骤。

### Step 3: 等待 Writers 完成

```bash
# Writer 完成协议：
# 1. 完成后不要退出 Codex CLI
# 2. 最后一行单独输出：HYPERLOOP_TASK_DONE
for task_id in 1 2 3; do
  LOG_FILE="$LOG_DIR/codex-writer-r${ROUND}-task${task_id}.log"
  while true; do
    if rg -q '^HYPERLOOP_TASK_DONE$' "$LOG_FILE" 2>/dev/null; then
      echo "task${task_id} completed"
      break
    fi
    if ! tmux list-panes -t "hyper-loop:w-task${task_id}" >/dev/null 2>&1; then
      echo "w-task${task_id} exited unexpectedly" >&2
      break
    fi
    sleep 10
  done
done
```

### Step 4: 收集 + 合并修改

```bash
BASE_SHA=$(git rev-parse HEAD)
INTEGRATION_BRANCH="hyper-loop/r${ROUND}-integration"
INTEGRATION_WT="$WORKTREE_BASE/integration-r${ROUND}"
SUMMARY_FILE="$ROUND_TASK_DIR/all-diffs.txt"
OVERLAP_FILE="$ROUND_TASK_DIR/overlap-files.txt"
CONFLICT_FILE="$ROUND_TASK_DIR/conflicts.md"

: > "$SUMMARY_FILE"
: > "$CONFLICT_FILE"
git worktree add "$INTEGRATION_WT" -b "$INTEGRATION_BRANCH" "$BASE_SHA"

# 从每个 worktree 收集 diff
for wt in "$WORKTREE_BASE"/task*; do
  TASK_NAME=$(basename "$wt")
  git -C "$wt" diff HEAD > "$ROUND_TASK_DIR/${TASK_NAME}.patch"
  {
    echo "=== $TASK_NAME ==="
    git -C "$wt" diff --stat
    echo
  } >> "$SUMMARY_FILE"
  git -C "$wt" diff --name-only HEAD | sort -u > "$ROUND_TASK_DIR/${TASK_NAME}.files"
done

find "$ROUND_TASK_DIR" -maxdepth 1 -type f -name 'task*.files' | sort | while read -r file; do
  cat "$file"
done | sort | uniq -d > "$OVERLAP_FILE"

# Claude 审查每个 diff：
# - 是否只改了任务指定的文件？
# - 有没有偷改 CSS？
# - 有没有碰重叠文件？

# 只把无重叠、无冲突的分支合并到 integration worktree。
# 主分支在本步骤保持干净，不提前落 merge commit。
for wt in "$WORKTREE_BASE"/task*; do
  TASK_NAME=$(basename "$wt")
  BRANCH=$(git -C "$wt" branch --show-current)
  if [ -s "$OVERLAP_FILE" ] && rg -qxFf "$OVERLAP_FILE" "$ROUND_TASK_DIR/${TASK_NAME}.files"; then
    printf '%s\tDEFERRED_SAME_FILE\n' "$TASK_NAME" >> "$CONFLICT_FILE"
    continue
  fi
  if ! git -C "$INTEGRATION_WT" merge "$BRANCH" --no-ff --no-edit; then
    git -C "$INTEGRATION_WT" merge --abort
    printf '%s\tMERGE_CONFLICT\n' "$TASK_NAME" >> "$CONFLICT_FILE"
  fi
done
```

`conflicts.md` 里出现的任务不自动硬解冲突，而是带着对应 patch 留到下一轮串行处理。这样能保住并行收益，同时避免主分支被半成品 merge 污染。

### Step 5: 构建并启动

```bash
cd "$INTEGRATION_WT"
eval "$CACHE_CLEAN"
eval "$BUILD_CMD"
eval "$BUILD_VERIFY"
pkill -f "$WINDOW_NAME" 2>/dev/null || true
sleep 1
eval "$LAUNCH_CMD"
sleep 3
```

### Step 6: 多模态感知（Claude）

- Peekaboo 截图 → 审视 → rm
- 功能检查清单逐项验证
- 收集客观数据（errors、flow pass/fail）

### Step 7: 双重独立评分

**Claude 评分**（基于 Step 6 的感知数据）

**Gemini 评分**（通过常驻 reviewer pane）：

```bash
REVIEW_FILE="$ROUND_TASK_DIR/review-round-${ROUND}.md"

# 准备评审材料
{
  echo "## 评审请求 Round $ROUND"
  echo
  echo "### 本轮修改汇总"
  cat "$SUMMARY_FILE"
  echo
  echo "### 详细 diff"
  find "$ROUND_TASK_DIR" -maxdepth 1 -type f -name '*.patch' | sort | while read -r patch; do
    cat "$patch"
    echo
  done
  echo
  echo "### 截图观察（Claude 的感知记录）"
  echo "[Claude 的视觉观察文字描述，不含评分]"
  echo
  echo "### 客观数据"
  echo "- Console 错误数：N"
  echo "- 构建验证：pass/fail"
  echo "- E2E 流程：pass/fail"
  echo
  echo "### 请按评估契约打分，只输出一个 JSON 对象，不要代码块"
} > "$REVIEW_FILE"

# 发送给常驻 Gemini（用 tmux buffer 粘贴多行文本，避免 send-keys 被长文本/换行打断）
tmux load-buffer -b "review-r${ROUND}" "$REVIEW_FILE"
tmux paste-buffer -d -r -b "review-r${ROUND}" -t hyper-loop:reviewer
tmux send-keys -t hyper-loop:reviewer Enter

# 等待并读取 Gemini 输出
sleep 30  # Gemini 思考时间
tmux capture-pane -t hyper-loop:reviewer -p -S - > "$ROUND_TASK_DIR/reviewer-pane.txt"
python3 - "$ROUND_TASK_DIR/reviewer-pane.txt" <<'PY'
from pathlib import Path
import json
import sys

text = Path(sys.argv[1]).read_text()
decoder = json.JSONDecoder()
last = None
for i, ch in enumerate(text):
    if ch != "{":
        continue
    try:
        obj, end = decoder.raw_decode(text[i:])
    except Exception:
        continue
    last = obj
if last is None:
    raise SystemExit("Gemini 输出里没有可解析 JSON")
print(json.dumps(last, ensure_ascii=False, indent=2))
PY
```

**合成最终分** = min(Claude, Gemini)。差异 > 2 分问用户。

### Step 8: 决策

```bash
if [ "$FINAL_SCORE_IMPROVED" = "1" ]; then
  git -C "$PROJECT_ROOT" merge --no-ff "$INTEGRATION_BRANCH" \
    -m "hyper-loop R${ROUND}: ${FIX_TYPE} — ${FIX_SUMMARY} [codex×${WRITER_COUNT}]"
  printf '%s\t%s\t%s\tKEPT\n' "$ROUND" "$FINAL_SCORE" "$FIX_TYPE" >> "$PROJECT_ROOT/_hyper-loop/results.tsv"
else
  printf '%s\t%s\t%s\tREJECTED\n' "$ROUND" "$FINAL_SCORE" "$FIX_TYPE" >> "$PROJECT_ROOT/_hyper-loop/results.tsv"
fi
```

因为所有 writer 分支都先合到 `integration worktree`，拒绝本轮时无需回滚主分支，直接丢弃 integration worktree 即可。

### Step 9: 清理 Worktrees

```bash
# 先关掉本轮 writer window，避免 worktree 被占用
tmux list-windows -t hyper-loop -F '#{window_name}' | rg '^w-task' | while read -r window; do
  tmux kill-window -t "hyper-loop:${window}" 2>/dev/null || true
done

# 删除本轮 worktrees（含 integration worktree）
for wt in "$WORKTREE_BASE"/task* "$INTEGRATION_WT"; do
  [ -d "$wt" ] || continue
  BRANCH=$(git -C "$wt" branch --show-current 2>/dev/null || true)
  git worktree remove "$wt" --force
  [ -n "$BRANCH" ] && git -C "$PROJECT_ROOT" branch -D "$BRANCH"
done
```

### Step 10: 终止检查

综合分 ≥ 阈值 / 轮次 ≥ max / 连续无提升 → Phase 2 或 Phase 3。
否则回到 Step 1。

---

## Phase 2: 元改进

### 触发条件（满足任一条就进入 Phase 2）

1. 每完成 3 轮常规循环，固定做一次元检查
2. 连续 2 轮综合分无提升，或提升 ≤ 0.2 分
3. 连续 3 轮 `fix_type=VISUAL`
4. 同一轮出现 `DEFERRED_SAME_FILE` 或 `MERGE_CONFLICT`
5. Gemini 连续 2 轮没有引用功能清单或设计文档中的具体条目
6. Writer 连续 2 轮产出与设计文档直接矛盾

### 执行步骤

1. 暂停新一轮任务分发，保留 `_hyper-loop/results.tsv`、`_hyper-loop/tasks/round-${ROUND}/`、`$LOG_DIR/`。
2. 只诊断一个主因，并写入 `_hyper-loop/meta-playbook.md`：
   - `trigger`: 触发条件
   - `hypothesis`: 为什么失败
   - `single_change`: 下轮只改哪一个元变量
   - `expected_metric`: 期望改善的指标
   - `abort_condition`: 看到什么信号就撤销这次元改进
3. 一次只允许改一个元变量：
   - `MAX_WRITERS`: 50 → 10 / 1
   - `CONTEXT_SCOPE`: 全量文档 → 摘要 + 关键章节
   - `TASK_GRANULARITY`: 大任务 → 更小的文件级任务
   - `REVIEWER_RULE`: 要求 Gemini 引用 checklist / 设计文档条目
4. 如果改的是上下文或评审规则：
   - 重新渲染 `REVIEWER_INIT.md`
   - 下一轮重新渲染每个 `WRITER_INIT.md`
   - 重启受影响的 tmux pane
5. 如果改的是并行度或任务粒度：
   - 不动 reviewer
   - 只调整下一轮的 worktree 数量和任务拆分方式
6. 元改进后的下一轮必须在 `results.tsv` 追加 `meta_change` 字段，明确记录只变了哪一个变量。
7. 如果实验轮仍无提升，恢复上一个元变量配置并暂停自动元改进，转为用户裁决。

---

## Phase 3: 结果归档

```markdown
## HyperLoop v4 报告
- 功能：[目标]
- 总轮次：N
- 并行 Writers 最大数：M
- 总 Worktrees 创建数：K
- 起始分：X → 最终分：Y
- FUNC/VISUAL 比例：X/Y
- 功能完整性：X% → Y%
- 未完成 P0/P1：[列出]
- Claude vs Gemini 评分趋势
- Writer 审计：每个 Codex 的修改摘要
```

```bash
# 清理
tmux kill-session -t hyper-loop 2>/dev/null
rm -rf "$WORKTREE_BASE"
```

---

## 使用方式

```bash
/hyper-loop                            # 完整流程
/hyper-loop 安装向导 --max-rounds 5     # 指定目标
/hyper-loop --resume                    # 恢复
/hyper-loop --max-writers 10            # 限制并行数
```

### 前置条件

```bash
codex --version    # Codex CLI
gemini --version   # Gemini CLI
tmux -V            # tmux
git worktree list  # git worktree 支持
```

降级模式：
- 无 Codex → Claude 自写（标注降级风险，主观上限降为 5.0）
- 无 Gemini → 只有 Claude 评分（主观上限降为 6.0）
- 无 tmux → 串行执行，无并行

---

## 持久化文件

```
_hyper-loop/
├── context/                 # 上下文包（每次启动重建）
│   ├── CLAUDE.md
│   ├── PRD.md
│   ├── architecture.md
│   ├── design-*.md
│   ├── contract.md
│   ├── checklist.md
│   ├── REVIEWER_INIT.md     # Reviewer 初始化提示词（模板渲染产物）
│   └── ORCHESTRATOR_CHECKLIST.md
├── project-config.env       # Phase 0 锁定的项目配置
├── contract.md              # 评估契约
├── checklist.md             # 功能检查清单
├── results.tsv              # 每轮评分
├── meta-playbook.md         # 元改进策略
├── logs/
│   └── YYYYMMDD-HHMMSS/
│       ├── orchestrator.log
│       ├── gemini-reviewer.log
│       └── codex-writer-rN-taskN.log
├── tasks/                   # 每轮任务拆解
│   └── round-N/
│       ├── task1.md
│       ├── task2.md
│       ├── task1.patch
│       ├── all-diffs.txt
│       ├── conflicts.md
│       └── ...
└── reports/
    └── YYYY-MM-DD-功能名.md
```

---

## 铁律

### 上下文纪律（v4 新增，最高优先级）
1. **Writer 启动前必须注入上下文包**：CLAUDE.md + PRD + 架构 + 设计 + 契约
2. **Reviewer 启动前必须注入评审上下文**：PRD + 架构 + 设计 + 契约 + 清单
3. **每个 Writer 在独立 Worktree 中工作**：禁止在主目录直接改代码
4. **进程常驻**：Writer 和 Reviewer 是交互式会话，不是一次性命令
5. **上下文包每次启动重建**：不用旧缓存，从源文档重新收集

### 角色分离
6. **Claude 不写业务代码**：编排、感知、评分、决策
7. **Codex 不评分**：只写代码
8. **Gemini 不写代码**：只评审
9. **最终分 = min(Claude, Gemini)**
10. **差异 > 2 分须用户裁决**

### 功能优先级
11. **P0→P1→P2→P3 严格顺序**
12. **前 5 轮必须 FUNC**
13. **连续 3 个 VISUAL 触发元改进**

### 评分纪律
14. **主观分上限 7.0**（用户确认前）
15. **客观指标权重 80%**
16. **功能清单来自设计文档**

### 操作安全
17. **Peekaboo 截图读完即 rm**
18. **构建前清缓存，构建后重启 App**
19. **拒绝轮次不回滚主分支**：直接丢弃 integration worktree
20. **Worktree 用完即删**
21. **架构级问题暂停循环**

---

## v3 → v4 变化

| 维度 | v3 | v4 |
|------|----|----|
| Writer 上下文 | 一句话任务描述 | BMAD 全套文档 + WRITER_INIT 模板 |
| Writer 进程 | 一次性命令 | 常驻交互式会话 |
| Writer 隔离 | 同一目录 | 每个任务独立 worktree |
| 并行度 | 1 个 writer | 最多 50 个并行 writer |
| Reviewer 上下文 | diff + 评估契约 | PRD + 架构 + 设计 + 契约 + 清单 |
| Reviewer 进程 | 一次性命令 | 常驻交互式会话 |
| 任务粒度 | 1 轮 = 1 个修复 | 1 轮 = N 个并行子任务 |
