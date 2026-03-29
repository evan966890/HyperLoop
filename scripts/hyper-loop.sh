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

start_agent() {
  local NAME="$1"    # tmux window name
  local CLI="$2"     # e.g. "codex --full-auto"
  local INIT="$3"    # 初始化文件的绝对路径
  local ROUND="$4"

  tmux new-window -t "hyper-loop" -n "$NAME"
  tmux pipe-pane -o -t "hyper-loop:${NAME}" "cat >> '${LOG_DIR}/${NAME}-r${ROUND}.log'"
  tmux send-keys -t "hyper-loop:${NAME}" "cd ${PROJECT_ROOT} && ${CLI}" Enter
  sleep 3

  # 注入初始化文件（传路径，不传内容）
  local INJECT="/tmp/hyper-loop-inject-${NAME}-r${ROUND}.md"
  {
    echo "请先读以下文件了解你的角色和上下文："
    echo "- 角色定义：${INIT}"
    echo "- BDD 行为规格：${PROJECT_ROOT}/_hyper-loop/context/bdd-specs.md"
    echo "- 评估契约：${PROJECT_ROOT}/_hyper-loop/context/contract.md"
    echo "- 历史评分：${PROJECT_ROOT}/_hyper-loop/results.tsv"
    # 注入最近 3 轮摘要
    if ls "${SUMMARY_DIR}/${NAME}-r"*.md >/dev/null 2>&1; then
      echo "- 你的历史摘要（最近 3 轮）："
      ls -t "${SUMMARY_DIR}/${NAME}-r"*.md 2>/dev/null | head -3 | while read -r f; do
        echo "  - $f"
      done
    fi
    echo ""
    echo "当前是第 ${ROUND} 轮。读完上述文件后回复'已就绪'。"
  } > "$INJECT"

  tmux load-buffer -b "inject-${NAME}-r${ROUND}" "$INJECT"
  tmux paste-buffer -d -r -b "inject-${NAME}-r${ROUND}" -t "hyper-loop:${NAME}"
  tmux send-keys -t "hyper-loop:${NAME}" Enter
  echo "  ✓ ${NAME} started (${CLI})"
}

kill_agent() {
  local NAME="$1"
  tmux kill-window -t "hyper-loop:${NAME}" 2>/dev/null || true
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

    # 启动 Writer（一次性）
    local WRITER_NAME="w-${TASK_NAME}"
    tmux new-window -t hyper-loop -n "$WRITER_NAME"
    tmux pipe-pane -o -t "hyper-loop:${WRITER_NAME}" "cat >> '${LOG_DIR}/${WRITER_NAME}.log'"
    tmux send-keys -t "hyper-loop:${WRITER_NAME}" \
      "cd ${WT} && codex --dangerously-bypass-approvals-and-sandbox" Enter

    # 等 Codex 启动 + 按过 "Do you trust this directory?" 确认
    # Codex 即使用了 --dangerously-bypass 仍会弹 trust 确认
    sleep 3
    tmux send-keys -t "hyper-loop:${WRITER_NAME}" Enter  # 按 Enter 确认 trust
    sleep 2

    # 注入 WRITER_INIT（Codex 已经进入交互模式后）
    tmux load-buffer -b "winit-${TASK_NAME}" "${WT}/WRITER_INIT.md"
    tmux paste-buffer -d -r -b "winit-${TASK_NAME}" -t "hyper-loop:${WRITER_NAME}"
    tmux send-keys -t "hyper-loop:${WRITER_NAME}" Enter

    echo "  ✓ Writer ${TASK_NAME} started in ${WT}"
  done
}

wait_writers() {
  local ROUND="$1"
  local TIMEOUT="${2:-900}"  # 默认 15 分钟

  echo "等待所有 Writer 完成（超时 ${TIMEOUT}s）..."

  local START_TIME
  START_TIME=$(date +%s)

  while true; do
    local ALL_DONE=true
    for WT in "${WORKTREE_BASE}"/task*; do
      [[ -d "$WT" ]] || continue
      if [[ ! -f "${WT}/DONE.json" ]]; then
        ALL_DONE=false
        break
      fi
    done

    if $ALL_DONE; then
      echo "  ✓ 所有 Writer 已完成"
      break
    fi

    local ELAPSED=$(( $(date +%s) - START_TIME ))
    if [[ "$ELAPSED" -gt "$TIMEOUT" ]]; then
      echo "  ⚠ 超时，强制结束未完成的 Writer"
      for WT in "${WORKTREE_BASE}"/task*; do
        [[ -f "${WT}/DONE.json" ]] || echo '{"status":"timeout"}' > "${WT}/DONE.json"
      done
      break
    fi

    sleep 10
  done

  # 关闭 writer windows
  tmux list-windows -t hyper-loop -F '#{window_name}' 2>/dev/null | grep '^w-' | while read -r w; do
    tmux kill-window -t "hyper-loop:${w}" 2>/dev/null || true
  done
}

# ── Diff 审计（autoresearch 启示：产出必须在可控范围内）──
audit_writer_diff() {
  local WT="$1"
  local TASK_FILE="${WT}/TASK.md"

  # 从 TASK.md 提取"相关文件"列表
  local ALLOWED_FILES
  ALLOWED_FILES=$(grep -A 20 '### 相关文件' "$TASK_FILE" 2>/dev/null | \
    grep -oE '[-a-zA-Z0-9_./ ]+\.(rs|svelte|ts|js|tsx|jsx|css|py|go|html)' | \
    sed 's/^[[:space:]]*//' | sort -u || true)

  if [[ -z "$ALLOWED_FILES" ]]; then
    echo "  ⚠ TASK.md 没有指定相关文件，跳过审计"
    return 0
  fi

  # 获取实际改了哪些文件
  local CHANGED_FILES
  CHANGED_FILES=$(git -C "$WT" diff --name-only HEAD 2>/dev/null | sort -u)

  if [[ -z "$CHANGED_FILES" ]]; then
    echo "  ⚠ Writer 没有改任何文件"
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
      DONE.json|WRITER_INIT.md|_ctx/*|TASK.md) FOUND=true ;;
    esac

    if ! $FOUND; then
      VIOLATIONS="${VIOLATIONS}    越界: ${changed}\n"
    fi
  done <<< "$CHANGED_FILES"

  if [[ -n "$VIOLATIONS" ]]; then
    echo "  ✗ Diff 审计失败：Writer 改了 TASK.md 范围外的文件"
    echo -e "$VIOLATIONS"
    return 1
  fi

  echo "  ✓ Diff 审计通过"
  return 0
}

# ── 合并 ──
merge_writers() {
  local ROUND="$1"
  local INTEGRATION_BRANCH="hyper-loop/r${ROUND}-integration"
  local INTEGRATION_WT="${WORKTREE_BASE}/integration"
  local BASE_SHA
  BASE_SHA=$(git -C "$PROJECT_ROOT" rev-parse HEAD)

  git -C "$PROJECT_ROOT" worktree add "$INTEGRATION_WT" -b "$INTEGRATION_BRANCH" "$BASE_SHA" 2>/dev/null

  local MERGED=0
  local FAILED=0

  echo "合并 Writer 产出..."

  for WT in "${WORKTREE_BASE}"/task*; do
    [[ -d "$WT" ]] || continue
    local TASK_NAME
    TASK_NAME=$(basename "$WT")

    local STATUS
    STATUS=$(python3 -c "import json; print(json.load(open('${WT}/DONE.json'))['status'])" 2>/dev/null || echo "unknown")
    if [[ "$STATUS" != "done" ]]; then
      echo "  ⚠ ${TASK_NAME}: status=${STATUS}, 跳过"
      ((FAILED++)) || true
      continue
    fi

    # Diff 审计：检查 Writer 是否只改了指定范围的文件
    if ! audit_writer_diff "$WT"; then
      echo "  ✗ ${TASK_NAME}: diff 审计失败，拒绝合并"
      ((FAILED++)) || true
      continue
    fi

    local BRANCH
    BRANCH=$(git -C "$WT" branch --show-current)

    # 保存 diff
    git -C "$WT" diff HEAD > "${TASK_DIR}/${TASK_NAME}.patch" 2>/dev/null
    git -C "$WT" diff --stat HEAD > "${TASK_DIR}/${TASK_NAME}.stat" 2>/dev/null

    # squash merge
    if git -C "$INTEGRATION_WT" merge "$BRANCH" --squash --no-edit 2>/dev/null; then
      git -C "$INTEGRATION_WT" commit --no-edit -m "hyper-loop R${ROUND} ${TASK_NAME}" 2>/dev/null
      echo "  ✓ ${TASK_NAME} merged"
      ((MERGED++)) || true
    else
      git -C "$INTEGRATION_WT" merge --abort 2>/dev/null || true
      echo "  ✗ ${TASK_NAME} conflict, deferred"
      ((FAILED++)) || true
    fi
  done

  echo "合并完成: ${MERGED} merged, ${FAILED} failed/skipped"
  echo "$INTEGRATION_WT"
}

# ── 构建 ──
build_app() {
  local BUILD_DIR="$1"
  echo "构建 App..."
  cd "$BUILD_DIR"
  eval "${CACHE_CLEAN:-true}" 2>/dev/null || true
  if eval "${BUILD_CMD:-echo 'no BUILD_CMD'}"; then
    echo "  ✓ 构建成功"
    return 0
  else
    echo "  ✗ 构建失败"
    return 1
  fi
}

# ── Tester ──
run_tester() {
  local ROUND="$1"

  echo "启动 Tester..."
  start_agent "tester" "claude --dangerously-skip-permissions" \
    "${PROJECT_ROOT}/_hyper-loop/context/TESTER_INIT.md" "$ROUND"

  sleep 5
  local TEST_REQ="/tmp/hyper-loop-test-req-r${ROUND}.md"
  cat > "$TEST_REQ" <<TREQ
## 试用请求 Round $ROUND

App 已构建。请执行以下操作：

1. 先读 ${PROJECT_ROOT}/_hyper-loop/context/bdd-specs.md 了解所有 BDD 场景
2. 运行后台测试：cd ${PROJECT_ROOT} && ${BUILD_VERIFY:-echo 'no verify cmd'}
3. 按 BDD spec 逐条验证，每个 Then 截图到 ${SCREENSHOT_DIR}/
4. 写试用报告到 ${REPORT_FILE}
5. 报告格式：每个场景 pass/fail + 截图路径 + P0/P1 bug 列表
6. 完成后输出：HYPERLOOP_TEST_DONE
TREQ

  tmux load-buffer -b "test-req-r${ROUND}" "$TEST_REQ"
  tmux paste-buffer -d -r -b "test-req-r${ROUND}" -t hyper-loop:tester
  tmux send-keys -t hyper-loop:tester Enter

  echo "等待 Tester 完成（最多 10 分钟）..."
  local WAITED=0
  while [[ ! -f "$REPORT_FILE" ]] && [[ "$WAITED" -lt 600 ]]; do
    sleep 15
    ((WAITED += 15))
    if ! tmux list-panes -t hyper-loop:tester >/dev/null 2>&1; then
      echo "  ⚠ Tester 进程已退出"
      break
    fi
  done

  if [[ -f "$REPORT_FILE" ]]; then
    echo "  ✓ 试用报告已生成: $REPORT_FILE"
  else
    echo "  ⚠ Tester 超时，生成空报告"
    echo "# Round $ROUND 试用报告（Tester 超时）" > "$REPORT_FILE"
    echo "Tester 未在 10 分钟内完成。需要人工验证。" >> "$REPORT_FILE"
  fi

  kill_agent "tester"
}

# ── 3 Reviewer 合议 ──
run_reviewers() {
  local ROUND="$1"

  echo "启动 3 个 Reviewer..."

  local REVIEW_REQ="/tmp/hyper-loop-review-r${ROUND}.md"
  {
    echo "## 评审请求 Round $ROUND"
    echo ""
    echo "请读以下文件后打分："
    echo "- 评估契约：${PROJECT_ROOT}/_hyper-loop/context/contract.md"
    echo "- BDD 规格：${PROJECT_ROOT}/_hyper-loop/context/bdd-specs.md"
    echo "- Tester 试用报告：${REPORT_FILE}"
    echo "- 截图目录：${SCREENSHOT_DIR}/"
    echo "- 本轮 diff："
    for STAT in "${TASK_DIR}"/*.stat; do
      [[ -f "$STAT" ]] && cat "$STAT"
    done
    echo ""
    echo "输出要求：只输出一个 JSON，格式："
    echo '{"score":数字,"issues":[{"severity":"P0","desc":"描述"}],"summary":"一句话"}'
    echo ""
    echo "把 JSON 写入文件 ${SCORES_DIR}/你的角色名.json 后输出：HYPERLOOP_REVIEW_DONE"
  } > "$REVIEW_REQ"

  local REVIEWERS=("reviewer-a:gemini --yolo" "reviewer-b:claude --dangerously-skip-permissions" "reviewer-c:codex --full-auto")

  for ENTRY in "${REVIEWERS[@]}"; do
    local NAME="${ENTRY%%:*}"
    local CLI="${ENTRY#*:}"

    start_agent "$NAME" "$CLI" \
      "${PROJECT_ROOT}/_hyper-loop/context/REVIEWER_INIT.md" "$ROUND"
    sleep 2

    tmux load-buffer -b "review-${NAME}-r${ROUND}" "$REVIEW_REQ"
    tmux paste-buffer -d -r -b "review-${NAME}-r${ROUND}" -t "hyper-loop:${NAME}"
    tmux send-keys -t "hyper-loop:${NAME}" Enter
  done

  echo "等待 3 个 Reviewer 完成（最多 5 分钟）..."
  local WAITED=0
  while [[ "$WAITED" -lt 300 ]]; do
    local DONE_COUNT=0
    for NAME in reviewer-a reviewer-b reviewer-c; do
      [[ -f "${SCORES_DIR}/${NAME}.json" ]] && ((DONE_COUNT++)) || true
    done
    [[ "$DONE_COUNT" -ge 3 ]] && break
    sleep 15
    ((WAITED += 15))
  done

  # 降级：从 pane 输出提取 JSON
  for NAME in reviewer-a reviewer-b reviewer-c; do
    if [[ ! -f "${SCORES_DIR}/${NAME}.json" ]]; then
      echo "  ⚠ ${NAME} 未写文件，从 pane 提取..."
      tmux capture-pane -t "hyper-loop:${NAME}" -p -S - > "/tmp/hyper-loop-pane-${NAME}.txt" 2>/dev/null || true
      python3 - "/tmp/hyper-loop-pane-${NAME}.txt" "${SCORES_DIR}/${NAME}.json" <<'PYEXTRACT' 2>/dev/null || true
import json, sys
from pathlib import Path
text = Path(sys.argv[1]).read_text()
decoder = json.JSONDecoder()
last = None
for i, ch in enumerate(text):
    if ch != "{": continue
    try:
        obj, _ = decoder.raw_decode(text[i:])
        if "score" in obj: last = obj
    except: pass
if last:
    Path(sys.argv[2]).write_text(json.dumps(last, ensure_ascii=False, indent=2))
    print(f"  ✓ extracted score: {last.get('score')}")
else:
    Path(sys.argv[2]).write_text('{"score":0,"issues":[],"summary":"未能获取评分"}')
    print("  ✗ no score found")
PYEXTRACT
    fi
  done

  for NAME in reviewer-a reviewer-b reviewer-c; do
    kill_agent "$NAME"
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
    tester_p0 = "P0" in text and ("bug" in text.lower() or "fail" in text.lower())

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
    f.write(f"SCORES={' '.join(str(s) for s in scores)}\n")
PYVERDICT

  echo "═══════════════════════════════════"
}

# ── 清理 ──
cleanup_round() {
  local ROUND="$1"

  tmux list-windows -t hyper-loop -F '#{window_name}' 2>/dev/null | grep -E '^w-|^tester|^reviewer' | while read -r w; do
    tmux kill-window -t "hyper-loop:${w}" 2>/dev/null || true
  done

  for WT in "${WORKTREE_BASE}"/task* "${WORKTREE_BASE}/integration"; do
    [[ -d "$WT" ]] || continue
    local BRANCH
    BRANCH=$(git -C "$WT" branch --show-current 2>/dev/null || true)
    git -C "$PROJECT_ROOT" worktree remove "$WT" --force 2>/dev/null || true
    [[ -n "$BRANCH" ]] && git -C "$PROJECT_ROOT" branch -D "$BRANCH" 2>/dev/null || true
  done

  cp "${TASK_DIR}/verdict.env" "${PROJECT_ROOT}/_hyper-loop/archive/round-${ROUND}/" 2>/dev/null || true
}

# ── 记录结果 ──
record_result() {
  local ROUND="$1"
  local VERDICT_FILE="${TASK_DIR}/verdict.env"

  [[ -f "$VERDICT_FILE" ]] || return
  # shellcheck source=/dev/null
  . "$VERDICT_FILE"

  printf '%s\t%s\t%s\t%s\n' \
    "$ROUND" "${MEDIAN:-0}" "${SCORES:-}" "${DECISION:-ERROR}" \
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
  if [[ -f "${PROJECT_ROOT}/_hyper-loop/results.tsv" ]]; then
    PREV_MEDIAN=$(tail -1 "${PROJECT_ROOT}/_hyper-loop/results.tsv" | cut -f2 || echo 0)
  fi

  start_writers "$ROUND"
  wait_writers "$ROUND"

  local INTEGRATION_WT
  INTEGRATION_WT=$(merge_writers "$ROUND")

  if ! build_app "$INTEGRATION_WT"; then
    echo "构建失败，跳过 Tester 和 Reviewer"
    echo "DECISION=BUILD_FAILED" > "${TASK_DIR}/verdict.env"
    echo "MEDIAN=0" >> "${TASK_DIR}/verdict.env"
    record_result "$ROUND"
    cleanup_round "$ROUND"
    return 1
  fi

  run_tester "$ROUND"
  run_reviewers "$ROUND"
  compute_verdict "$ROUND" "$PREV_MEDIAN"
  record_result "$ROUND"

  echo ""
  # shellcheck source=/dev/null
  . "${TASK_DIR}/verdict.env"

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

cmd_status() {
  echo "tmux windows:"
  tmux list-windows -t hyper-loop 2>/dev/null || echo "  (no session)"
  echo ""
  echo "results.tsv:"
  cat "${PROJECT_ROOT:-.}/_hyper-loop/results.tsv" 2>/dev/null || echo "  (empty)"
}

# ── 自动拆解下一轮任务（基于上一轮结果）──
auto_decompose() {
  local ROUND="$1"
  local TASK_DIR="${PROJECT_ROOT}/_hyper-loop/tasks/round-${ROUND}"
  mkdir -p "$TASK_DIR"

  echo "自动拆解 Round ${ROUND} 任务..."

  # 用 Claude 非交互模式拆解任务
  local DECOMPOSE_PROMPT="/tmp/hyper-loop-decompose-r${ROUND}.md"
  cat > "$DECOMPOSE_PROMPT" <<DPROMPT
你是 HyperLoop 的任务拆解器。请基于以下信息拆解本轮任务。

## 上下文
- BDD 行为规格：${PROJECT_ROOT}/_hyper-loop/bdd-specs.md
- 评估契约：${PROJECT_ROOT}/_hyper-loop/contract.md
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
每个任务写成一个独立的 markdown 文件，保存到 ${TASK_DIR}/taskN.md。

每个文件格式：
\`\`\`
## 修复任务: TASK-N
### 上下文
先读 _ctx/ 下所��文件。
### 问题
[优先级] 具体问题描述
### 相关文件
- 具体文件路径 (行号范围)
### 约束
- 只修指定文件
- 不改 CSS
### 验收标准
引用 BDD 场景 SXXX
\`\`\`

直接写文件，不要输出到 stdout。
DPROMPT

  claude --dangerously-skip-permissions -p "$(cat "$DECOMPOSE_PROMPT")" \
    --add-dir "$PROJECT_ROOT" \
    > "${PROJECT_ROOT}/_hyper-loop/logs/decompose-r${ROUND}.log" 2>&1 || true

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

  cp "${PROJECT_ROOT}/_hyper-loop/bdd-specs.md" "$ARCHIVE/" 2>/dev/null || true
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

# ── 死循环模式（autoresearch 启示：NEVER STOP）──
cmd_loop() {
  local MAX_ROUNDS="${1:-999}"
  local STOP_FILE="${PROJECT_ROOT:-.}/_hyper-loop/STOP"

  load_config

  echo ""
  echo "╔══════════════════════════════════════════════════╗"
  echo "║  HyperLoop LOOP 模式 — 最多 ${MAX_ROUNDS} 轮             "
  echo "║  创建 _hyper-loop/STOP 文件可优雅停止          "
  echo "╚══════════════════════════════════════════════════╝"
  echo ""

  # 确定起始轮次
  local ROUND=1
  if [[ -f "${PROJECT_ROOT}/_hyper-loop/results.tsv" ]]; then
    local LAST_ROUND
    LAST_ROUND=$(tail -1 "${PROJECT_ROOT}/_hyper-loop/results.tsv" | cut -f1 || echo 0)
    ROUND=$((LAST_ROUND + 1))
  fi

  local CONSECUTIVE_REJECTS=0
  local BEST_ROUND=0
  local BEST_MEDIAN=0

  while [[ "$ROUND" -le "$MAX_ROUNDS" ]]; do
    # 检查停止信号
    if [[ -f "$STOP_FILE" ]]; then
      echo "检测到 STOP 文件，优雅退出"
      rm "$STOP_FILE"
      break
    fi

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  LOOP: Round ${ROUND}/${MAX_ROUNDS}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # 自动拆解任务
    auto_decompose "$ROUND"

    # 执行本轮
    init_dirs "$ROUND"
    ensure_session

    local PREV_MEDIAN=0
    if [[ -f "${PROJECT_ROOT}/_hyper-loop/results.tsv" ]]; then
      PREV_MEDIAN=$(tail -1 "${PROJECT_ROOT}/_hyper-loop/results.tsv" | cut -f2 || echo 0)
    fi

    start_writers "$ROUND"
    wait_writers "$ROUND"

    local INTEGRATION_WT
    INTEGRATION_WT=$(merge_writers "$ROUND")

    if ! build_app "$INTEGRATION_WT"; then
      echo "构建失败"
      echo "DECISION=BUILD_FAILED" > "${TASK_DIR}/verdict.env"
      echo "MEDIAN=0" >> "${TASK_DIR}/verdict.env"
      record_result "$ROUND"
      cleanup_round "$ROUND"
      ((CONSECUTIVE_REJECTS++)) || true
    else
      run_tester "$ROUND"
      run_reviewers "$ROUND"
      compute_verdict "$ROUND" "$PREV_MEDIAN"
      record_result "$ROUND"

      # 读取决策
      # shellcheck source=/dev/null
      . "${TASK_DIR}/verdict.env"

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
  round)        cmd_round "${2:-}" ;;
  loop)         cmd_loop "${2:-999}" ;;
  resume-from)  cmd_resume_from "${2:-}" ;;
  status)       cmd_status ;;
  *)
    echo "用法:"
    echo "  hyper-loop.sh round <N>       # 执行第 N 轮循环（需要先写 task*.md）"
    echo "  hyper-loop.sh loop [max]      # 死循环模式（autoresearch 式，默认 999 轮）"
    echo "  hyper-loop.sh resume-from <N> # 从档案库第 N 轮重新开始"
    echo "  hyper-loop.sh status          # 查看当前状态"
    echo ""
    echo "前置条件：Claude Code 已完成 Phase 0（BDD spec + project-config.env）"
    echo "停止方法：touch _hyper-loop/STOP"
    ;;
esac
