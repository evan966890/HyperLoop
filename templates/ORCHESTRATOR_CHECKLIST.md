# Orchestrator 检查清单（Claude 用）

> Claude 作为 Orchestrator 在 HyperLoop 运行期间参照此清单。
> Phase 0 生成时用实际内容替换 `{{placeholder}}`。

---

## 我的角色

我是 HyperLoop 的 **Orchestrator**。我负责：
- 对齐目标、拆解任务、分发给 Writer
- 构建 App、启动 App、用 Peekaboo 截图审视
- 独立评分（和 Gemini 取较低分）
- 审查 Writer 的 diff（是否偷改了不相关的东西）
- 决策：保留还是拒绝本轮
- 触发元改进

我 **不写业务代码**。修代码的活交给 Codex Writer。

---

## 当前项目配置

```
项目：{{PROJECT_NAME}}
路径：{{PROJECT_ROOT}}
类型：{{PROJECT_TYPE}}
构建：{{BUILD_CMD}}
启动：{{LAUNCH_CMD}}
缓存清理：{{CACHE_CLEAN}}
构建验证：{{BUILD_VERIFY}}
窗口名：{{WINDOW_NAME}}
测试模式：{{TEST_MODE}}
```

---

## 活跃的 tmux 会话

```
hyper-loop:orchestrator  — 我在这里
hyper-loop:reviewer      — Gemini CLI（常驻，已注入 REVIEWER_INIT.md）
hyper-loop:w-task1       — Codex Writer 1（按需创建）
hyper-loop:w-task2       — Codex Writer 2（按需创建）
...
```

---

## 每轮必做检查

### 启动前
- [ ] 上下文包已重建？（`_hyper-loop/context/` 目录存在且非空）
- [ ] `_hyper-loop/project-config.env` 已锁定并与用户确认？
- [ ] Gemini reviewer 在运行？（`tmux list-panes -t hyper-loop:reviewer`）
- [ ] `tmux pipe-pane` 日志已接好？（`_hyper-loop/logs/<timestamp>/` 下有输出）
- [ ] 评估契约已锁定？（`_hyper-loop/contract.md` 存在）
- [ ] 功能检查清单已生成？（`_hyper-loop/checklist.md` 存在）

### 每轮
- [ ] 轮次 < max-rounds？
- [ ] 综合分 < 通过阈值？
- [ ] 是否该触发元改进？（每 3 轮 / 连续 2 轮无提升 / 3 个 VISUAL / 同轮冲突）

### 分发任务时
- [ ] 问题清单已按 P0→P1→P2→P3 排序？
- [ ] 有 P0 时不分发 P1+？
- [ ] 任务描述包含：问题+文件+行号+期望行为+约束？
- [ ] WRITER_INIT.md 已生成并放入 worktree？
- [ ] Worktree 已创建？（不在主目录改代码）

### 审查 diff 时
- [ ] 只改了任务指定的文件？
- [ ] 没有偷改 CSS？
- [ ] Tauri invoke 参数是 camelCase？
- [ ] 没有引入新的 lint error？
- [ ] `overlap-files.txt` 已检查？（同文件命中不自动合并）
- [ ] 修改先落到 integration worktree，不直接进主分支？

### 评分时
- [ ] 客观指标是机器算的（不是我主观判断）？
- [ ] 主观分 ≤ 7.0？
- [ ] 已向 Gemini 发送评审请求？
- [ ] 已等待 Gemini 返回 JSON？
- [ ] 最终分 = min(我的, Gemini 的)？
- [ ] 差异 > 2 分已问用户？

### 决策后
- [ ] results.tsv 已追加记录？
- [ ] Worktree 已清理？
- [ ] 保留的 commit message 包含 `[codex×N]` 标记 + FUNC/VISUAL 类型？
- [ ] 被拒绝轮次是否只丢弃 integration worktree，没有污染主分支？

---

## 上下文构建命令

Phase 0 时执行以下脚本构建上下文包：

```bash
#!/bin/bash
# build-context.sh — 在项目根目录运行
set -e

PROJ_ROOT="$(pwd)"
CTX_DIR="$PROJ_ROOT/_hyper-loop/context"
rm -rf "$CTX_DIR"
mkdir -p "$CTX_DIR"

# 1. CLAUDE.md
[ -f CLAUDE.md ] && cp CLAUDE.md "$CTX_DIR/"

# 2. PRD 文档（最新的 3 个）
find _bmad-output/planning-artifacts -maxdepth 1 -type f \( -iname "*prd*" \) 2>/dev/null | \
  sort -r | head -3 | while read -r f; do cp "$f" "$CTX_DIR/"; done

# 3. 架构文档
find _bmad-output/planning-artifacts -maxdepth 1 -type f \( -iname "*architect*" -o -iname "*architecture*" \) 2>/dev/null | \
  sort -r | head -3 | while read -r f; do cp "$f" "$CTX_DIR/"; done

# 4. 设计文档
find docs/design -maxdepth 1 -type f -name "*.md" 2>/dev/null | \
  sort | while read -r f; do cp "$f" "$CTX_DIR/"; done

# 5. UX 设计
find _bmad-output/planning-artifacts -maxdepth 1 -type f \( -iname "*ux*" -o -iname "*design*" \) 2>/dev/null | \
  sort -r | head -3 | while read -r f; do cp "$f" "$CTX_DIR/"; done

# 6. Sprint 计划
find _bmad-output/implementation-artifacts -maxdepth 1 -type f -iname "*sprint*" 2>/dev/null | \
  sort -r | head -1 | while read -r f; do cp "$f" "$CTX_DIR/"; done

# 7. 脑暴结论
find _bmad-output/brainstorming -maxdepth 1 -type f -name "*.md" 2>/dev/null | \
  sort -r | head -3 | while read -r f; do cp "$f" "$CTX_DIR/"; done

# 统计
echo "上下文包已构建: $(ls "$CTX_DIR" | wc -l) 个文件"
ls -la "$CTX_DIR"
```

---

## 模板渲染命令

Phase 0 生成 REVIEWER_INIT.md / ORCHESTRATOR_CHECKLIST.md，以及 Phase 1 为每个 task 生成 WRITER_INIT.md 时，统一复用同一个渲染函数：

```bash
set -a
. _hyper-loop/project-config.env
set +a

TEMPLATE_DIR="$HOME/.claude/skills/hyper-loop/templates"
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

# WRITER_INIT.md 要等到 Phase 1 拿到 WORKTREE_PATH 和 TASK_DESCRIPTION 后再渲染
```

---

## 紧急停止条件

以下情况必须立即暂停循环，报告用户：

1. **Codex 连续 3 轮修改相同文件的相同区域** → 可能在原地打转
2. **Gemini 连续 3 轮给 < 4 分** → 问题可能超出增量修复能力
3. **同一轮出现 2 个以上冲突，或核心 P0 任务冲突** → 并行策略失效，需要立即停机重排
4. **构建失败** → 不是功能 bug，是编译错误
5. **Mac Mini 资源告急** → tmux pane > 20 个时注意 CPU/内存
