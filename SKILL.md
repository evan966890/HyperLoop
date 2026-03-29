---
name: hyper-loop
description: "Multi-agent self-improving loop with full context injection. Writers (any CLI) write code in worktrees, Tester validates with real UI automation + screenshots, 3 Reviewers score independently with consensus mechanism, Orchestrator decides. Roles decoupled from LLMs."
tools: Read, Edit, Write, Bash, Glob, Grep, Agent, AskUserQuestion
---

# HyperLoop v5 — 角色解耦 · 合议评审 · 真人试用

## 版本演进

> v2: 同一个 Agent 自写自审 → 30 轮 CSS 自嗨
> v3: 角色分离了但 Codex 没上下文 → 写出来的代码不符合设计
> v4: 上下文注入解决了，但 CLI 命令全写错、heredoc 被 shell 吃掉、没有真人试用验证
> **v5: 角色与 LLM 解耦 · 3 Reviewer 合议 · Tester 独立角色 · CLI 参数实测验证 · 传文件路径不传文本**

---

## 铁律（所有 Phase 通用，违反即停）

### 上下文传递纪律（v5 最高优先级）

1. **传文件路径，不传文本内容** — 每个 agent 都能读文件，prompt 里给路径让它自己读。禁止通过 shell heredoc/send-keys 传大段文本（会被引号吃掉、被 shell 截断、被 tmux buffer 限制）
2. **上下文文件统一放 `_hyper-loop/context/`** — prompt 只需说"先读 `_hyper-loop/context/` 下的所有 .md 文件"
3. **每个 Writer 在独立 worktree 工作** — 上下文包复制到 worktree 的 `_ctx/` 目录
4. **上下文包每次启动重建** — 从源文档重新收集，不用旧缓存

### 角色纪律

5. **角色与 LLM 解耦** — Writer/Reviewer/Tester 可以用任意 CLI（Claude/Codex/Gemini），按任务类型和能力选
6. **Orchestrator 不写业务代码** — 编排、决策、和议仲裁
7. **Writer 不评分** — 只写代码，写完退出
8. **Reviewer 不写代码** — 只评审，常驻跨轮
9. **Tester 不评分不写代码** — 只操作 App、截图、生成试用报告

### 评审纪律

10. **3 个 Reviewer 独立评分，取中位数** — 用不同 LLM 保证独立性
11. **任意 Reviewer 分 < 4.0 触发一票否决** — 不管中位数多高
12. **Tester 报告的 P0 bug 一票否决** — 不管分数多高
13. **差异 > 2 分须用户裁决**
14. **主观分上限 7.0**（用户确认前）
15. **客观指标权重 80%**

### 功能优先级

16. **P0→P1→P2→P3 严格顺序**
17. **前 5 轮必须 FUNC**
18. **连续 3 个 VISUAL 触发元改进**

### 操作安全

19. **截图保留不删** — `_hyper-loop/screenshots/round-N/` 是证据链
20. **构建前清缓存，构建后重启 App**
21. **拒绝轮次不回滚主分支** — 直接丢弃 integration worktree
22. **Worktree 用完即删**
23. **架构级问题暂停循环**

---

## 架构

```
┌──────────────────────────────────────────────────────────────┐
│ ORCHESTRATOR (Claude Code 主会话)                              │
│ 职责：对齐→拆任务→分发→收集→和议→决策                          │
│ 禁止：写业务代码、自己给最终分                                  │
├──────────────────────────────────────────────────────────────┤
│                                                              │
│  常驻角色（跨轮记忆，tmux 交互式会话）                           │
│  ├── Tester      (任意LLM) — 模拟真人试用，截图取证，维护测试集  │
│  ├── Reviewer A  (Gemini)  — 独立评分                          │
│  ├── Reviewer B  (Claude)  — 独立评分                          │
│  └── Reviewer C  (Codex)   — 独立评分                          │
│                                                              │
│  一次性角色（任务完成即退出，每个在独立 worktree）                │
│  ├── Writer-1 (任意LLM) — 按 blast radius 拆分的子任务         │
│  ├── Writer-2 (任意LLM) — 每个 Writer 5 分钟内应完成            │
│  └── Writer-N ...合理并行数 5-8 个                             │
│                                                              │
│  和议机制                                                      │
│  ├── 3 个 Reviewer 独立打分（用不同 LLM 保证独立性）            │
│  ├── Tester 提供截图证据 + 试用报告（客观事实，不打分）          │
│  ├── 最终分 = 中位数（3 个分中间那个）                          │
│  ├── 任意一个 < 4.0 → 一票否决                                │
│  ├── 任意两个差 > 2 分 → 用户裁决                              │
│  └── Tester 报告 P0 bug → 一票否决（不管分数多高）             │
│                                                              │
├──────────────────────────────────────────────────────────────┤
│ 数据流                                                        │
│                                                              │
│  Orchestrator → Writer: worktree 里的 TASK.md 路径              │
│  Writer → git: diff 留在 worktree，写 DONE.json 后退出         │
│  Orchestrator → merge: squash merge 到 integration worktree    │
│  Orchestrator → build+launch: 构建并启动 App                   │
│  Orchestrator → Tester: "App 已启动，去试用"                    │
│  Tester → screenshots/: 截图证据链                             │
│  Tester → reports/: 试用报告（事实，不含评分）                   │
│  Orchestrator → 3 Reviewers: "读试用报告+截图+diff，打分"       │
│  3 Reviewers → scores/: 各自独立评分 JSON                      │
│  Orchestrator: 和议 → 决策 → merge 到 main 或丢弃              │
└──────────────────────────────────────────────────────────────┘
```

---

## CLI 参数速查（实测验证 2026-03-29）

### 核心原则

**不在 shell 里传文本。每个 agent 都能读文件。把文件路径给它，让它自己读。**

### 启动方式

常驻角色用 tmux 交互模式启动，通过 `tmux load-buffer` + `paste-buffer` 注入初始化 prompt（文件路径引用）。

一次性 Writer 同样在 tmux window 中启动交互模式，注入任务后等待 DONE.json 完成信号。

| CLI | 启动命令 | bypass 标志 | 传上下文方式 |
|-----|---------|-------------|-------------|
| **Codex CLI** | `codex --full-auto` | `--full-auto`（沙箱内安全）或 `--dangerously-bypass-approvals-and-sandbox`（写 worktree 外文件时用） | prompt 中写"先读 `_ctx/` 目录下所有文件" |
| **Gemini CLI** | `gemini --yolo` | `--yolo` 或 `-y` | prompt 中写"先读 `_ctx/REVIEWER_INIT.md`" |
| **Claude Code** | `claude --dangerously-skip-permissions` | `--dangerously-skip-permissions` | prompt 中写"先读 `_ctx/` 目录" 或用 `--add-dir` |

### 已验证的事实

- `codex --help` 没有 `--file` 参数。注入 prompt 的方式是先启动 `codex --full-auto`，再用 `tmux load-buffer` / `paste-buffer` 把初始化文件作为第一条消息送进去。
- `gemini --help` 没有 `--system-prompt` 参数。同样用 `tmux load-buffer` / `paste-buffer` 注入。
- Claude Code 有 `--system-prompt` 参数（可用），也有 `--add-dir` 给子进程读目录权限。
- `tmux pipe-pane -o` 把 pane 输出送进 shell-command 做日志记录。
- `tmux capture-pane -S -` 抓全部可访问历史，受 `history-limit` 限制（当前 50000）。
- 显式命名的 tmux buffer（如 `load-buffer -b myname`）不受 `buffer-limit=50` 淘汰规则影响。

### 规则

- Codex Writer 在 Tauri 项目中需要写 Rust 文件，用 `--dangerously-bypass-approvals-and-sandbox`
- Gemini Reviewer 只读不写，`--yolo` 够了
- Claude 子进程用 `--dangerously-skip-permissions`

---

## 初始化文档模板

模板在 `~/.claude/skills/hyper-loop/templates/` 下：

| 文件 | 给谁 | 内容 |
|------|------|------|
| `WRITER_INIT.md` | 一次性 Writer | 角色定义 + 项目概览 + "先读 `_ctx/` 下所有文件" + 任务描述 + 完成协议 |
| `REVIEWER_INIT.md` | 常驻 Reviewer | 角色定义 + "先读 `_ctx/` 下的 PRD/架构/设计/契约" + 评分规则 + JSON 输出格式 |
| `TESTER_INIT.md` | 常驻 Tester | 角色定义 + 测试工具用法 + 截图保存规则 + 试用报告格式 |
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
- App 窗口名（Peekaboo/cliclick 用）
- 测试模式：[packaged-app / dev-server]
- 前端 dev server 端口：[如 1420]
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
TEST_MODE="dev-server"
DEV_SERVER_PORT="1420"
TECH_STACK="Tauri v2 + Svelte 5 + Rust + TypeScript"
EOF
```

### Step B: 问用户三个问题

Q1: 试用什么？ Q2: 什么算成功？ Q3: 最担心什么？

### Step C: 收集 BMAD 全套文档，构建上下文包

```bash
CONTEXT_DIR="_hyper-loop/context"
mkdir -p "$CONTEXT_DIR"

cp CLAUDE.md "$CONTEXT_DIR/" 2>/dev/null

find _bmad-output/planning-artifacts -type f \( -iname "*prd*" \) 2>/dev/null | sort | head -3 | while read -r f; do
  cp "$f" "$CONTEXT_DIR/"
done

find _bmad-output/planning-artifacts -type f \( -iname "*architect*" -o -iname "*architecture*" \) 2>/dev/null | sort | head -3 | while read -r f; do
  cp "$f" "$CONTEXT_DIR/"
done

find docs/design -maxdepth 1 -type f -name "*.md" 2>/dev/null | sort | while read -r f; do
  cp "$f" "$CONTEXT_DIR/"
done

find _bmad-output/planning-artifacts -type f \( -iname "*ux*" -o -iname "*design*" \) 2>/dev/null | sort | head -3 | while read -r f; do
  cp "$f" "$CONTEXT_DIR/"
done

find _bmad-output/implementation-artifacts -type f -iname "*sprint*" 2>/dev/null | sort | head -1 | while read -r f; do
  cp "$f" "$CONTEXT_DIR/"
done
```

### Step D: 读取设计文档，生成功能检查清单

从上下文包中的设计文档提取功能点，生成 `_hyper-loop/checklist.md`，同时复制到 `_hyper-loop/context/checklist.md`。

### Step E: 生成评估契约

写入 `_hyper-loop/contract.md`，同时复制到 `_hyper-loop/context/contract.md`。

### Step F: 生成测试集框架

```bash
mkdir -p _hyper-loop/test-suites

cat > _hyper-loop/test-suites/smoke.md <<'SMOKE'
# 冒烟测试集（每轮必跑）
## 后台测试（不需要 UI）
- [ ] `cargo test` 全部通过
- [ ] `pnpm lint` 无错误
- [ ] `pnpm build` 成功

## 真人模拟测试（需要 UI + 截图）
- [ ] 启动 App → 首屏正常渲染（截图）
- [ ] 主要导航流程可走通（每步截图）
- [ ] 关键按钮可点击、有响应（截图）
SMOKE
```

### Step G: 渲染初始化模板

```bash
set -a
. _hyper-loop/project-config.env
set +a

TEMPLATE_DIR="$HOME/.claude/skills/hyper-loop/templates"
mkdir -p _hyper-loop/context _hyper-loop/tasks _hyper-loop/logs _hyper-loop/screenshots _hyper-loop/scores

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
import os, re, sys
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
render_template "$TEMPLATE_DIR/TESTER_INIT.md" "_hyper-loop/context/TESTER_INIT.md"
render_template "$TEMPLATE_DIR/ORCHESTRATOR_CHECKLIST.md" "_hyper-loop/context/ORCHESTRATOR_CHECKLIST.md"
```

### Step H: 初始化 tmux + 常驻角色

```bash
LOG_DIR="$PROJECT_ROOT/_hyper-loop/logs/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$LOG_DIR"

tmux new-session -d -s hyper-loop -n orchestrator
tmux pipe-pane -o -t hyper-loop:orchestrator "cat >> '$LOG_DIR/orchestrator.log'"

# Tester（常驻）
tmux new-window -t hyper-loop -n tester
tmux pipe-pane -o -t hyper-loop:tester "cat >> '$LOG_DIR/tester.log'"
tmux send-keys -t hyper-loop:tester "cd $PROJECT_ROOT && claude --dangerously-skip-permissions" Enter
sleep 3
tmux load-buffer -b tester-init "$PROJECT_ROOT/_hyper-loop/context/TESTER_INIT.md"
tmux paste-buffer -d -r -b tester-init -t hyper-loop:tester
tmux send-keys -t hyper-loop:tester Enter

# Reviewer A (Gemini)
tmux new-window -t hyper-loop -n reviewer-a
tmux pipe-pane -o -t hyper-loop:reviewer-a "cat >> '$LOG_DIR/reviewer-a-gemini.log'"
tmux send-keys -t hyper-loop:reviewer-a "cd $PROJECT_ROOT && gemini --yolo" Enter
sleep 2
tmux load-buffer -b reviewer-a-init "$PROJECT_ROOT/_hyper-loop/context/REVIEWER_INIT.md"
tmux paste-buffer -d -r -b reviewer-a-init -t hyper-loop:reviewer-a
tmux send-keys -t hyper-loop:reviewer-a Enter

# Reviewer B (Claude)
tmux new-window -t hyper-loop -n reviewer-b
tmux pipe-pane -o -t hyper-loop:reviewer-b "cat >> '$LOG_DIR/reviewer-b-claude.log'"
tmux send-keys -t hyper-loop:reviewer-b "cd $PROJECT_ROOT && claude --dangerously-skip-permissions" Enter
sleep 3
tmux load-buffer -b reviewer-b-init "$PROJECT_ROOT/_hyper-loop/context/REVIEWER_INIT.md"
tmux paste-buffer -d -r -b reviewer-b-init -t hyper-loop:reviewer-b
tmux send-keys -t hyper-loop:reviewer-b Enter

# Reviewer C (Codex)
tmux new-window -t hyper-loop -n reviewer-c
tmux pipe-pane -o -t hyper-loop:reviewer-c "cat >> '$LOG_DIR/reviewer-c-codex.log'"
tmux send-keys -t hyper-loop:reviewer-c "cd $PROJECT_ROOT && codex --full-auto" Enter
sleep 2
tmux load-buffer -b reviewer-c-init "$PROJECT_ROOT/_hyper-loop/context/REVIEWER_INIT.md"
tmux paste-buffer -d -r -b reviewer-c-init -t hyper-loop:reviewer-c
tmux send-keys -t hyper-loop:reviewer-c Enter
```

**常驻角色 context rot 管理：**

```bash
check_context_rot() {
  local PANE_NAME="$1"
  local LOG_FILE="$2"
  local LINE_COUNT
  LINE_COUNT=$(wc -l < "$LOG_FILE" 2>/dev/null || echo 0)
  if [ "$LINE_COUNT" -gt 3000 ]; then
    echo "WARNING: $PANE_NAME context approaching limit ($LINE_COUNT lines), restarting..."
    tmux kill-window -t "hyper-loop:$PANE_NAME" 2>/dev/null
    return 1
  fi
  return 0
}
```

用户确认配置、契约、检查清单后锁定。

---

## Phase 1: 棘轮循环

### Step 1: 问题拆解（Blast Radius 控制）

**拆解规则**：
- 合理并行数 **5-8 个**
- 每个子任务应 **5 分钟内可完成**
- 同一 P0/P1 可拆多个子任务并行修，不同优先级不混
- 每个子任务指定具体文件和行号范围
- **预先计算文件重叠** — 重叠文件多的任务不并行
- 有依赖关系按拓扑序执行

### Step 2: 为每个子任务创建 Worktree + Writer

```bash
WORKTREE_BASE="/tmp/hyper-loop-worktrees"

for TASK_ID in 1 2 3; do
  WORKTREE_PATH="$WORKTREE_BASE/task${TASK_ID}"
  BRANCH="hyper-loop/r${ROUND}-task${TASK_ID}"
  git worktree add "$WORKTREE_PATH" -b "$BRANCH"

  # 渲染 WRITER_INIT.md + 复制上下文
  cp -r _hyper-loop/context "$WORKTREE_PATH/_ctx"

  # 创建 tmux window
  tmux new-window -t hyper-loop -n "w-task${TASK_ID}"
  tmux pipe-pane -o -t "hyper-loop:w-task${TASK_ID}" "cat >> '$LOG_DIR/writer-r${ROUND}-task${TASK_ID}.log'"
  tmux send-keys -t "hyper-loop:w-task${TASK_ID}" \
    "cd $WORKTREE_PATH && codex --dangerously-bypass-approvals-and-sandbox" Enter
  sleep 2
  tmux load-buffer -b "w-init-${TASK_ID}" "$WORKTREE_PATH/WRITER_INIT.md"
  tmux paste-buffer -d -r -b "w-init-${TASK_ID}" -t "hyper-loop:w-task${TASK_ID}"
  tmux send-keys -t "hyper-loop:w-task${TASK_ID}" Enter
done
```

### Step 3: 等待 Writers 完成（fswatch 事件驱动）

```bash
for TASK_ID in 1 2 3; do
  (
    timeout 900 fswatch -1 "$WORKTREE_BASE/task${TASK_ID}/DONE.json" 2>/dev/null
    if [ $? -eq 124 ]; then
      echo '{"status":"timeout"}' > "$WORKTREE_BASE/task${TASK_ID}/DONE.json"
    fi
  ) &
done
wait
```

### Step 4: 收集 + 合并修改

```bash
INTEGRATION_BRANCH="hyper-loop/r${ROUND}-integration"
INTEGRATION_WT="$WORKTREE_BASE/integration-r${ROUND}"
git worktree add "$INTEGRATION_WT" -b "$INTEGRATION_BRANCH" "$(git rev-parse HEAD)"

for wt in "$WORKTREE_BASE"/task*; do
  TASK_NAME=$(basename "$wt")
  STATUS=$(python3 -c "import json; print(json.load(open('$wt/DONE.json'))['status'])" 2>/dev/null || echo "unknown")
  [ "$STATUS" = "done" ] || continue
  BRANCH=$(git -C "$wt" branch --show-current)
  if ! git -C "$INTEGRATION_WT" merge "$BRANCH" --squash --no-edit; then
    git -C "$INTEGRATION_WT" merge --abort
  else
    git -C "$INTEGRATION_WT" commit --no-edit -m "hyper-loop R${ROUND} ${TASK_NAME}" 2>/dev/null
  fi
done
```

### Step 5: 构建并启动

```bash
cd "$INTEGRATION_WT"
eval "$CACHE_CLEAN" && eval "$BUILD_CMD" && eval "$BUILD_VERIFY"
pkill -f "$WINDOW_NAME" 2>/dev/null; sleep 1; eval "$LAUNCH_CMD" &; sleep 5
```

### Step 6: Tester 真人模拟试用

```bash
SCREENSHOT_DIR="$PROJECT_ROOT/_hyper-loop/screenshots/round-${ROUND}"
REPORT_FILE="$PROJECT_ROOT/_hyper-loop/reports/round-${ROUND}-test.md"
mkdir -p "$SCREENSHOT_DIR"

# 构造试用请求文件
cat > "/tmp/hyper-loop-test-request-r${ROUND}.md" <<TESTREQ
App 已构建并启动。请执行试用：
1. 读 _hyper-loop/test-suites/smoke.md
2. 运行后台测试
3. 打开 App 执行真人模拟测试，每步截图到 $SCREENSHOT_DIR/
4. 写试用报告到 $REPORT_FILE
TESTREQ

tmux load-buffer -b "test-req-${ROUND}" "/tmp/hyper-loop-test-request-r${ROUND}.md"
tmux paste-buffer -d -r -b "test-req-${ROUND}" -t hyper-loop:tester
tmux send-keys -t hyper-loop:tester Enter

timeout 600 fswatch -1 "$REPORT_FILE" 2>/dev/null
```

### Step 7: 三方独立评分（合议制）

```bash
SCORES_DIR="$PROJECT_ROOT/_hyper-loop/scores/round-${ROUND}"
mkdir -p "$SCORES_DIR"

REVIEW_FILE="/tmp/hyper-loop-review-r${ROUND}.md"
cat > "$REVIEW_FILE" <<REVIEW
评审请求 Round $ROUND
- 试用报告: $REPORT_FILE
- 截图: $SCREENSHOT_DIR/
- 契约: _hyper-loop/context/contract.md
- 输出 JSON 到: $SCORES_DIR/你的角色名.json
REVIEW

for REVIEWER in reviewer-a reviewer-b reviewer-c; do
  tmux load-buffer -b "review-${ROUND}-${REVIEWER}" "$REVIEW_FILE"
  tmux paste-buffer -d -r -b "review-${ROUND}-${REVIEWER}" -t "hyper-loop:${REVIEWER}"
  tmux send-keys -t "hyper-loop:${REVIEWER}" Enter
done

for REVIEWER in reviewer-a reviewer-b reviewer-c; do
  timeout 300 fswatch -1 "$SCORES_DIR/${REVIEWER}.json" 2>/dev/null || true
done
```

### Step 8: 和议决策

```bash
SCORES=()
VETO=false

for SCORE_FILE in "$SCORES_DIR"/*.json; do
  SCORE=$(python3 -c "import json; print(json.load(open('$SCORE_FILE'))['score'])")
  SCORES+=("$SCORE")
  python3 -c "exit(0 if float('$SCORE') < 4.0 else 1)" && VETO=true
done

# Tester P0 一票否决
rg -q '"severity":\s*"P0"' "$REPORT_FILE" 2>/dev/null && VETO=true

MEDIAN=$(python3 -c "
scores = sorted([float(s) for s in '''${SCORES[*]}'''.split()])
n = len(scores)
print(scores[n//2] if n%2 else (scores[n//2-1]+scores[n//2])/2)
")

MAX_DIFF=$(python3 -c "
scores = [float(s) for s in '''${SCORES[*]}'''.split()]
print(max(scores) - min(scores))
")

if [ "$VETO" = true ]; then
  DECISION="REJECTED_VETO"
elif python3 -c "exit(0 if float('$MAX_DIFF') > 2.0 else 1)"; then
  DECISION="PENDING_USER"
elif python3 -c "exit(0 if float('$MEDIAN') > float('${PREV_MEDIAN:-0}') else 1)"; then
  DECISION="ACCEPTED"
else
  DECISION="REJECTED_NO_IMPROVEMENT"
fi

[ "$DECISION" = "ACCEPTED" ] && git merge --no-ff "$INTEGRATION_BRANCH" \
  -m "hyper-loop R${ROUND}: median=${MEDIAN}"

printf '%s\t%s\t%s\t%s\n' "$ROUND" "$MEDIAN" "${SCORES[*]}" "$DECISION" \
  >> _hyper-loop/results.tsv
```

### Step 9: 清理 Worktrees + context rot 检查

### Step 10: 终止检查 → Phase 2 或 Phase 3

---

## Phase 2: 元改进

### 触发条件（满足任一进入）
1. 每 3 轮固定检查
2. 连续 2 轮中位数无提升或 ≤ 0.2
3. 连续 3 轮 VISUAL
4. 同轮出现 MERGE_CONFLICT
5. Reviewer 连续 2 轮没引用功能清单
6. Writer 连续 2 轮与设计文档矛盾
7. Tester 连续 2 轮报告同一 bug

### 执行
1. 暂停任务分发
2. 只诊断一个主因 → 只改一个元变量
3. 可改的元变量：MAX_WRITERS / CONTEXT_SCOPE / TASK_GRANULARITY / REVIEWER_RULE / TESTER_SCOPE / WRITER_LLM
4. 记录到 `meta-playbook.md`
5. 实验轮仍无提升 → 恢复 + 用户裁决

---

## Phase 3: 结果归档

生成报告 → 清理 tmux → 清理 worktrees。

---

## 使用方式

```bash
/hyper-loop                            # 完整流程
/hyper-loop 安装向导 --max-rounds 5     # 指定目标
/hyper-loop --resume                    # 恢复
/hyper-loop --max-writers 5             # 限制并行数
```

---

## 持久化文件

```
_hyper-loop/
├── context/                     # 上下文包（每次重建）
├── project-config.env           # 项目配置
├── contract.md                  # 评估契约
├── checklist.md                 # 功能检查清单
├── results.tsv                  # 每轮评分
├── meta-playbook.md             # 元改进策略
├── test-suites/                 # 测试集
├── screenshots/round-N/         # 截图证据链
├── reports/round-N-test.md      # Tester 报告
├── scores/round-N/*.json        # 3 Reviewer 评分
├── logs/YYYYMMDD-HHMMSS/        # 全部会话日志
└── tasks/round-N/               # 任务文件+diff+patch
```

---

## 设计来源

| 来源 | 借鉴 |
|------|------|
| **Karpathy AutoResearch** | 棘轮循环、不可变评估者、results.tsv |
| **Meta HyperAgents** | 元认知自改进、策略进化 |
| **2026-03-29 教训** | 角色分离、双评取低分、FUNC/VISUAL 审计 |
| **司法制度** | 合议庭、回避制度、一票否决 |
| **Peekaboo + Playwright** | 三层测试：Playwright CDP > Peekaboo > AI 视觉 |
