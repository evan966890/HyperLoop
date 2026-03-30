## 修复任务: TASK-4
### 上下文
先读 _ctx/ 下所有文件。
### 问题
[P1] 三处代码卫生问题合并修复

**4a. build_app 改变 cwd 未恢复 (L367)**
```bash
build_app() {
  local BUILD_DIR="$1"
  cd "$BUILD_DIR"   # ← 改变了 shell cwd，函数返回后不恢复
```
后续函数多用绝对路径暂无影响，但长期运行是隐患。

**4b. cmd_status 重复定义 (L673-679 vs L935)**
两处定义 `cmd_status()`，L673-679 是死代码（被 L935 的定义覆盖）。

**4c. 注释与代码不一致 (L476)**
注释写 "fallback 给 3 分"，但实际 fallback 给 5 分 (L479):
```bash
# 确保所有评分文件存在（fallback 给 3 分）  ← 注释错误
echo '{"score":5,...}'                          ← 实际给 5 分
```

### 相关文件
- scripts/hyper-loop.sh (L364-376 build_app; L673-679 第一个 cmd_status; L476 注释)

### 修复方案
**4a**: 用 subshell 隔离 cd：
```bash
build_app() {
  local BUILD_DIR="$1"
  echo "构建 App..."
  (
    cd "$BUILD_DIR" || return 1
    eval "${CACHE_CLEAN:-true}" 2>/dev/null || true
    if eval "${BUILD_CMD:-echo 'no BUILD_CMD'}"; then
      echo "  ✓ 构建成功"
      return 0
    else
      echo "  ✗ 构建失败"
      return 1
    fi
  )
}
```

**4b**: 删除 L673-679 的第一个 cmd_status 定义。

**4c**: 将 L476 注释改为 `# 确保所有评分文件存在（fallback 给 5 分）`

### 约束
- 只修 scripts/hyper-loop.sh 中指定的三处
- 每处修改不超过 5 行
- 不改 CSS
### 验收标准
引用 BDD 场景 S007 — build_app 后 cwd 不影响后续函数；脚本中只有一个 cmd_status 定义；注释与代码一致
