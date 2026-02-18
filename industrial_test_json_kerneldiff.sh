#!/bin/bash
############################################################
# Industrial RAM Test Script + JSON Upload Version
############################################################

TEST_TIME=300
LOG_DIR="/root/test_logs"
UPLOAD_URL="http://your-server/api/upload"   # ← 改成你的服务器地址
mkdir -p $LOG_DIR

GSAT_LOG="$LOG_DIR/gsat_$(date +%Y%m%d_%H%M%S).log"
MEM_INV_LOG="$LOG_DIR/memory_inventory.log"

############################################
# PHASE 1 — DIMM Inventory
############################################

HW_DROP_DETECTED=0

INV_DATA=$(sudo dmidecode -t memory | grep -E "Locator:|Size:" | grep -v "Bank" | awk '
BEGIN { print "--- Physical Slot Inventory ---" }
 /Size:/ { line = $0; sub(/.*Size: /, "", line); current_size = line }
 /Locator:/ {
     line = $0; sub(/.*Locator: /, "", line); loc = line;
     if (current_size ~ /No Module Installed/) {
         printf "%s|EMPTY\n", loc
         system("echo 1 > /tmp/hw_drop")
     } else {
         printf "%s|%s\n", loc, current_size
     }
 }')

[ -f /tmp/hw_drop ] && HW_DROP_DETECTED=1 && rm /tmp/hw_drop
echo "$INV_DATA" > "$MEM_INV_LOG"

############################################
# PHASE 2 — Stress Test
############################################

TOTAL_CORES=$(nproc)
FREE_KB=$(awk '/MemAvailable/ {print $2}' /proc/meminfo)
TEST_MB=$((FREE_KB * 95 / 100 / 1024))
[ "$TEST_MB" -lt 1024 ] && TEST_MB=1024

MEM_THREADS=$(( TOTAL_CORES / 2 ))
[ "$MEM_THREADS" -lt 4 ] && MEM_THREADS=4

############################################
# Kernel baseline logs
############################################

dmesg | grep -iE "ECC|EDAC|MCE|Machine Check" > /tmp/pre_errors.log

############################################
# Run stressapptest
############################################

stressapptest \
-M ${TEST_MB} \
-s ${TEST_TIME} \
-W \
-m ${MEM_THREADS} \
-C ${TOTAL_CORES} \
--cc_test > $GSAT_LOG 2>&1

GSAT_EXIT=$?

############################################
# Kernel errors after test
############################################

dmesg | grep -iE "ECC|EDAC|MCE|Machine Check" > /tmp/post_errors.log
diff /tmp/pre_errors.log /tmp/post_errors.log > /tmp/diff_errors.log

############################################
# 分类统计错误类型
############################################

MEMORY_ERRORS=$(grep -iE "ECC|EDAC" /tmp/diff_errors.log | wc -l)
CPU_ERRORS=$(grep -iE "MCE|Machine Check" /tmp/diff_errors.log | wc -l)

############################################
# GSAT error count
############################################

GSAT_REAL_ERRORS=$(grep "with .* errors" "$GSAT_LOG" | tail -n1 | awk -F', ' '{print $2}' | awk '{print $1}')
[ -z "$GSAT_REAL_ERRORS" ] && GSAT_REAL_ERRORS=0

TOTAL_CRITICAL_ERRORS=$((GSAT_REAL_ERRORS + MEMORY_ERRORS + CPU_ERRORS))

############################################
# FINAL STATUS
############################################

if [ "$GSAT_EXIT" -ne 0 ] || [ "$TOTAL_CRITICAL_ERRORS" -gt 0 ]; then
    FINAL_STATUS="FAIL"
elif [ "$HW_DROP_DETECTED" -eq 1 ]; then
    FINAL_STATUS="WARNING"
else
    FINAL_STATUS="PASS"
fi

############################################
# 构建 JSON
############################################

HOSTNAME=$(hostname)
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# DIMM JSON
SLOTS_JSON=$(awk -F'|' '
BEGIN{printf "["}
{
printf "{\"slot\":\"%s\",\"size\":\"%s\"}",$1,$2
if(NR!=NR_END) printf ","
}
END{printf "]"}
' NR_END=$(wc -l < "$MEM_INV_LOG") "$MEM_INV_LOG")

JSON_DATA=$(cat <<EOF
{
  "device":{
    "hostname":"$HOSTNAME",
    "timestamp":"$TIMESTAMP"
  },
  "result":{
    "status":"$FINAL_STATUS",
    "test_time_sec":$TEST_TIME
  },
  "system":{
    "cpu_cores":$TOTAL_CORES,
    "tested_memory_mb":$TEST_MB
  },
  "errors":{
    "gsat":$GSAT_REAL_ERRORS,
    "memory":$MEMORY_ERRORS,
    "cpu":$CPU_ERRORS
  },
  "memory_slots":$SLOTS_JSON
}
EOF
)

############################################
# 保存 JSON 日志
############################################

JSON_FILE="$LOG_DIR/report_$(date +%s).json"
echo "$JSON_DATA" > "$JSON_FILE"

############################################
# 上传到服务器
############################################

curl -s -X POST "$UPLOAD_URL" \
-H "Content-Type: application/json" \
-d "$JSON_DATA" >/dev/null

############################################
# 本地打印总结
############################################

echo "=================================="
echo "STATUS: $FINAL_STATUS"
echo "GSAT ERRORS: $GSAT_REAL_ERRORS"
echo "MEMORY ERRORS: $MEMORY_ERRORS"
echo "CPU ERRORS: $CPU_ERRORS"
echo "JSON saved: $JSON_FILE"
echo "=================================="

while true; do sleep 60; done
