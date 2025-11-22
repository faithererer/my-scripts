#!/bin/bash

# =========================================================
# Gost v3 一键安装管理脚本 (NAT VPS 优化版)
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
GAI_CONF="/etc/gai.conf"

# --- 基础检查 ---
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}[错误]${PLAIN} 必须使用 root 用户运行此脚本！"
        exit 1
    fi
}

check_sys() {
    # 简单的发行版检测，兼容常见 VPS 系统
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        RELEASE=$ID
    else
        echo -e "${RED}[错误]${PLAIN} 无法检测操作系统，本脚本仅支持 Debian/Ubuntu/CentOS。"
        exit 1
    fi
}

check_arch() {
    ARCH=$(uname -m)
    case $ARCH in
        x86_64|amd64) GOST_ARCH="linux_amd64" ;;
        aarch64|arm64) GOST_ARCH="linux_arm64" ;;
        *) echo -e "${RED}[错误]${PLAIN} 不支持的架构: $ARCH"; exit 1 ;;
    esac
}

# --- IPv6 管理模块 ---
set_ipv6_preference() {
    local mode=$1
    
    # 备份配置文件
    if [[ ! -f "${GAI_CONF}.bak" && -f "${GAI_CONF}" ]]; then
        cp "${GAI_CONF}" "${GAI_CONF}.bak"
    fi

    # 确保文件存在
    touch "${GAI_CONF}"

    # 清理旧配置 (删除相关的 precedence 设置)
    sed -i '/^precedence ::ffff:0:0\/96/d' "${GAI_CONF}"

    echo -e "------------------------------------------------"
    if [[ "$mode" == "ipv6" ]]; then
        # 强制 IPv6 优先：降低 IPv4 映射地址的优先级 (设为 10)
        # ::/0 默认为 40，所以 10 < 40，IPv6 胜出
        echo "precedence ::ffff:0:0/96  10" >> "${GAI_CONF}"
        echo -e "${GREEN}[成功]${PLAIN} 已设置策略：${BLUE}优先使用 IPv6${PLAIN}"
        echo -e "${BLUE}[提示]${PLAIN} 请确保本机拥有有效的 IPv6 地址。"
    elif [[ "$mode" == "ipv4" ]]; then
        # 强制 IPv4 优先：提高 IPv4 映射地址的优先级 (设为 100)
        echo "precedence ::ffff:0:0/96  100" >> "${GAI_CONF}"
        echo -e "${GREEN}[成功]${PLAIN} 已设置策略：${YELLOW}优先使用 IPv4${PLAIN}"
    else
        # 恢复默认 (什么都不加，由系统决定)
        echo -e "${GREEN}[成功]${PLAIN} 已恢复系统默认出站策略。"
    fi
    echo -e "------------------------------------------------"
}

ipv6_menu() {
    echo -e "------------------------------------------------"
    echo -e "  ${BLUE}IPv6 出站优先级管理 (修改 /etc/gai.conf)${PLAIN}"
    echo -e "  * 针对 NAT VPS，建议选择 IPv6 优先以保护共享 IPv4"
    echo -e "------------------------------------------------"
    echo -e "  ${GREEN}1.${PLAIN} 设置：优先使用 IPv6 (推荐)"
    echo -e "  ${GREEN}2.${PLAIN} 设置：优先使用 IPv4"
    echo -e "  ${GREEN}3.${PLAIN} 恢复：系统默认"
    echo -e "------------------------------------------------"
    read -p " 请输入选择 [1-3]: " v6_choice

    case "$v6_choice" in
        1) set_ipv6_preference "ipv6" ;;
        2) set_ipv6_preference "ipv4" ;;
        3) set_ipv6_preference "default" ;;
        *) echo -e "${RED}取消操作${PLAIN}" ;;
    esac
}

# --- 核心功能 ---
install_base() {
    echo -e "${BLUE}[信息]${PLAIN} 正在安装必要依赖..."
    if [[ "${RELEASE}" == "centos" ]]; then
        yum install -y curl wget tar
    else
        apt-get update && apt-get install -y curl wget tar
    fi
}

get_latest_version() {
    echo -e "${BLUE}[信息]${PLAIN} 正在查询 Gost 最新版本..."
    LATEST_VERSION=$(curl -s https://api.github.com/repos/go-gost/gost/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    if [[ -z "$LATEST_VERSION" ]]; then
        LATEST_VERSION="v3.0.0"
        echo -e "${YELLOW}[警告]${PLAIN} 获取失败，使用默认版本 ${LATEST_VERSION}"
    else
        echo -e "${GREEN}[信息]${PLAIN} 检测到最新版本: ${LATEST_VERSION}"
    fi
}

configure_gost() {
    echo -e "------------------------------------------------"
    echo -e "${YELLOW}>> 配置 Gost 运行参数${PLAIN}"
    echo -e "------------------------------------------------"

    read -p "请输入端口 (默认: 45654): " PORT
    [[ -z "${PORT}" ]] && PORT="45654"

    read -p "请输入用户名 (默认: admin): " USER
    [[ -z "${USER}" ]] && USER="admin"

    read -p "请输入密码 (默认: 123456): " PASS
    [[ -z "${PASS}" ]] && PASS="123456"

    echo -e "------------------------------------------------"
    echo -e "${YELLOW}>> 网络偏好设置 (NAT VPS 重要)${PLAIN}"
    echo -e "是否优先使用 IPv6 出站？(防止共享 IPv4 滥用)"
    read -p "确认开启 IPv6 优先? [y/n] (默认: y): " V6_CONFIRM
    [[ -z "${V6_CONFIRM}" ]] && V6_CONFIRM="y"

    echo -e "------------------------------------------------"
    echo -e "${GREEN}配置确认:${PLAIN}"
    echo -e "端口: ${BLUE}${PORT}${PLAIN}"
    echo -e "认证: ${BLUE}${USER}:${PASS}${PLAIN}"
    if [[ "${V6_CONFIRM}" == "y" || "${V6_CONFIRM}" == "Y" ]]; then
        echo -e "网络: ${BLUE}优先 IPv6${PLAIN}"
    else
        echo -e "网络: ${YELLOW}默认/IPv4${PLAIN}"
    fi
    echo -e "------------------------------------------------"
    
    read -p "确认安装? [y/n]: " CONFIRM
    if [[ "${CONFIRM}" != "y" && "${CONFIRM}" != "Y" ]]; then
        echo -e "${RED}已取消安装。${PLAIN}"
        exit 1
    fi

    # 写入 Systemd 服务
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

    # 应用 IPv6 设置
    if [[ "${V6_CONFIRM}" == "y" || "${V6_CONFIRM}" == "Y" ]]; then
        set_ipv6_preference "ipv6"
    fi

    echo -e "${GREEN}[成功]${PLAIN} 配置完成。"
}

install_gost() {
    check_root
    check_sys
    check_arch
    install_base
    get_latest_version

    VERSION_NUM=${LATEST_VERSION#v}
    DOWNLOAD_URL="https://github.com/go-gost/gost/releases/download/${LATEST_VERSION}/gost_${VERSION_NUM}_${GOST_ARCH}.tar.gz"

    echo -e "${BLUE}[信息]${PLAIN} 正在下载 Gost..."
    wget -N --no-check-certificate -O gost.tar.gz ${DOWNLOAD_URL}
    
    if [[ $? -ne 0 ]]; then
        echo -e "${RED}[错误]${PLAIN} 下载失败，请检查网络。"
        exit 1
    fi

    tar -zxvf gost.tar.gz > /dev/null
    mv gost ${BIN_PATH}
    chmod +x ${BIN_PATH}
    rm -f gost.tar.gz README.md LICENSE

    configure_gost

    systemctl daemon-reload
    systemctl enable gost
    systemctl restart gost

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
        CURRENT_PORT=$(grep "ExecStart" ${SERVICE_FILE} | awk -F':' '{print $NF}')
        # 获取本机 IPv4 和 IPv6
        IPV4=$(curl -s4m 3 https://ipinfo.io/ip)
        IPV6=$(curl -s6m 3 https://ipinfo.io/ip)
        echo -e "------------------------------------------------"
        echo -e "连接地址: ${BLUE}http://${IPV4}:${CURRENT_PORT}${PLAIN}"
        if [[ -n "$IPV6" ]]; then
            echo -e "IPv6地址: ${BLUE}http://[${IPV6}]:${CURRENT_PORT}${PLAIN}"
        fi
        echo -e "------------------------------------------------"
    else
        echo -e "${RED}[状态] Gost 未运行${PLAIN}"
    fi
}

# --- 菜单 ---
show_menu() {
    clear
    echo -e "==============================================="
    echo -e "    Gost v3 一键管理脚本 (IPv6 优化版)"
    echo -e "    ${BLUE}适用于 NAT VPS 环境${PLAIN}"
    echo -e "==============================================="
    echo -e "  ${GREEN}1.${PLAIN} 安装 / 重装 Gost"
    echo -e "  ${GREEN}2.${PLAIN} 卸载 Gost"
    echo -e "  ${GREEN}3.${PLAIN} 查看运行状态"
    echo -e "  ${GREEN}4.${PLAIN} 重启服务"
    echo -e "  ${GREEN}5.${PLAIN} 设置 IPv4/IPv6 优先级"
    echo -e "  ${GREEN}0.${PLAIN} 退出"
    echo -e "==============================================="
    read -p " 请输入数字 [0-5]: " num

    case "$num" in
        1) install_gost ;;
        2) uninstall_gost ;;
        3) check_status ;;
        4) systemctl restart gost && echo -e "${GREEN}服务已重启${PLAIN}" && check_status ;;
        5) ipv6_menu ;;
        0) exit 0 ;;
        *) echo -e "${RED}输入错误${PLAIN}" ;;
    esac
}

show_menu