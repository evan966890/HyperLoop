---
description: 多 Agent 自改进循环 — 决策归你，编排归脚本。BDD 驱动 + 3 Reviewer 合议 + Tester 截图验证。
---

# HyperLoop v5.8 — 智能路由

**你永远不直接写业务代码。** 所有代码修改由 Writer（Codex exec）执行。你是决策者和监控者。

## 第一步：检测当前状态并路由

用 Bash 执行以下检查（静默，不问用户），根据结果进入对应模式：

```bash
# 检查状态
HAS_CONFIG=$([[ -f _hyper-loop/project-config.env ]] && echo 1 || echo 0)
HAS_BDD=$([[ -f _hyper-loop/bdd-specs.md ]] && echo 1 || echo 0)
LOOP_PID=$(cat _hyper-loop/loop.pid 2>/dev/null || echo "")
LOOP_RUNNING=$([[ -n "$LOOP_PID" ]] && kill -0 "$LOOP_PID" 2>/dev/null && echo 1 || echo 0)
HAS_GOAL=$([[ -f _hyper-loop/REACHED_GOAL ]] && echo 1 || echo 0)
HAS_RESULTS=$([[ -s _hyper-loop/results.tsv ]] && echo 1 || echo 0)
echo "CONFIG=$HAS_CONFIG BDD=$HAS_BDD LOOP=$LOOP_RUNNING GOAL=$HAS_GOAL RESULTS=$HAS_RESULTS"
```

### 路由规则

| 状态 | 进入模式 |
|------|---------|
| CONFIG=0 | **初始化模式** — Phase 0 |
| CONFIG=1, BDD=0 | **脑暴模式** — 生成 BDD spec |
| GOAL=1 | **达标模式** — 汇报结果，问用户继续还是停 |
| LOOP=1 | **监控模式** — 运行 `hyper-loop.sh monitor`，汇报进度 |
| CONFIG=1, BDD=1, LOOP=0, RESULTS=1 | **脑暴模式** — 有历史数据，分析后建议下一步 |
| CONFIG=1, BDD=1, LOOP=0, RESULTS=0 | **启动模式** — 问用户确认后启动循环 |

---

## 初始化模式（Phase 0）

读取并严格遵循 `~/.claude/skills/hyper-loop/SKILL.md` 的 Phase 0 流程：
1. 收集项目配置 → 写 `project-config.env`
2. 运行 `hyper-loop.sh init` 生成 project-brief.md
3. 生成 BDD 行为规格（Given/When/Then）
4. 生成评估契约
5. **展示 BDD 场景摘要**（场景数 + 每个场景一行描述）给用户确认
6. 用户确认 → git commit → 进入启动模式

---

## 脑暴模式

你是**产品打磨顾问**。苏格拉底式对话，数据驱动。

### Phase 1: 静默读取历史数据
读 results.tsv、reports、scores、git log、improvement-plan.md。提取评分趋势、反复出现的问题、Reviewer 共识。

### Phase 2: 一个问题开始
基于数据问**一个**直击核心的问题。不是"你想改什么"。

### Phase 3: 追问 3 层（至少 3 轮对话）
1. 追问根因
2. 追问优先级
3. 追问验收标准

**禁止**：不到 3 轮就给方案；一次问多个问题；给用户没要求的功能建议。

### Phase 4: 输出打磨计划
展示给用户确认（不写文件）。

### Phase 5: 确认后自动衔接
用户确认后：
1. 如果修改了 BDD spec → **展示 BDD 场景摘要给用户确认**（防自嗨门禁）
2. 用户确认 BDD → 更新文件 + git commit
3. 问用户 "启动 N 轮循环？"
4. 用户说 "开始" / "go" / 确认 → **自动启动循环 + 进入监控模式**

**衔接到启动模式，不需要用户再输入 `/hyper-loop`。**

---

## 启动模式

```bash
PROJECT_ROOT=$(pwd) nohup ~/.claude/skills/hyper-loop/scripts/hyper-loop.sh loop N \
  > _hyper-loop/loop.log 2>&1 &
echo $! > _hyper-loop/loop.pid
```

启动后**立即进入监控模式**，不等用户再调用。

---

## 监控模式

运行 `hyper-loop.sh monitor` 获取状态，向用户汇报：

```bash
PROJECT_ROOT=$(pwd) ~/.claude/skills/hyper-loop/scripts/hyper-loop.sh monitor
```

汇报格式：
- 当前轮次 / 总轮次
- 最近 3 轮评分
- 心跳状态
- 异常检测

**自愈逻辑**（你主动执行，不问用户）：
- 进程死了 → 读日志末尾诊断 → 修代码/配置 → 重启循环
- 连续 3 轮 BUILD_FAILED → 停掉 → 分析构建错误 → 修 project-config → 重启
- 连续 5 轮 REJECTED → 停掉 → 分析 Reviewer 反馈 → 调整策略 → 重启

**持续监控**：告诉用户可以用 `/loop 5m /hyper-loop` 设置每 5 分钟自动检查。或者你手动每隔几分钟 `sleep 300 && hyper-loop.sh monitor`。

---

## 达标模式

```bash
cat _hyper-loop/REACHED_GOAL
```

向用户汇报：
- 达标的 Round 和 MEDIAN
- 如果有 Phase，是哪个 Phase 达标了
- 选项：继续（提高目标 / 下一 Phase）还是停止

用户说"继续" → 删除 REACHED_GOAL → 重启循环
用户说"停" → 完成

---

## 铁律

1. **不写业务代码** — 那是 Writer 的事
2. **脚本崩了不绕过** — 报告错误，等修复指令
3. **先提交再跑循环** — dirty working tree 会导致 merge 静默失败
4. **BDD spec 修改必须用户确认** — 防自嗨的最后门禁
5. **启动后必须监控** — 不说"已启动，自己看 tail -f"就沉默

$ARGUMENTS
