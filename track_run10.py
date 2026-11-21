# -*- coding: utf-8 -*-
import urllib.request
import json
import time

time.sleep(3)
url = "https://api.github.com/repos/744875773z-prog/Z30Control/actions/runs"
req = urllib.request.Request(url, headers={"User-Agent": "Antigravity-Agent"})
with urllib.request.urlopen(req) as resp:
    data = json.loads(resp.read().decode("utf-8"))
    latest = data.get("workflow_runs", [])[0]
    run_id = latest.get("id")
    print(f"Latest Run #{latest.get('run_number')}: ID {run_id}")
    print(f"Status: {latest.get('status')} | Conclusion: {latest.get('conclusion')}")
    print(f"Commit: {latest.get('head_commit', {}).get('message')}")
    print(f"HTML URL: {latest.get('html_url')}")

jobs_url = f"https://api.github.com/repos/744875773z-prog/Z30Control/actions/runs/{run_id}/jobs"

for i in range(15):
    try:
        req2 = urllib.request.Request(jobs_url, headers={"User-Agent": "Antigravity-Agent"})
        with urllib.request.urlopen(req2, timeout=10) as resp2:
            data2 = json.loads(resp2.read().decode("utf-8"))
            job = data2.get("jobs", [])[0]
            print(f"[{time.strftime('%H:%M:%S')}] Job: {job.get('status')} ({job.get('conclusion')})")
            for step in job.get("steps", []):
                print(f"   -> {step.get('name')} [{step.get('status')} | {step.get('conclusion')}]")
            if job.get("status") == "completed":
                break
    except Exception as e:
        print("Track error:", e)
    time.sleep(15)
