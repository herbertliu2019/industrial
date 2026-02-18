from flask import Flask, jsonify, request
import os, json, time

app = Flask(__name__)

BASE_DIR = "data"
HISTORY_DIR = os.path.join(BASE_DIR, "history")
LATEST_DIR = os.path.join(BASE_DIR, "latest")

os.makedirs(HISTORY_DIR, exist_ok=True)
os.makedirs(LATEST_DIR, exist_ok=True)

@app.route("/api/upload", methods=["POST"])
def upload():
    data = request.json
    if not data: return jsonify({"status": "error", "message": "no data"}), 400
    
    hostname = data.get("device", {}).get("hostname", "unknown")
    # 清理文件名
    hostname = "".join(c for c in hostname if c.isalnum() or c in "-_").rstrip()
    
    ts = int(time.time())
    
    # 保存历史 (带上时间戳防止冲突)
    with open(os.path.join(HISTORY_DIR, f"{hostname}_{ts}.json"), "w") as f:
        json.dump(data, f, indent=2)

    # 更新最新状态
    with open(os.path.join(LATEST_DIR, f"{hostname}.json"), "w") as f:
        json.dump(data, f, indent=2)

    return jsonify({"status": "ok", "received": hostname})

@app.route("/api/latest")
def latest_all():
    result = []
    for file in os.listdir(LATEST_DIR):
        if not file.endswith(".json"): continue
        with open(os.path.join(LATEST_DIR, file)) as f:
            result.append(json.load(f))
    return jsonify(result)

@app.route("/")
def dashboard():
    return """
<!DOCTYPE html>
<html>
<head>
    <title>RAM Test Center</title>
    <style>
        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; background: #f4f7f6; padding: 20px; }
        .card { background: white; border-radius: 8px; padding: 15px; margin-bottom: 10px; box-shadow: 0 2px 5px rgba(0,0,0,0.1); display: flex; justify-content: space-between; align-items: center; }
        .status-PASS { border-left: 10px solid #2ecc71; }
        .status-FAIL { border-left: 10px solid #e74c3c; }
        .status-WARNING { border-left: 10px solid #f1c40f; }
        .info { flex-grow: 1; margin-left: 20px; }
        .hostname { font-size: 1.2em; font-weight: bold; }
        .error-badge { background: #eee; padding: 2px 8px; border-radius: 4px; font-size: 0.9em; margin-right: 10px; }
    </style>
</head>
<body>
    <h1>Memory Test Dashboard</h1>
    <div id="container">Loading servers...</div>
    <script>
        async function update() {
            const r = await fetch('/api/latest');
            const data = await r.json();
            const container = document.getElementById('container');
            container.innerHTML = data.map(d => `
                <div class="card status-${d.result.status}">
                    <div class="info">
                        <div class="hostname">${d.device.hostname}</div>
                        <div>Status: <strong>${d.result.status}</strong> | Last Seen: ${d.device.timestamp}</div>
                        <div style="margin-top:5px">
                            <span class="error-badge">GSAT: ${d.errors.gsat}</span>
                            <span class="error-badge">MEM: ${d.errors.memory}</span>
                            <span class="error-badge">CPU: ${d.errors.cpu}</span>
                        </div>
                    </div>
                    <div style="text-align:right; font-size:0.9em; color:#666;">
                        Tested: ${d.system.tested_memory_mb} MB<br>
                        Cores: ${d.system.cpu_cores}
                    </div>
                </div>
            `).join('');
        }
        setInterval(update, 3000);
        update();
    </script>
</body>
</html>
"""

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=False)
