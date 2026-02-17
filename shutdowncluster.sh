#!/bin/bash

# ======================================================
# Supermicro Cluster - Batch Shutdown & Log Cleanup Tool
# Purpose: Clear hardware logs, Power off, and Verify Offline status
# ======================================================

# --- Configuration ---
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

USER="admin"
PASS="ADMIN"

DELAY_BETWEEN=8      # Seconds to wait between servers to prevent power surge
TIMEOUT=15           # Timeout for ipmitool commands
VERIFY_WAIT=30       # Seconds to wait before final offline verification

# --- Colors ---
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

# --- Header ---
echo -e "${BLUE}=================================================${NC}"
echo -e "${BLUE}   Supermicro Cluster: LOG CLEAR & SHUTDOWN      ${NC}"
echo -e "${BLUE}   Started: $(date '+%Y-%m-%d %H:%M:%S')          ${NC}"
echo -e "${BLUE}=================================================${NC}"

# --- Safety confirmation ---
read -p "Clear logs and SHUT DOWN ${#SERVERS[@]} servers? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}Operation cancelled.${NC}"
    exit 0
fi

count=0; success=0; failed=0

for IP in "${SERVERS[@]}"; do
    ((count++))
    echo -e "${CYAN}[$count/${#SERVERS[@]}] Processing: $IP${NC}"

    # --- STEP 1: Clear IPMI SEL Log (Preparation for next test) ---
    echo -n "  -> Clearing IPMI SEL Log... "
    if timeout "$TIMEOUT" ipmitool -H "$IP" -U "$USER" -P "$PASS" sel clear >/dev/null 2>&1; then
        echo -e "${GREEN}DONE${NC}"
    else
        echo -e "${RED}FAILED${NC} (Check network/auth)"
    fi

    # --- STEP 2: Shutdown Sequence ---
    echo -n "  -> Issuing Shutdown...      "
    # Try Soft first
    if timeout "$TIMEOUT" ipmitool -H "$IP" -U "$USER" -P "$PASS" chassis power soft >/dev/null 2>&1; then
        echo -e "${GREEN}SOFT CMD SENT${NC}"
        ((success++))
    else
        # Fallback to Hard
        echo -n -e "${YELLOW}Soft failed, trying HARD... "
        if timeout "$TIMEOUT" ipmitool -H "$IP" -U "$USER" -P "$PASS" chassis power down >/dev/null 2>&1; then
            echo -e "SUCCESS${NC}"
            ((success++))
        else
            echo -e "${RED}FAILED${NC}"
            ((failed++))
        fi
    fi

    # Delay between servers
    [ "$count" -lt "${#SERVERS[@]}" ] && sleep "$DELAY_BETWEEN"
done

# --- STEP 3: Final Verification ---
echo -e "\n${BLUE}=================================================${NC}"
echo -e "${CYAN}Waiting ${VERIFY_WAIT}s for servers to fully power off...${NC}"
sleep "$VERIFY_WAIT"
echo -e "${CYAN}Verifying Offline Status (Ping Check):${NC}"

still_online=0
for IP in "${SERVERS[@]}"; do
    if ping -c 1 -W 1 "$IP" > /dev/null 2>&1; then
        echo -e "  [!] ${RED}$IP is STILL ONLINE${NC}"
        ((still_online++))
    else
        echo -e "  [OK] $IP is Offline"
    fi
done

# --- Final Summary ---
echo -e "${BLUE}=================================================${NC}"
echo -e "   Summary Result:"
echo -e "   Successfully Shutdown Processed: ${GREEN}${success}${NC}"
echo -e "   Failed Shutdown Commands       : ${RED}${failed}${NC}"
if [ "$still_online" -gt 0 ]; then
    echo -e "   Verification Status            : ${RED}${still_online} server(s) still pingable!${NC}"
else
    echo -e "   Verification Status            : ${GREEN}All servers confirmed OFFLINE${NC}"
fi
echo -e "${BLUE}=================================================${NC}\n"
