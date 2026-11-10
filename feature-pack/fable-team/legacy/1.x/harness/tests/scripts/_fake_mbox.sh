#!/usr/bin/env bash
# 가짜 mbox.sh — send/relay 를 큐(mailbox.jsonl)·사본 로그(mailbox.log.jsonl)에 JSON 행으로 쌓는다. 환경변수로 장애 주입.
# FAKE_NO_QUEUED=1 rc 0 인데 QUEUED 줄 없음(결과 불명) · FAKE_LOGFAIL=1 사본 로그 미기록 · FAKE_FAIL_TO=<수신자> 그 수신자 호출 실패 · FAKE_PENDING=<n> 보고할 큐 길이
exec python3 - "$@" <<'PY'
import json, os, sys
cmd, to, frm = sys.argv[1], sys.argv[2], sys.argv[3]
body = sys.argv[4] if cmd == "send" else open(sys.argv[4], encoding="utf-8").read() + "\n" + sys.argv[5]
d = os.path.dirname(os.path.abspath(os.environ["FAKE_MBOX"]))
if os.environ.get("FAKE_FAIL_TO") == to:
    print("QUEUE_FULL", file=sys.stderr); sys.exit(3)
if os.environ.get("FAKE_NO_QUEUED"):
    sys.exit(0)
q = os.path.join(d, "mailbox.jsonl")
seq = sum(1 for _ in open(q)) + 1 if os.path.exists(q) else 1
row = json.dumps({"seq": seq, "to": to, "from": frm, "body": body}, ensure_ascii=False) + "\n"
open(q, "a", encoding="utf-8").write(row)
if not os.environ.get("FAKE_LOGFAIL"):
    open(os.path.join(d, "mailbox.log.jsonl"), "a", encoding="utf-8").write(row)
print(f"QUEUED seq={seq} to={to} pending={os.environ.get('FAKE_PENDING', '1')}")
PY
