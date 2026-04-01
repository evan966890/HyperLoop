#!/usr/bin/env bash
set -euo pipefail

# 进程守护：异常退出时记录位置
trap 'echo "[FATAL] line $LINENO exit=$? cmd=$BASH_COMMAND" >> "${PROJECT_ROOT:-.}/_hyper-loop/loop.log" 2>/dev/null' ERR
trap 'echo "[EXIT] exit=$?" >> "${PROJECT_ROOT:-.}/_hyper-loop/loop.log" 2>/dev/null' EXIT

# ============================================================================
# HyperLoop v5.7 — 编排脚本
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

# ── Worktree 环境准备（symlink 共享依赖 + Cargo target 隔离）──
prepare_worktree() {
  local WT="$1"

  # Symlink 共享大体积依赖目录（node_modules 等，npm 读安全）
  for SHARED_DIR in ${SHARED_DEPS:-}; do
    local SRC="${PROJECT_ROOT}/${SHARED_DIR}"
    local DST="${WT}/${SHARED_DIR}"
    if [[ -d "$SRC" ]] && [[ ! -e "$DST" ]]; then
      mkdir -p "$(dirname "$DST")"
      ln -sf "$SRC" "$DST"
      echo "  ↗ symlink: ${SHARED_DIR}" >&2
    fi
  done

  # Cargo target 隔离（每个 worktree 独立，防并行编译死锁）
  # 查找 worktree 内的 Cargo.toml，为每个设置独立 CARGO_TARGET_DIR
  local CARGO_ENV="${WT}/.cargo-env.sh"
  if find "$WT" -maxdepth 3 -name "Cargo.toml" -print -quit 2>/dev/null | grep -q .; then
    echo "export CARGO_TARGET_DIR=\"${WT}/.cargo-target\"" > "$CARGO_ENV"
    echo "  🦀 CARGO_TARGET_DIR=${WT}/.cargo-target" >&2
  fi
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

    # 环境准备：symlink 共享依赖 + Cargo target 隔离
    prepare_worktree "$WT"

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
      # Source Cargo target 隔离环境（如果存在）
      [[ -f "${WT}/.cargo-env.sh" ]] && source "${WT}/.cargo-env.sh"
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

  # 获取实际改了哪些 git 追踪的文件（不含 untracked 编译产物）
  # 编译产物（.cargo-target/, node_modules/, target/ 等）在 .gitignore 里，不会出现在这里
  local CHANGED_FILES
  CHANGED_FILES=$(git -C "$WT" diff --name-only HEAD 2>/dev/null | sort -u)

  if [[ -z "$CHANGED_FILES" ]]; then
    echo "  ⚠ Writer 没有改任何文件" >&2
    return 0
  fi

  # 黑名单：评估文件不可被 Writer 修改（即使 TASK.md 列出了它们）
  local EVAL_VIOLATIONS=""
  while IFS= read -r changed; do
    case "$changed" in
      _hyper-loop/bdd-specs.md|_hyper-loop/contract.md|_hyper-loop/context/bdd-specs.md|_hyper-loop/context/contract.md)
        EVAL_VIOLATIONS="${EVAL_VIOLATIONS}    评估文件不可修改: ${changed}\n" ;;
    esac
  done <<< "$CHANGED_FILES"

  if [[ -n "$EVAL_VIOLATIONS" ]]; then
    echo "  ✗ Diff 审计失败：Writer 试图修改评估文件" >&2
    echo -e "$EVAL_VIOLATIONS" >&2
    return 1
  fi

  # 检查是否有越界改动
  local VIOLATIONS=""
  while IFS= read -r changed; do
    local FOUND=false
    while IFS= read -r allowed; do
      [[ -z "$allowed" ]] && continue
      # 路径匹配：allowed 是 basename 或相对路径，changed 是相对路径
      # 精确匹配 basename 或完整路径（不再子串模糊匹配）
      local changed_base
      changed_base=$(basename "$changed")
      local allowed_base
      allowed_base=$(basename "$allowed")
      if [[ "$changed" == "$allowed" ]] || [[ "$changed_base" == "$allowed_base" ]] || \
         [[ "$changed" == */"$allowed" ]] || [[ "$allowed" == */"$changed" ]]; then
        FOUND=true
        break
      fi
    done <<< "$ALLOWED_FILES"

    # 允许改 DONE.json、WRITER_INIT.md 等 HyperLoop 元数据文件
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

  # 构建 Tester prompt（静态验证 + 可选动态验证）
  local BRIEF_REF=""
  if [[ -f "${PROJECT_ROOT}/_hyper-loop/context/project-brief.md" ]]; then
    BRIEF_REF="7. 读 ${PROJECT_ROOT}/_hyper-loop/context/project-brief.md 了解用户的设计意图，评估代码是否偏离设计"
  fi

  # 如果有分阶段，告诉 Tester 只重点验证当前 Phase
  local PHASE_HINT=""
  if [[ -n "${CURRENT_PHASE:-}" ]] && [[ "${CURRENT_PHASE:-0}" -gt 0 ]]; then
    PHASE_HINT="
**当前处于 Phase ${CURRENT_PHASE}。** 重点验证 Phase ${CURRENT_PHASE} 的场景，但也列出其他场景的状态。
P0 判定仅限 Phase ${CURRENT_PHASE} 的场景。其他 Phase 的 FAIL 不影响本轮评估。"
  fi

  # stepping stones 上下文
  local SS_HINT=""
  local SS_DIR="${PROJECT_ROOT}/_hyper-loop/stepping-stones"
  if [[ -d "$SS_DIR" ]]; then
    local LATEST_SS
    LATEST_SS=$(ls -td "${SS_DIR}"/round-* 2>/dev/null | head -1)
    if [[ -n "$LATEST_SS" ]] && [[ -f "${LATEST_SS}/verdict.env" ]]; then
      local SS_IMPROVED
      SS_IMPROVED=$(grep '^IMPROVED_SCENARIOS=' "${LATEST_SS}/verdict.env" 2>/dev/null | cut -d= -f2- | tr -d '"')
      if [[ -n "$SS_IMPROVED" ]]; then
        SS_HINT="
**上一轮 stepping stone：** 场景 ${SS_IMPROVED} 曾 PASS（patch 在 ${LATEST_SS}/）。如果这些场景现在变 FAIL，是回退。"
      fi
    fi
  fi

  local TESTER_PROMPT="你是代码测试员。请执行以下操作：

1. 读 ${PROJECT_ROOT}/_hyper-loop/context/bdd-specs.md 了解 BDD 场景
2. 读 ${SUMMARY} 了解本轮修改
3. 运行 bash -n ${PROJECT_ROOT}/scripts/hyper-loop.sh 验证语法
4. 按 BDD 场景逐条检查脚本代码，标注 pass/fail
5. 将结果写入 ${REPORT_FILE}，格式：每行一个场景 ID + pass/fail + 原因
6. 列出发现的 P0/P1 bug
${BRIEF_REF}
${PHASE_HINT}
${SS_HINT}

**重要：报告最后必须包含以下两行结构化摘要（verdict 逻辑依赖它们）：**
\`\`\`
BDD_PASS: <通过数>/<总数>
P0_COUNT: <P0 bug 数量>
\`\`\`"

  echo "$TESTER_PROMPT" | timeout 600 claude --dangerously-skip-permissions -p - \
    --add-dir "$PROJECT_ROOT" 2>&1 | \
    tee "${LOG_DIR}/round-${ROUND}_tester_bdd-verify_claude.log" > "${REPORT_FILE}" || true

  if [[ -s "$REPORT_FILE" ]]; then
    echo "  ✓ 静态验证报告已生成: $REPORT_FILE"
  else
    echo "  ⚠ Tester 无输出，生成默认报告"
    echo "# Round $ROUND — Tester 无输出" > "$REPORT_FILE"
  fi

  # ── 动态验证阶段（当 LAUNCH_CMD 存在时）──
  if [[ -n "${LAUNCH_CMD:-}" ]] && [[ "$LAUNCH_CMD" != "echo"* ]]; then
    echo "  启动动态验证（app 截图 + 用户流程）..."
    local APP_PID=""

    # 启动 app（后台）
    (
      cd "$PROJECT_ROOT"
      eval "$LAUNCH_CMD" > "${LOG_DIR}/round-${ROUND}_app_launch.log" 2>&1
    ) &
    APP_PID=$!

    # 等待 app 启动（根据 DEV_SERVER_PORT 或固定等待）
    if [[ -n "${DEV_SERVER_PORT:-}" ]]; then
      echo "  等待端口 ${DEV_SERVER_PORT}..."
      local WAIT_START
      WAIT_START=$(date +%s)
      while ! nc -z localhost "$DEV_SERVER_PORT" 2>/dev/null; do
        if [[ $(( $(date +%s) - WAIT_START )) -gt 30 ]]; then
          echo "  ⚠ app 启动超时（30s），跳过动态验证" >&2
          kill "$APP_PID" 2>/dev/null || true
          APP_PID=""
          break
        fi
        sleep 2
      done
    else
      sleep 10  # 无端口信息，固定等 10 秒
    fi

    if [[ -n "$APP_PID" ]] && kill -0 "$APP_PID" 2>/dev/null; then
      # 构造动态验证 prompt
      local DYN_PROMPT="你是 App 动态测试员。App 已在本机运行。

## 任务
1. 对 web 应用：用 Playwright 浏览器工具访问 http://localhost:${DEV_SERVER_PORT:-3000} 截图
   对 native 应用：用 screencapture 命令截图
2. 按 BDD 场景逐条验证视觉和交互
3. 截图保存到 ${SCREENSHOT_DIR}/
4. 把动态验证结果追加到 ${REPORT_FILE}

截图命令参考：
- Web: npx playwright screenshot http://localhost:${DEV_SERVER_PORT:-3000} ${SCREENSHOT_DIR}/home.png
- Native: screencapture -l \$(osascript -e 'tell app \"${WINDOW_NAME:-App}\" to id of window 1') ${SCREENSHOT_DIR}/window.png
- 通用: screencapture ${SCREENSHOT_DIR}/screen.png"

      echo "$DYN_PROMPT" | timeout 300 claude --dangerously-skip-permissions -p - \
        --add-dir "$PROJECT_ROOT" 2>&1 | \
        tee "${LOG_DIR}/round-${ROUND}_tester_dynamic_claude.log" >> "${REPORT_FILE}" || true

      echo "  ✓ 动态验证完成"

      # 关闭 app
      kill "$APP_PID" 2>/dev/null || true
      wait "$APP_PID" 2>/dev/null || true
    fi
  fi
}

# ── 3 Reviewer 合议（非交互管道模式）──
run_reviewers() {
  local ROUND="$1"

  echo "启动 3 个 Reviewer（非交互模式）..."

  # 构造评审 prompt（注入设计文档 + BDD + Tester 报告）
  local BRIEF_CONTENT=""
  if [[ -f "${PROJECT_ROOT}/_hyper-loop/context/project-brief.md" ]]; then
    BRIEF_CONTENT=$(cat "${PROJECT_ROOT}/_hyper-loop/context/project-brief.md")
  fi

  local REVIEW_PROMPT="你是代码评审官。你的职责是对照用户的**原始设计意图**评估代码质量。

## 用户的设计意图（项目简报，从 BMAD 文档提炼）
${BRIEF_CONTENT:-（项目简报不存在，仅依据 BDD 和契约评分）}

## 评估依据
评估契约：${PROJECT_ROOT}/_hyper-loop/context/contract.md
BDD 规格：${PROJECT_ROOT}/_hyper-loop/context/bdd-specs.md
Tester 报告：${REPORT_FILE}

## 本轮修改
$(for STAT in "${TASK_DIR}"/*.stat; do [[ -f "$STAT" ]] && cat "$STAT"; done)

## 评分要求
1. 读项目简报了解用户的原始设计意图
2. 读 BDD 规格和 Tester 报告了解通过情况
3. 评分时，issues 必须引用设计文档的具体要求（如「简报中要求 X，但当前实现 Y」）
4. 不要自创评分标准——只基于用户的设计文档和 BDD 规格

只输出一个 JSON 对象，不要代码块，不要解释，不要 markdown：
{\"score\":数字0到10,\"issues\":[{\"severity\":\"P0\",\"desc\":\"引用设计文档的具体要求 + 当前偏差\"}],\"summary\":\"一句话总结\"}"

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

  # Prompt 长度检查：>100KB 时裁剪为摘要模式（防止 Gemini 截断/超时）
  local PROMPT_SIZE
  PROMPT_SIZE=$(wc -c < "$REVIEW_PROMPT_FILE" | tr -d ' ')
  if [[ "$PROMPT_SIZE" -gt 102400 ]]; then
    echo "  ⚠ Reviewer prompt 过大 (${PROMPT_SIZE} bytes)，裁剪为摘要模式" >&2
    # 重建 prompt：只用 stat + Tester 报告摘要，不含完整 diff
    {
      echo "$REVIEW_PROMPT" | head -30  # 保留 prompt 头部（角色 + 契约 + BDD 路径）
      echo ""
      echo "## 本轮修改（摘要，原始 prompt 过大已裁剪）"
      for STAT in "${TASK_DIR}"/*.stat; do [[ -f "$STAT" ]] && cat "$STAT"; done
      echo ""
      echo "## Tester 报告摘要"
      head -50 "$REPORT_FILE" 2>/dev/null
      echo ""
      echo "（完整报告见 ${REPORT_FILE}）"
    } > "$REVIEW_PROMPT_FILE"
    echo "  裁剪后: $(wc -c < "$REVIEW_PROMPT_FILE" | tr -d ' ') bytes" >&2
  fi

  # 并行跑 3 个 Reviewer（非交互 -p 模式，stdout 管道提取 JSON）
  (
    timeout 300 gemini -y -p "$(cat "$REVIEW_PROMPT_FILE")" --include-directories "$PROJECT_ROOT" 2>&1 | \
      tee "${LOG_DIR}/round-${ROUND}_reviewer-a_scoring_gemini.log" | \
      python3 -c "$EXTRACT_PY" > "${SCORES_DIR}/reviewer-a.json" 2>/dev/null
    echo "  ✓ reviewer-a (gemini) done: $(python3 -c "import json; print(json.load(open('${SCORES_DIR}/reviewer-a.json'))['score'])" 2>/dev/null || echo 'fallback')"
  ) &

  (
    cat "$REVIEW_PROMPT_FILE" | timeout 300 claude --dangerously-skip-permissions -p - \
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

  # 读取当前 Phase（分阶段 BDD 评估）
  local CURRENT_PHASE="${CURRENT_PHASE:-0}"
  local BDD_FILE="${PROJECT_ROOT}/_hyper-loop/context/bdd-specs.md"

  python3 - "${SCORES[*]}" "$PREV_MEDIAN" "$REPORT_FILE" "${TASK_DIR}/verdict.env" "$CURRENT_PHASE" "$BDD_FILE" <<'PYVERDICT'
import sys, json, re
from pathlib import Path

scores_str, prev_median_str, report_path, output_path, phase_str, bdd_path = sys.argv[1:7]
scores = sorted([float(s) for s in scores_str.split()])
n = len(scores)
median = scores[n//2] if n % 2 else (scores[n//2-1] + scores[n//2]) / 2
max_diff = max(scores) - min(scores)
prev_median = float(prev_median_str)
current_phase = int(phase_str) if phase_str.isdigit() else 0

veto = any(s < 4.0 for s in scores)

# ── 分阶段 BDD 评估 ──
# 如果 BDD spec 有 Phase 标注，只评估当前 Phase 的场景
phase_scenarios = set()
if current_phase > 0:
    bdd = Path(bdd_path)
    if bdd.exists():
        bdd_text = bdd.read_text()
        # 找当前 Phase 包含的场景 ID（## Phase N: ... 下的 ## SXXX / ## GXXX 等）
        in_phase = False
        for line in bdd_text.splitlines():
            phase_match = re.match(r'^##\s+Phase\s+(\d+)', line)
            if phase_match:
                in_phase = (int(phase_match.group(1)) == current_phase)
                continue
            if in_phase:
                # 提取场景 ID（## S001, ## G001, ## C001 等）
                scenario_match = re.match(r'^##\s+([A-Z]\d{3})', line)
                if scenario_match:
                    phase_scenarios.add(scenario_match.group(1))

tester_p0 = False
bdd_phase_pass = 0
bdd_phase_total = 0
bdd_pass_total = 0
bdd_total_total = 0
improved_scenarios = []  # 用于 stepping stones

report = Path(report_path)
if report.exists():
    text = report.read_text()
    # 优先解析结构化摘要行
    p0_match = re.search(r'P0_COUNT:\s*(\d+)', text)
    bdd_match = re.search(r'BDD_PASS:\s*(\d+)\s*/\s*(\d+)', text)

    if bdd_match:
        bdd_pass_total = int(bdd_match.group(1))
        bdd_total_total = int(bdd_match.group(2))

    if p0_match:
        p0_count = int(p0_match.group(1))
        # 分阶段时：只在当前 Phase 有 P0 才否决
        if phase_scenarios:
            # 检查 P0 bug 是否属于当前 Phase 的场景
            p0_in_phase = False
            for s in phase_scenarios:
                if re.search(rf'{s}.*(?:FAIL|fail)', text):
                    p0_in_phase = True
                    break
            tester_p0 = p0_count > 0 and p0_in_phase
        else:
            tester_p0 = p0_count > 0
    else:
        p0_bugs = re.findall(r'^###\s+P0', text, re.MULTILINE)
        bdd_fails = re.findall(r'\|\s*\*?\*?FAIL\*?\*?\s*\|', text)
        tester_p0 = len(p0_bugs) >= 1 and len(bdd_fails) >= 1

    # 统计当前 Phase 的通过率（如果有 Phase）
    if phase_scenarios:
        for s in phase_scenarios:
            bdd_phase_total += 1
            if re.search(rf'\|\s*{s}\s*\|.*PASS', text, re.IGNORECASE):
                bdd_phase_pass += 1

    # 提取有进步的场景（从 FAIL → PASS）用于 stepping stones
    for match in re.finditer(r'\|\s*([A-Z]\d{3})\s*\|.*?(PASS|FAIL)', text, re.IGNORECASE):
        sid, result = match.group(1), match.group(2).upper()
        if result == "PASS":
            improved_scenarios.append(sid)

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

phase_info = ""
if current_phase > 0 and bdd_phase_total > 0:
    phase_info = f" (Phase {current_phase}: {bdd_phase_pass}/{bdd_phase_total})"
print(f"  中位数: {median}")
print(f"  分歧: {max_diff}")
print(f"  否决: {veto}")
print(f"  Tester P0: {tester_p0}")
if phase_info:
    print(f"  Phase: {phase_info}")
print(f"  决策: {decision}")

with open(output_path, 'w') as f:
    f.write(f"DECISION={decision}\n")
    f.write(f"MEDIAN={median}\n")
    f.write(f"MAX_DIFF={max_diff}\n")
    f.write(f"VETO={veto}\n")
    f.write(f"TESTER_P0={tester_p0}\n")
    f.write(f"SCORES=\"{' '.join(str(s) for s in scores)}\"\n")
    f.write(f"CURRENT_PHASE={current_phase}\n")
    f.write(f"BDD_PHASE_PASS={bdd_phase_pass}\n")
    f.write(f"BDD_PHASE_TOTAL={bdd_phase_total}\n")
    f.write(f"IMPROVED_SCENARIOS=\"{' '.join(improved_scenarios)}\"\n")
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
    [[ -f "$f" ]] && echo "$(basename "$f"): $(cat "$f" 2>/dev/null)"
  done
fi)

$(if [[ -n "${CURRENT_PHASE:-}" ]] && [[ "${CURRENT_PHASE:-0}" -gt 0 ]]; then
  echo "## 当前阶段"
  echo "处于 Phase ${CURRENT_PHASE}。只需修复 Phase ${CURRENT_PHASE} 的 BDD 场景，不要试图修复其他 Phase 的问题。"
fi)

$(local SS_DIR="${PROJECT_ROOT}/_hyper-loop/stepping-stones"
if [[ -d "$SS_DIR" ]]; then
  local LATEST_SS
  LATEST_SS=$(ls -td "${SS_DIR}"/round-* 2>/dev/null | head -1)
  if [[ -n "$LATEST_SS" ]]; then
    echo "## Stepping Stones（上一轮有价值的改动）"
    echo "以下 patch 来自之前被 REJECTED 但有部分进步的轮次。Writer 应在这些改动基础上继续，不要重写已验证通过的部分："
    for P in "${LATEST_SS}"/*.patch; do
      [[ -f "$P" ]] && echo "- $(basename "$P"): $(head -5 "$P" 2>/dev/null)"
    done
    local SS_IMPROVED
    SS_IMPROVED=$(grep '^IMPROVED_SCENARIOS=' "${LATEST_SS}/verdict.env" 2>/dev/null | cut -d= -f2- | tr -d '"')
    [[ -n "$SS_IMPROVED" ]] && echo "已通过的场景：${SS_IMPROVED}"
  fi
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

  # ── 文件交集检测：决定并行度 ──
  local PLAN_FILE="${TASK_DIR}/parallel-plan.txt"
  local ALL_FILES_UNIQUE=true

  # 提取每个 task 的"相关文件"
  for TASK_FILE in "$TASK_DIR"/task*.md; do
    [[ -f "$TASK_FILE" ]] || continue
    local TNAME
    TNAME=$(basename "$TASK_FILE" .md)
    grep -A 20 '### 相关文件' "$TASK_FILE" 2>/dev/null | \
      grep -oE '[-a-zA-Z0-9_./ ]+\.(rs|svelte|ts|js|tsx|jsx|css|py|go|html|sh|bash|toml|json|md|yaml|yml)' | \
      sed 's/^[[:space:]]*//' | sort -u > "${TASK_DIR}/${TNAME}.files" 2>/dev/null || true
  done

  # 检测任意两个 task 是否有文件交集
  local TASK_FILES_LIST
  TASK_FILES_LIST=$(ls "${TASK_DIR}"/*.files 2>/dev/null || true)
  if [[ -n "$TASK_FILES_LIST" ]]; then
    local i j
    for i in ${TASK_DIR}/*.files; do
      for j in ${TASK_DIR}/*.files; do
        [[ "$i" == "$j" ]] && continue
        if comm -12 "$i" "$j" 2>/dev/null | grep -q .; then
          ALL_FILES_UNIQUE=false
          break 2
        fi
      done
    done
  fi

  if [[ "$ALL_FILES_UNIQUE" == "true" ]] && [[ "${TASK_COUNT:-1}" -gt 1 ]]; then
    echo "PARALLEL=true" > "$PLAN_FILE"
    echo "WRITER_COUNT=${TASK_COUNT:-1}" >> "$PLAN_FILE"
    echo "  ✓ 文件无交集 → ${TASK_COUNT:-1} Writer 并行"
  else
    echo "PARALLEL=false" > "$PLAN_FILE"
    echo "WRITER_COUNT=1" >> "$PLAN_FILE"
    if [[ "${TASK_COUNT:-1}" -gt 1 ]]; then
      echo "  ⚠ 文件有交集或无法判断 → 1 Writer 串行（合并所有 task）"
      # 合并所有 task 为 task1.md
      {
        for TASK_FILE in "$TASK_DIR"/task*.md; do
          [[ -f "$TASK_FILE" ]] || continue
          cat "$TASK_FILE"
          echo ""
          echo "---"
          echo ""
        done
      } > "${TASK_DIR}/task1-merged.md"
      # 删除原始 task 文件，保留合并版
      rm -f "${TASK_DIR}"/task[2-9]*.md 2>/dev/null
      mv "${TASK_DIR}/task1-merged.md" "${TASK_DIR}/task1.md"
    else
      echo "  ✓ 单任务 → 1 Writer"
    fi
  fi
  rm -f "${TASK_DIR}"/*.files 2>/dev/null
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

  # ── 启动时清理历史残留 ──
  echo "清理历史残留..."
  rm -rf /tmp/hyper-loop-worktrees-* 2>/dev/null || true
  git -C "$PROJECT_ROOT" worktree prune 2>/dev/null || true
  for _BRANCH in $(git -C "$PROJECT_ROOT" branch --list 'hyper-loop/*' 2>/dev/null); do
    git -C "$PROJECT_ROOT" branch -D "$_BRANCH" 2>/dev/null || true
  done
  tmux kill-session -t hyper-loop 2>/dev/null || true

  while [[ "$ROUND" -le "$END_ROUND" ]]; do
    # 写心跳（monitor 用来检测进程是否活着）
    date +%s > "${PROJECT_ROOT}/_hyper-loop/heartbeat"

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
        # Stash dirty working tree 防止 merge 静默失败
        local STASHED=false
        if [[ -n "$(git -C "$PROJECT_ROOT" status --porcelain 2>/dev/null)" ]]; then
          echo "  ⚠ Working tree dirty，先 stash" >&2
          git -C "$PROJECT_ROOT" stash push -m "hyper-loop-r${ROUND}-pre-merge" 2>/dev/null && STASHED=true
        fi
        local PRE_MERGE_SHA
        PRE_MERGE_SHA=$(git -C "$PROJECT_ROOT" rev-parse HEAD 2>/dev/null)
        git -C "$PROJECT_ROOT" merge --no-ff "hyper-loop/r${ROUND}-integration" \
          -m "hyper-loop R${ROUND}: median=${MEDIAN}" 2>/dev/null || true
        local POST_MERGE_SHA
        POST_MERGE_SHA=$(git -C "$PROJECT_ROOT" rev-parse HEAD 2>/dev/null)
        if [[ "$STASHED" == "true" ]]; then
          git -C "$PROJECT_ROOT" stash pop 2>/dev/null || true
        fi
        # 校验 merge 是否真的成功（HEAD 应该变了）
        if [[ "$PRE_MERGE_SHA" == "$POST_MERGE_SHA" ]]; then
          echo "  ⚠ merge 到 main 失败（HEAD 未变），本轮视为 REJECTED" >&2
          ((CONSECUTIVE_REJECTS++)) || true
        else
          echo "  ✓ merge 成功 (${POST_MERGE_SHA:0:8})"
          CONSECUTIVE_REJECTS=0
        fi

        # 追踪最佳轮次
        if python3 -c "exit(0 if float('${MEDIAN}') > float('${BEST_MEDIAN}') else 1)" 2>/dev/null; then
          BEST_ROUND=$ROUND
          BEST_MEDIAN=$MEDIAN
        fi
      else
        echo "  → RESET: 丢弃本轮 ($DECISION)"
        ((CONSECUTIVE_REJECTS++)) || true

        # ── Stepping stones：保留有进步的 REJECTED 轮次 patch ──
        local IMPROVED
        IMPROVED=$(grep '^IMPROVED_SCENARIOS=' "${TASK_DIR}/verdict.env" 2>/dev/null | cut -d= -f2- | tr -d '"')
        if [[ -n "$IMPROVED" ]] && [[ "$IMPROVED" != " " ]]; then
          local SS_DIR="${PROJECT_ROOT}/_hyper-loop/stepping-stones/round-${ROUND}"
          mkdir -p "$SS_DIR"
          # 保存 patch 和 verdict
          for P in "${TASK_DIR}"/*.patch; do
            [[ -f "$P" ]] && cp "$P" "$SS_DIR/"
          done
          cp "${TASK_DIR}/verdict.env" "$SS_DIR/" 2>/dev/null
          echo "  💎 Stepping stone saved: ${IMPROVED} (${SS_DIR})"
        fi
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

    # 中位数 >= 8.0 → 达标
    if python3 -c "exit(0 if float('${MEDIAN:-0}') >= 8.0 else 1)" 2>/dev/null; then
      echo ""
      echo "🎉 中位数达到 ${MEDIAN} >= 8.0"

      # ── 分阶段推进：如果还有下一个 Phase，自动推进 ──
      if [[ -n "${CURRENT_PHASE:-}" ]] && [[ "${CURRENT_PHASE:-0}" -gt 0 ]]; then
        local NEXT_PHASE=$((CURRENT_PHASE + 1))
        # 检查 BDD spec 是否有下一个 Phase
        if grep -q "^## Phase ${NEXT_PHASE}" "${PROJECT_ROOT}/_hyper-loop/context/bdd-specs.md" 2>/dev/null; then
          echo "Phase ${CURRENT_PHASE} 达标！自动推进到 Phase ${NEXT_PHASE}"
          CURRENT_PHASE=$NEXT_PHASE
          # 更新 project-config.env 中的 CURRENT_PHASE
          if grep -q '^CURRENT_PHASE=' "${PROJECT_ROOT}/_hyper-loop/project-config.env" 2>/dev/null; then
            sed -i.bak "s/^CURRENT_PHASE=.*/CURRENT_PHASE=${NEXT_PHASE}/" "${PROJECT_ROOT}/_hyper-loop/project-config.env"
          else
            echo "CURRENT_PHASE=${NEXT_PHASE}" >> "${PROJECT_ROOT}/_hyper-loop/project-config.env"
          fi
          # 重置 PREV_MEDIAN（新 Phase 从 0 开始）
          CONSECUTIVE_REJECTS=0
          echo "  ✓ CURRENT_PHASE=${NEXT_PHASE}，继续循环"
          # 清理 stepping stones（新 Phase 重新开始）
          rm -rf "${PROJECT_ROOT}/_hyper-loop/stepping-stones" 2>/dev/null
          ((ROUND++))
          sleep 30
          continue
        fi
      fi

      # 没有更多 Phase 或未使用分阶段 → 写 REACHED_GOAL 并停止
      echo "所有 Phase 已完成（或未使用分阶段）。写入 REACHED_GOAL。"
      echo "ROUND=${ROUND} MEDIAN=${MEDIAN} PHASE=${CURRENT_PHASE:-all} TIME=$(date '+%Y-%m-%d %H:%M:%S')" \
        > "${PROJECT_ROOT}/_hyper-loop/REACHED_GOAL"
      echo "等待用户确认是否继续。"
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

# ── 监控（Claude watchdog 调用）──
cmd_monitor() {
  load_config 2>/dev/null || true
  local LOGFILE="${PROJECT_ROOT:-.}/_hyper-loop/loop.log"
  local HEARTBEAT="${PROJECT_ROOT:-.}/_hyper-loop/heartbeat"
  local PID_FILE="${PROJECT_ROOT:-.}/_hyper-loop/loop.pid"
  local GOAL_FILE="${PROJECT_ROOT:-.}/_hyper-loop/REACHED_GOAL"

  # 达标检查
  if [[ -f "$GOAL_FILE" ]]; then
    echo "🎉 目标达成！"
    cat "$GOAL_FILE"
    echo "用户决定：继续 → 删除 REACHED_GOAL 并重启 loop；停止 → 完成"
    return 0
  fi

  # 进程状态
  local PID
  PID=$(cat "$PID_FILE" 2>/dev/null || echo "")
  if [[ -n "$PID" ]] && kill -0 "$PID" 2>/dev/null; then
    echo "状态: 运行中 (PID $PID)"
  else
    echo "状态: 已停止"
    echo "最后日志:"
    tail -5 "$LOGFILE" 2>/dev/null
    return 1
  fi

  # 心跳检查
  if [[ -f "$HEARTBEAT" ]]; then
    local LAST NOW AGE
    LAST=$(cat "$HEARTBEAT")
    NOW=$(date +%s)
    AGE=$(( NOW - LAST ))
    echo "心跳: ${AGE}s 前"
    if [[ "$AGE" -gt 300 ]]; then
      echo "⚠ 心跳超时（>5分钟），可能卡住"
    fi
  else
    echo "心跳: 无记录"
  fi

  # 最新结果
  echo "---"
  echo "最近 3 轮:"
  tail -3 "${PROJECT_ROOT:-.}/_hyper-loop/results.tsv" 2>/dev/null || echo "  (无数据)"
  echo "---"
  tail -5 "$LOGFILE" 2>/dev/null
}

# ── 入口 ──
case "${1:-help}" in
  init)         cmd_init ;;
  round)        cmd_round "${2:-}" ;;
  loop)         cmd_loop "${2:-999}" ;;
  resume-from)  cmd_resume_from "${2:-}" ;;
  status)       cmd_status ;;
  monitor)      cmd_monitor ;;
  *)
    echo "用法:"
    echo "  hyper-loop.sh init            # 扫描项目，生成上下文简报（首次必须执行）"
    echo "  hyper-loop.sh round <N>       # 执行第 N 轮循环（需要先写 task*.md）"
    echo "  hyper-loop.sh loop [max]      # 死循环模式（autoresearch 式，默认 999 轮）"
    echo "  hyper-loop.sh resume-from <N> # 从档案库第 N 轮重新开始"
    echo "  hyper-loop.sh status          # 查看当前状态"
    echo "  hyper-loop.sh monitor         # 监控循环状态（Claude watchdog 调用）"
    echo ""
    echo "前置条件：project-config.env + hyper-loop.sh init"
    echo "停止方法：touch _hyper-loop/STOP"
    ;;
esac
