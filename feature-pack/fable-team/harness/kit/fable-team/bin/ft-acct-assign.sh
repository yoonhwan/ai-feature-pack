#!/usr/bin/env bash
# ft-acct-assign.sh — «이 모델로 새 좌석을 열어도 되나» 를 계정 주간 한도로 한 줄 답한다 (r1217 · Issue #5345 ⑦)
#   ft-acct-assign.sh <model> [--seat-kind nano|role] [--json]
# 입력 = ft-acct-forecast.sh --json(같은 폴더 · 1회 · 모델 인자 없이 = 모든 계정 × 모든 창) + model-scope.tsv + model-fallback.tsv
#        + 정지 판정 = 같은 폴더 ft-acct-pause.sh status --check <P>/<M>(r1214 · 있을 때만 · 없으면 INFO 1줄로 건너뜀) · 쓰기 0
# 마감: 정지 확인 + 예측(잠금 대기 포함) 합쳐 70초(FT_ACCT_ASSIGN_BUDGET · 70 넘는 값은 70) · 넘으면 «불명(예측 시간 초과)»
# 판정 = 후보 계정 «전체» 기준(cliproxy fill-first 는 어느 계정을 고를지 모른다 — 일부만 여유 = 허용 0)
#   계정 가용 = 공통 창·모델 scope 창 소진 0(r1213 판정 그대로) · 여유 = 공통 주간 창과 모델 scope 창 둘 다 < FT_ACCT_ASSIGN_FULL(기본 90)
# 결과 1줄: 허용 <모델> · 대체 <모델> · 권고 <모델>(role) · 대체 없음 · 선택 불명(…) · 불명(<사유>) · 가용 0 · 풀림 HH:MM · 정지 중 · 풀림 HH:MM
# rc: 0 허용·대체·권고 · 1 사용법 · 3 그 밖(불명·가용 0·정지 중·대체 없음)
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
command -v python3 >/dev/null 2>&1 || { echo "불명(python3 없음)"; exit 3; }
FT_ACCT_ASSIGN_BIN="$HERE" exec python3 - "$@" <<'PY'
import datetime as dt
import json
import os
import re
import signal
import subprocess
import sys
import time

NA = "근거 없음"
BIN = os.environ.get("FT_ACCT_ASSIGN_BIN") or "."
FULL = float(os.environ.get("FT_ACCT_ASSIGN_FULL") or "90")
BUDGET = min(70.0, float(os.environ.get("FT_ACCT_ASSIGN_BUDGET") or "70"))  # 스냅샷 전체 마감(하드 룰 12 배치 상한)
START = time.monotonic()
KEYS = ["verdict", "model", "next", "reason", "available", "unknown", "margin", "reset_at", "rc"]
USAGE = "사용법: ft-acct-assign.sh <model> [--seat-kind nano|role] [--json]"
_now = os.environ.get("FT_ACCT_USAGE_NOW")
NOW = float(_now) if _now not in (None, "") else time.time()


def base_model(m):  # claude-x[1m] → claude-x
    return re.sub(r"\[[^\]]*\]$", "", m or "")


def label(model, scope):
    if scope != "-":
        return scope.lower()
    m = re.match(r"^claude-([a-z]+)", base_model(model))
    return m.group(1) if m else base_model(model)


def hhmm(t):
    return dt.datetime.fromtimestamp(t).strftime("%H:%M") if t is not None else NA


def epoch(v):
    if v is None or v == "" or isinstance(v, bool):
        return None
    if isinstance(v, (int, float)):
        return float(v)
    try:
        return dt.datetime.fromisoformat(str(v)).timestamp()
    except ValueError:
        return None


def read_tsv(name, ncol):
    out = {}
    with open(os.path.join(BIN, name), encoding="utf-8") as f:
        for line in f:
            if not line.strip() or line.startswith("#"):
                continue
            c = line.rstrip("\n").split("\t")
            if len(c) >= ncol:
                out[base_model(c[0])] = c[1:ncol]
    return out


def left():  # 마감까지 남은 초(호출마다 timeout 으로 준다)
    return max(0.5, BUDGET - (time.monotonic() - START))


def run_capped(cmd, tmo):  # 마감 = 프로세스 그룹째 끊는다(손자 curl 이 파이프를 잡아 마감이 늘어나지 않게)
    p = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
                         env=os.environ, start_new_session=True)
    try:
        out, _err = p.communicate(timeout=tmo)
    except subprocess.TimeoutExpired:
        os.killpg(p.pid, signal.SIGKILL)
        p.communicate()
        raise
    return p.returncode, out


def next_at(hm):  # "HH:MM" → 지금 뒤 가장 가까운 그 시각(epoch)
    h, m = (int(x) for x in hm.split(":"))
    t = dt.datetime.fromtimestamp(NOW).replace(hour=h, minute=m, second=0, microsecond=0).timestamp()
    return t if t >= NOW - 60 else t + 86400


def pause_check(prov, model):
    """r1214 도구에 묻는다 → ("none"|"paused"|"error"|"absent", 풀림 epoch, 사유)"""
    tool = os.path.join(BIN, "ft-acct-pause.sh")
    if not os.path.isfile(tool):
        return "absent", None, ""
    try:
        rc, out = run_capped(["bash", tool, "status", "--check", f"{prov}/{base_model(model)}"], min(7.0, left()))
    except subprocess.TimeoutExpired:
        return "error", None, "시간 초과"
    except OSError as e:
        return "error", None, f"실행 실패 {type(e).__name__}"
    first = next((x.strip() for x in (out or "").splitlines() if x.strip()), f"rc={rc}")
    if rc == 0:
        return "none", None, ""
    if rc != 3:
        return "error", None, first
    ends = [next_at(v) for v in re.findall(r"(?:until|release)=(\d\d:\d\d)", first)]
    return "paused", (min(ends) if ends else None), first


def scope_model(scope_s):  # 예측 도구 scope 직렬화 → 모델 이름(id 우선 · display_name) · 미상 = None
    try:
        s = json.loads(scope_s)
    except ValueError:
        return None
    if not isinstance(s, dict) or s.get("surface") not in (None, ""):
        return None
    m = s.get("model")
    if isinstance(m, dict):
        return m.get("id") or m.get("display_name") or None
    return m if isinstance(m, str) and m else None


def is_weekly(kind):
    return "week" in kind or "seven" in kind or kind == "7d"


def account(acc, scope):
    """계정 1개 → ("E", 풀림) 소진 · ("U", 사유) 불명 · ("A", 여유 bool, 모델%, 공통%)"""
    if acc.get("judge") == "판정 불가" or not acc.get("windows"):
        return ("U", "판정 불가")
    rel, seen, mp, cp = [], False, [], []
    for w in acc["windows"]:
        kind = str(w.get("kind") or "")
        if "scoped" in kind or w.get("scope"):
            name = scope_model(w.get("scope") or "")
            if name is None:
                return ("U", "scope 미상")
            if scope == "-" or name.lower() != scope.lower():
                continue
            seen = True
            rel.append(w)
            if isinstance(w.get("percent"), (int, float)):
                mp.append(w["percent"])
        else:
            rel.append(w)
            if is_weekly(kind) and isinstance(w.get("percent"), (int, float)):
                cp.append(w["percent"])
    if scope != "-" and not seen:
        return ("U", "scope 미상")
    ex = [w for w in rel if w.get("state") == "소진"]
    if ex:
        rs = [t for t in (epoch(w.get("resets_at")) for w in ex) if t is not None]
        return ("E", max(rs) if rs else None)
    if any(w.get("state") == "재조회 필요" or (w.get("state") == NA and w.get("why") == "값") for w in rel):
        return ("U", "판정 불가")
    return ("A", all(p < FULL for p in mp + cp), mp, cp)


def judge(pools, model, scopes):
    prov, scope = scopes[base_model(model)]
    pool = next((p for p in pools if p.get("pool") == prov), None)
    if pool is None:
        return {"err": f"예측 풀 없음 {prov}"}
    r = {"A": 0, "F": 0, "E": [], "U": {}, "mp": [], "cp": [], "label": label(model, scope)}
    for acc in pool.get("windows") or []:
        v = account(acc, scope)
        if v[0] == "E":
            r["E"].append(v[1])
        elif v[0] == "U":
            r["U"][v[1]] = r["U"].get(v[1], 0) + 1
        else:
            r["A"] += 1
            r["F"] += 1 if v[1] else 0
            r["mp"] += v[2]
            r["cp"] += v[3]
    r["ok"] = r["A"] > 0 and r["F"] == r["A"]
    return r


def span(xs):
    return f"{min(xs):g}~{max(xs):g}%" if xs else f"{NA}(창)"


def basis(r):
    nu = sum(r["U"].values())
    head = (f"{r['label']} 주간 후보 {r['A']}계정 {span(r['mp'])} · 공통 {span(r['cp'])}" if r["mp"]
            else f"{r['label']} 공통 주간 후보 {r['A']}계정 {span(r['cp'])}")
    return head + (f" · 불명 {nu}" if nu else "")


def share(r):  # 여유 k/N + 판정 못 한 계정 수(대체·권고 근거에도 보존)
    nu = sum(r["U"].values())
    return f"{r['F']}/{r['A']}" + (f"(불명 {nu})" if nu else "")


def forecast():
    try:
        rc, out = run_capped(["bash", os.path.join(BIN, "ft-acct-forecast.sh"), "--json"], left())
    except subprocess.TimeoutExpired:
        return None, "예측 시간 초과"
    except OSError as e:
        return None, f"예측 실행 실패 {type(e).__name__}"
    try:
        pools = json.loads(out)
    except ValueError:
        pools = None
    if rc not in (0, 3) or not isinstance(pools, list):
        line = next((x for x in (out or "").splitlines() if x.strip()), f"rc={rc}")
        return None, f"예측 {line.strip()}"
    return pools, ""


def decide(model, kind):
    try:
        scopes = read_tsv("model-scope.tsv", 3)
        table = {k: v[0] for k, v in read_tsv("model-fallback.tsv", 2).items()}
    except OSError as e:
        return {"verdict": "불명", "reason": f"표 읽기 실패 {type(e).__name__}"}
    if base_model(model) not in scopes:
        return {"verdict": "불명", "reason": f"scope 표 없음 {model}"}
    prov = scopes[base_model(model)][0]
    st, end, why = pause_check(prov, model)
    if st == "absent":
        print(f"INFO 정지 판정 건너뜀 — ft-acct-pause.sh 없음({BIN})", file=sys.stderr)
    elif st == "error":
        return {"verdict": "불명", "reason": f"정지 판정 불가 {why}"}
    elif st == "paused":
        return {"verdict": "정지 중", "reset_at": end, "reason": f"{prov}/{base_model(model)}"}
    pools, err = forecast()
    if pools is None:
        return {"verdict": "불명", "reason": err}
    r = judge(pools, model, scopes)
    if "err" in r:
        return {"verdict": "불명", "reason": r["err"]}
    cnt = {"available": r["A"], "unknown": sum(r["U"].values()), "margin": r["F"]}
    if r["ok"]:
        return dict(cnt, verdict="허용", reason=basis(r))
    if r["A"] == 0:
        if not r["U"] and r["E"]:
            rs = [t for t in r["E"] if t is not None]
            return dict(cnt, verdict="가용 0", reset_at=(min(rs) if rs else None), reason=f"소진 {len(r['E'])}")
        parts = [f"{k} 계정 {n}" for k, n in r["U"].items()] + ([f"소진 {len(r['E'])}"] if r["E"] else [])
        return dict(cnt, verdict="불명", reason=" · ".join(parts) or "계정 0")
    trail, seen, nxt = [f"{r['label']} {share(r)}"], {base_model(model)}, table.get(base_model(model), "")
    while nxt and base_model(nxt) not in seen:
        seen.add(base_model(nxt))
        if base_model(nxt) not in scopes:
            return dict(cnt, verdict="불명", reason=f"scope 표 없음 {base_model(nxt)}")
        if pause_check(scopes[base_model(nxt)][0], nxt)[0] in ("none", "absent"):
            n = judge(pools, nxt, scopes)
            if "err" not in n and n["ok"]:
                v = "권고" if kind == "role" else "대체"
                return dict(cnt, verdict=v, next=nxt,
                            reason=f"{r['label']} 여유 {share(r)} · {n['label']} 여유 {share(n)}")
            if "err" not in n:
                trail.append(f"{n['label']} {share(n)}")
        nxt = table.get(base_model(nxt), "")
    return dict(cnt, verdict="대체 없음", reason=f"선택 불명({' · '.join(trail)})")


def line(d, model):
    v = d["verdict"]
    if v in ("허용",):
        return f"허용 {model} · 근거: {d['reason']}"
    if v in ("대체", "권고"):
        return f"{v} {d['next']} · 근거: {d['reason']}"
    if v == "대체 없음":
        return f"대체 없음 · {d['reason']}"
    if v in ("가용 0", "정지 중"):
        return f"{v} · 풀림 {hhmm(d.get('reset_at'))} · 근거: {d['reason']}"
    return f"불명({d['reason']})"


def main(argv):
    pos = [a for a in argv if not a.startswith("--")]
    kind = "nano"
    if "--seat-kind" in argv:
        i = argv.index("--seat-kind")
        kind = argv[i + 1] if i + 1 < len(argv) else ""
        pos = [a for a in pos if a != kind]
    if len(pos) != 1 or kind not in ("nano", "role"):
        print(USAGE, file=sys.stderr)
        return 1
    d = decide(pos[0], kind)
    rc = 0 if d["verdict"] in ("허용", "대체", "권고") else 3
    if "--json" in argv:
        out = {k: d.get(k) for k in KEYS}
        out.update(model=pos[0], rc=rc,
                   reset_at=(dt.datetime.fromtimestamp(d["reset_at"]).isoformat(timespec="seconds")
                             if d.get("reset_at") else None))
        for k in KEYS:
            if out[k] is None:
                out[k] = f"{NA}({'해당 없음' if k in ('next', 'reset_at') else '판정 전'})"
        print(json.dumps(out, ensure_ascii=False))
    else:
        print(line(d, pos[0]))
    return rc


sys.exit(main(sys.argv[1:]))
PY
