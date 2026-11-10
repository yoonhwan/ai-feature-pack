#!/usr/bin/env python3
# pyright: basic
"""ft_trigger_fetch.py — r1285 Logging API entries:list 한 쪽 조회. 요청 JSON(filter·orderBy·pageSize·pageToken)을 stdin 으로 받아
응답 JSON 을 stdout 에 그대로 낸다. 실패 = stderr 한 줄 + rc≠0 (조용한 빈 응답 0). 토큰 = gcloud auth print-access-token 1회.
env FT_TRIGGER_PROJECT(기본 byz-agents-484214 · prod-dev) · FT_TRIGGER_CALL_SEC(7). 시험은 FT_TRIGGER_LOG_CMD 로 이 파일을 스텁으로 바꾼다."""
import json
import os
import subprocess
import sys
import urllib.error
import urllib.request

URL = "https://logging.googleapis.com/v2/entries:list"


def main() -> int:
    sec = float(os.environ.get("FT_TRIGGER_CALL_SEC") or 7)
    req = json.load(sys.stdin)
    req.setdefault("resourceNames", ["projects/" + (os.environ.get("FT_TRIGGER_PROJECT") or "byz-agents-484214")])
    p = subprocess.run(["gcloud", "auth", "print-access-token"], capture_output=True, text=True, timeout=sec)
    if p.returncode != 0 or not p.stdout.strip():
        print(f"gcloud token rc={p.returncode} {p.stderr.strip()[:120]}", file=sys.stderr)
        return 2
    r = urllib.request.Request(URL, data=json.dumps(req).encode(), headers={"Authorization": "Bearer " + p.stdout.strip(), "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(r, timeout=sec) as resp:
            sys.stdout.write(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        print(f"entries:list HTTP {e.code} {e.read().decode('utf-8', 'replace')[:120]}", file=sys.stderr)
        return 3
    return 0


if __name__ == "__main__":
    sys.exit(main())
