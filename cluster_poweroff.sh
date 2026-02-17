#!/bin/bash

# ======================================================
# Supermicro Cluster Remote Power-Off Tool
# ======================================================

# --- 1. 配置区 (确保与监控脚本中的 IP 列表一致) ---
SERVERS=(
    "192.168.1.101"
    "192.168.1.102"
    "192.168.1.103"
    "192.168.1.104"
    "192.168.1.105"
    "192.168.1.106"
    "192.168.1.107"
    "192.168.1.108"
    "192.168.1.109"
    "192.168.1.110"
)

USER="admin"      # IPMI 用户名
PASS="ADMIN"     # IPMI 密码

# --- 2. 颜色定义 ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}WARNING: This will power off ALL servers in the list!${NC}"
read -p "Are you sure you want to proceed? (y/n): " CONFIRM

if [[ $CONFIRM != "y" ]]; then
    echo "Operation cancelled."
    exit 0
fi

echo "-----------------------------------------------------"

for IP in "${SERVERS[@]}"; do
    echo -n "Sending Power-Off command to [$IP]... "
    
    # 使用 ipmitool 发送关机指令 (soft 代表正常关机，如果无效可以改为 off 强制切断电源)
    # 建议先用 soft，这样操作系统有时间保存最后的日志
    RESULT=$(ipmitool -H "$IP" -U "$USER" -P "$PASS" chassis power soft 2>&1)
    
    if [[ $? -eq 0 ]]; then
        echo -e "${GREEN}SUCCESS${NC}"
    else
        echo -e "${RED}FAILED${NC}"
        echo "  Error: $RESULT"
    fi
done

echo "-----------------------------------------------------"
echo "All commands sent."
