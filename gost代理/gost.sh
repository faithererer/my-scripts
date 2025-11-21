#!/bin/bash

# =========================================================
# Gost v3 一键安装管理脚本
# 适用于 Debian / Ubuntu
# =========================================================

# --- 颜色定义 ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;36m'
PLAIN='\033[0m'

# --- 变量定义 ---
SERVICE_FILE="/etc/systemd/system/gost.service"
BIN_PATH="/usr/local/bin/gost"
CONF_FILE="/etc/gost/config.yaml" # 预留，目前使用命令行参数

# --- 基础检查 ---
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}[错误]${PLAIN} 必须使用 root 用户运行此脚本！"
        exit 1
    fi
}

check_sys() {
    if [[ -f /etc/redhat-release ]]; then
        RELEASE="centos"
    elif cat /etc/issue | grep -q -E -i "debian"; then
        RELEASE="debian"
    elif cat /etc/issue | grep -q -E -i "ubuntu"; then
        RELEASE="ubuntu"
    elif cat /etc/issue | grep -q -E -i "centos|red hat|redhat"; then
        RELEASE="centos"
    elif cat /proc/version | grep -q -E -i "debian"; then
        RELEASE="debian"
    elif cat /proc/version | grep -q -E -i "ubuntu"; then
        RELEASE="ubuntu"
    elif cat /proc/version | grep -q -E -i "centos|red hat|redhat"; then
        RELEASE="centos"
    else
        echo -e "${RED}[错误]${PLAIN} 无法检测操作系统，本脚本仅支持 Debian/Ubuntu。"
        exit 1
    fi
}

check_arch() {
    ARCH=$(uname -m)
    case $ARCH in
        x86_64|amd64)
            GOST_ARCH="linux_amd64"
            ;;
        aarch64|arm64)
            GOST_ARCH="linux_arm64"
            ;;
        *)
            echo -e "${RED}[错误]${PLAIN} 不支持的架构: $ARCH"
            exit 1
            ;;
    esac
}

# --- 辅助函数 ---
install_base() {
    echo -e "${BLUE}[信息]${PLAIN} 正在安装必要依赖 (curl, wget, tar)..."
    if [[ "${RELEASE}" == "centos" ]]; then
        yum install -y curl wget tar
    else
        apt-get update && apt-get install -y curl wget tar
    fi
}

get_latest_version() {
    # 获取 GitHub 最新 Release 版本号 (排除 v 前缀)
    echo -e "${BLUE}[信息]${PLAIN} 正在查询 Gost 最新版本..."
    LATEST_VERSION=$(curl -s https://api.github.com/repos/go-gost/gost/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    if [[ -z "$LATEST_VERSION" ]]; then
        echo -e "${YELLOW}[警告]${PLAIN} 获取最新版本失败，使用默认版本 v3.0.0"
        LATEST_VERSION="v3.0.0"
    else
        echo -e "${GREEN}[信息]${PLAIN} 检测到最新版本: ${LATEST_VERSION}"
    fi
}

configure_gost() {
    echo -e "------------------------------------------------"
    echo -e "${YELLOW}请配置 Gost 运行参数:${PLAIN}"
    echo -e "------------------------------------------------"

    read -p "请输入端口 (默认: 45654): " PORT
    [[ -z "${PORT}" ]] && PORT="45654"

    read -p "请输入用户名 (默认: admin): " USER
    [[ -z "${USER}" ]] && USER="admin"

    read -p "请输入密码 (默认: 123456): " PASS
    [[ -z "${PASS}" ]] && PASS="123456"

    echo -e "------------------------------------------------"
    echo -e "${GREEN}配置确认:${PLAIN}"
    echo -e "端口: ${BLUE}${PORT}${PLAIN}"
    echo -e "用户: ${BLUE}${USER}${PLAIN}"
    echo -e "密码: ${BLUE}${PASS}${PLAIN}"
    echo -e "------------------------------------------------"
    
    read -p "确认安装? [y/n]: " CONFIRM
    if [[ "${CONFIRM}" != "y" && "${CONFIRM}" != "Y" ]]; then
        echo -e "${RED}已取消安装。${PLAIN}"
        exit 1
    fi

    # 生成 systemd 文件
    cat > ${SERVICE_FILE} <<EOF
[Unit]
Description=GOST Tunnel Service
After=network.target

[Service]
Type=simple
User=root
ExecStart=${BIN_PATH} -L auto://${USER}:${PASS}@:${PORT}
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

    echo -e "${GREEN}[成功]${PLAIN} 服务配置文件已生成。"
}

install_gost() {
    check_root
    check_sys
    check_arch
    install_base
    get_latest_version

    # 处理版本号文件名差异 (v3.0.0 -> gost_3.0.0_linux_amd64.tar.gz)
    VERSION_NUM=${LATEST_VERSION#v}
    DOWNLOAD_URL="https://github.com/go-gost/gost/releases/download/${LATEST_VERSION}/gost_${VERSION_NUM}_${GOST_ARCH}.tar.gz"

    echo -e "${BLUE}[信息]${PLAIN} 正在下载 Gost (${DOWNLOAD_URL})..."
    wget -N --no-check-certificate -O gost.tar.gz ${DOWNLOAD_URL}

    if [[ $? -ne 0 ]]; then
        echo -e "${RED}[错误]${PLAIN} 下载失败，请检查网络连接。"
        exit 1
    fi

    tar -zxvf gost.tar.gz
    mv gost ${BIN_PATH}
    chmod +x ${BIN_PATH}
    rm -f gost.tar.gz README.md LICENSE

    configure_gost

    # 启动服务
    systemctl daemon-reload
    systemctl enable gost
    systemctl restart gost

    # 检查状态
    check_status
}

uninstall_gost() {
    echo -e "${YELLOW}[警告]${PLAIN} 正在卸载 Gost..."
    systemctl stop gost
    systemctl disable gost
    rm -f ${SERVICE_FILE}
    systemctl daemon-reload
    rm -f ${BIN_PATH}
    echo -e "${GREEN}[成功]${PLAIN} Gost 已卸载。"
}

check_status() {
    if systemctl is-active --quiet gost; then
        echo -e "${GREEN}[状态] Gost 正在运行${PLAIN}"
        echo -e "------------------------------------------------"
        # 尝试获取当前端口
        CURRENT_PORT=$(grep "ExecStart" ${SERVICE_FILE} | awk -F':' '{print $NF}')
        echo -e "连接地址: ${BLUE}http://<你的IP>:${CURRENT_PORT}${PLAIN}"
        echo -e "------------------------------------------------"
    else
        echo -e "${RED}[状态] Gost 未运行${PLAIN}"
    fi
}

# --- 菜单 ---
show_menu() {
    clear
    echo -e "==============================================="
    echo -e "    Gost v3 一键管理脚本 (Debian/Ubuntu)"
    echo -e "    ${BLUE}适合 200MB 小内存机器使用${PLAIN}"
    echo -e "==============================================="
    echo -e "  ${GREEN}1.${PLAIN} 安装 / 重装 Gost"
    echo -e "  ${GREEN}2.${PLAIN} 卸载 Gost"
    echo -e "  ${GREEN}3.${PLAIN} 查看运行状态"
    echo -e "  ${GREEN}4.${PLAIN} 重启服务"
    echo -e "  ${GREEN}0.${PLAIN} 退出"
    echo -e "==============================================="
    read -p " 请输入数字 [0-4]: " num

    case "$num" in
        1) install_gost ;;
        2) uninstall_gost ;;
        3) check_status ;;
        4) systemctl restart gost && echo -e "${GREEN}服务已重启${PLAIN}" && check_status ;;
        0) exit 0 ;;
        *) echo -e "${RED}输入错误${PLAIN}" ;;
    esac
}

# 入口
show_menu