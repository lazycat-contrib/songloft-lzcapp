#!/usr/bin/env bash
# Songloft 懒猫应用一键更新脚本
# 用法: ./update.sh <版本号>
# 示例: ./update.sh 2.10.0
#
# 流程: 更新 package.yml 版本 → 更新 manifest 镜像 → 构建 LPK

set -euo pipefail

# ──────────────────────────────────────────────
# 配置
# ──────────────────────────────────────────────
SERVICE_NAME="songloft-app"
PACKAGE_FILE="package.yml"
MANIFEST_FILE="lzc-manifest.yml"
BUILD_FILE="lzc-build.yml"
# 镜像模板，{version} 会被替换为实际版本号
IMAGE_TEMPLATE="docker.1ms.run/songloft/songloft:{version}"

# ──────────────────────────────────────────────
# 颜色
# ──────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

info()    { echo -e "${GREEN}✓${NC} $*"; }
warn()    { echo -e "${YELLOW}⚠${NC} $*"; }
err()     { echo -e "${RED}✗${NC} $*" >&2; }
step()    { echo -e "${CYAN}${BOLD}▶${NC} $*"; }
header()  { echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; }

die()     { err "$@"; exit 1; }

# ──────────────────────────────────────────────
# 用法
# ──────────────────────────────────────────────
usage() {
  cat <<'EOF'
Songloft 懒猫应用一键更新脚本

用法: ./update.sh <版本号> [选项]

示例:
  ./update.sh 2.10.0              # 更新到 2.10.0
  ./update.sh 2.10.0 --skip-build # 只更新文件，不构建 LPK

选项:
  --skip-build    只更新文件，不构建 LPK
  -h, --help     显示帮助
EOF
}

# ──────────────────────────────────────────────
# 解析参数
# ──────────────────────────────────────────────
VERSION="${1:-}"
if [[ -z "$VERSION" || "$VERSION" == "-h" || "$VERSION" == "--help" ]]; then
  usage
  [[ "$VERSION" == "-h" || "$VERSION" == "--help" ]] && exit 0
  exit 1
fi
shift
[[ "$VERSION" != *[[:space:]]* ]] || die "版本号不能包含空格"

SKIP_BUILD=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-build)  SKIP_BUILD=1; shift ;;
    -h|--help)     usage; exit 0 ;;
    *)             die "未知选项: $1" ;;
  esac
done

# ──────────────────────────────────────────────
# 前置检查
# ──────────────────────────────────────────────
need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "缺少必要命令: $1"
}

header
echo -e "${BOLD}  Songloft 懒猫应用更新${NC}"
header
echo ""

step "前置检查..."
need_cmd awk
need_cmd mktemp

[[ -f "$PACKAGE_FILE" ]]   || die "$PACKAGE_FILE 未找到"
[[ -f "$MANIFEST_FILE" ]]  || die "$MANIFEST_FILE 未找到"
[[ -f "$BUILD_FILE" ]]     || die "$BUILD_FILE 未找到"

info "所有配置文件就绪"

# ──────────────────────────────────────────────
# 读取当前配置
# ──────────────────────────────────────────────
CURRENT_VERSION=$(awk '/^version:/ { print $2; exit }' "$PACKAGE_FILE")
PACKAGE_ID=$(awk '/^package:/ { gsub(/["'"'"' ]/, "", $2); print $2; exit }' "$PACKAGE_FILE")
CURRENT_IMAGE=$(awk -v svc="$SERVICE_NAME" '
  /^[[:space:]]*services:/ { in_services=1; next }
  in_services && /^[^[:space:]]/ { in_services=0 }
  in_services && /^  '"$SERVICE_NAME"':/ { in_target=1; next }
  in_target && /^    image:/ { sub(/^.*image:[[:space:]]*/, ""); print; exit }
' "$MANIFEST_FILE")

# 渲染新镜像地址
NEW_IMAGE="${IMAGE_TEMPLATE//\{version\}/$VERSION}"

echo ""
echo -e "${BOLD}当前状态:${NC}"
echo "  包名:    $PACKAGE_ID"
echo "  版本:    $CURRENT_VERSION → ${GREEN}${VERSION}${NC}"
echo "  服务:    $SERVICE_NAME"
echo "  当前镜像: $CURRENT_IMAGE"
echo "  新镜像:   ${GREEN}${NEW_IMAGE}${NC}"
echo ""

# ──────────────────────────────────────────────
# 步骤 1: 更新 package.yml 版本
# ──────────────────────────────────────────────
step "[1/3] 更新 package.yml 版本..."

TMP=$(mktemp)
awk -v version="$VERSION" '
  !done && /^version:/ { print "version: " version; done=1; next }
  { print }
  END { if (!done) { print "version 字段未找到" > "/dev/stderr"; exit 1 } }
' "$PACKAGE_FILE" > "$TMP" || { rm -f "$TMP"; die "更新 package.yml 版本失败"; }
mv "$TMP" "$PACKAGE_FILE"

info "package.yml 版本: $CURRENT_VERSION → $VERSION"

# ──────────────────────────────────────────────
# 步骤 2: 更新 lzc-manifest.yml 镜像和注释
# ──────────────────────────────────────────────
echo ""
step "[2/3] 更新 lzc-manifest.yml 镜像..."

TMP=$(mktemp)
# 注释用原始名 songloft/songloft: 版本，方便下次推导
SOURCE_COMMENT="songloft/songloft:$VERSION"

awk -v service_name="$SERVICE_NAME" -v image="$NEW_IMAGE" -v comment="$SOURCE_COMMENT" '
  /^[[:space:]]*services:/ { in_services=1; print; next }
  in_services && /^[^[:space:]][^:]*:/ { in_services=0; in_target=0 }
  in_services && /^  [A-Za-z0-9_.-]+:/ {
    current=$1; sub(/:$/, "", current)
    in_target=(current == service_name)
    print
    next
  }
  in_target && /^    # / && !comment_done {
    print "    # " comment
    comment_done=1
    next
  }
  in_target && /^    image:/ {
    print "    image: " image
    next
  }
  { print }
' "$MANIFEST_FILE" > "$TMP" || { rm -f "$TMP"; die "更新 manifest 镜像失败"; }
mv "$TMP" "$MANIFEST_FILE"

info "lzc-manifest.yml 镜像: $CURRENT_IMAGE → $NEW_IMAGE"
info "lzc-manifest.yml 注释: # $SOURCE_COMMENT"

# ──────────────────────────────────────────────
# 步骤 3: 构建 LPK
# ──────────────────────────────────────────────
echo ""
LPK_FILE="${PACKAGE_ID}-v${VERSION}.lpk"

if [[ "$SKIP_BUILD" == "1" ]]; then
  step "[3/3] 跳过构建（--skip-build）"
  warn "请手动执行: lzc-cli project build -f $BUILD_FILE"
else
  step "[3/3] 构建 LPK 包..."
  need_cmd lzc-cli

  if lzc-cli project build -f "$BUILD_FILE"; then
    if [[ -f "$LPK_FILE" ]]; then
      info "构建成功: $LPK_FILE ($(ls -lh "$LPK_FILE" | awk '{print $5}'))"
    else
      warn "构建完成但未找到预期文件: $LPK_FILE"
      warn "请检查构建输出目录"
    fi
  else
    die "LPK 构建失败，请检查配置文件"
  fi
fi

# ──────────────────────────────---------------
# 完成
# ──────────────────────────────---------------
echo ""
header
echo -e "${GREEN}${BOLD}  更新完成！${NC}"
header
echo ""
echo -e "  ${BOLD}版本:${NC}    $CURRENT_VERSION → ${GREEN}$VERSION${NC}"
echo -e "  ${BOLD}服务:${NC}    $SERVICE_NAME"
echo -e "  ${BOLD}镜像:${NC}    $NEW_IMAGE"
echo -e "  ${BOLD}LPK 包:${NC}  ${LPK_FILE:-未构建}"
echo ""
