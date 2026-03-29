---
name: hyper-loop
description: "Multi-agent self-improving loop. Claude does decisions (BDD specs, task decomposition, verdict interpretation), hyper-loop.sh does orchestration (tmux, writers, tester, reviewers, consensus). Roles decoupled from LLMs. SKILL.md self-evolves."
tools: Read, Bash, Glob, Grep, Write, Agent, AskUserQuestion
---

# HyperLoop v5.2 — 决策归你，编排归脚本

## 核心原则

**Claude Code 只做决策，不做编排。** 进程管理、等待、评分收集全部由 `hyper-loop.sh` 脚本执行。

```
Claude Code 的职责：生成 BDD spec → 拆解任务 → 写任务文件 → 调用脚本 → 读结果做判断
hyper-loop.sh 的职责：启动 tmux → 管理子进程 → 等待完成 → 收集评分 → 输出决策建议
```

**不可违反的规则：**
1. 传文件路径，不传文本内容
2. 不直接写业务代码（那是 Writer 的事）
3. 不跳过 Tester 和 Reviewer（脚本强制执行）
4. 任务文件必须写到 `_hyper-loop/tasks/round-N/` 才能被脚本识别

---

## Phase 0: 你的决策工作

### Step 1: 收集项目配置

问用户三个问题后，写 `_hyper-loop/project-config.env`：

```bash
mkdir -p _hyper-loop/context
cat > _hyper-loop/project-config.env <<'EOF'
PROJECT_ROOT="/absolute/path"
PROJECT_TYPE="Tauri"
BUILD_CMD="pnpm build"
LAUNCH_CMD="pnpm tauri dev"
CACHE_CLEAN="rm -rf node_modules/.vite dist target"
BUILD_VERIFY="pnpm tauri build"
WINDOW_NAME="ClawMom"
DEV_SERVER_PORT="1420"
TECH_STACK="Tauri v2 + Svelte 5 + Rust + TypeScript"
EOF
```

### Step 2: 收集上下文包

把 BMAD 文档复制到 `_hyper-loop/context/`：

```bash
cp CLAUDE.md _hyper-loop/context/
find _bmad-output -iname "*prd*" -exec cp {} _hyper-loop/context/ \;
find _bmad-output -iname "*architect*" -exec cp {} _hyper-loop/context/ \;
find docs/design -name "*.md" -exec cp {} _hyper-loop/context/ \;
```

### Step 3: 生成 BDD 行为规格

读设计文档，对每个功能点生成 Given/When/Then 格式。**这是你最重要的决策工作。**

规则：
- 每个功能 → 至少 2 个场景（正常 + 异常）
- 每个 Then = Tester 的一个截图验证点
- 覆盖所有用户路径分支
- 写入 `_hyper-loop/bdd-specs.md` 并复制到 `_hyper-loop/context/`

### Step 4: 生成评估契约

写入 `_hyper-loop/contract.md` 并复制到 `_hyper-loop/context/`。

### Step 5: 确认

展示 BDD 场景列表给用户确认。用户说 OK 后锁定。

---

## Phase 1: 每轮循环

### Step 1: 拆解任务（你的决策）

分析当前问题，拆成独立子任务。每个任务写成 `_hyper-loop/tasks/round-N/taskM.md`：

**拆解规则：**
- 5-8 个并行任务（不超过 8 个）
- 每个任务 5 分钟内可完成
- 指定具体文件和行号
- 预先检查文件重叠，重叠的不并行
- P0 优先，不混不同优先级

```markdown
## 修复任务: TASK-1

### 上下文
先读 _ctx/ 下所有文件。

### 问题
[P0] Gateway 不启动。

### 相关文件
- daemon/src/gateway.rs (line 45-120)

### 约束
- 只修 gateway.rs
- 不改 CSS

### 验收标准（引用 BDD）
场景 S012: Gateway 异常时显示红灯
```

### Step 2: 调用脚本

```bash
PROJECT_ROOT=$(pwd) ~/.claude/skills/hyper-loop/scripts/hyper-loop.sh round 1
```

**脚本自动执行（你不需要手动做）：**
1. 为每个 task*.md 创建 worktree + 启动 Codex Writer
2. 等待所有 Writer 完成（超时 15min）
3. Squash merge 到 integration 分支
4. 构建 App
5. 启动 Tester（Claude），按 BDD spec 截图验证
6. 启动 3 个 Reviewer（Gemini + Claude + Codex），独立评分
7. 和议计算：中位数 + 一票否决
8. 输出决策建议 + 清理 worktrees

### Step 3: 读结果，做判断

```bash
cat _hyper-loop/tasks/round-1/verdict.env
```

- `ACCEPTED` → `git merge --no-ff hyper-loop/r1-integration`
- `REJECTED_*` → 分析原因，调整任务，回到 Step 1
- `PENDING_USER` → 展示评分分歧给用户裁决

### Step 4: 下一轮

```bash
PROJECT_ROOT=$(pwd) ~/.claude/skills/hyper-loop/scripts/hyper-loop.sh round 2
```

---

## Phase 2: 元改进

### 触发条件
1. 每 3 轮固定检查
2. 连续 2 轮中位数无提升
3. 连续 3 轮只改 CSS
4. Tester 连续 2 轮报告同一 bug

### 你做什么
分析 `results.tsv` + 试用报告 + 评分 JSON，诊断一个主因，调整一个变量。

### SKILL.md 自修改（每 5 轮）
让 3 个 Reviewer 评审 SKILL.md 本身。经用户确认后修改。

---

## CLI 速查

| CLI | bypass | 角色 |
|-----|--------|------|
| `codex --dangerously-bypass-approvals-and-sandbox` | 完全自主 | Writer |
| `codex --full-auto` | 沙箱 | Reviewer C |
| `gemini --yolo` | 全自动 | Reviewer A |
| `claude --dangerously-skip-permissions` | 全自动 | Tester / Reviewer B |

---

## 文件结构

```
_hyper-loop/
├── project-config.env
├── bdd-specs.md
├── contract.md
├── results.tsv
├── context/                    # 所有 agent 读这里
├── tasks/round-N/
│   ├── task1.md, task2.md      # ← 你写的
│   ├── task1.patch, task1.stat # ← 脚本收集
│   └── verdict.env             # ← 脚本计算
├── screenshots/round-N/
├── reports/round-N-test.md
├── scores/round-N/*.json
├── summaries/
├── archive/round-N/
├── logs/YYYYMMDD-HHMMSS/
└── meta-playbook.md
```

---

## 使用

```bash
/hyper-loop                     # Phase 0 → Phase 1 循环
/hyper-loop --resume            # 恢复
```

Phase 0 完成后，每轮循环就是：
1. 你拆任务 → 写 task*.md
2. 跑 `hyper-loop.sh round N`
3. 读 verdict.env → 决策 → 下一轮
