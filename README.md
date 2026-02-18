## 当前系统运行逻辑（完整流程）
测试机
   ↓ POST JSON
服务器
   ├── 保存 history 文件
   └── 覆盖 latest 文件
           ↓
网页读取 latest

## 目录结构（自动创建）

运行后服务器会生成：

data/
 ├── history/
 └── latest/


## 接口说明（给前端或调试用）
上传数据
POST /api/upload

获取全部最新状态
GET /api/latest


返回：

[
 {server1 json},
 {server2 json}
]

### 总结逻辑流程
测试机上传 JSON
         ↓
   中控服务器处理：
   ├─ 保存历史记录：history/hostname_时间.json （永久保存）
   └─ 更新最新状态：latest/hostname.json （覆盖旧文件）
         ↓
网页读取 latest 文件夹
         ↓
显示所有机器的最新状态


所以“最新数据”就是 latest 文件夹里的 JSON 文件，判断依据：

同一台机器只有一个 latest 文件

最新上传的数据覆盖旧文件

文件名或者 JSON 内的 timestamp 可辅助排序（可选

### 核心思想：

history/ = 永久存档

latest/ = 最新状态（每台机器覆盖）

网页只看 latest/ → 总是显示最新测试数

## 网页显示：http://中控服务器IP:5000/

显示所有测试机的最新状态（latest 文件夹）

每行一台测试机

背景颜色根据状态：

PASS = 绿色

FAIL = 红色

WARNING = 黄色

数据来源：

/api/latest 返回所有测试机 JSON

HTML页面通过 JS fetch 自动读取并生成表格

自动每2秒刷新

测试机上传逻辑：

继续用你整合好的 curl POST 上传 JSON

上传后 /data/latest/hostname.json 会被更新

网页自动显示最新状态


## END


















To make your 10-server testing operation seamless and professional, here is the Standard Operating Procedure (SOP).

I have integrated the "Log Clear" tool into a final package. You should have these three files on your Master Control PC.

# 1. Preparation: The Three Tools
Filename,Purpose,When to run
cluster_monitor.sh,Real-time dashboard (Status of 10 nodes),Continuous (using watch)

cluster_clear_logs.sh,Reset hardware logs for a fresh start,Before starting each batch

cluster_poweroff.sh,Shut down all successful nodes,After testing is complete

# 2. The Logic for cluster_clear_logs.sh
Create this new script to ensure old errors from previous RAM sticks don't confuse your current test.


# 3. Step-by-Step Operation Order (SOP)
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

# 4. Summary of Master PC Commands

1. Start Batch
./cluster_clear_logs.sh

 2. Monitor (Keep this running in a dedicated terminal window)
watch -d -n 10 ./cluster_monitor.sh

3. End Batch
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


**“死在 BIOS 阶段”**的情况确实时有发生。
简短的回答是：监控脚本完全可以得知。 即使系统没有加载（没进 Linux），Supermicro 的 BMC（管理芯片） 是独立于 CPU 和操作系统的。只要电源线插着，BMC 就会在后台持续监控 BIOS 的自检过程。

以下是监控脚本在不同 BIOS 故障场景下的表现：

1. 监控脚本如何捕捉 BIOS 报错？
当内存损坏导致 BIOS 无法通过自检（POST）时，Supermicro 主板会将错误实时写入 SEL（系统事件日志）。

场景 A：致命损坏（无法开机）
如果内存彻底损坏，BIOS 会卡在内存初始化阶段。此时，监控脚本会抓取到类似这样的日志：
Latest SEL: Memory | Memory Device Disabled | Critical | Slot DIMMA1
监控显示： FAILED | on | ERROR!

场景 B：内存被禁用（能开机但容量不对）
如果某根内存不稳定，BIOS 可能会为了保护系统而将其“屏蔽（Disabled）”。
监控显示： 同样会显示 ERROR!，日志会提示 Memory configuration error 或 Correctable ECC logging limit reached。

# 你的完整工作流：
# 开始：在 10 台机器上插入内存。

# 压测：服务器启动后自动运行 GSAT 脚本。

#监控：在主控机运行 watch -n 10 ./cluster_monitor.sh。

#等待：GSAT 跑完 5 分钟后，服务器会 sleep 60。

#收尾：你在主控机看到所有机器都测试通过，运行 ./cluster_poweroff.sh。

#物理拆卸：看到机器全黑了，直接拔掉内存，换下一批。


你的“无人值守”流程建议
既然你已经有 10 台机器，你可以这样布置你的控制台：

准备一台笔记本，作为主控机。

分屏操作：

左边窗口： 运行 watch -n 10 ./ipmi_monitor.sh。看到绿色就不用管，看到红色就记录下对应的 IP。

右边窗口： 随时准备远程 SSH 进入红色的机器看具体的 GSAT 报错细节。

关键点： 如果你发现某台机器变红了，但它还在跑测试，不要立即关机。先看 ipmitool sel list 报错里提到的 DIMM Slot（如 DIMM A1），这样你拆机的时候就知道该拔哪一根，而不是瞎猜。

# 免密码sudo（工业机推荐）：

echo 'ALL ALL=(ALL) NOPASSWD: /usr/sbin/uhubctl' | sudo tee /etc/sudoers.d/uhubctl
sudo chmod 440 /etc/sudoers.d/uhubctl

