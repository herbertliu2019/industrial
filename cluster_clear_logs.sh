#!/bin/bash
# cluster_clear_logs.sh
SERVERS=("192.168.1.101" "192.168.1.102" "192.168.1.103" "192.168.1.104" "192.168.1.105" "192.168.1.106" "192.168.1.107" "192.168.1.108" "192.168.1.109" "192.168.1.110")
USER="admin"
PASS="ADMIN"

echo "Clearing IPMI Logs on all servers..."
for IP in "${SERVERS[@]}"; do
    echo -n "Clearing [$IP]... "
    ipmitool -H "$IP" -U "$USER" -P "$PASS" sel clear > /dev/null 2>&1
    if [ $? -eq 0 ]; then echo "DONE"; else echo "FAILED"; fi
done
