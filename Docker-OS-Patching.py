import os
import subprocess
import time
import json
import requests
import yaml

BASE_DIR = "/docker"
SLACK_WEBHOOK_URL = "https://hooks.slack.com/services/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"

def find_compose_files(base_dir):
    for root, dirs, files in os.walk(base_dir):
        if "docker-compose.yml" in files:
            yield os.path.join(root, "docker-compose.yml")

def run_cmd(cmd, cwd):
    try:
        subprocess.run(cmd, cwd=cwd, shell=True, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        return True, ""
    except subprocess.CalledProcessError as e:
        return False, e.stderr.decode()

def check_health(cwd):
    try:
        ps_output = subprocess.check_output("docker inspect --format='{{json .State}}' $(docker compose ps -q)", cwd=cwd, shell=True)
        states = ps_output.decode().strip().split('/n')
        for state_json in states:
            state = json.loads(state_json)
            if state.get("Health") and state["Health"].get("Status") != "healthy":
                return False
            if state.get("Status") != "running":
                return False
        return True
    except Exception as e:
        print(f"Health check failed: {e}")
        return False

def notify_slack(summary):
    payload = {"text": summary}
    requests.post(SLACK_WEBHOOK_URL, json=payload)

def check_if_latest(compose_file):
    try:
        with open(compose_file, 'r') as f:
            compose_data = yaml.safe_load(f)
        images = []
        services = compose_data.get('services', {})
        for svc in services.values():
            image = svc.get('image', '')
            if image and not image.endswith(':latest'):
                images.append(image)
        return images
    except Exception:
        return ["Could not parse"]

def main():
    print("Starting monthly Docker and OS update...")
    os_update = {
        "apt_update": False,
        "apt_upgrade": False,
        "error": ""
    }
    report = []

    for compose_file in find_compose_files(BASE_DIR):
        print(f"\nProcessing: {compose_file}")
        folder = os.path.dirname(compose_file)
        not_latest_images = check_if_latest(compose_file)

        status = {
            "folder": folder,
            "pull": False,
            "down": False,
            "up": False,
            "healthy": False,
            "not_latest": not_latest_images,
            "error": ""
        }

        print("Running: docker compose pull")
        ok, err = run_cmd("docker compose pull", folder)
        status["pull"] = ok
        if not ok:
            status["error"] = f"Pull failed: {err}"
            report.append(status)
            continue

        print("Running: docker compose down")
        ok, err = run_cmd("docker compose down", folder)
        status["down"] = ok
        if not ok:
            status["error"] = f"Down failed: {err}"
            report.append(status)
            continue

        print("Running: docker compose up -d")
        ok, err = run_cmd("docker compose up -d", folder)
        status["up"] = ok
        if not ok:
            status["error"] = f"Up failed: {err}"
            report.append(status)
            continue

        print("Waiting 10 seconds before health check...")
        time.sleep(10)
        status["healthy"] = check_health(folder)
        print(f"Health status: {status['healthy']}")
        report.append(status)

    lines = [
        f"{r['folder']} - Pull: {r['pull']} | Down: {r['down']} | Up: {r['up']} | Healthy: {r['healthy']} | Not Latest: {', '.join(r['not_latest']) if r['not_latest'] else 'All latest'} | Error: {r['error']}"
        for r in report
    ]

    print("\nRunning: apt-get update -y --allow-releaseinfo-change")
    ok, err = run_cmd("apt-get update -y", "/")
    os_update["apt_update"] = ok
    if not ok:
        os_update["error"] += f"APT update failed: {err}\n"

    print("Running: apt-get upgrade -y")
    ok, err = run_cmd("apt-get upgrade -y", "/")
    os_update["apt_upgrade"] = ok
    if not ok:
        os_update["error"] += f"APT upgrade failed: {err}"

    lines.append("")
    lines.append(f"OS Update - apt update: {os_update['apt_update']} | apt upgrade: {os_update['apt_upgrade']} | Error: {os_update['error']}")

    print("Running: docker image prune -f")
    run_cmd("docker image prune -f", "/")

    print("Sending summary to Slack...")
    import socket
    hostname = socket.gethostname()
    header = f"Update Summary for Host: {hostname}"
    notify_slack(header + "".join(lines))

if __name__ == "__main__":
    main()
