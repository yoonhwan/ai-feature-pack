"""ft_key_rotate_journal.py — 값 없는 시도 기록(journal) (R206c). 줄마다 시도·단계·결과·대상 ID·전/후 버전·지문 접두만 — 값·해시 원문 0.
파일: <상태 폴더>/<묶음>.jsonl (600 · append-only). 시험 훅: FT_KEY_ROTATE_STATE."""

import hashlib
import json
import os
import re
import time

OK, NOT_RUN, UNKNOWN, DEAD_EVID, UNCONFIRMED = "완료", "미실행", "불명", "이미 폐기(증거)", "미확인"
CLOSED = (OK, DEAD_EVID)
_SAFE = re.compile(r"^[\w .:=/()\-·,>—가-힣]{0,160}$")
_NAME = re.compile(r"^[a-z0-9][a-z0-9-]{0,39}$")


def state_dir():
    d = os.environ.get("FT_KEY_ROTATE_STATE") or os.path.expanduser("~/.local/state/ft-key-rotate")
    os.makedirs(d, mode=0o700, exist_ok=True)
    return d


def path(bundle):
    if not _NAME.match(bundle):
        raise ValueError("묶음 이름 형식 아님: %s" % bundle)
    return os.path.join(state_dir(), bundle + ".jsonl")


def fp(value):
    """대조 전용 짧은 지문(sha256 앞 6자). 값 복원 불가."""
    return hashlib.sha256(value.encode("utf-8")).hexdigest()[:6]


def now():
    return time.strftime("%Y%m%dT%H%M%S")


def append(bundle, **rec):
    for k, v in rec.items():
        if v is not None and not _SAFE.match(str(v)):
            raise ValueError("journal 필드 %s 에 허용 밖 글자" % k)
    rec["t"] = now()
    line = json.dumps({k: v for k, v in rec.items() if v is not None}, ensure_ascii=False) + "\n"
    fd = os.open(path(bundle), os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600)
    try:
        os.fchmod(fd, 0o600)
        os.write(fd, line.encode("utf-8"))
        os.fsync(fd)
    finally:
        os.close(fd)


def read(bundle):
    p = path(bundle)
    if not os.path.exists(p):
        return []
    out = []
    with open(p, encoding="utf-8") as f:
        for n, line in enumerate(f, 1):
            try:
                out.append(json.loads(line))
            except ValueError:
                raise ValueError("journal 손상 %s %d줄 — 조용히 건너뛰지 않음" % (bundle, n))
    return out


def current(bundle):
    """(시도 번호, 마지막 시도의 기록들) — 기록 없으면 (0, [])."""
    es = read(bundle)
    if not es:
        return 0, []
    att = es[-1]["att"]
    return att, [e for e in es if e["att"] == att]


def bundles():
    return sorted(f[:-6] for f in os.listdir(state_dir()) if f.endswith(".jsonl"))


def last(es, step, phase="result"):
    for e in reversed(es):
        if e.get("step") == step and e["phase"] == phase:
            return e
    return None


def step_state(es, step):
    """단계의 최신 기록 — 마지막이 intent 뿐이면(결과 전에 프로세스가 죽음) 결과 «불명» 으로 본다."""
    for e in reversed(es):
        if e.get("step") == step and e["phase"] in ("intent", "result"):
            return e if e["phase"] == "result" else dict(e, phase="result", res=UNKNOWN)
    return None


def summarize(es):
    """-> 상태 문자열. 진행/불명(단계 n)/중단(…)/완료/미확인(…)/없음 — 단계 결과가 상태를 정한다. 결과 없는 intent 는 불명."""
    status, pend = "없음", []
    for e in es:
        s, ph = e.get("step"), e["phase"]
        if ph == "intent":
            status = "진행(단계 %s)" % s
            pend.append(s)
        elif ph == "result":
            r = e["res"]
            pend = [x for x in pend if x != s]
            status = (
                "불명(단계 %s)" % s
                if r == UNKNOWN
                else "중단(단계 %s)" % s
                if r == NOT_RUN
                else "진행(단계 %s 뒤)" % s
            )
        elif ph == "resume":
            status = "진행(재개)"
        elif ph == "end":
            status = e["res"]
        elif ph == "abandon":
            status = "중단(%s)" % e.get("detail", "")
    return "불명(단계 %s)" % pend[-1] if pend and status.startswith("진행") else status


def is_open(status):
    return status.split("(")[0] in ("진행", "불명", "중단")


def ops_touched(es):
    """운영 반영 단계가 완료·불명이면 True — 불명(결과 없는 intent 포함)은 반영됐을 수 있어 «반영»으로 센다."""
    steps = {e["step"] for e in es if e["phase"] in ("intent", "result") and e.get("ops")}
    return any(step_state(es, x)["res"] in (OK, UNKNOWN) for x in steps)


def blocks_others(es, locals_done):
    """다른 묶음 열기를 막는 열린 묶음 — 운영 반영(완료·불명)이 있거나 불명·중단이거나 묶음 안 필드가 덜 끝난 것. 로컬만 바뀐 평범한 진행은 막지 않는다."""
    st = summarize(es)
    return is_open(st) and not safe_abandon(es) and (ops_touched(es) or not st.startswith("진행") or not locals_done)


def safe_abandon(es):
    return bool(es) and es[-1]["phase"] == "abandon" and not ops_touched(es)


def abandon_table(es):
    """남은 복사본 표 — 어느 곳에 새 값/옛 값이 있는지(ID·버전·백업 파일 이름만)."""
    rows = []
    for e in (step_state(es, x) for x in dict.fromkeys(e["step"] for e in es if e["phase"] in ("intent", "result"))):
        if e["res"] not in (OK, UNKNOWN):
            continue
        s = e["step"]
        if s.startswith("local:"):
            rows.append("COPY %s 새 값=지금 활성 줄 · 옛 값=%s" % (s, e.get("detail") or "백업 파일"))
        elif e.get("ops") or e.get("id") or e.get("after"):
            rows.append("COPY %s 새=id=%s ver=%s res=%s" % (s, e.get("id", "-"), e.get("after", "-"), e["res"]))
    return rows or ["COPY (남은 복사본 기록 없음)"]


def status_lines():
    out = []
    for b in bundles():
        es = current(b)[1]
        steps = {}
        for e in es:
            if e["phase"] == "result":
                steps[e["step"]] = e["res"]
        out.append("BUNDLE %-24s %s steps=%s" % (b, summarize(es), ",".join("%s:%s" % kv for kv in steps.items()) or "-"))
    return out
