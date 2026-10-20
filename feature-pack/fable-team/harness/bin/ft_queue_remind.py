"""ft_queue_remind.py — ft-queue.sh remind(r529): due 줄마다 그 팀 명부 _master 에 [재질문] 1통 · 자율 ON = 아침 묶음 줄만(r291)

ft_queue.py 가 run(kv, due 줄, 지금, 상태 폴더, out) 으로 부른다. 받는 이 = seats-<팀>.json 의 _master (seats.json = _master 이름의 byz-<팀>-)
· 팀 - 또는 명부 없는 팀 = planner _master. 같은 줄(번호·보여준 시각·tag) = min 분 안 다시 0(<상태>/queue-reask.json · 하루 지난 서명은 버림).
"""
import json
import os
import re
import subprocess
import sys
from datetime import datetime, timedelta
from pathlib import Path

FMT = "%Y-%m-%d %H:%M"


def masters(d, out):
    m = {}
    for f in sorted(Path(d).glob("seats*.json")):
        try:
            v = json.loads(f.read_text(encoding="utf-8")).get("_master")
        except (OSError, ValueError) as e:
            out(f"ERROR 명부 읽기 실패: {f}: {e}", 2)
        mt = re.match(r"seats-(.+)\.json$", f.name) or re.match(r"byz-([a-z0-9]+(?:-[a-z0-9]+)*?)-master", v or "")
        if isinstance(v, str) and mt:
            m.setdefault(mt.group(1), v)
    return m


def body(h):
    head = {"재확인": f"보류 재확인 시각 지남({h['recheck']})"}.get(h["tag"]) or (f"보여준 지 {h['age']}분" if h["age"] is not None else "아직 오빠께 안 보여줌")
    return (f"[재질문] {h['n']} · {head} · {h['q']} · desk [인터뷰 요청] 로 다시"
            f" · 물은 턴에 ft-queue.sh shown {h['n']} · 값 오면 ft-queue.sh take {h['n']} --value <값> --by <나> --verdict <N>")


def send(mbox, to, text):
    for _ in range(2):  # 7초 상한 + 재시도 1회(판정 666)
        try:
            if subprocess.run(["bash", mbox, "send", to, "ft-tick", text], capture_output=True, timeout=7).returncode == 0:
                return True
        except subprocess.TimeoutExpired:
            pass
    return False


def run(kv, hits, now, state, out):
    minutes = int(kv.get("min", "60"))
    m = masters(kv["rosters"], out)
    sf = Path(state) / "queue-reask.json"
    try:
        sent = json.loads(sf.read_text(encoding="utf-8")) if sf.exists() else {}
    except (OSError, ValueError) as e:
        out(f"ERROR 재질문 기록 읽기 실패: {sf}: {e}", 2)
    stat = {"sent": 0, "skip": 0, "err": 0}
    for h in hits:
        sig = f"{h['n']}|{h['shown']}|{h['tag']}"
        if sig in sent and now - datetime.strptime(sent[sig], FMT) < timedelta(minutes=minutes):
            stat["skip"] += 1
            continue
        to = m.get(h["team"]) or m.get("planner")
        if not to:
            print(f"ERROR {h['n']} 받을 master 없음(팀 {h['team']} · planner 명부 _master 없음)", file=sys.stderr)
            stat["err"] += 1
            continue
        if os.environ.get("FT_QUEUE_MODE") == "on":
            try:
                with open(Path(state) / "queue-reask-morning.md", "a", encoding="utf-8") as f:
                    f.write(f"- {now.strftime(FMT)} {body(h)} → {to}\n")
            except OSError as e:
                out(f"ERROR 아침 묶음 쓰기 실패: {e}", 5)
            via = "morning"
        elif send(kv["mbox"], to, body(h)):
            via = "mbox"
        else:
            print(f"ERROR {h['n']} mbox send 실패 to={to}", file=sys.stderr)
            stat["err"] += 1
            continue
        sent[sig] = now.strftime(FMT)
        stat["sent"] += 1
        print(f"REMIND {h['n']} to={to} via={via} tag={h['tag']}")
    keep = {k: v for k, v in sent.items() if now - datetime.strptime(v, FMT) < timedelta(days=1)}
    try:
        Path(state).mkdir(parents=True, exist_ok=True)
        sf.write_text(json.dumps(keep, ensure_ascii=False), encoding="utf-8")
    except OSError as e:
        out(f"ERROR 재질문 기록 쓰기 실패: {sf}: {e}", 5)
    out(f"QUEUE-REMIND sent={stat['sent']} skip={stat['skip']} err={stat['err']}", 1 if stat["err"] else 0)
