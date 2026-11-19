# mbox 상한 고르기 + 큐 포화 경보 (r2291 · r1466 -r2) · mbox_ops.send 가 부른다 · 200줄 규칙 분리(mbox_ops ≤200줄 · DA#32 조건 1).
"""★상한은 «역할» 로 고르고, 버림은 «받는 쪽 팀장» 이 듣는다★ (r2291)

실측(11-08 · arch#243): 상한이 역할과 무관하게 10이라 pi 팀장 좌석 큐가 늘 차 있었고, 버림은 발신자
stderr 와 drops.log 에만 남아 받는 좌석도 그 팀장도 몰랐다(하루 23건 · h 결과 5 · [HIL] 3).

  ring(to)  = 받는 좌석이 <명부 폴더>/seats-<팀>.json 의 `_master`·`_arch`·`_desk` 값(역할 키 비교)이면
              FT_MBOX_RING_LEAD(기본 30) · 아니면 FT_MBOX_RING(기본 10) · 명부 못 읽음 = FT_MBOX_RING(보수)
  after(…)  = send 가 잠금을 푼 뒤 1회 — pending < ring 이면 표식 삭제(닫는 사건) · 버림이 있고 표식이
              10분 안이 아니면 표식을 «먼저» 쓰고 팀 master(받는 이가 그 master 면 seats-harness.json `_master`)
              에게 발신 `ft-mbox-ring` 으로 «[큐 포화]» 1통. 경보 발신의 stdout 은 stderr 로 돌린다(QUEUED 줄 1개 유지).
"""
import contextlib, json, os, re, sys, time
from functools import lru_cache
from mbox_conf import MAX_PER_TO, RING_LEAD, role_key
import mbox_lineage

LEAD_KEYS = ("_master", "_arch", "_desk")
ALARM_FROM = "ft-mbox-ring"
ALARM_WIN = 600   # 같은 좌석 경보 10분 1회


def _team(name):
    m = re.match(r"^(?:byz|ft)-([a-z0-9]+)-", name or "")
    return m.group(1) if m else ""


@lru_cache(maxsize=32)
def _roster(team):
    """팀 명부 dict — 못 읽음·dict 아님 = {}(부르는 쪽이 보수 쪽으로 간다)."""
    d = os.path.dirname(mbox_lineage._seats_json()) or "."
    try:
        with open(os.path.join(d, "seats-%s.json" % team), encoding="utf-8") as fh:
            v = json.load(fh)
    except (OSError, ValueError):
        return {}
    return v if isinstance(v, dict) else {}


def _leads(team):
    doc = _roster(team) if team else {}
    return {role_key(v) for k in LEAD_KEYS if isinstance(v := doc.get(k), str) and v}


def ring(to):
    """받는 좌석(또는 역할 키) 의 상한."""
    return RING_LEAD if role_key(to) in _leads(_team(to)) else MAX_PER_TO


def boss(to):
    """경보 받을 이 — 팀 master · 받는 이가 그 master 거나 팀 master 없음 = 하네스 master · 둘 다 없으면 ""."""
    m = _roster(_team(to)).get("_master") if _team(to) else None
    if isinstance(m, str) and m and role_key(m) != role_key(to):
        return m
    h = _roster("harness").get("_master")
    return h if isinstance(h, str) else ""


def _marker(canon, to):
    sd = os.environ.get("FT_MBOX_STATE_DIR") or os.path.join(canon, "..", "state")
    return os.path.join(sd, "ring-full." + role_key(to))


def after(canon, to, pend, cap, dropped, oldest, send):
    """send 가 잠금을 푼 뒤 1회 — 표식 닫기 또는 «[큐 포화]» 1통. 실패는 stderr 1줄(본 send 결과는 그대로)."""
    mk = _marker(canon, to)
    if pend < cap:
        with contextlib.suppress(OSError):
            os.remove(mk)                 # 닫는 사건 — 큐가 상한 아래로 내려갔다
        return
    if not dropped:
        return
    with contextlib.suppress(OSError):
        if time.time() - os.path.getmtime(mk) < ALARM_WIN:
            return                        # 10분 안 재발 = 0통
    who = boss(to)
    if not who:
        sys.stderr.write("[큐 포화] 경보 받을 master 판정 불가 to=%s (명부 _master 없음)\n" % to)
        return
    body = "[큐 포화] to=%s pending=%d ring=%d 버림 %d oldest=#%s · drops.log 참조" % (to, pend, cap, dropped, oldest)
    try:
        os.makedirs(os.path.dirname(mk), exist_ok=True)
        with open(mk, "w", encoding="utf-8") as fh:   # 표식 «먼저» — 경보 send 가 다시 넘쳐도 되부름이 끝난다
            fh.write(body + "\n")
        with contextlib.redirect_stdout(sys.stderr):
            send(who, ALARM_FROM, body, force=True)
    except (Exception, SystemExit) as e:
        sys.stderr.write("[큐 포화] 경보 발신 실패 to=%s → %s: %s\n" % (to, who, e))
