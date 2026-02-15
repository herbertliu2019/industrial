To make your 10-server testing operation seamless and professional, here is the Standard Operating Procedure (SOP).

I have integrated the "Log Clear" tool into a final package. You should have these three files on your Master Control PC.

1. Preparation: The Three Tools
Filename,Purpose,When to run
cluster_monitor.sh,Real-time dashboard (Status of 10 nodes),Continuous (using watch)

cluster_clear_logs.sh,Reset hardware logs for a fresh start,Before starting each batch

cluster_poweroff.sh,Shut down all successful nodes,After testing is complete

2. The Logic for cluster_clear_logs.sh
Create this new script to ensure old errors from previous RAM sticks don't confuse your current test.


3. Step-by-Step Operation Order (SOP)
Step 1: Physical Setup
Insert the RAM sticks into the 10 servers and connect the power. Ensure the IPMI network cables are connected to your switch.

Step 2: Reset logs (Master PC)
Run this to wipe the history of the "previous" batch of RAM.

chmod +x *.sh
./cluster_clear_logs.sh

Step 3: Power On & Monitor (Master PC)
Turn on the servers. Immediately start the monitoring dashboard:

watch -d -n 10 ./cluster_monitor.sh

Look for FAILED: If a server turns red within 2 minutes, the RAM failed BIOS initialization. You can pull it immediately.

Look for ONLINE: This means the OS loaded and GSAT is now running.

Step 4: Verification (Master PC)
Wait for the test duration (e.g., 5 minutes).

When a server finishes, the dashboard will show a new entry in the Latest SEL column (the custom record you added to the GSAT script).

If the status remains HEALTHY and you see the "Test Finished" log, the RAM is good.

Step 5: Batch Shutdown (Master PC)
Once all servers are either FAILED or COMPLETED, run the shutdown tool:

./cluster_poweroff.sh

Wait for the dashboard to show all servers as POWER OFF.

4. Summary of Master PC Commands

# 1. Start Batch
./cluster_clear_logs.sh

# 2. Monitor (Keep this running in a dedicated terminal window)
watch -d -n 10 ./cluster_monitor.sh

# 3. End Batch
./cluster_poweroff.sh

Final Tip: If you notice one server is consistently OFFLINE while others are ONLINE, check if its system disk is disconnected or if the BIOS is stuck on a "Keyboard Not Found" style prompt (which you can bypass using the IPMI Web KVM).









cluster_monitor:
配合使用的工作流
Clear Old Logs (Before starting a new batch):
运行以下命令清空 10 台机器的历史日志，确保监控到的是当前内存的结果：

Bash
for IP in "${SERVERS[@]}"; do ipmitool -H $IP -U admin -P ADMIN sel clear; done
Start Monitoring:
使用 watch 命令让它每 10 秒刷新一次：

Bash
watch -d -n 10 ./cluster_monitor.sh
Monitor the Stages:

INITIALIZING (Cyan): 刚开机，正在过 BIOS 或加载系统。

ONLINE / HEALTHY (Green): 正在跑 GSAT 压测。

FAILED (Red): 内存报错！脚本会直接把 BIOS 里的报错行打印出来（即使没进系统也能看到）。

OFFLINE / POWER OFF: 测试完成或机器未通电。

Batch Power Off:
测试全部完成后，运行我们之前写的 cluster_poweroff.sh。

这个监控脚本现在非常健壮，能够帮你准确区分“系统还没启动”、“正在启动”、“内存报错”和“测试完成”四种状态。


