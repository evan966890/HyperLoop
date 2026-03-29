#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# HyperLoop v5.2 — 编排脚本
#
# 这个脚本硬编码了多 Agent 编排流程。Claude Code 调用它，不需要"记住"要做什么。
# 脚本负责：启动子进程 → 等完成 → 收集结果 → 输出决策建议
# Claude Code 负责：Phase 0 决策（BDD/任务拆解）+ 读结果做下一轮决策
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

    # 生成 Writer 初始化
    cat > "${WT}/WRITER_INIT.md" <<WINIT
你是 HyperLoop Writer。请按以下步骤工作：

1. 先读 _ctx/ 下所有 .md 文件了解项目背景
2. 再读 TASK.md 了解本次任务
3. 完成代码修改
4. 运行验证命令确认无报错
5. 将结果写入 DONE.json：
   {"status":"done","files_changed":["file1"],"lint_pass":true}
6. 最后一行输出：HYPERLOOP_TASK_DONE
WINIT

    # 启动 Writer（一次性）
    local WRITER_NAME="w-${TASK_NAME}"
    tmux new-window -t hyper-loop -n "$WRITER_NAME"
    tmux pipe-pane -o -t "hyper-loop:${WRITER_NAME}" "cat >> '${LOG_DIR}/${WRITER_NAME}.log'"
    tmux send-keys -t "hyper-loop:${WRITER_NAME}" \
      "cd ${WT} && codex --dangerously-bypass-approvals-and-sandbox" Enter
    sleep 2
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

# ── 入口 ──
case "${1:-help}" in
  round)  cmd_round "${2:-}" ;;
  status) cmd_status ;;
  *)
    echo "用法:"
    echo "  hyper-loop.sh round <N>   # 执行第 N 轮循环"
    echo "  hyper-loop.sh status      # 查看当前状态"
    echo ""
    echo "前置条件：Claude Code 已完成 Phase 0（BDD spec + 任务拆解）"
    ;;
esac
