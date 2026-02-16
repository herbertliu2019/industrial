#!/bin/bash

# ======================================================
# Supermicro Cluster - Batch Shutdown Script
# Used to gracefully power off all test servers after health screening
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

DELAY_BETWEEN=8      # Seconds to wait between issuing shutdown commands
TIMEOUT=15           # Timeout (seconds) for each ipmitool command

# --- Colors for console output ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'         # No Color

# --- Check if ipmitool is installed ---
if ! command -v ipmitool &> /dev/null; then
    echo -e "${RED}Error: ipmitool not found. Please install it:${NC}"
    echo "   sudo apt update && sudo apt install ipmitool -y"
    exit 1
fi

# --- Header ---
echo -e "${BLUE}=================================================${NC}"
echo -e "${BLUE}   Supermicro Cluster Batch Shutdown Tool${NC}"
echo -e "${BLUE}   Started: $(date '+%Y-%m-%d %H:%M:%S')${NC}"
echo -e "${BLUE}=================================================${NC}"
echo -e "  Total servers : ${#SERVERS[@]}"
echo -e "  Delay between : ${DELAY_BETWEEN} seconds"
echo -e "  Command timeout: ${TIMEOUT} seconds"
echo ""

# --- Safety confirmation ---
read -p "Are you sure you want to shut down all ${#SERVERS[@]} servers? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}Operation cancelled.${NC}"
    exit 0
fi

echo -e "${YELLOW}Starting shutdown sequence...${NC}\n"

count=0
success=0
failed=0

for IP in "${SERVERS[@]}"; do
    ((count++))

    printf "(%2d/%d) %-15s  " "$count" "${#SERVERS[@]}" "$IP"

    # Try graceful shutdown first (ACPI power button event)
    if timeout "$TIMEOUT" ipmitool -H "$IP" -U "$USER" -P "$PASS" chassis power soft >/dev/null 2>&1; then
        echo -e "${GREEN}Shutdown command sent${NC}"
        ((success++))
    else
        # Fall back to hard power off if soft failed
        echo -n -e "${YELLOW}soft failed, trying hard... "
        if timeout "$TIMEOUT" ipmitool -H "$IP" -U "$USER" -P "$PASS" chassis power down >/dev/null 2>&1; then
            echo -e "Hard power off successful${NC}"
            ((success++))
        else
            echo -e "${RED}Failed (timeout or auth issue)${NC}"
            ((failed++))
        fi
    fi

    # Wait between servers (skip wait after the last one)
    if [ "$count" -lt "${#SERVERS[@]}" ]; then
        printf "  Waiting %d seconds...\n" "$DELAY_BETWEEN"
        sleep "$DELAY_BETWEEN"
    fi
done

# --- Summary ---
echo ""
echo -e "${BLUE}=================================================${NC}"
echo -e "  Finished : $(date '+%Y-%m-%d %H:%M:%S')"
echo -e "  Success  : ${GREEN}${success}${NC} servers"
echo -e "  Failed   : ${RED}${failed}${NC} servers"
echo -e "${BLUE}=================================================${NC}"

if [ "$failed" -gt 0 ]; then
    echo -e "${YELLOW}Warning: ${failed} server(s) failed to shut down. Check network, credentials, or do it manually.${NC}"
fi

echo ""
