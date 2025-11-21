#!/bin/bash

# =========================================================
# Linux Swap 一键智能管理脚本 (Pro 版)
# 适用于 Debian / Ubuntu / CentOS
# =========================================================

# --- 颜色定义 ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;36m'
PLAIN='\033[0m'

# --- 变量定义 ---
SWAP_FILE="/swapfile"

# --- 基础检查 ---
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}[错误]${PLAIN} 必须使用 root 用户运行此脚本！"
        exit 1
    fi
}

# --- 工具函数：解析容量输入 ---
# 将 1.5G, 100M, 100mb 等格式转换为纯 MB 整数
convert_to_mb() {
    local input=$1
    # 1. 转大写
    local upper_input=$(echo "$input" | tr 'a-z' 'A-Z')
    # 2. 提取数字部分 (保留小数点)
    local number=$(echo "$upper_input" | sed 's/[^0-9.]//g')
    # 3. 提取单位部分
    local unit=$(echo "$upper_input" | sed 's/[0-9.]//g')

    # 空输入检查
    if [[ -z "$number" ]]; then echo "0"; return; fi

    # 计算逻辑 (使用 awk 处理浮点数运算)
    if [[ "$unit" == *"G"* ]]; then
        # 如果包含 G，乘以 1024
        awk -v num="$number" 'BEGIN {printf "%.0f", num * 1024}'
    elif [[ "$unit" == *"M"* ]] || [[ -z "$unit" ]]; then
        # 如果是 M 或者没单位，直接取整
        awk -v num="$number" 'BEGIN {printf "%.0f", num}'
    else
        # 无法识别的单位，返回 0
        echo "0"
    fi
}

# --- 获取当前状态 ---
get_swap_status() {
    TOTAL_RAM=$(free -h | grep Mem | awk '{print $2}')
    TOTAL_SWAP=$(free -h | grep Swap | awk '{print $2}')
    
    if [[ -f "${SWAP_FILE}" ]]; then
        FILE_SIZE=$(du -h "${SWAP_FILE}" | awk '{print $1}')
        SWAP_EXIST="${GREEN}已存在 (${FILE_SIZE})${PLAIN}"
    else
        SWAP_EXIST="${RED}未创建${PLAIN}"
    fi
}

# --- 添加 Swap ---
add_swap() {
    if [[ -f "${SWAP_FILE}" ]]; then
        echo -e "${YELLOW}[警告]${PLAIN} 检测到已存在 /swapfile，请先执行卸载操作。"
        return
    fi

    echo -e "------------------------------------------------"
    echo -e "您的物理内存: ${BLUE}${TOTAL_RAM}${PLAIN}"
    echo -e "${YELLOW}建议大小:${PLAIN}"
    echo -e "  - 2G 内存以下: 建议设置为内存的 2 倍"
    echo -e "  - 2G-8G 内存 : 建议设置为等同内存大小"
    echo -e "------------------------------------------------"
    echo -e "支持格式示例: ${GREEN}512M, 1024MB, 1G, 1.5GB${PLAIN}"
    
    read -p "请输入要添加的 Swap 大小: " INPUT_SIZE

    # 调用解析函数
    SWAP_SIZE_MB=$(convert_to_mb "$INPUT_SIZE")

    # 校验解析结果
    if [[ "$SWAP_SIZE_MB" == "0" || -z "$SWAP_SIZE_MB" ]]; then
        echo -e "${RED}[错误]${PLAIN} 输入格式无效，请检查后重试。"
        return
    fi

    echo -e "${BLUE}[信息]${PLAIN} 目标大小: ${SWAP_SIZE_MB}MB"
    echo -e "${BLUE}[信息]${PLAIN} 正在创建 Swap 文件，请稍候..."

    # 优先使用 fallocate，失败回退到 dd
    if ! fallocate -l "${SWAP_SIZE_MB}M" ${SWAP_FILE} 2>/dev/null; then
        echo -e "${YELLOW}[提示]${PLAIN} fallocate 失败，切换为 dd 模式..."
        dd if=/dev/zero of=${SWAP_FILE} bs=1M count=${SWAP_SIZE_MB} status=progress
    fi

    chmod 600 ${SWAP_FILE}
    mkswap ${SWAP_FILE}
    swapon ${SWAP_FILE}

    # 写入 fstab
    if grep -q "${SWAP_FILE}" /etc/fstab; then
        sed -i "/${SWAP_FILE//\//\\/}/d" /etc/fstab
    fi
    echo "${SWAP_FILE} none swap sw 0 0" | tee -a /etc/fstab

    echo -e "${GREEN}[成功]${PLAIN} Swap 添加完成！"
    free -h
}

# --- 删除 Swap ---
del_swap() {
    if [[ ! -f "${SWAP_FILE}" ]]; then
        echo -e "${RED}[错误]${PLAIN} 未检测到 /swapfile，无法删除。"
        return
    fi

    echo -e "${YELLOW}[警告]${PLAIN} 正在关闭 Swap，请确保剩余内存充足..."
    
    swapoff ${SWAP_FILE}
    if [[ $? -ne 0 ]]; then
        echo -e "${RED}[失败]${PLAIN} 关闭 Swap 失败 (内存可能不足)，请先释放内存。"
        return
    fi

    rm -f ${SWAP_FILE}
    sed -i "/swapfile/d" /etc/fstab

    echo -e "${GREEN}[成功]${PLAIN} Swap 已彻底删除。"
    free -h
}

# --- 菜单 ---
show_menu() {
    check_root
    get_swap_status
    
    clear
    echo -e "==============================================="
    echo -e "    Linux Swap 智能管理脚本 (Pro)"
    echo -e "    ${BLUE}当前内存: ${TOTAL_RAM} | 当前 Swap: ${TOTAL_SWAP}${PLAIN}"
    echo -e "    ${BLUE}Swap文件: ${SWAP_EXIST}${PLAIN}"
    echo -e "==============================================="
    echo -e "  ${GREEN}1.${PLAIN} 添加 Swap (智能识别单位)"
    echo -e "  ${GREEN}2.${PLAIN} 删除 Swap"
    echo -e "  ${GREEN}0.${PLAIN} 退出"
    echo -e "==============================================="
    read -p " 请输入数字 [0-2]: " num

    case "$num" in
        1) add_swap ;;
        2) del_swap ;;
        0) exit 0 ;;
        *) echo -e "${RED}输入错误${PLAIN}" ;;
    esac
}

show_menu