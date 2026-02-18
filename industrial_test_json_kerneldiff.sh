#!/bin/bash
############################################################
# Industrial RAM Test Script - Full Version with API Upload
############################################################

# --- 1. 配置区 ---
TEST_TIME=300                          # 压力测试持续时间（秒）
LOG_DIR="/root/test_logs"              # 日志存储路径
UPLOAD_URL="http://中控服务器IP:5000/api/upload"  # ←【务必修改】改成你的中控服务器 IP
mkdir -p $LOG_DIR

# 生成唯一文件名
TIMESTAMP_FILE=$(date +%Y%m%d_%H%M%S)
GSAT_LOG="$LOG_DIR/gsat_${TIMESTAMP_FILE}.log"
MEM_INV_LOG="$LOG_DIR/memory_inventory.log"
JSON_FILE="$LOG_DIR/report_$(date +%s).json"

echo "Starting Industrial RAM Test Pipeline..."

############################################################
# 2. 内存插槽清点 (DIMM Inventory)
############################################################
echo "Scanning memory slots..."
HW_DROP_DETECTED=0

# 使用 dmidecode 获取插槽信息
INV_DATA=$(sudo dmidecode -t memory | grep -E "Locator:|Size:" | grep -v "Bank" | awk '
BEGIN { }
 /Size:/ { line = $0; sub(/.*Size: /, "", line); current_size = line }
 /Locator:/ {
     line = $0; sub(/.*Locator: /, "", line); loc = line;
     if (current_size ~ /No Module Installed/) {
         printf "%s|EMPTY\n", loc
         system("touch /tmp/hw_drop")
     } else {
         printf "%s|%s\n", loc, current_size
     }
 }')

if [ -f /tmp/hw_drop ]; then
    HW_DROP_DETECTED=1
    rm /tmp/hw_drop
fi
echo "$INV_DATA" > "$MEM_INV_LOG"

############################################################
# 3. 运行压力测试 (Stress Test)
############################################################
TOTAL_CORES=$(nproc)
FREE_KB=$(awk '/MemAvailable/ {print $2}' /proc/meminfo)
TEST_MB=$((FREE_KB * 95 / 100 / 1024))
[ "$TEST_MB" -lt 1024 ] && TEST_MB=1024

MEM_THREADS=$(( TOTAL_CORES / 2 ))
[ "$MEM_THREADS" -lt 4 ] && MEM_THREADS=4

# 抓取测试前的内核错误基准
dmesg | grep -iE "ECC|EDAC|MCE|Machine Check" > /tmp/pre_errors.log

echo "Running stressapptest ($TEST_TIME sec)..."
stressapptest \
    -M ${TEST_MB} \
    -s ${TEST_TIME} \
    -W \
    -m ${MEM_THREADS} \
    -C ${TOTAL_CORES} \
    --cc_test > "$GSAT_LOG" 2>&1

GSAT_EXIT=$?

# 抓取测试后的内核错误并对比
dmesg | grep -iE "ECC|EDAC|MCE|Machine Check" > /tmp/post_errors.log
diff /tmp/pre_errors.log /tmp/post_errors.log > /tmp/diff_errors.log

# 统计各类错误数量
MEMORY_ERRORS=$(grep -iE "ECC|EDAC" /tmp/diff_errors.log | wc -l)
CPU_ERRORS=$(grep -iE "MCE|Machine Check" /tmp/diff_errors.log | wc -l)

# 解析 GSAT 报告中的错误数
GSAT_REAL_ERRORS=$(grep "with .* errors" "$GSAT_LOG" | tail -n1 | awk -F', ' '{print $2}' | awk '{print $1}')
[ -z "$GSAT_REAL_ERRORS" ] && GSAT_REAL_ERRORS=0

TOTAL_CRITICAL_ERRORS=$((GSAT_REAL_ERRORS + MEMORY_ERRORS + CPU_ERRORS))

# 确定最终状态
if [ "$GSAT_EXIT" -ne 0 ] || [ "$TOTAL_CRITICAL_ERRORS" -gt 0 ]; then
    FINAL_STATUS="FAIL"
elif [ "$HW_DROP_DETECTED" -eq 1 ]; then
    FINAL_STATUS="WARNING"
else
    FINAL_STATUS="PASS"
fi

############################################################
# 4. 构建健壮的 JSON (Build JSON)
############################################################
echo "Generating JSON report..."
HOSTNAME_VAL=$(hostname)
UTC_TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# 改进点：使用更健壮的 awk 循环构建 JSON 数组，处理空行情况
SLOTS_JSON=$(awk -F'|' '
    BEGIN { printf "[" }
    {
        if (NR > 1) printf ","
        printf "{\"slot\":\"%s\",\"size\":\"%s\"}", $1, $2
    }
    END { printf "]" }
' "$MEM_INV_LOG")

JSON_DATA=$(cat <<EOF
{
  "device": {
    "hostname": "$HOSTNAME_VAL",
    "timestamp": "$UTC_TIMESTAMP"
  },
  "result": {
    "status": "$FINAL_STATUS",
    "test_time_sec": $TEST_TIME
  },
  "system": {
    "cpu_cores": $TOTAL_CORES,
    "tested_memory_mb": $TEST_MB
  },
  "errors": {
    "gsat": $GSAT_REAL_ERRORS,
    "memory": $MEMORY_ERRORS,
    "cpu": $CPU_ERRORS
  },
  "memory_slots": $SLOTS_JSON
}
EOF
)

echo "$JSON_DATA" > "$JSON_FILE"

############################################################
# 5. 上传与重试逻辑 (Upload with Retry)
############################################################
echo "Uploading results to $UPLOAD_URL..."
MAX_RETRIES=3
RETRY_COUNT=0
UPLOAD_SUCCESS=0

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    # 使用 --fail 让 curl 在 HTTP 报错时返回非零退出码
    curl -s --fail -X POST "$UPLOAD_URL" \
         -H "Content-Type: application/json" \
         -d @"$JSON_FILE"
    
    if [ $? -eq 0 ]; then
        echo "Upload successful!"
        UPLOAD_SUCCESS=1
        break
    else
        RETRY_COUNT=$((RETRY_COUNT + 1))
        echo "Upload failed. Retrying ($RETRY_COUNT/$MAX_RETRIES)..."
        sleep 5
    fi
done

if [ $UPLOAD_SUCCESS -eq 0 ]; then
    echo "ERROR: Could not upload data after $MAX_RETRIES attempts."
fi

############################################################
# 6. 打印总结
############################################################
echo "=================================="
echo "FINAL STATUS: $FINAL_STATUS"
echo "GSAT ERRORS : $GSAT_REAL_ERRORS"
echo "HW ERRORS   : $((MEMORY_ERRORS + CPU_ERRORS))"
echo "Report saved: $JSON_FILE"
echo "=================================="

# 如果
