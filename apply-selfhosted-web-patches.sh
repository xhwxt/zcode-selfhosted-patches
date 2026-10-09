#!/usr/bin/env bash
# ZCode 自托管 web 增强补丁 — 一键应用脚本
# 基线：zai-org/ZCode v3.14.3 (commit 29628c9)
# 补丁内容：
#   0001 web parity（5 项：用户名、会话恢复、目录浏览器、draft 输入等）
#   0002 web 连接守卫（后台断连提示 + 回前台自动恢复）
#   0003 手机抽屉布局（<768px 左侧栏/右侧面板浮层化 + 左上角开关 + 遮罩）
#   0004 抽屉打磨 + 目录浏览器新建文件夹（IFileService.createDirectory）
#   0005 二轮实测修复（高度对齐/抽屉互斥/守卫误判/触屏操作栏/问答解析）
#   0006 三轮恢复体验（header 空垫/滚动记忆持久化+收敛/软重连/恢复锚定）
#   0007 WS 连接存活与恢复系列（多提交 mbox，39 个提交）：半开判死 →
#        心跳/热换底/原地恢复 → SW v8（探针 scripts 走 network-first）→ 标题收敛
# 用法：在 ZCode 仓库根目录执行  bash apply-selfhosted-web-patches.sh
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"

# 展开补丁为「可直接 git apply 的单元」。
# 为什么需要：0007 是 `git format-patch` 产物（多个提交的 mbox）。单次 `git apply`
# 把整份 mbox 当一个补丁应用时，同一文件被多个提交改到的后续 hunk 会因上下文
# 不匹配而失败（git apply 不按提交推进快照）——实测 38 提交的 mbox 必失败。
# 这里按提交拆分后逐个应用；单提交补丁（0000–0006）原样返回。
SPLIT_DIRS=()
cleanup_split_dirs() {
  local d
  for d in "${SPLIT_DIRS[@]:-}"; do
    [[ -n "$d" ]] && rm -rf "$d"
  done
  return 0
}
trap cleanup_split_dirs EXIT

expand_patch() {
  local p="$1" n d
  n="$(grep -c '^From [0-9a-f]\{40\} ' "$p" 2>/dev/null || true)"
  if [[ "${n:-0}" -gt 1 ]]; then
    d="$(mktemp -d)"; SPLIT_DIRS+=("$d")
    git mailsplit -o"$d" "$p" >/dev/null
    find "$d" -type f | sort
  else
    printf '%s\n' "$p"
  fi
}

# 默认走拆分序列 0001→0007；ALL_IN_ONE=1 时改用单文件 0000（二者等价，二选一）。
if [[ "${ALL_IN_ONE:-0}" == "1" ]]; then
  PATCHES=(
    "$DIR/0000-all-in-one-selfhosted-web.patch"
  )
else
  PATCHES=(
    "$DIR/0001-self-hosted-web-parity.patch"
    "$DIR/0002-web-connection-guard.patch"
    "$DIR/0003-feat-ui-mobile-drawer-layout-for-sidebar-and-side-pa.patch"
    "$DIR/0004-fix-ui-mobile-drawer-polish-directory-browser-create.patch"
    "$DIR/0005-fix-ui-web-round2-mobile-fixes.patch"
    "$DIR/0006-fix-ui-web-mobile-header-window-controls-padding-per.patch"
    "$DIR/0007-fix-rpc-client-server-websocket-keepalive-liveness.patch"
  )
fi

echo "==> 检查基线（严格模式：基线不符即退出）"
current="$(git rev-parse --short HEAD)"
if [[ "$current" != "29628c9" ]]; then
  echo "错误: 当前 HEAD 是 $current 而非基线 29628c9。" >&2
  echo "      本补丁组只对基线 29628c9 做过整组验证；其他版本请先 checkout 基线。" >&2
  echo "      （确需强行为之：修改本脚本的 STRICT=0，风险自负）" >&2
  if [[ "${STRICT:-1}" == "1" ]]; then
    exit 1
  fi
fi

echo "==> 检查工作区干净"
if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "错误: 工作区有未提交改动，先 commit 或 stash" >&2
  exit 1
fi

echo "==> 整组预检（在临时 index 上按序累积应用，任一失败即退出，不留半应用状态）"
TMPINDEX="$(mktemp)"
export GIT_INDEX_FILE="$TMPINDEX"
git read-tree HEAD
PRECHECK_OK=1
for p in "${PATCHES[@]}"; do
  if [[ ! -f "$p" ]]; then
    echo "错误: 找不到补丁文件 $p" >&2
    PRECHECK_OK=0
    break
  fi
  # --cached 在临时 index 上累积应用：与真实应用的工作区状态完全同构。
  # 逐「提交单元」应用（多提交补丁已由 expand_patch 拆开）。
  while IFS= read -r part; do
    if ! git apply --cached --check "$part" 2>/dev/null; then
      echo "错误: 预检失败 $p（与前面补丁叠加后冲突或基线不符）" >&2
      echo "      未应用任何改动，工作区保持干净。" >&2
      PRECHECK_OK=0
      break
    fi
    git apply --cached "$part" 2>/dev/null
  done < <(expand_patch "$p")
  [[ "$PRECHECK_OK" != "1" ]] && break
  echo "    预检通过 $(basename "$p")"
done
rm -f "$TMPINDEX"
unset GIT_INDEX_FILE
if [[ "$PRECHECK_OK" != "1" ]]; then
  git read-tree HEAD   # 还原临时 index 之外的任何残留
  exit 1
fi
echo "    预检通过：全部 ${#PATCHES[@]} 个补丁可依次应用"

echo "==> 应用补丁"
for p in "${PATCHES[@]}"; do
  name="$(basename "$p")"
  while IFS= read -r part; do
    git apply "$part"
  done < <(expand_patch "$p")
  echo "    已应用 $name"
done

cat <<'ROLLBACK'

==> 完成（全部未提交）。
    检查无误后提交:  git add -A && git commit
    发现问题需要回滚: git apply -R --reverse <补丁文件> 逐个逆向应用，
                      或直接 git checkout -- . 丢弃全部未提交改动
                    （本脚本保证失败时不会留下半应用状态）。
ROLLBACK
echo "==> 重建发行包:"
echo "    pnpm install && pnpm build:zcode"
echo "    产物在 dist/zcode/releases/<version>/，解压到部署目录后重启服务即可。"
