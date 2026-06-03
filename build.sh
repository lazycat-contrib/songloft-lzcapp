#!/bin/bash

# MiMusic LazyCat App Build Script
# 用于构建和发布 MiMusic 到懒猫应用商店

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 配置
APP_NAME="mimusic"
APP_VERSION=$(grep '^version:' lzc-manifest.yml | awk '{print $2}')
PACKAGE_NAME="cloud.lazycat.app.mimusic"
ORIGINAL_IMAGE="hanxi/mimusic:full"

# 打印函数
print_header() {
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}  MiMusic 懒猫应用构建脚本${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

print_info() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

# 检查必需文件
check_files() {
    local missing=0

    echo "检查必需文件..."

    if [ ! -f "lzc-manifest.yml" ]; then
        print_error "缺少 lzc-manifest.yml"
        missing=1
    else
        print_info "找到 lzc-manifest.yml"
    fi

    if [ ! -f "lzc-build.yml" ]; then
        print_error "缺少 lzc-build.yml"
        missing=1
    else
        print_info "找到 lzc-build.yml"
    fi

    if [ ! -f "lzc-deploy-params.yml" ]; then
        print_warning "缺少 lzc-deploy-params.yml (可选)"
    else
        print_info "找到 lzc-deploy-params.yml"
    fi

    if [ ! -f "icon.png" ]; then
        print_warning "缺少 icon.png (需要 512x512 PNG 格式)"
        missing=1
    else
        print_info "找到 icon.png"
    fi

    if [ $missing -eq 1 ]; then
        print_error "缺少必需文件，请先准备"
        return 1
    fi

    print_info "所有必需文件已就绪"
    return 0
}

# 显示应用信息
show_info() {
    echo ""
    echo -e "${GREEN}应用信息:${NC}"
    echo "  名称: $APP_NAME"
    echo "  版本: $APP_VERSION"
    echo "  包名: $PACKAGE_NAME"
    echo "  镜像: $ORIGINAL_IMAGE"
    echo ""
    echo -e "${GREEN}配置参数:${NC}"
    echo "  - admin_username: 管理员用户名"
    echo "  - admin_password: 管理员密码"
    echo ""
}

# 构建应用
build_app() {
    echo ""
    echo -e "${YELLOW}构建 LPK 包...${NC}"

    if ! check_files; then
        return 1
    fi

    local output_file="${APP_NAME}-${APP_VERSION}.lpk"

    if lzc-cli project build -o "$output_file"; then
        print_info "构建成功: $output_file"
        ls -lh "$output_file"
        return 0
    else
        print_error "构建失败"
        return 1
    fi
}

# 检查登录状态
check_login() {
    if ! lzc-cli appstore my-images &> /dev/null 2>&1; then
        print_warning "未登录懒猫应用商店"
        print_info "请先执行: lzc-cli appstore login"
        return 1
    fi
    print_info "已登录应用商店"
    return 0
}

# 复制镜像到懒猫仓库
copy_image() {
    echo ""
    echo -e "${YELLOW}复制镜像到懒猫仓库...${NC}"

    if ! check_login; then
        return 1
    fi

    print_info "原镜像: $ORIGINAL_IMAGE"

    local result
    result=$(lzc-cli appstore copy-image "$ORIGINAL_IMAGE" 2>&1)
    local exit_code=$?

    if [ $exit_code -eq 0 ]; then
        # 提取新镜像地址
        local new_image
        new_image=$(echo "$result" | grep "^uploaded:" | awk '{print $2}')

        if [ -n "$new_image" ]; then
            print_info "新镜像: $new_image"

            # 更新 manifest
            update_manifest_image "$new_image"

            return 0
        else
            print_error "未能获取新镜像地址"
            return 1
        fi
    else
        print_error "镜像复制失败"
        echo "$result"
        return 1
    fi
}

# 更新 manifest 中的镜像
update_manifest_image() {
    local new_image="$1"

    echo ""
    echo -e "${YELLOW}更新 manifest 镜像地址...${NC}"

    # 备份原文件
    cp lzc-manifest.yml lzc-manifest.yml.bak

    # 使用 sed 替换镜像（保留原镜像作为注释）
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        sed -i '' "s|image: hanxi/mimusic:full|    # hanxi/mimusic:full\n    image: $new_image|" lzc-manifest.yml
    else
        # Linux
        sed -i "s|image: hanxi/mimusic:full|    # hanxi/mimusic:full\n    image: $new_image|" lzc-manifest.yml
    fi

    print_info "Manifest 已更新"
    print_warning "原镜像已注释保留在 manifest 中"
}

# 发布到应用商店
publish_app() {
    echo ""
    echo -e "${YELLOW}发布到应用商店...${NC}"

    if ! check_login; then
        return 1
    fi

    local lpk_file="${APP_NAME}-${APP_VERSION}.lpk"

    if [ ! -f "$lpk_file" ]; then
        print_error "找不到 LPK 文件: $lpk_file"
        print_info "请先执行构建"
        return 1
    fi

    if lzc-cli appstore publish "$lpk_file"; then
        print_info "发布成功"
        print_info "应用将进入审核流程（通常 1-3 天）"
        return 0
    else
        print_error "发布失败"
        return 1
    fi
}

# 一键构建+发布
one_click_publish() {
    echo ""
    echo -e "${GREEN}开始一键构建+发布流程...${NC}"
    echo ""

    # 阶段 1: 初始构建
    echo -e "${BLUE}[阶段 1/4] 初始构建（原始镜像）${NC}"
    if ! build_app; then
        print_error "初始构建失败，停止流程"
        return 1
    fi

    # 阶段 2: 镜像复制
    echo -e "${BLUE}[阶段 2/4] 镜像复制到懒猫仓库${NC}"
    if ! copy_image; then
        print_error "镜像复制失败，停止流程"
        return 1
    fi

    # 阶段 3: 重新构建
    echo -e "${BLUE}[阶段 3/4] 重新构建（新镜像）${NC}"
    if ! build_app; then
        print_error "重新构建失败，停止流程"
        return 1
    fi

    # 阶段 4: 发布
    echo -e "${BLUE}[阶段 4/4] 发布到应用商店${NC}"
    if ! publish_app; then
        print_error "发布失败"
        return 1
    fi

    echo ""
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}  一键发布流程完成！${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# 主菜单
show_menu() {
    print_header
    echo "请选择操作:"
    echo ""
    echo "  1. 📦 构建应用 (Build)"
    echo "  2. 🔧 镜像复制到懒猫仓库 (Copy Image)"
    echo "  3. 📤 发布到应用商店 (Publish)"
    echo "  4. 🚀 一键构建+镜像复制+发布 (One-Click)"
    echo "  5. 📋 查看应用信息 (Info)"
    echo "  6. ❌ 退出"
    echo ""
}

# 主循环
main() {
    while true; do
        show_menu
        read -p "请输入选项 (1-6): " choice
        echo ""

        case $choice in
            1)
                build_app
                ;;
            2)
                copy_image
                ;;
            3)
                publish_app
                ;;
            4)
                one_click_publish
                ;;
            5)
                show_info
                check_files
                ;;
            6)
                echo "退出"
                exit 0
                ;;
            *)
                print_error "无效选项，请重新选择"
                ;;
        esac

        echo ""
        read -p "按回车继续..."
    done
}

# 运行
main