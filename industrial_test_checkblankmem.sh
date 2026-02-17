#!/bin/bash
# Industrial-grade RAM screening script - "Report-Only" Version
# Logic: Errors = FAIL | Missing DIMMs = WARNING

############################
# 0. Global Settings
############################
TEST_TIME=300
LOG_DIR="/root/test_logs"
mkdir -p $LOG_DIR
GSAT_LOG="$LOG_DIR/gsat_$(date +%Y%m%d_%H%M%S).log"
MEM_INV_LOG="$LOG_DIR/memory_inventory.log"
IPMI_LOG="$LOG_DIR/ipmi_faults.log"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

############################################################
# PHASE 1: Hardware Scan (No Interruption)
############################################################
setterm -background blue -foreground white -clear all
echo "=========================================================="
echo " PHASE 1: HARDWARE SCAN (INFORMATIONAL)"
echo "=========================================================="

# 1.1 Scan for DIMM Slots status
HW_DROP_DETECTED=0
INV_DATA=$(sudo dmidecode -t memory | grep -E "Locator:|Size:" | grep -v "Bank" | awk '
    BEGIN { print "--- Physical Slot Inventory ---" }
    /Size:/ { line = $0; sub(/.*Size: /, "", line); current_size = line }
    /Locator:/ { 
        line = $0; sub(/.*Locator: /, "", line); loc = line;
        if (current_size ~ /No Module Installed/) {
            printf "[!] Slot %-12s : EMPTY/DISABLED\n", loc
            system("echo 1 > /tmp/hw_drop")
        } else {
            printf "[OK] Slot %-12s : %s\n", loc, current_size
        }
    }
')
[ -f /tmp/hw_drop ] && HW_DROP_DETECTED=1 && rm /tmp/hw_drop
echo -e "$INV_DATA"
echo -e "$INV_DATA" | sed 's/\x1b\[[0-9;]*m//g' > "$MEM_INV_LOG"

# 1.2 Scan IPMI SEL for memory faults
IPMI_ERRORS=$(ipmitool sel list 2>/dev/null | tail -n 100 | grep -iE "Memory|ECC|DIMM" | grep -iv "Informational")
[ -n "$IPMI_ERRORS" ] && echo "$IPMI_ERRORS" > "$IPMI_LOG"

echo -e "\nPre-check finished. Proceeding to Stress Test..."
sleep 2

############################################################
# PHASE 2: Stress Testing (GSAT)
############################################################
setterm -background black -foreground white -clear all
echo "=========================================================="
echo " PHASE 2: RUNNING GSAT STRESS TEST ($((TEST_TIME/60)) min)"
echo "=========================================================="

TOTAL_CORES=$(nproc)
FREE_KB=$(awk '/MemAvailable/ {print $2}' /proc/meminfo)
TEST_MB=$((FREE_KB * 95 / 100 / 1024)) # Using 95% of available memory
[ "$TEST_MB" -lt 1024 ] && TEST_MB=1024
MEM_THREADS=$(( $(nproc) / 2 ))
[ "$MEM_THREADS" -lt 4 ] && MEM_THREADS=4

dmesg | grep -iE "ECC|MCE|Hardware Error" > /tmp/pre_test_errors.log

echo -n "GSAT is running... [ "
stressapptest \
    -M ${TEST_MB} \
    -s ${TEST_TIME} \
    -W \
    -m ${MEM_THREADS} \
    -C ${TOTAL_CORES}   \
    --cc_test > $GSAT_LOG 2>&1 &
GSAT_PID=$!

# 在后台运行时显示简单的进度
while kill -0 $GSAT_PID 2>/dev/null; do
    echo -n "#"
    sleep 10
done
wait $GSAT_PID
GSAT_EXIT=$?
echo " ] Done!"

dmesg | grep -iE "ECC|MCE|Hardware Error" > /tmp/post_test_errors.log
NEW_ERRORS=$(diff /tmp/pre_test_errors.log /tmp/post_test_errors.log | grep '^>' | wc -l)
ERROR_COUNT=$(grep -iE "FAIL|ERROR" "$GSAT_LOG" | grep -vi "0 errors" | wc -l)

############################################################
# 9. Final Summary Report (Tiered Decision)
############################################################

# --- A. Extract exact error count from GSAT log ---
# Looks for the specific line "with X hardware incidents, Y errors"
GSAT_REAL_ERRORS=$(grep "with .* errors" "$GSAT_LOG" | tail -n 1 | awk -F', ' '{print $2}' | awk '{print $1}')
[ -z "$GSAT_REAL_ERRORS" ] && GSAT_REAL_ERRORS=0

# --- B. Critical Error Summation ---
# FAIL occurs only if GSAT crashes, finds bit flips, or Kernel reports MCE/ECC
TOTAL_CRITICAL_ERRORS=$((GSAT_REAL_ERRORS + NEW_ERRORS))

if [ "$GSAT_EXIT" -ne 0 ] || [ "$TOTAL_CRITICAL_ERRORS" -gt 0 ]; then
    # Actual hardware instability or test failure
    FINAL_STATUS="FAIL"
    setterm -background red -foreground white -clear all
elif [ "$HW_DROP_DETECTED" -eq 1 ] || [ -n "$IPMI_ERRORS" ]; then
    # Test passed, but hardware configuration is incomplete or has history faults
    FINAL_STATUS="WARNING"
    setterm -background yellow -foreground black -clear all
else
    # Perfect Run
    FINAL_STATUS="PASS"
    setterm -background green -foreground white -clear all
fi

echo -e "\n=========================================="
echo -e "         FINAL TEST SUMMARY REPORT"
echo -e "=========================================="
echo -e "  Overall Verdict      : $FINAL_STATUS"
echo -e "  GSAT Execution       : $([ "$GSAT_EXIT" -eq 0 ] && echo "SUCCESS" || echo "INTERRUPTED")"
echo -e "  GSAT Memory Errors   : $GSAT_REAL_ERRORS"
echo -e "  New Kernel Errors    : $NEW_ERRORS"
echo -e "------------------------------------------"
echo -e "  DIMM Configuration   : $([ "$HW_DROP_DETECTED" -eq 1 ] && echo -e "INCOMPLETE (Slots Empty)" || echo "FULL / AS DETECTED")"
echo -e "  IPMI History Status  : $([ -n "$IPMI_ERRORS" ] && echo -e "FAULT LOGS FOUND" || echo "CLEAN")"
echo -e "==========================================\n"

# Only trigger the buzzer alarm on actual FAIL
if [ "$FINAL_STATUS" == "FAIL" ]; then
    for i in {1..10}; do echo -e "\a" > /dev/tty1; sleep 0.3; done
fi

echo "Detailed logs are available in: $LOG_DIR"
echo "System idling. Press Ctrl+C to exit or wait for remote monitoring."

while true; do sleep 60; done
