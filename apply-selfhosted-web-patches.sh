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
# 用法：在 ZCode 仓库根目录执行  bash apply-selfhosted-web-patches.sh
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
PATCHES=(
  "$DIR/0001-self-hosted-web-parity.patch"
  "$DIR/0002-web-connection-guard.patch"
  "$DIR/0003-feat-ui-mobile-drawer-layout-for-sidebar-and-side-pa.patch"
  "$DIR/0004-fix-ui-mobile-drawer-polish-directory-browser-create.patch"
  "$DIR/0005-fix-ui-web-round2-mobile-fixes.patch"
  "$DIR/0006-fix-ui-web-mobile-header-window-controls-padding-per.patch"
)

echo "==> 检查基线（应为 v3.14.3 / 29628c9，其他版本需自行确认可合并）"
current="$(git rev-parse --short HEAD)"
if [[ "$current" != "29628c9" ]]; then
  echo "警告: 当前 HEAD 是 $current 而非 29628c9，将尝试直接 apply（冲突需手工处理）"
fi

echo "==> 检查工作区干净"
if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "错误: 工作区有未提交改动，先 commit 或 stash" >&2
  exit 1
fi

echo "==> 应用补丁"
for p in "${PATCHES[@]}"; do
  if [[ ! -f "$p" ]]; then
    echo "错误: 找不到补丁文件 $p" >&2
    exit 1
  fi
  name="$(basename "$p")"
  if git apply --check "$p" 2>/dev/null; then
    git apply "$p"
    echo "    已应用 $name"
  else
    echo "错误: $name 无法应用（冲突或基线不符）" >&2
    exit 1
  fi
done

echo "==> 完成（全部未提交）。检查无误后自行提交: git add -A && git commit"
echo "==> 重建发行包:"
echo "    pnpm install && pnpm build:zcode"
echo "    产物在 dist/zcode/releases/<version>/，解压到部署目录后重启服务即可。"
