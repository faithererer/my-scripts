#!/bin/bash

# =========================================================
# Gost v3 最终修正版 (兼容 BusyBox / Alpine / 无 Systemd)
# =========================================================

# --- 变量定义 ---
BIN_PATH="/usr/local/bin/gost"
LOG_FILE="/tmp/gost.log"
CONF_FILE="/etc/gost_config.conf"
GAI_CONF="/etc/gai.conf"

# --- 颜色定义 ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;36m'
PLAIN='\033[0m'

# --- 基础检查 ---
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}[错误]${PLAIN} 必须使用 root 用户运行此脚本！"
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

# --- IPv6 管理 ---
set_ipv6_preference() {
    local mode=$1
    [[ ! -f "${GAI_CONF}.bak" && -f "${GAI_CONF}" ]] && cp "${GAI_CONF}" "${GAI_CONF}.bak"
    touch "${GAI_CONF}"
    sed -i '/^precedence ::ffff:0:0\/96/d' "${GAI_CONF}"
    
    echo -e "------------------------------------------------"
    if [[ "$mode" == "ipv6" ]]; then
        echo "precedence ::ffff:0:0/96  10" >> "${GAI_CONF}"
        echo -e "${GREEN}[成功]${PLAIN} 已设置策略：${BLUE}优先使用 IPv6${PLAIN}"
    elif [[ "$mode" == "ipv4" ]]; then
        echo "precedence ::ffff:0:0/96  100" >> "${GAI_CONF}"
        echo -e "${GREEN}[成功]${PLAIN} 已设置策略：${YELLOW}优先使用 IPv4${PLAIN}"
    else
        echo -e "${GREEN}[成功]${PLAIN} 已恢复默认策略。"
    fi
    echo -e "------------------------------------------------"
}

ipv6_menu() {
    echo -e "------------------------------------------------"
    echo -e "  ${BLUE}IPv6 出站优先级管理${PLAIN}"
    echo -e "  ${GREEN}1.${PLAIN} 优先 IPv6 (推荐)"
    echo -e "  ${GREEN}2.${PLAIN} 优先 IPv4"
    echo -e "  ${GREEN}3.${PLAIN} 恢复默认"
    echo -e "------------------------------------------------"
    read -p " 请输入 [1-3]: " v6_choice
    case "$v6_choice" in
        1) set_ipv6_preference "ipv6" ;;
        2) set_ipv6_preference "ipv4" ;;
        3) set_ipv6_preference "default" ;;
        *) echo -e "${RED}取消${PLAIN}" ;;
    esac
}

# --- 核心功能 ---
install_base() {
    echo -e "${BLUE}[信息]${PLAIN} 安装依赖..."
    # 兼容 Alpine (apk) 和其他系统
    if command -v apk >/dev/null 2>&1; then
        apk add --no-cache curl wget tar ca-certificates
    elif command -v apt-get >/dev/null 2>&1; then
        apt-get update && apt-get install -y curl wget tar
    elif command -v yum >/dev/null 2>&1; then
        yum install -y curl wget tar
    fi
}

get_latest_version() {
    echo -e "${BLUE}[信息]${PLAIN} 查询版本..."
    LATEST_VERSION=$(curl -s https://api.github.com/repos/go-gost/gost/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    [[ -z "$LATEST_VERSION" ]] && LATEST_VERSION="v3.0.0"
    echo -e "${GREEN}[信息]${PLAIN} 版本: ${LATEST_VERSION}"
}

configure_gost() {
    echo -e "------------------------------------------------"
    read -p "端口 (默认 45654): " PORT
    [[ -z "${PORT}" ]] && PORT="45654"

    read -p "用户 (默认 admin): " USER
    [[ -z "${USER}" ]] && USER="admin"

    read -p "密码 (默认 123456): " PASS
    [[ -z "${PASS}" ]] && PASS="123456"

    read -p "开启 IPv6 优先? [y/n] (默认 y): " V6_CONFIRM
    [[ -z "${V6_CONFIRM}" ]] && V6_CONFIRM="y"
    
    [[ "${V6_CONFIRM}" =~ [yY] ]] && set_ipv6_preference "ipv6"

    # 写入配置
    echo "GOST_CMD=\"-L auto://${USER}:${PASS}@:${PORT}\"" > ${CONF_FILE}
    start_gost
}

start_gost() {
    if [[ ! -f ${CONF_FILE} ]]; then
        echo -e "${RED}[错误]${PLAIN} 未找到配置。"
        return
    fi
    source ${CONF_FILE}

    # 停止旧进程
    if pgrep -f "${BIN_PATH}" > /dev/null; then
        kill $(pgrep -f "${BIN_PATH}") > /dev/null 2>&1
    fi

    echo -e "${BLUE}[信息]${PLAIN} 正在启动..."
    nohup ${BIN_PATH} ${GOST_CMD} > ${LOG_FILE} 2>&1 &
    sleep 2
    check_status
}

stop_gost() {
    if pgrep -f "${BIN_PATH}" > /dev/null; then
        kill $(pgrep -f "${BIN_PATH}")
        echo -e "${GREEN}[成功]${PLAIN} 已停止。"
    else
        echo -e "${YELLOW}[提示]${PLAIN} 未运行。"
    fi
}

install_gost() {
    check_root
    install_base
    check_arch
    get_latest_version

    VERSION_NUM=${LATEST_VERSION#v}
    DOWNLOAD_URL="https://github.com/go-gost/gost/releases/download/${LATEST_VERSION}/gost_${VERSION_NUM}_${GOST_ARCH}.tar.gz"

    wget -N --no-check-certificate -O gost.tar.gz ${DOWNLOAD_URL}
    tar -zxvf gost.tar.gz > /dev/null
    mv gost ${BIN_PATH}
    chmod +x ${BIN_PATH}
    rm -f gost.tar.gz README.md LICENSE

    configure_gost
}

uninstall_gost() {
    stop_gost
    rm -f ${BIN_PATH} ${CONF_FILE}
    echo -e "${GREEN}[成功]${PLAIN} 已卸载。"
}

check_status() {
    if pgrep -f "${BIN_PATH}" > /dev/null; then
        echo -e "${GREEN}[状态] Gost 正在运行${PLAIN}"
        if [[ -f ${CONF_FILE} ]]; then
            source ${CONF_FILE}
            # === 修复点：使用 grep -oE 替代 grep -P 以兼容 BusyBox ===
            CURRENT_PORT=$(echo "$GOST_CMD" | grep -oE '[0-9]+$')
            
            IPV4=$(curl -s4m 3 https://ipinfo.io/ip)
            IPV6=$(curl -s6m 3 https://ipinfo.io/ip)
            
            echo -e "------------------------------------------------"
            echo -e "连接地址: ${BLUE}http://${IPV4}:${CURRENT_PORT}${PLAIN}"
            [[ -n "$IPV6" ]] && echo -e "IPv6地址: ${BLUE}http://[${IPV6}]:${CURRENT_PORT}${PLAIN}"
            echo -e "------------------------------------------------"
        fi
    else
        echo -e "${RED}[状态] Gost 未运行${PLAIN}"
    fi
}

# --- 菜单 ---
show_menu() {
    clear
    echo -e "==============================================="
    echo -e "    Gost v3 (BusyBox/Alpine 兼容版)"
    echo -e "==============================================="
    echo -e "  ${GREEN}1.${PLAIN} 安装 / 重装"
    echo -e "  ${GREEN}2.${PLAIN} 卸载"
    echo -e "  ${GREEN}3.${PLAIN} 状态"
    echo -e "  ${GREEN}4.${PLAIN} 重启"
    echo -e "  ${GREEN}5.${PLAIN} 停止"
    echo -e "  ${GREEN}6.${PLAIN} IPv6 设置"
    echo -e "  ${GREEN}0.${PLAIN} 退出"
    echo -e "==============================================="
    read -p " 请输入: " num

    case "$num" in
        1) install_gost ;;
        2) uninstall_gost ;;
        3) check_status ;;
        4) start_gost ;;
        5) stop_gost ;;
        6) ipv6_menu ;;
        0) exit 0 ;;
        *) echo -e "${RED}错误${PLAIN}" ;;
    esac
}

show_menu