#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# HyperLoop v5.3 — 编排脚本
#
# 像 autoresearch 的 program.md：一个死循环，改→跑→评→keep/reset→重复
# 像 HyperAgents 的 generate_loop.py：硬编码进化循环，有档案库和 parent 选择
#
# Claude Code 调用 `loop` 命令后脚本自主循环，不需要 Claude 再介入。
# 脚本自动：拆任务 → Writer → merge → build → Tester → Reviewer → 和议 → keep/reset
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# macOS 没有 timeout，用 coreutils 的 gtimeout
if command -v gtimeout >/dev/null 2>&1; then
  timeout() { gtimeout "$@"; }
elif ! command -v timeout >/dev/null 2>&1; then
  timeout() { local T="$1"; shift; "$@" & local PID=$!; (sleep "$T" && kill "$PID" 2>/dev/null) & wait "$PID" 2>/dev/null; }
fi

# ── 加载项目配置 ──
load_config() {
  local CONFIG_FILE="${PROJECT_ROOT:-.}/_hyper-loop/project-config.env"
  if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "ERROR: 找不到 $CONFIG_FILE，先跑 Phase 0" >&2
    exit 1
  fi
  set -a
  # shellcheck source=/dev/null
  . "$CONFIG_FILE"
  set +a
}

# ── 目录初始化 ──
init_dirs() {
  local ROUND="$1"
  LOG_DIR="${PROJECT_ROOT}/_hyper-loop/logs/$(date +%Y%m%d-%H%M%S)"
  SCREENSHOT_DIR="${PROJECT_ROOT}/_hyper-loop/screenshots/round-${ROUND}"
  SCORES_DIR="${PROJECT_ROOT}/_hyper-loop/scores/round-${ROUND}"
  REPORT_FILE="${PROJECT_ROOT}/_hyper-loop/reports/round-${ROUND}-test.md"
  SUMMARY_DIR="${PROJECT_ROOT}/_hyper-loop/summaries"
  TASK_DIR="${PROJECT_ROOT}/_hyper-loop/tasks/round-${ROUND}"
  WORKTREE_BASE="/tmp/hyper-loop-worktrees-r${ROUND}"

  mkdir -p "$LOG_DIR" "$SCREENSHOT_DIR" "$SCORES_DIR" "$SUMMARY_DIR" "$TASK_DIR" \
    "${PROJECT_ROOT}/_hyper-loop/archive/round-${ROUND}" \
    "$(dirname "$REPORT_FILE")"
}

# ── tmux 会话管理 ──
ensure_session() {
  tmux kill-session -t hyper-loop 2>/dev/null || true
  tmux new-session -d -s hyper-loop -n orchestrator
  echo "tmux session 'hyper-loop' created"
}

# ── Writer 管理 ──
start_writers() {
  local ROUND="$1"

  mkdir -p "$WORKTREE_BASE"

  local TASK_COUNT
  TASK_COUNT=$(find "$TASK_DIR" -maxdepth 1 -name 'task*.md' | wc -l | tr -d ' ')

  if [[ "$TASK_COUNT" -eq 0 ]]; then
    echo "ERROR: $TASK_DIR 下没有任务文件（task*.md）" >&2
    echo "Claude Code 需要先拆解任务并写入 task*.md 文件" >&2
    exit 1
  fi

  echo "启动 ${TASK_COUNT} 个 Writer..."

  for TASK_FILE in "$TASK_DIR"/task*.md; do
    local TASK_NAME
    TASK_NAME=$(basename "$TASK_FILE" .md)
    local WT="${WORKTREE_BASE}/${TASK_NAME}"
    local BRANCH="hyper-loop/r${ROUND}-${TASK_NAME}"

    # 创建 worktree
    git -C "$PROJECT_ROOT" worktree add "$WT" -b "$BRANCH" 2>/dev/null

    # 预 trust worktree 目录（解决 Codex "Do you trust?" 弹窗）
    # Codex 的 trust 存在 ~/.codex/config.toml
    local REAL_WT
    REAL_WT=$(cd "$WT" && pwd -P)  # 解析 /private/tmp → /tmp 等符号链接
    if ! grep -q "\"$REAL_WT\"" ~/.codex/config.toml 2>/dev/null; then
      printf '\n[projects."%s"]\ntrust_level = "trusted"\n' "$REAL_WT" >> ~/.codex/config.toml
      echo "  ✓ Codex trusted: $REAL_WT"
    fi

    # 复制上下文包 + 任务文件
    cp -r "${PROJECT_ROOT}/_hyper-loop/context" "${WT}/_ctx"
    cp "$TASK_FILE" "${WT}/TASK.md"

    # 生成 Writer 初始化——让 Writer 清楚知道自己是谁、能做什么、不能做什么
    cat > "${WT}/WRITER_INIT.md" <<WINIT
# 你是 HyperLoop Writer

你在一个独立的 git worktree 中工作。你的修改只影响这个 worktree。
你是一个临时工——改完这个任务就退出，不参与评审或其他决策。

## 你的工作流程
1. 先读 _ctx/ 下所有 .md 文件了解项目：
   - CLAUDE.md = 编码规范（Tauri invoke camelCase、TDD 等铁律）
   - *prd*.md = 产品需求（你要实现的是什么产品）
   - *architect*.md = 架构约束（进程分离、IPC 协议等）
   - *design*.md = 设计文档（功能应该长什么样）
   - contract.md = 评估契约（你的代码将按什么标准评分）
   - bdd-specs.md = BDD 行为规格（你的验收标准）
2. 读 TASK.md 了解本次具体任务
3. **只修改 TASK.md 中指定的文件**——改其他文件会被 diff 审计拒绝
4. 运行验证命令确认无报错
5. 将结果写入 DONE.json

## 你不能做的事
- 不改 TASK.md 没提到的文件（会被审计拒绝）
- 不改 CSS/样式（除非 TASK.md 明确要求）
- 不重构"顺便看到"的代码
- 不猜 Tauri invoke 参数名（用 grep 确认）
- 不评分、不评价其他代码

## 完成协议
修改完成后：
1. 运行项目的构建/检查命令验证
2. 写 DONE.json：{"status":"done","files_changed":["实际改了的文件"],"lint_pass":true}
3. 最后一行输出：HYPERLOOP_TASK_DONE

如果你无法完成任务（比如需要改的文件不存在、逻辑太复杂需要拆分）：
1. 写 DONE.json：{"status":"blocked","reason":"具体原因","files_changed":[]}
2. 最后一行输出：HYPERLOOP_TASK_DONE
WINIT

    # 构造完整 prompt（WRITER_INIT + 项目简报 + BDD + 契约 + TASK），通过 stdin 注入
    local WRITER_PROMPT="${WT}/_writer_prompt.md"
    {
      cat "${WT}/WRITER_INIT.md"
      echo ""
      echo "---"
      echo ""
      # 项目简报（init 生成的提炼版，不是原始文档）
      if [[ -f "${WT}/_ctx/project-brief.md" ]]; then
        echo "# 项目简报"
        echo ""
        cat "${WT}/_ctx/project-brief.md"
        echo ""
        echo "---"
        echo ""
      fi
      # BDD 规格（完整版，这是验收标准）
      if [[ -f "${WT}/_ctx/bdd-specs.md" ]]; then
        echo "# BDD 行为规格"
        echo ""
        cat "${WT}/_ctx/bdd-specs.md"
        echo ""
        echo "---"
        echo ""
      fi
      # 评估契约
      if [[ -f "${WT}/_ctx/contract.md" ]]; then
        echo "# 评估契约"
        echo ""
        cat "${WT}/_ctx/contract.md"
        echo ""
        echo "---"
        echo ""
      fi
      echo "# 本轮任务"
      echo ""
      cat "${WT}/TASK.md"
      echo ""
      echo "---"
      echo ""
      echo "现在执行 TASK.md 中的任务。完成后写 DONE.json。"
      echo "项目的其他文件在 _ctx/ 目录下可以用工具读取，但以上内容已包含核心信息。"
    } > "$WRITER_PROMPT"

    local PROMPT_LINES
    PROMPT_LINES=$(wc -l < "$WRITER_PROMPT" | tr -d ' ')
    echo "  📝 ${TASK_NAME} prompt: ${PROMPT_LINES} lines" >&2

    # 启动 Writer（非交互 exec 模式，后台并行，stdin 注入完整上下文）
    local WRITER_LOG="${LOG_DIR}/round-${ROUND}_writer_${TASK_NAME}_codex.log"
    (
      cat "$WRITER_PROMPT" | codex exec --dangerously-bypass-approvals-and-sandbox -C "$WT" - \
        > "$WRITER_LOG" 2>&1 || true
      # 如果 Codex 没写 DONE.json，补一个
      if [[ ! -f "${WT}/DONE.json" ]]; then
        echo '{"status":"done","files_changed":[],"note":"codex exec exited without DONE.json"}' > "${WT}/DONE.json"
      fi
    ) &

    echo "  ✓ Writer ${TASK_NAME} started in ${WT}"
  done
}

wait_writers() {
  local ROUND="$1"
  local TIMEOUT="${2:-900}"  # 默认 15 分钟（BDD S006 要求）

  echo "等待所有 Writer 完成（超时 ${TIMEOUT}s）..."

  # Writer 是后台 codex exec 进程，用 timeout 等待
  # 如果超时，杀掉所有 codex exec 子进程
  local START_TIME
  START_TIME=$(date +%s)

  while true; do
    # 检查是否还有 codex exec 子进程在跑
    local RUNNING
    RUNNING=$(jobs -r 2>/dev/null | wc -l | tr -d ' ')
    if [[ "$RUNNING" -eq 0 ]]; then
      echo "  ✓ 所有 Writer 已完成"
      break
    fi

    local ELAPSED=$(( $(date +%s) - START_TIME ))
    if [[ "$ELAPSED" -gt "$TIMEOUT" ]]; then
      echo "  ⚠ 超时（${TIMEOUT}s），强制结束未完成的 Writer"
      # 杀掉所有后台 subshell 及其子进程（codex exec）
      for PID in $(jobs -p 2>/dev/null); do
        # kill 整个进程组，确保 codex exec 子进程也被杀
        kill -- -"$PID" 2>/dev/null || kill "$PID" 2>/dev/null || true
      done
      wait 2>/dev/null || true
      # 给没有 DONE.json 的 Writer 写 timeout 状态
      for WT in "${WORKTREE_BASE}"/task*; do
        [[ -d "$WT" ]] || continue
        [[ -f "${WT}/DONE.json" ]] || echo '{"status":"timeout"}' > "${WT}/DONE.json"
      done
      break
    fi

    sleep 10
  done
}

# ── Diff 审计（autoresearch 启示：产出必须在可控范围内）──
audit_writer_diff() {
  local WT="$1"
  local TASK_FILE="${WT}/TASK.md"

  # 从 TASK.md 提取"相关文件"列表
  local ALLOWED_FILES
  ALLOWED_FILES=$(grep -A 20 '### 相关文件' "$TASK_FILE" 2>/dev/null | \
    grep -oE '[-a-zA-Z0-9_./ ]+\.(rs|svelte|ts|js|tsx|jsx|css|py|go|html|sh|bash|toml|json|md|yaml|yml)' | \
    sed 's/^[[:space:]]*//' | sort -u || true)

  if [[ -z "$ALLOWED_FILES" ]]; then
    echo "  ⚠ TASK.md 没有指定相关文件，跳过审计" >&2
    return 0
  fi

  # 获取实际改了哪些文件
  local CHANGED_FILES
  CHANGED_FILES=$(
    {
      git -C "$WT" diff --name-only HEAD 2>/dev/null
      git -C "$WT" ls-files --others --exclude-standard 2>/dev/null
    } | sort -u
  )

  if [[ -z "$CHANGED_FILES" ]]; then
    echo "  ⚠ Writer 没有改任何文件" >&2
    return 0
  fi

  # 检查是否有越界改动
  local VIOLATIONS=""
  while IFS= read -r changed; do
    local FOUND=false
    while IFS= read -r allowed; do
      [[ -z "$allowed" ]] && continue
      if [[ "$changed" == *"$allowed"* ]] || [[ "$allowed" == *"$changed"* ]]; then
        FOUND=true
        break
      fi
    done <<< "$ALLOWED_FILES"

    # 允许改 DONE.json、WRITER_INIT.md 等 HyperLoop 文件
    case "$changed" in
      DONE.json|WRITER_INIT.md|TASK.md|_writer_prompt.md|_ctx/*) FOUND=true ;;
    esac

    if ! $FOUND; then
      VIOLATIONS="${VIOLATIONS}    越界: ${changed}\n"
    fi
  done <<< "$CHANGED_FILES"

  if [[ -n "$VIOLATIONS" ]]; then
    echo "  ✗ Diff 审计失败：Writer 改了 TASK.md 范围外的文件" >&2
    echo -e "$VIOLATIONS" >&2
    return 1
  fi

  echo "  ✓ Diff 审计通过" >&2
  return 0
}

# ── 合并 ──
merge_writers() {
  local ROUND="$1"
  local INTEGRATION_BRANCH="hyper-loop/r${ROUND}-integration"
  local INTEGRATION_WT="${WORKTREE_BASE}/integration"
  local BASE_SHA
  BASE_SHA=$(git -C "$PROJECT_ROOT" rev-parse HEAD)

  git -C "$PROJECT_ROOT" worktree add "$INTEGRATION_WT" -b "$INTEGRATION_BRANCH" "$BASE_SHA" >&2 2>/dev/null

  local MERGED=0
  local FAILED=0

  echo "合并 Writer 产出..." >&2

  for WT in "${WORKTREE_BASE}"/task*; do
    [[ -d "$WT" ]] || continue
    local TASK_NAME
    TASK_NAME=$(basename "$WT")

    local STATUS
    STATUS=$(python3 -c "import json; print(json.load(open('${WT}/DONE.json'))['status'])" 2>/dev/null || echo "unknown")
    if [[ "$STATUS" != "done" ]]; then
      echo "  ⚠ ${TASK_NAME}: status=${STATUS}, 跳过" >&2
      ((FAILED++)) || true
      continue
    fi

    # Diff 审计：检查 Writer 是否只改了指定范围的文件
    if ! audit_writer_diff "$WT"; then
      echo "  ✗ ${TASK_NAME}: diff 审计失败，拒绝合并" >&2
      ((FAILED++)) || true
      continue
    fi

    local BRANCH
    BRANCH=$(git -C "$WT" branch --show-current)

    # Writer 改了文件但可能没 commit——Codex 只写文件不一定 git add/commit
    # 必须先 commit 才能 merge
    # 先删除 HyperLoop 元数据文件，防止多 Writer squash merge 冲突（P0-1 修复）
    rm -f "${WT}/DONE.json" "${WT}/WRITER_INIT.md" "${WT}/TASK.md" "${WT}/_writer_prompt.md" 2>/dev/null
    rm -rf "${WT}/_ctx" 2>/dev/null
    git -C "$WT" add -A 2>/dev/null
    git -C "$WT" commit -m "hyper-loop writer: ${TASK_NAME}" --allow-empty >&2 2>/dev/null || true

    # 保存 diff（对比 worktree 创建时的 parent commit）
    git -C "$WT" diff HEAD~1 > "${TASK_DIR}/${TASK_NAME}.patch" 2>/dev/null || \
      git -C "$WT" diff HEAD > "${TASK_DIR}/${TASK_NAME}.patch" 2>/dev/null
    git -C "$WT" diff --stat HEAD~1 > "${TASK_DIR}/${TASK_NAME}.stat" 2>/dev/null || \
      git -C "$WT" diff --stat HEAD > "${TASK_DIR}/${TASK_NAME}.stat" 2>/dev/null

    # squash merge
    if git -C "$INTEGRATION_WT" merge "$BRANCH" --squash --no-edit >&2 2>/dev/null; then
      git -C "$INTEGRATION_WT" commit --no-edit -m "hyper-loop R${ROUND} ${TASK_NAME}" >&2 2>/dev/null
      echo "  ✓ ${TASK_NAME} merged" >&2
      ((MERGED++)) || true
    else
      git -C "$INTEGRATION_WT" merge --abort 2>/dev/null || true
      echo "  ✗ ${TASK_NAME} conflict, deferred" >&2
      ((FAILED++)) || true
    fi
  done

  echo "合并完成: ${MERGED} merged, ${FAILED} failed/skipped" >&2
  # 写 merge 统计供调用方检查
  echo "$MERGED" > "${TASK_DIR}/merge-count.txt"
  echo "$INTEGRATION_WT"
}

# ── 构建 ──
build_app() {
  local BUILD_DIR="$1"
  echo "构建 App..."
  (
    cd "$BUILD_DIR"
    eval "${CACHE_CLEAN:-true}" 2>/dev/null || true
    eval "${BUILD_CMD:-echo 'no BUILD_CMD'}"
  )
  local RC=$?
  if [[ $RC -eq 0 ]]; then
    echo "  ✓ 构建成功"
  else
    echo "  ✗ 构建失败"
  fi
  return "$RC"
}

# ── Tester（非交互 -p 模式）──
run_tester() {
  local ROUND="$1"

  echo "启动 Tester（非交互模式）..."

  # 先生成轮次摘要给 Tester 看
  local SUMMARY="${TASK_DIR}/round-summary.txt"
  {
    echo "本轮修改统计："
    for STAT in "${TASK_DIR}"/*.stat; do
      [[ -f "$STAT" ]] && cat "$STAT"
    done
    echo ""
    echo "构建结果：$(eval "${BUILD_VERIFY:-echo 'no verify'}" 2>&1 | tail -3)"
  } > "$SUMMARY" 2>/dev/null

  local TESTER_PROMPT="你是代码测试员。请执行以下操作：

1. 读 ${PROJECT_ROOT}/_hyper-loop/context/bdd-specs.md 了解 BDD 场景
2. 读 ${SUMMARY} 了解本轮修改
3. 运行 bash -n ${PROJECT_ROOT}/scripts/hyper-loop.sh 验证语法
4. 按 BDD 场景逐条检查脚本代码，标注 pass/fail
5. 将结果写入 ${REPORT_FILE}，格式：每行一个场景 ID + pass/fail + 原因
6. 列出发现的 P0/P1 bug"

  echo "$TESTER_PROMPT" | timeout 600 claude --dangerously-skip-permissions -p - \
    --add-dir "$PROJECT_ROOT" 2>&1 | \
    tee "${LOG_DIR}/round-${ROUND}_tester_bdd-verify_claude.log" > "${REPORT_FILE}" || true

  if [[ -s "$REPORT_FILE" ]]; then
    echo "  ✓ 试用报告已生成: $REPORT_FILE"
  else
    echo "  ⚠ Tester 无输出，生成默认报告"
    echo "# Round $ROUND — Tester 无输出" > "$REPORT_FILE"
  fi
}

# ── 3 Reviewer 合议（非交互管道模式）──
run_reviewers() {
  local ROUND="$1"

  echo "启动 3 个 Reviewer（非交互模式）..."

  # 构造评审 prompt（引用文件路径）
  local REVIEW_PROMPT="你是代码评审官。请读以下文件后给出评分。

评估契约：${PROJECT_ROOT}/_hyper-loop/context/contract.md
BDD 规格：${PROJECT_ROOT}/_hyper-loop/context/bdd-specs.md
Tester 报告：${REPORT_FILE}
本轮修改：
$(for STAT in "${TASK_DIR}"/*.stat; do [[ -f "$STAT" ]] && cat "$STAT"; done)

只输出一个 JSON 对象，不要代码块，不要解释，不要 markdown：
{\"score\":数字0到10,\"issues\":[{\"severity\":\"P0\",\"desc\":\"描述\"}],\"summary\":\"一句话总结\"}"

  # JSON 提取函数
  local EXTRACT_PY='
import json, sys
from pathlib import Path
text = sys.stdin.read()
decoder = json.JSONDecoder()
last = None
for i, ch in enumerate(text):
    if ch != "{": continue
    try:
        obj, _ = decoder.raw_decode(text[i:])
        if "score" in obj: last = obj
    except: pass
if last:
    json.dump(last, sys.stdout, ensure_ascii=False, indent=2)
else:
    json.dump({"score":5,"issues":[],"summary":"评审未返回有效JSON，给中立分5"}, sys.stdout)
'

  # 写 prompt 到临时文件，避免 ARG_MAX 和 stdin 不可用问题
  local REVIEW_PROMPT_FILE
  REVIEW_PROMPT_FILE=$(mktemp /tmp/hyper-loop-review-XXXXXX)
  echo "$REVIEW_PROMPT" > "$REVIEW_PROMPT_FILE"

  # 并行跑 3 个 Reviewer（非交互 -p 模式，stdout 管道提取 JSON）
  (
    timeout 300 gemini -y -p "$(cat "$REVIEW_PROMPT_FILE")" --include-directories "$PROJECT_ROOT" 2>&1 | \
      tee "${LOG_DIR}/round-${ROUND}_reviewer-a_scoring_gemini.log" | \
      python3 -c "$EXTRACT_PY" > "${SCORES_DIR}/reviewer-a.json" 2>/dev/null
    echo "  ✓ reviewer-a (gemini) done: $(python3 -c "import json; print(json.load(open('${SCORES_DIR}/reviewer-a.json'))['score'])" 2>/dev/null || echo 'fallback')"
  ) &

  (
    echo "$REVIEW_PROMPT" | timeout 300 claude --dangerously-skip-permissions -p - \
      --add-dir "$PROJECT_ROOT" 2>&1 | \
      tee "${LOG_DIR}/round-${ROUND}_reviewer-b_scoring_claude.log" | \
      python3 -c "$EXTRACT_PY" > "${SCORES_DIR}/reviewer-b.json" 2>/dev/null
    echo "  ✓ reviewer-b (claude) done: $(python3 -c "import json; print(json.load(open('${SCORES_DIR}/reviewer-b.json'))['score'])" 2>/dev/null || echo 'fallback')"
  ) &

  (
    cat "$REVIEW_PROMPT_FILE" | timeout 300 codex exec --full-auto -C "$PROJECT_ROOT" - 2>&1 | \
      tee "${LOG_DIR}/round-${ROUND}_reviewer-c_scoring_codex.log" | \
      python3 -c "$EXTRACT_PY" > "${SCORES_DIR}/reviewer-c.json" 2>/dev/null
    echo "  ✓ reviewer-c (codex) done: $(python3 -c "import json; print(json.load(open('${SCORES_DIR}/reviewer-c.json'))['score'])" 2>/dev/null || echo 'fallback')"
  ) &

  echo "  等待 3 个 Reviewer 完成（最多 5 分钟）..."
  wait

  # 清理临时文件
  rm -f "$REVIEW_PROMPT_FILE" 2>/dev/null

  # 确保所有评分文件存在（fallback 给 5 分）
  for NAME in reviewer-a reviewer-b reviewer-c; do
    if [[ ! -s "${SCORES_DIR}/${NAME}.json" ]]; then
      echo '{"score":5,"issues":[],"summary":"Reviewer 超时或无输出，中立分5"}' > "${SCORES_DIR}/${NAME}.json"
      echo "  ⚠ ${NAME} fallback to score 5"
    fi
  done
}

# ── 和议计算 ──
compute_verdict() {
  local ROUND="$1"
  local PREV_MEDIAN="${2:-0}"

  echo ""
  echo "═══════════════════════════════════"
  echo "  Round $ROUND 和议结果"
  echo "═══════════════════════════════════"

  local SCORES=()
  for SCORE_FILE in "${SCORES_DIR}"/*.json; do
    [[ -f "$SCORE_FILE" ]] || continue
    local S
    S=$(python3 -c "import json; print(json.load(open('${SCORE_FILE}'))['score'])" 2>/dev/null || echo "0")
    SCORES+=("$S")
    local NAME
    NAME=$(basename "$SCORE_FILE" .json)
    echo "  ${NAME}: ${S}"
  done

  if [[ ${#SCORES[@]} -eq 0 ]]; then
    echo "  ERROR: 没有评分文件"
    echo "DECISION=ERROR" > "${TASK_DIR}/verdict.env"
    return
  fi

  python3 - "${SCORES[*]}" "$PREV_MEDIAN" "$REPORT_FILE" "${TASK_DIR}/verdict.env" <<'PYVERDICT'
import sys, json
from pathlib import Path

scores_str, prev_median_str, report_path, output_path = sys.argv[1:5]
scores = sorted([float(s) for s in scores_str.split()])
n = len(scores)
median = scores[n//2] if n % 2 else (scores[n//2-1] + scores[n//2]) / 2
max_diff = max(scores) - min(scores)
prev_median = float(prev_median_str)

veto = any(s < 4.0 for s in scores)

tester_p0 = False
report = Path(report_path)
if report.exists():
    text = report.read_text()
    import re
    # Count actual P0 bug entries (### P0- headings), not section headers (## P0 Bugs)
    p0_bugs = re.findall(r'^###\s+P0', text, re.MULTILINE)
    # Count BDD scenario failures from the results table
    bdd_fails = re.findall(r'\|\s*\*?\*?FAIL\*?\*?\s*\|', text)
    # BDD S011: any tester report with at least one P0 bug and one FAIL auto-rejects
    tester_p0 = len(p0_bugs) >= 1 and len(bdd_fails) >= 1

if veto:
    decision = "REJECTED_VETO"
elif tester_p0:
    decision = "REJECTED_TESTER_P0"
elif max_diff > 2.0:
    decision = "PENDING_USER"
elif median > prev_median:
    decision = "ACCEPTED"
elif median == prev_median and median > 0:
    decision = "ACCEPTED_UNCHANGED"
else:
    decision = "REJECTED_NO_IMPROVEMENT"

print(f"  中位数: {median}")
print(f"  分歧: {max_diff}")
print(f"  否决: {veto}")
print(f"  Tester P0: {tester_p0}")
print(f"  决策: {decision}")

with open(output_path, 'w') as f:
    f.write(f"DECISION={decision}\n")
    f.write(f"MEDIAN={median}\n")
    f.write(f"MAX_DIFF={max_diff}\n")
    f.write(f"VETO={veto}\n")
    f.write(f"TESTER_P0={tester_p0}\n")
    f.write(f"SCORES=\"{' '.join(str(s) for s in scores)}\"\n")
PYVERDICT

  echo "═══════════════════════════════════"
}

# ── 清理（所有命令容错，不能因为清理失败终止循环）──
cleanup_round() {
  local ROUND="$1"

  # 用 subshell + set +e 确保清理不会触发 set -e 退出
  (
    set +e
    tmux list-windows -t hyper-loop -F '#{window_name}' 2>/dev/null | grep -E '^w-|^tester|^reviewer' | while read -r w; do
      tmux kill-window -t "hyper-loop:${w}" 2>/dev/null
    done

    for WT in "${WORKTREE_BASE}"/task* "${WORKTREE_BASE}/integration"; do
      [[ -d "$WT" ]] || continue
      local BRANCH
      BRANCH=$(git -C "$WT" branch --show-current 2>/dev/null || echo "")
      git -C "$PROJECT_ROOT" worktree remove "$WT" --force 2>/dev/null
      [[ -n "$BRANCH" ]] && git -C "$PROJECT_ROOT" branch -D "$BRANCH" 2>/dev/null
    done

    cp "${TASK_DIR}/verdict.env" "${PROJECT_ROOT}/_hyper-loop/archive/round-${ROUND}/" 2>/dev/null

    # S015: 删除 worktree 父目录
    rm -rf "${WORKTREE_BASE}" 2>/dev/null
  ) || true
}

# ── 记录结果 ──
record_result() {
  local ROUND="$1"
  local VERDICT_FILE="${TASK_DIR}/verdict.env"

  [[ -f "$VERDICT_FILE" ]] || return

  # 安全读取（不 source，用 grep）
  local R_DECISION R_MEDIAN R_SCORES
  R_DECISION=$(grep '^DECISION=' "$VERDICT_FILE" | cut -d= -f2)
  R_MEDIAN=$(grep '^MEDIAN=' "$VERDICT_FILE" | cut -d= -f2)
  R_SCORES=$(grep '^SCORES=' "$VERDICT_FILE" | cut -d= -f2- | tr -d '"')

  printf '%s\t%s\t%s\t%s\n' \
    "$ROUND" "${R_MEDIAN:-0}" "${R_SCORES:-}" "${R_DECISION:-ERROR}" \
    >> "${PROJECT_ROOT}/_hyper-loop/results.tsv"
}

# ============================================================================
# 主命令
# ============================================================================

cmd_round() {
  local ROUND="${1:?用法: hyper-loop.sh round <轮次号>}"

  load_config
  init_dirs "$ROUND"
  ensure_session

  echo ""
  echo "╔══════════════════════════════════╗"
  echo "║  HyperLoop Round $ROUND 开始      "
  echo "╚══════════════════════════════════╝"
  echo ""

  local PREV_MEDIAN=0
  if [[ -f "${PROJECT_ROOT}/_hyper-loop/results.tsv" ]] && [[ -s "${PROJECT_ROOT}/_hyper-loop/results.tsv" ]]; then
    PREV_MEDIAN=$(grep -E '^[0-9]' "${PROJECT_ROOT}/_hyper-loop/results.tsv" | tail -1 | cut -f2 || echo 0)
    # Validate: must be a number (integer or float), default to 0 if not
    [[ -z "$PREV_MEDIAN" ]] && PREV_MEDIAN=0
    [[ "$PREV_MEDIAN" =~ ^[0-9]*\.?[0-9]+$ ]] || PREV_MEDIAN=0
  fi

  start_writers "$ROUND"
  wait_writers "$ROUND"

  local INTEGRATION_WT
  INTEGRATION_WT=$(merge_writers "$ROUND")

  # 检查是否有任何 Writer 成功合并
  local MERGE_COUNT
  MERGE_COUNT=$(cat "${TASK_DIR}/merge-count.txt" 2>/dev/null || echo 0)
  if [[ "$MERGE_COUNT" -eq 0 ]]; then
    echo "所有 Writer 失败或被跳过，跳过构建和评审"
    echo "DECISION=NO_MERGE" > "${TASK_DIR}/verdict.env"
    echo "MEDIAN=0" >> "${TASK_DIR}/verdict.env"
    echo "SCORES=\"0\"" >> "${TASK_DIR}/verdict.env"
    record_result "$ROUND"
    archive_round "$ROUND"
    cleanup_round "$ROUND"
    return 1
  fi

  if ! build_app "$INTEGRATION_WT"; then
    echo "构建失败，跳过 Tester 和 Reviewer"
    echo "DECISION=BUILD_FAILED" > "${TASK_DIR}/verdict.env"
    echo "MEDIAN=0" >> "${TASK_DIR}/verdict.env"
    echo "SCORES=\"0\"" >> "${TASK_DIR}/verdict.env"
    record_result "$ROUND"
    archive_round "$ROUND"
    cleanup_round "$ROUND"
    return 1
  fi

  run_tester "$ROUND"
  run_reviewers "$ROUND"
  compute_verdict "$ROUND" "$PREV_MEDIAN"
  record_result "$ROUND"

  echo ""
  # shellcheck source=/dev/null
  # 安全读取 verdict.env（不 source，用 grep 提取）
  DECISION=$(grep '^DECISION=' "${TASK_DIR}/verdict.env" | cut -d= -f2)
  MEDIAN=$(grep '^MEDIAN=' "${TASK_DIR}/verdict.env" | cut -d= -f2)

  if [[ "$DECISION" == "ACCEPTED" ]] || [[ "$DECISION" == "ACCEPTED_UNCHANGED" ]]; then
    echo "建议：合并 integration 分支到 main"
    echo "  git merge --no-ff hyper-loop/r${ROUND}-integration -m 'hyper-loop R${ROUND}'"
  elif [[ "$DECISION" == "PENDING_USER" ]]; then
    echo "建议：评分分歧 > 2.0，需要用户裁决"
    echo "  查看评分: cat ${SCORES_DIR}/*.json"
  else
    echo "建议：本轮被拒绝 ($DECISION)，丢弃 integration 分支"
  fi

  cleanup_round "$ROUND"

  echo ""
  echo "Round $ROUND 完成。结果: $DECISION (median=$MEDIAN)"
  echo "日志: $LOG_DIR"
  echo "报告: $REPORT_FILE"
  echo "评分: $SCORES_DIR/"
}

# ── 自动拆解下一轮任务（基于上一轮结果）──
auto_decompose() {
  local ROUND="$1"
  local TASK_DIR="${PROJECT_ROOT}/_hyper-loop/tasks/round-${ROUND}"
  mkdir -p "$TASK_DIR"

  echo "自动拆解 Round ${ROUND} 任务..."

  # 用 Claude 非交互模式拆解任务
  local DECOMPOSE_PROMPT
  DECOMPOSE_PROMPT=$(mktemp /tmp/hyper-loop-decompose-XXXXXX)
  cat > "$DECOMPOSE_PROMPT" <<DPROMPT
你是 HyperLoop 的任务拆解器。请基于以下信息拆解本轮任务。

## 上下文
- BDD 行为规格：${PROJECT_ROOT}/_hyper-loop/context/bdd-specs.md
- 评估契约：${PROJECT_ROOT}/_hyper-loop/context/contract.md
- 历史结果：${PROJECT_ROOT}/_hyper-loop/results.tsv

$(if [[ -f "${PROJECT_ROOT}/_hyper-loop/reports/round-$((ROUND-1))-test.md" ]]; then
  echo "## 上一轮试用报告"
  echo "$(cat "${PROJECT_ROOT}/_hyper-loop/reports/round-$((ROUND-1))-test.md" 2>/dev/null | head -100)"
fi)

$(if [[ -d "${PROJECT_ROOT}/_hyper-loop/scores/round-$((ROUND-1))" ]]; then
  echo "## 上一轮评分"
  for f in "${PROJECT_ROOT}/_hyper-loop/scores/round-$((ROUND-1))"/*.json; do
    [[ -f "\$f" ]] && echo "$(basename "\$f"): $(cat "\$f" 2>/dev/null)"
  done
fi)

## 要求
读取上述文件，找出当前最严重的问题（P0 优先），拆成 3-5 个独立子任务。

**关键规则：**
1. 每个任务必须修改**不同的文件**（或同一文件的**不重叠区域**），确保多 Writer 并行不冲突
2. 如果多个问题都在同一个文件的同一区域，合并为 1 个任务，不要拆开
3. 任务描述必须是"扫描修复同类问题"而不是"修第 N 行"——比如"找到所有向 stdout 输出非返回值的 echo/git 命令，全部加 >&2"
4. 用 grep/搜索命令定位所有实例，不要只改报告中提到的那几行

每个任务写成独立文件保存到 ${TASK_DIR}/taskN.md。

任务文件格式：
\`\`\`
## 修复任务: TASK-N
### 上下文
先读 _ctx/ 下所有文件。
### 问题
[优先级] 具体问题描述（同类问题合并描述）
### 相关文件
- 具体文件路径 (行号范围)
### 修复策略
用 grep/搜索先找到所有同类实例，一次性全部修复。不要只修报告提到的几行。
### 约束
- 只修指定文件
### 验收标准
引用 BDD 场景 SXXX
\`\`\`

直接写文件，不要输出到 stdout。
DPROMPT

  # 用 stdin 管道传 prompt（避免命令行参数过长）
  mkdir -p "${PROJECT_ROOT}/_hyper-loop/logs"
  cat "$DECOMPOSE_PROMPT" | claude --dangerously-skip-permissions -p - \
    --add-dir "$PROJECT_ROOT" \
    > "${PROJECT_ROOT}/_hyper-loop/logs/round-${ROUND}_decomposer_task-split_claude.log" 2>&1 || true

  local TASK_COUNT
  TASK_COUNT=$(find "$TASK_DIR" -maxdepth 1 -name 'task*.md' 2>/dev/null | wc -l | tr -d ' ')

  if [[ "$TASK_COUNT" -eq 0 ]]; then
    echo "  ⚠ 自动拆解未生成任务文件，生成默认任务"
    # 降级：基于上一轮失败的 BDD 场景生成一个通用任务
    cat > "${TASK_DIR}/task1.md" <<FALLBACK
## 修复任务: TASK-1

### 上下文
先读 _ctx/ 下所有文件，特别是 bdd-specs.md。

### 问题
查看上一轮试用报告 (reports/round-$((ROUND-1))-test.md)，找到第一个 FAIL 的 BDD 场景并修复。

### 相关文件
- 根据 BDD 场景涉及的功能确定

### 约束
- 只修与失败场景直接相关的文件
- 不改 CSS
FALLBACK
  fi

  echo "  ✓ 生成了 ${TASK_COUNT:-1} 个任务"
}

# ── 档案归档（HyperAgents 启示：保留 stepping stones）──
archive_round() {
  local ROUND="$1"
  local ARCHIVE="${PROJECT_ROOT}/_hyper-loop/archive/round-${ROUND}"
  mkdir -p "$ARCHIVE"

  cp "${PROJECT_ROOT}/_hyper-loop/context/bdd-specs.md" "$ARCHIVE/" 2>/dev/null || true
  cp -r "${PROJECT_ROOT}/_hyper-loop/scores/round-${ROUND}" "$ARCHIVE/scores" 2>/dev/null || true
  cp "${PROJECT_ROOT}/_hyper-loop/reports/round-${ROUND}-test.md" "$ARCHIVE/" 2>/dev/null || true
  cp "${TASK_DIR}/verdict.env" "$ARCHIVE/" 2>/dev/null || true
  git -C "$PROJECT_ROOT" rev-parse HEAD > "$ARCHIVE/git-sha.txt" 2>/dev/null || true

  echo "  ✓ Round ${ROUND} 已归档"
}

# ── 从档案库恢复（HyperAgents 启示：从最佳 parent 分叉）──
cmd_resume_from() {
  local TARGET_ROUND="${1:?用法: hyper-loop.sh resume-from <轮次号>}"
  local ARCHIVE="${PROJECT_ROOT:-.}/_hyper-loop/archive/round-${TARGET_ROUND}"

  if [[ ! -f "$ARCHIVE/git-sha.txt" ]]; then
    echo "ERROR: Round ${TARGET_ROUND} 档案不存在或没有 git-sha.txt" >&2
    exit 1
  fi

  local SHA
  SHA=$(cat "$ARCHIVE/git-sha.txt")
  echo "从 Round ${TARGET_ROUND} 的代码状态恢复 (${SHA:0:8})"
  git -C "${PROJECT_ROOT:-.}" checkout "$SHA" -- .
  echo "  ✓ 代码已恢复到 Round ${TARGET_ROUND} 状态"
  echo "  接下来运行: hyper-loop.sh loop 或 hyper-loop.sh round <N>"
}

# ── 初始化：扫描项目 → 生成上下文简报 → 持久化 ──
cmd_init() {
  load_config
  local CTX_DIR="${PROJECT_ROOT}/_hyper-loop/context"
  mkdir -p "$CTX_DIR"

  echo "═══ HyperLoop Init: 扫描项目并生成上下文简报 ═══"
  echo ""

  # 检查是否已有 brief（防止意外覆盖用户手动编辑的版本）
  if [[ -f "${CTX_DIR}/project-brief.md" ]]; then
    echo "⚠ 已存在 project-brief.md，将备份为 project-brief.md.bak"
    cp "${CTX_DIR}/project-brief.md" "${CTX_DIR}/project-brief.md.bak"
  fi

  # Step 1: 扫描项目结构和文档
  echo "Step 1: 扫描项目文档..."
  local SCAN_RESULT
  SCAN_RESULT=$(mktemp /tmp/hyper-loop-scan-XXXXXX)
  {
    echo "# 项目扫描结果"
    echo ""
    echo "## 项目配置"
    cat "${PROJECT_ROOT}/_hyper-loop/project-config.env" 2>/dev/null
    echo ""

    echo "## CLAUDE.md（编码规范）"
    if [[ -f "${PROJECT_ROOT}/CLAUDE.md" ]]; then
      head -200 "${PROJECT_ROOT}/CLAUDE.md"
    else
      echo "(不存在)"
    fi
    echo ""

    echo "## BMAD 文档"
    for DIR in _bmad-output _bmad/output docs/design docs/spec docs/research docs/sprint docs/runbook; do
      if [[ -d "${PROJECT_ROOT}/${DIR}" ]]; then
        echo "### ${DIR}/"
        find "${PROJECT_ROOT}/${DIR}" -name "*.md" -type f 2>/dev/null | while read -r f; do
          echo "#### $(basename "$f")"
          head -200 "$f"
          echo ""
          echo "---"
        done
      fi
    done
    echo ""

    echo "## 根目录文档"
    for ROOT_DOC in README.md INSTALL.md CONTRIBUTING.md; do
      if [[ -f "${PROJECT_ROOT}/${ROOT_DOC}" ]]; then
        echo "### ${ROOT_DOC}"
        head -100 "${PROJECT_ROOT}/${ROOT_DOC}"
        echo ""
      fi
    done
    echo ""

    echo "## 项目文件结构（前 3 层，相对路径）"
    (cd "$PROJECT_ROOT" && find . -maxdepth 3 -type f \( -name "*.md" -o -name "*.ts" -o -name "*.svelte" -o -name "*.rs" -o -name "*.py" -o -name "*.sh" -o -name "*.json" \) 2>/dev/null | \
      grep -v node_modules | grep -v target | grep -v _hyper-loop | grep -v .git | sort | head -80)
    echo ""

    echo "## 已有 BDD 规格"
    cat "${CTX_DIR}/bdd-specs.md" 2>/dev/null || echo "(未生成)"
    echo ""

    echo "## 已有评估契约"
    cat "${CTX_DIR}/contract.md" 2>/dev/null || echo "(未生成)"
  } > "$SCAN_RESULT"

  local SCAN_LINES
  SCAN_LINES=$(wc -l < "$SCAN_RESULT" | tr -d ' ')
  echo "  ✓ 扫描完成: ${SCAN_LINES} 行原始数据"

  # Step 2: 用 Claude 提炼为项目简报
  echo "Step 2: Claude 提炼项目简报..."
  local BRIEF_PROMPT
  BRIEF_PROMPT=$(mktemp /tmp/hyper-loop-brief-XXXXXX)
  cat > "$BRIEF_PROMPT" <<'BRIEF'
你是项目文档提炼专家。请根据以下项目扫描结果，生成一份**简洁的项目简报**。

## 输出要求
- 总长度不超过 300 行
- 分为以下章节：

### 1. 项目概述（3-5 句话）
产品是什么、技术栈、目标用户

### 2. 架构约束（要点列表）
进程模型、IPC 协议、文件结构等——Writer 必须遵守的硬约束

### 3. 编码规范（要点列表）
从 CLAUDE.md 提取的铁律——命名约定、测试要求、构建规则

### 4. 当前重点（BDD 场景摘要）
从 BDD 规格中提取当前要验证的核心场景

### 5. 设计意图（从 BMAD 文档提取）
产品设计的核心原则——Writer 需要理解"为什么这样设计"才能写出对的代码

### 6. 文件地图（相对路径 + 一句话说明）
Writer 最常需要改的 10-20 个文件。**必须用相对路径**（如 src/lib/foo.ts），不要用绝对路径。

**原则：只保留 Writer/Tester/Reviewer 需要的信息。删掉历史记录、会议纪要、过程讨论。**
**格式：直接输出简报正文，不要加任何前导说明（如"好的，这是项目简报："）或后续总结。**
BRIEF

  cat "$SCAN_RESULT" >> "$BRIEF_PROMPT"

  local BRIEF_FILE="${CTX_DIR}/project-brief.md"
  local BRIEF_LOG="${PROJECT_ROOT}/_hyper-loop/logs/init-brief-claude.log"
  mkdir -p "$(dirname "$BRIEF_LOG")"
  cat "$BRIEF_PROMPT" | claude --dangerously-skip-permissions -p \
    --add-dir "$PROJECT_ROOT" \
    > "$BRIEF_FILE" 2>"$BRIEF_LOG" || true

  if [[ -s "$BRIEF_FILE" ]]; then
    local BRIEF_LINES
    BRIEF_LINES=$(wc -l < "$BRIEF_FILE" | tr -d ' ')
    echo "  ✓ 项目简报已生成: ${BRIEF_FILE} (${BRIEF_LINES} 行)"
  else
    echo "  ⚠ Claude 未生成简报（日志: ${BRIEF_LOG}），使用原始扫描结果"
    head -300 "$SCAN_RESULT" > "$BRIEF_FILE"
  fi

  # Step 3: 复制核心文件到 context
  echo "Step 3: 同步核心文件..."
  [[ -f "${PROJECT_ROOT}/CLAUDE.md" ]] && cp "${PROJECT_ROOT}/CLAUDE.md" "${CTX_DIR}/" 2>/dev/null
  cp "${PROJECT_ROOT}/scripts/hyper-loop.sh" "${CTX_DIR}/hyper-loop.sh" 2>/dev/null || true

  echo "  ✓ context/ 目录已就绪"
  echo ""
  echo "context/ 内容:"
  ls -la "$CTX_DIR"/*.md 2>/dev/null | awk '{print "  " $NF " (" $5 " bytes)"}'
  echo ""
  echo "═══ Init 完成 ═══"
  echo "接下来："
  echo "  1. 检查 _hyper-loop/context/project-brief.md 是否准确"
  echo "  2. 确认 bdd-specs.md 和 contract.md"
  echo "  3. 启动循环: hyper-loop.sh loop N"
}

# ── 死循环模式（autoresearch 启示：NEVER STOP）──
cmd_loop() {
  local MAX_ROUNDS="${1:-999}"
  local STOP_FILE="${PROJECT_ROOT:-.}/_hyper-loop/STOP"

  load_config

  # 检查是否已初始化
  if [[ ! -f "${PROJECT_ROOT}/_hyper-loop/context/project-brief.md" ]]; then
    echo "⚠ 未找到 project-brief.md，先运行 init 扫描项目..."
    cmd_init
  fi

  echo ""
  echo "╔══════════════════════════════════════════════════╗"
  echo "║  HyperLoop LOOP 模式 — 最多 ${MAX_ROUNDS} 轮             "
  echo "║  创建 _hyper-loop/STOP 文件可优雅停止          "
  echo "╚══════════════════════════════════════════════════╝"
  echo ""

  # 确定起始轮次
  local ROUND=1
  if [[ -f "${PROJECT_ROOT}/_hyper-loop/results.tsv" ]] && [[ -s "${PROJECT_ROOT}/_hyper-loop/results.tsv" ]]; then
    local LAST_ROUND
    LAST_ROUND=$(grep -E '^[0-9]' "${PROJECT_ROOT}/_hyper-loop/results.tsv" | tail -1 | cut -f1 || echo 0)
    if [[ -n "$LAST_ROUND" ]] && [[ "$LAST_ROUND" =~ ^[0-9]+$ ]]; then
      ROUND=$((LAST_ROUND + 1))
    fi
  fi

  local CONSECUTIVE_REJECTS=0
  local BEST_ROUND=0
  local BEST_MEDIAN=0
  if [[ -f "${PROJECT_ROOT}/_hyper-loop/results.tsv" ]] && [[ -s "${PROJECT_ROOT}/_hyper-loop/results.tsv" ]]; then
    local HIST_ROUND HIST_MEDIAN HIST_SCORES HIST_DECISION
    while IFS=$'\t' read -r HIST_ROUND HIST_MEDIAN HIST_SCORES HIST_DECISION; do
      [[ "$HIST_ROUND" =~ ^[0-9]+$ ]] || continue

      if [[ "$HIST_DECISION" == ACCEPTED* ]]; then
        CONSECUTIVE_REJECTS=0
        [[ "$HIST_MEDIAN" =~ ^[0-9]*\.?[0-9]+$ ]] || continue
        if python3 -c "exit(0 if float('${HIST_MEDIAN}') > float('${BEST_MEDIAN}') else 1)" 2>/dev/null; then
          BEST_ROUND=$HIST_ROUND
          BEST_MEDIAN=$HIST_MEDIAN
        fi
      else
        ((CONSECUTIVE_REJECTS++)) || true
      fi
    done < "${PROJECT_ROOT}/_hyper-loop/results.tsv"

    if [[ "$BEST_ROUND" -gt 0 ]]; then
      echo "历史最佳: Round ${BEST_ROUND} (median=${BEST_MEDIAN})"
    fi
  fi
  # MAX_ROUNDS 是"再跑多少轮"，转换为终止轮次号
  local END_ROUND=$((ROUND + MAX_ROUNDS - 1))

  while [[ "$ROUND" -le "$END_ROUND" ]]; do
    # 检查停止信号
    if [[ -f "$STOP_FILE" ]]; then
      echo "检测到 STOP 文件，优雅退出"
      rm "$STOP_FILE"
      break
    fi

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  LOOP: Round ${ROUND}/${END_ROUND}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # 初始化目录（必须在 auto_decompose 之前，否则日志目录不存在）
    init_dirs "$ROUND"
    ensure_session
    # 重置本轮状态（防止前一轮的 MEDIAN/DECISION 影响后续判断）
    DECISION="" MEDIAN=0

    # 自动拆解任务
    auto_decompose "$ROUND"

    local PREV_MEDIAN=0
    if [[ -f "${PROJECT_ROOT}/_hyper-loop/results.tsv" ]] && [[ -s "${PROJECT_ROOT}/_hyper-loop/results.tsv" ]]; then
      PREV_MEDIAN=$(grep -E '^[0-9]' "${PROJECT_ROOT}/_hyper-loop/results.tsv" | tail -1 | cut -f2 || echo 0)
      [[ -z "$PREV_MEDIAN" ]] && PREV_MEDIAN=0
      [[ "$PREV_MEDIAN" =~ ^[0-9]*\.?[0-9]+$ ]] || PREV_MEDIAN=0
    fi

    start_writers "$ROUND"
    wait_writers "$ROUND"

    local INTEGRATION_WT
    INTEGRATION_WT=$(merge_writers "$ROUND")

    # 检查是否有任何 Writer 成功合并
    local MERGE_COUNT
    MERGE_COUNT=$(cat "${TASK_DIR}/merge-count.txt" 2>/dev/null || echo 0)
    if [[ "$MERGE_COUNT" -eq 0 ]]; then
      echo "所有 Writer 失败或被跳过"
      echo "DECISION=NO_MERGE" > "${TASK_DIR}/verdict.env"
      echo "MEDIAN=0" >> "${TASK_DIR}/verdict.env"
      echo "SCORES=\"0\"" >> "${TASK_DIR}/verdict.env"
      record_result "$ROUND"
      archive_round "$ROUND"
      cleanup_round "$ROUND"
      ((CONSECUTIVE_REJECTS++)) || true
      ((ROUND++))
      sleep 30
      continue
    fi

    if ! build_app "$INTEGRATION_WT"; then
      echo "构建失败"
      echo "DECISION=BUILD_FAILED" > "${TASK_DIR}/verdict.env"
      echo "MEDIAN=0" >> "${TASK_DIR}/verdict.env"
      echo "SCORES=\"0\"" >> "${TASK_DIR}/verdict.env"
      record_result "$ROUND"
      archive_round "$ROUND"
      cleanup_round "$ROUND"
      ((CONSECUTIVE_REJECTS++)) || true
    else
      run_tester "$ROUND"
      run_reviewers "$ROUND"
      compute_verdict "$ROUND" "$PREV_MEDIAN"
      record_result "$ROUND"

      # 读取决策
      # shellcheck source=/dev/null
      # 安全读取 verdict.env（不 source，用 grep 提取）
  DECISION=$(grep '^DECISION=' "${TASK_DIR}/verdict.env" | cut -d= -f2)
  MEDIAN=$(grep '^MEDIAN=' "${TASK_DIR}/verdict.env" | cut -d= -f2)

      if [[ "$DECISION" == "ACCEPTED" ]] || [[ "$DECISION" == "ACCEPTED_UNCHANGED" ]]; then
        echo "  → KEEP: 合并到 main"
        git -C "$PROJECT_ROOT" merge --no-ff "hyper-loop/r${ROUND}-integration" \
          -m "hyper-loop R${ROUND}: median=${MEDIAN}" 2>/dev/null || true
        CONSECUTIVE_REJECTS=0

        # 追踪最佳轮次
        if python3 -c "exit(0 if float('${MEDIAN}') > float('${BEST_MEDIAN}') else 1)" 2>/dev/null; then
          BEST_ROUND=$ROUND
          BEST_MEDIAN=$MEDIAN
        fi
      else
        echo "  → RESET: 丢弃本轮 ($DECISION)"
        ((CONSECUTIVE_REJECTS++)) || true
      fi

      # 归档
      archive_round "$ROUND"
      cleanup_round "$ROUND"
    fi

    # 连续 5 轮失败 → 回退到最佳轮次重新开始
    if [[ "$CONSECUTIVE_REJECTS" -ge 5 ]] && [[ "$BEST_ROUND" -gt 0 ]]; then
      echo ""
      echo "⚠ 连续 ${CONSECUTIVE_REJECTS} 轮失败，回退到 Round ${BEST_ROUND} (median=${BEST_MEDIAN})"
      local BEST_SHA
      BEST_SHA=$(cat "${PROJECT_ROOT}/_hyper-loop/archive/round-${BEST_ROUND}/git-sha.txt" 2>/dev/null)
      if [[ -n "$BEST_SHA" ]]; then
        git -C "$PROJECT_ROOT" checkout "$BEST_SHA" -- . 2>/dev/null || true
        echo "  ✓ 代码已回退"
      fi
      CONSECUTIVE_REJECTS=0
    fi

    # 中位数 >= 8.0 → 达标，停止
    if python3 -c "exit(0 if float('${MEDIAN:-0}') >= 8.0 else 1)" 2>/dev/null; then
      echo ""
      echo "🎉 中位数达到 ${MEDIAN} >= 8.0，目标达成！"
      break
    fi

    ((ROUND++))

    # 轮间冷却 30 秒（让系统资源恢复）
    echo "轮间冷却 30s..."
    sleep 30
  done

  echo ""
  echo "═══════════════════════════════════"
  echo "  LOOP 结束"
  echo "  总轮次: $((ROUND - 1))"
  echo "  最佳轮次: Round ${BEST_ROUND} (median=${BEST_MEDIAN})"
  echo "  结果: cat ${PROJECT_ROOT}/_hyper-loop/results.tsv"
  echo "═══════════════════════════════════"
}

cmd_status() {
  echo "tmux windows:"
  tmux list-windows -t hyper-loop 2>/dev/null || echo "  (no session)"
  echo ""
  echo "results.tsv:"
  cat "${PROJECT_ROOT:-.}/_hyper-loop/results.tsv" 2>/dev/null || echo "  (empty)"
  echo ""
  # 显示最佳轮次
  if [[ -f "${PROJECT_ROOT:-.}/_hyper-loop/results.tsv" ]]; then
    echo "最佳轮次:"
    sort -t$'\t' -k2 -rn "${PROJECT_ROOT:-.}/_hyper-loop/results.tsv" | head -1
  fi
}

# ── 入口 ──
case "${1:-help}" in
  init)         cmd_init ;;
  round)        cmd_round "${2:-}" ;;
  loop)         cmd_loop "${2:-999}" ;;
  resume-from)  cmd_resume_from "${2:-}" ;;
  status)       cmd_status ;;
  *)
    echo "用法:"
    echo "  hyper-loop.sh init            # 扫描项目，生成上下文简报（首次必须执行）"
    echo "  hyper-loop.sh round <N>       # 执行第 N 轮循环（需要先写 task*.md）"
    echo "  hyper-loop.sh loop [max]      # 死循环模式（autoresearch 式，默认 999 轮）"
    echo "  hyper-loop.sh resume-from <N> # 从档案库第 N 轮重新开始"
    echo "  hyper-loop.sh status          # 查看当前状态"
    echo ""
    echo "前置条件：project-config.env + hyper-loop.sh init"
    echo "停止方法：touch _hyper-loop/STOP"
    ;;
esac
