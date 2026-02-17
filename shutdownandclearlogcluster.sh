#!/bin/bash

# ======================================================
# Supermicro Cluster - Batch Shutdown & Log Cleanup Tool
# Optimized with OS/BMC IP Mapping
# ======================================================

# --- 1. Configuration (OS IP => IPMI/BMC IP Mapping) ---
declare -A SERVERS=(
    ["192.168.1.101"]="192.168.30.101"
    ["192.168.1.102"]="192.168.30.102"
    ["192.168.1.103"]="192.168.30.103"
    ["192.168.1.104"]="192.168.30.104"
    ["192.168.1.105"]="192.168.30.105"
    ["192.168.1.106"]="192.168.30.106"
    ["192.168.1.107"]="192.168.30.107"
    ["192.168.1.108"]="192.168.30.108"
    ["192.168.1.109"]="192.168.30.109"
    ["192.168.1.110"]="192.168.30.110"
)

USER="admin"
PASS="ADMIN"

DELAY_BETWEEN=5      # Delay between servers
TIMEOUT=12           # Command timeout
VERIFY_WAIT=20       # Wait before final ping check

# --- 2. Color Definitions ---
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

# --- 3. Header ---
echo -e "${BLUE}=================================================${NC}"
echo -e "${BLUE}   Supermicro Cluster: CLEANUP & SHUTDOWN        ${NC}"
echo -e "${BLUE}   Targeting ${#SERVERS[@]} Server Nodes           ${NC}"
echo -e "${BLUE}=================================================${NC}"

# --- 4. Safety Confirmation ---
read -p "Are you sure you want to clear logs and SHUT DOWN all nodes? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}Operation cancelled.${NC}"
    exit 0
fi

count=0; success=0; failed=0

# Sort and iterate through the OS IPs
for OS_IP in $(echo "${!SERVERS[@]}" | tr ' ' '\n' | sort -V); do
    BMC_IP=${SERVERS[$OS_IP]}
    ((count++))
    
    echo -e "${CYAN}[$count/${#SERVERS[@]}] Node: $OS_IP (BMC: $BMC_IP)${NC}"

    # --- STEP 1: Clear IPMI SEL Log ---
    echo -n "  -> Clearing IPMI Log... "
    if timeout "$TIMEOUT" ipmitool -H "$BMC_IP" -U "$USER" -P "$PASS" sel clear >/dev/null 2>&1; then
        echo -e "${GREEN}DONE${NC}"
    else
        echo -e "${RED}FAILED${NC} (BMC unreachable)"
    fi

    # --- STEP 2: Shutdown ---
    echo -n "  -> Issuing Shutdown...  "
    # Try Soft Down (Safe)
    if timeout "$TIMEOUT" ipmitool -H "$BMC_IP" -U "$USER" -P "$PASS" chassis power soft >/dev/null 2>&1; then
        echo -e "${GREEN}SOFT SENT${NC}"
        ((success++))
    else
        # Force Hard Down
        echo -n -e "${YELLOW}Soft failed, trying HARD... "
        if timeout "$TIMEOUT" ipmitool -H "$BMC_IP" -U "$USER" -P "$PASS" chassis power down >/dev/null 2>&1; then
            echo -e "SUCCESS${NC}"
            ((success++))
        else
            echo -e "${RED}FAILED${NC}"
            ((failed++))
        fi
    fi

    # Delay
    [ "$count" -lt "${#SERVERS[@]}" ] && sleep "$DELAY_BETWEEN"
done

# --- 5. Final Verification ---
echo -e "\n${BLUE}=================================================${NC}"
echo -e "${CYAN}Waiting ${VERIFY_WAIT}s for power-off verification...${NC}"
sleep "$VERIFY_WAIT"

still_online=0
for OS_IP in $(echo "${!SERVERS[@]}" | tr ' ' '\n' | sort -V); do
    if ping -c 1 -W 1 "$OS_IP" > /dev/null 2>&1; then
        echo -e "  [!] ${RED}$OS_IP is STILL ONLINE${NC}"
        ((still_online++))
    else
        echo -e "  [OK] $OS_IP is Offline"
    fi
done

# --- Final Summary ---
echo -e "${BLUE}=================================================${NC}"
echo -e "   Summary Result:"
echo -e "   Successfully Processed: ${GREEN}${success}${NC}"
echo -e "   Failed to Respond     : ${RED}${failed}${NC}"
if [ "$still_online" -gt 0 ]; then
    echo -e "   Final Status          : ${RED}${still_online} node(s) still UP${NC}"
else
    echo -e "   Final Status          : ${GREEN}All nodes SHUTDOWN${NC}"
fi
echo -e "${BLUE}=================================================${NC}\n"
