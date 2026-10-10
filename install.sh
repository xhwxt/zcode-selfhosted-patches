#!/usr/bin/env bash
# ZCode 自托管 web 补丁 — 一键安装
# 基线：zai-org/ZCode v3.14.3 (commit 29628c9)
# 内容：全部功能打在同一个文件 zcode-selfhosted-web.patch 里（单次 git apply 可整份应用）
# 用法：在 ZCode 仓库根目录执行  bash install.sh
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
PATCH="$DIR/zcode-selfhosted-web.patch"

if [[ ! -f "$PATCH" ]]; then
  echo "错误: 找不到补丁文件 $PATCH（请在解压后的补丁目录里运行本脚本）" >&2
  exit 1
fi

echo "==> 检查基线（严格模式：基线不符即退出）"
current="$(git rev-parse --short HEAD)"
if [[ "$current" != "29628c9" ]]; then
  echo "错误: 当前 HEAD 是 $current 而非基线 29628c9。" >&2
  echo "      本补丁只对基线 29628c9 做过整体验证；其他版本请先 checkout 基线：" >&2
  echo "      git checkout 29628c9" >&2
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

echo "==> 预检（在临时 index 上试装，失败则原样退出，不留半装状态）"
TMPINDEX="$(mktemp)"
trap 'rm -f "$TMPINDEX"; unset GIT_INDEX_FILE' EXIT
export GIT_INDEX_FILE="$TMPINDEX"
git read-tree HEAD
if ! git apply --cached --check "$PATCH" 2>/tmp/install-precheck.err; then
  echo "错误: 预检失败，补丁与当前代码不匹配：" >&2
  cat /tmp/install-precheck.err >&2
  exit 1
fi
rm -f /tmp/install-precheck.err

echo "==> 应用补丁（单文件，一次到位）"
unset GIT_INDEX_FILE
git apply "$PATCH"

cat <<'ROLLBACK'

==> 完成（全部改动未提交）。
    检查无误后提交:      git add -A && git commit -m "zcode selfhosted web patch"
    发现问题需要回滚:    git checkout -- .        （丢弃全部未提交改动）
    （本脚本保证：预检失败时不会留下半应用状态）

==> 重建发行包:
    pnpm install
    pnpm build:zcode
    产物在 dist/zcode/releases/<version>/，解压到部署目录后重启服务即可。
ROLLBACK
