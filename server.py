# server.py
from flask import Flask, jsonify
import os, json

app = Flask(__name__)

# 文件夹路径
BASE_DIR = "data"
HISTORY_DIR = os.path.join(BASE_DIR, "history")
LATEST_DIR = os.path.join(BASE_DIR, "latest")

# 创建文件夹
os.makedirs(HISTORY_DIR, exist_ok=True)
os.makedirs(LATEST_DIR, exist_ok=True)

#########################################################
# 上传接口：测试机 POST JSON
#########################################################
@app.route("/api/upload", methods=["POST"])
def upload():
    data = request.json
    if not data:
        return jsonify({"error": "no json"}), 400

    hostname = data.get("device", {}).get("hostname", "unknown")
    ts = int(json.get("device", {}).get("timestamp_ts", str(int(os.times()[4]))))  # 可选时间戳 fallback

    # ---------- 保存历史 ----------
    history_file = f"{hostname}_{ts}.json"
    with open(os.path.join(HISTORY_DIR, history_file), "w") as f:
        json.dump(data, f, indent=2)

    # ---------- 更新最新 ----------
    latest_file = os.path.join(LATEST_DIR, f"{hostname}.json")
    with open(latest_file, "w") as f:
        json.dump(data, f, indent=2)

    return jsonify({"status": "ok"})


#########################################################
# 获取所有最新状态（网页或API读取）
#########################################################
@app.route("/api/latest")
def latest_all():
    result = []
    for file in os.listdir(LATEST_DIR):
        path = os.path.join(LATEST_DIR, file)
        try:
            with open(path) as f:
                result.append(json.load(f))
        except:
            continue
    return jsonify(result)


#########################################################
# 网页仪表盘
#########################################################
@app.route("/")
def dashboard():
    return """
<html>
<head>
<title>Memory Test Dashboard</title>
<style>
body{font-family:Arial;}
table{border-collapse:collapse;width:100%;}
th,td{border:1px solid #333;padding:8px;text-align:center;}
th{background:#555;color:white;}
</style>
<script>
async function load(){
    let r = await fetch('/api/latest');
    let data = await r.json();
    let html = "<h2>Memory Test Dashboard - All Machines</h2>";
    html += "<table>";
    html += "<tr><th>Hostname</th><th>Status</th><th>GSAT Errors</th><th>Memory Errors</th><th>CPU Errors</th><th>Test Time</th></tr>";

    data.forEach(d=>{
        let status = d.result.status;
        let color = status=="PASS"?"#9cff9c":status=="FAIL"?"#ff9c9c":"#ffe49c";
        html += `<tr style="background:${color}">
            <td>${d.device.hostname}</td>
            <td>${status}</td>
            <td>${d.errors.gsat}</td>
            <td>${d.errors.memory}</td>
            <td>${d.errors.cpu}</td>
            <td>${d.device.timestamp}</td>
        </tr>`;
    });

    html += "</table>";
    document.body.innerHTML = html;
}
setInterval(load, 2000);  // 每2秒刷新一次
load();
</script>
</head>
<body>
Loading...
</body>
</html>
"""

#########################################################
# 启动服务器
#########################################################
if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
