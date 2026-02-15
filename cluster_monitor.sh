#!/bin/bash

# ======================================================
# Supermicro Cluster Memory Health Monitor (Final)
# Designed for Industrial GSAT Screening
# ======================================================

# --- 1. Configuration ---
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

USER="admin"      # IPMI Username
PASS="ADMIN"     # IPMI Password

# --- 2. Color Definitions ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# --- 3. Environment Check ---
if ! command -v ipmitool &> /dev/null; then
    echo -e "${RED}ERROR: ipmitool not found. Install with: sudo apt install ipmitool${NC}"
    exit 1
fi

# --- 4. Monitoring Logic ---
echo -e "${BLUE}=====================================================${NC}"
echo -e "${BLUE}   Supermicro Cluster Memory Health Monitor          ${NC}"
echo -e "${BLUE}   Scan Time: $(date '+%Y-%m-%d %H:%M:%S')            ${NC}"
echo -e "${BLUE}=====================================================${NC}"
printf "%-15s | %-12s | %-10s | %-12s\n" "SERVER IP" "OS STATUS" "POWER" "MEM HEALTH"
echo "-----------------------------------------------------"

for IP in "${SERVERS[@]}"; do
    # A. Check OS/Network Connectivity
    # If ping fails, the server is either booting, crashed in BIOS, or powered off
    if ! ping -c 1 -W 1 "$IP" > /dev/null 2>&1; then
        OS_STATUS="${YELLOW}OFFLINE/BOOT${NC}"
    else
        OS_STATUS="${GREEN}ONLINE (OS)${NC}"
    fi

    # B. Get Hardware Power Status via IPMI
    POWER=$(ipmitool -H "$IP" -U "$USER" -P "$PASS" chassis power status 2>/dev/null | awk '{print $4}')
    [ -z "$POWER" ] && POWER="N/A"

    # C. Get Latest Memory/ECC Errors from SEL
    # This captures errors even if the server is stuck in BIOS
    ERROR_LOG=$(ipmitool -H "$IP" -U "$USER" -P "$PASS" sel list 2>/dev/null | grep -iE "Memory|ECC|Correctable" | tail -n 1)

    # D. Status Triage Logic
    if [ -n "$ERROR_LOG" ]; then
        # 1. Hardware Error Detected (Highest Priority)
        printf "%-15s | %-21s | %-10s | ${RED}%-12s${NC}\n" "$IP" "$OS_STATUS" "$POWER" "FAILED"
        echo -e "  └─ ${RED}HW ERROR: $ERROR_LOG${NC}"
        echo -e "\a" # set alarm sound
    
    elif [[ "$POWER" == "off" ]]; then
        # 2. Server is Powered Off
        printf "%-15s | %-21s | %-10s | ${NC}%-12s${NC}\n" "$IP" "$OS_STATUS" "$POWER" "POWER OFF"
    
    elif [[ "$OS_STATUS" == *OFFLINE* ]]; then
        # 3. Power is ON but OS is not responding (Likely stuck in BIOS or Loading)
        printf "%-15s | %-21s | %-10s | ${CYAN}%-12s${NC}\n" "$IP" "$OS_STATUS" "$POWER" "INITIALIZING"
    
    else
        # 4. Running Healthy
        printf "%-15s | %-21s | %-10s | ${GREEN}%-12s${NC}\n" "$IP" "$OS_STATUS" "$POWER" "HEALTHY"
    fi
done

echo "-----------------------------------------------------"
echo -e "${CYAN}TIPS:${NC}"
echo -e "1. If status is ${CYAN}INITIALIZING${NC} for >5 min, check BIOS screen via IPMI Web KVM."
echo -e "2. Use 'watch -n 10 $0' to run this dashboard."
