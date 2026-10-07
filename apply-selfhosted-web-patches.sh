#!/usr/bin/env bash
# ZCode 自托管 web 增强补丁 — 一键应用脚本
# 基线：zai-org/ZCode v3.14.3 (commit 29628c9)
# 用法：在 ZCode 仓库根目录执行  bash apply-selfhosted-web-patches.sh
set -euo pipefail

PATCH_FILE="$(cd "$(dirname "$0")" && pwd)/0001-self-hosted-web-parity.patch"

if [[ ! -f "$PATCH_FILE" ]]; then
  echo "错误: 找不到补丁文件 $PATCH_FILE" >&2
  exit 1
fi

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
if git apply --check "$PATCH_FILE" 2>/dev/null; then
  git apply "$PATCH_FILE"
  echo "==> 已应用（未提交）。检查无误后自行提交，或运行: git commit -am 'apply selfhosted web patches'"
else
  echo "git apply 冲突，尝试 git am（保留提交信息）"
  git am "$PATCH_FILE"
fi

echo "==> 完成。重建发行包:"
echo "    pnpm install && pnpm build:zcode --base-url https://your-domain/dist/"
echo "    产物在 dist/zcode/releases/<version>/，解压到部署目录后重启服务即可。"
