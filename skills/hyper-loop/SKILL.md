---
name: hyper-loop
description: "多 Agent 自改进循环 — 决策归你，编排归脚本。BDD 驱动 + 3 Reviewer 合议 + Tester 截图验证。"
tools: Read, Bash, Glob, Grep, Write, Agent, AskUserQuestion
---

# HyperLoop v5.5 — 决策归你，编排归脚本

## 核心原则

**Claude Code 只做决策，不做编排。** 进程管理、等待、评分收集全部由 `hyper-loop.sh` 脚本执行。

```
Claude Code 的职责：生成 BDD spec → 拆解任务 → 写任务文件 → 调用脚本 → 读结果做判断
hyper-loop.sh 的职责：启动 codex exec → 管理子进程 → 等待完成 → 收集评分 → 输出决策建议
```

**不可违反的规则：**
1. 传文件路径，不传文本内容
2. 不直接写业务代码（那是 Writer 的事）
3. **脚本崩了不绕过** — 报告错误给用户并等待修复指令。绝对不能说"这次我不依赖脚本"然后自己写代码
4. 不跳过 Tester 和 Reviewer（脚本强制执行）
5. 任务文件必须写到 `_hyper-loop/tasks/round-N/` 才能被脚本识别
6. **先提交再跑循环** — nohup 后台跑时 dirty working tree 会阻止 merge to main

---

## 已验证的架构（v5.5 实测数据）

### Agent 通信模式
| 角色 | 模式 | 命令 | 验证状态 |
|------|------|------|---------|
| Writer (Codex) | stdin 管道 | `cat prompt \| codex exec -C $WT -` | ✅ 4/4 并行合并 |
| Tester (Claude) | stdin 管道 | `echo prompt \| claude -p - --add-dir $DIR` | ✅ BDD 逐条验证 |
| Reviewer A (Gemini) | -p 参数 | `gemini -y -p "$(cat file)" --include-directories $DIR` | ✅ 真实评分 9.4 |
| Reviewer B (Claude) | stdin 管道 | `echo prompt \| claude -p - --add-dir $DIR` | ✅ 真实评分 9.0 |
| Reviewer C (Codex) | stdin 管道 | `cat file \| codex exec --full-auto -C $DIR -` | ✅ 真实评分 8.4 |

**关键教训：**
- Gemini 不读 stdin，必须用 `-p "$(cat file)"`
- Codex exec 用 `-` 读 stdin，用 `-C` 设工作目录
- Claude 用 `-p -` 读 stdin，用 `--add-dir` 加项目目录
- 所有 agent 用非交互管道模式，不用 tmux 交互

### 评估管道
- **P0 检测**：结构化计数 `### P0` headings + `| FAIL |` 表格项，不是子串匹配
- **和议**：3 Reviewer 中位数，veto < 4.0，分歧 > 2.0 需用户裁决
- **棘轮**：ACCEPTED 合并到 main，REJECTED 丢弃 integration 分支

### 多 Writer 并行
- 每个 Writer 独立 git worktree，互不影响
- 合并前 `rm -f DONE.json WRITER_INIT.md TASK.md _writer_prompt.md && rm -rf _ctx/` 防元数据冲突
- `audit_writer_diff` 检查越界修改（包括 untracked 文件）
- `build_app` 在 subshell 中执行，不污染父进程 cwd

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
WINDOW_NAME=""
DEV_SERVER_PORT=""
TECH_STACK="Tauri v2 + Svelte 5 + Rust + TypeScript"
EOF
```

### Step 2: 初始化项目上下文

```bash
PROJECT_ROOT=$(pwd) ~/.claude/skills/hyper-loop/scripts/hyper-loop.sh init
```

自动扫描 → Claude 提炼 ≤300 行 project-brief.md → 持久化到 `_hyper-loop/context/`。

### Step 3: 生成 BDD 行为规格

读设计文档，对每个功能点生成 Given/When/Then 格式。**这是你最重要的决策工作。**

- 每个功能 → 至少 2 个场景（正常 + 异常）
- 每个 Then = Tester 的一个验证点
- 写入 `_hyper-loop/bdd-specs.md` 并复制到 `_hyper-loop/context/`

### Step 4: 生成评估契约

写入 `_hyper-loop/contract.md` 并复制到 `_hyper-loop/context/`。

### Step 5: 确认并提交

展示 BDD 场景列表给用户确认。**用户确认后，git commit 所有 Phase 0 产出，确保 working tree 干净。**

---

## Phase 1: 启动循环

Phase 0 完成后，用 Bash 工具把脚本扔到后台：

```bash
PROJECT_ROOT=$(pwd) nohup ~/.claude/skills/hyper-loop/scripts/hyper-loop.sh loop 50 \
  > _hyper-loop/loop.log 2>&1 &
echo "HyperLoop 已在后台启动，PID: $!"
echo $! > _hyper-loop/loop.pid
```

**`loop N` = 再跑 N 轮**（不是跑到第 N 轮）。脚本自动从 results.tsv 恢复上次进度。

循环内容：auto_decompose → Writer (codex exec) → merge → build → Tester (claude -p) → 3 Reviewer → 和议 → keep/reset → 30s 冷却

告诉用户：
- **看进度：** `tail -f _hyper-loop/loop.log`
- **停止：** `touch _hyper-loop/STOP`
- **自动达标停止：** median >= 8.0
- **自动回退：** 连续 5 轮失败 → 回退最佳轮次
- **查看结果：** `cat _hyper-loop/results.tsv`

---

## Phase 2: 元改进

### 触发条件
1. 每 3 轮固定检查
2. 连续 2 轮中位数无提升
3. Tester 连续 2 轮报告同一 bug

### 做什么
分析 `results.tsv` + 试用报告 + 评分 JSON，诊断一个主因，调整一个变量。

---

## 调试优先级（从实战总结）

当循环跑不动时，**先查评估管道，再查 Writer 产出**：

1. `compute_verdict` Python 逻辑 — tester_p0 检测、veto 阈值
2. Reviewer prompt 送达 — agent 是否真的收到了 prompt
3. Tester 报告解析 — 报告格式是否匹配 verdict 预期
4. Writer 产出质量 — 最后才看

**教训：** 10 轮全 REJECTED 的根因是评估逻辑 bug，不是代码质量。修复 3 行评估代码 → 评分从 5.0 飙到 9.0。

---

## 已知陷阱

| 陷阱 | 根因 | 防御 |
|------|------|------|
| mktemp 后缀不兼容 | macOS 要求 X 在模板末尾 | 不加 `.md` 后缀 |
| Gemini 收不到 prompt | `-p ""` 不读 stdin | 用 `-p "$(cat file)"` |
| nohup merge 静默失败 | dirty working tree | 先 commit 再跑循环 |
| 元数据合并冲突 | DONE.json 等进入 git | merge 前 rm -f 清理 |
| P0 检测假阳性 | 子串匹配命中标题 | 结构化计数 `### P0` |
| loop N 语义混淆 | 原意"跑到第 N 轮" | 已改为"再跑 N 轮" |
| 前轮 MEDIAN 残留 | 循环变量未重置 | 每轮开头 MEDIAN=0 |

---

## CLI 速查

| CLI | bypass | 角色 |
|-----|--------|------|
| `codex exec --dangerously-bypass-approvals-and-sandbox -C $WT -` | stdin 管道 | Writer |
| `codex exec --full-auto -C $DIR -` | stdin 管道 | Reviewer C |
| `gemini -y -p "$(cat file)" --include-directories $DIR` | -p 参数 | Reviewer A |
| `claude --dangerously-skip-permissions -p - --add-dir $DIR` | stdin 管道 | Tester / Reviewer B |

---

## 文件结构

```
_hyper-loop/
├── project-config.env
├── bdd-specs.md
├── contract.md
├── results.tsv                 # 轮次\t中位数\t三个评分\t决策
├── context/                    # 所有 agent 读这里
│   ├── project-brief.md        # init 生成的项目简报
│   ├── bdd-specs.md
│   ├── contract.md
│   └── hyper-loop.sh           # 脚本副本供 agent 审查
├── tasks/round-N/
│   ├── task*.md                # auto_decompose 生成
│   ├── task*.patch, task*.stat # merge 时收集
│   ├── merge-count.txt         # 合并成功数
│   └── verdict.env             # 和议结果
├── reports/round-N-test.md     # Tester 报告
├── scores/round-N/*.json       # 3 Reviewer 评分
├── archive/round-N/            # 每轮快照（含 git-sha.txt）
├── logs/YYYYMMDD-HHMMSS/       # 完整对话日志
└── improvement-plan.md         # 改进日志
```

---

## 使用

### 方式 1: 无人值守循环（推荐）

```bash
/hyper-loop                     # Phase 0 → 确认 → commit
# 然后：
PROJECT_ROOT=$(pwd) nohup ~/.claude/skills/hyper-loop/scripts/hyper-loop.sh loop 50 \
  > _hyper-loop/loop.log 2>&1 &
```

### 方式 2: 手动单轮

```bash
# 1. 拆任务 → 写 task*.md
# 2. PROJECT_ROOT=$(pwd) ~/.claude/skills/hyper-loop/scripts/hyper-loop.sh round N
# 3. 读 verdict.env → 决策 → 下一轮
```

### 方式 3: 从历史最佳轮次重新开始

```bash
PROJECT_ROOT=$(pwd) ~/.claude/skills/hyper-loop/scripts/hyper-loop.sh resume-from 5
```
