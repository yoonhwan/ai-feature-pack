#!/usr/bin/env python3
"""ft_head_lag_stop.py — r1492: «이 팀, 지금 쪽지를 받아도 되나» 판정 한 곳(ft_head_lag.py 가 발신 «직전» 부른다 · 읽기 전용 · 모델 0 · 새 상태 0).
정지 표식의 정본을 재사용한다 — ⓐ `ft-penalty.sh check <팀>`(R320b · spawn 이 쓰는 판정기 · rc3 = 재개 전) ⓑ `ft_stall_detect.all_stop`(r1371 전팀 정지 표식 읽기 «한 곳»).
→ "penalty" · "all-stop" · ""(정지 아님) · None(판정 불가 — 부르는 쪽이 지금처럼 발신한다: 못 보면 조용히 안 보내는 쪽이 아니라 WARN + 발신이 안전).
보류는 «받는이(master)별»로 남긴다(DA #276249 R1) — 같은 워크트리에 앉은 활성 팀의 발신 성공이 정지 팀의 held 를 지우면 그 팀은 재개 뒤에도 알림을 못 받는다.
head-lag.json 기록 꼴(워크트리 1칸) = {"seq","ts","n"} + r1492 {"acked":[이미 받은 master…], "held":{master: 사유}} — R836 의 n/ts 규칙은 그대로.
env: FT_HEAD_LAG_PENALTY_SH(시험 — 판정기 자리 치환) · 자식에게는 root 를 FT_ROOT 로 넘긴다(리포 밖 cwd 에서도 같은 state 를 본다).
"""
import os
import subprocess
from pathlib import Path

from ft_head_lag_seats import master_of, team_of, warn

HERE = os.path.dirname(os.path.abspath(__file__))
PENALTY_S = 25   # 로컬 하네스 상한(하드 룰 12 · 외부 호출 0)


def stopped_team(root, team):
    """팀이 지금 정지 중인가 — "penalty"(재개 전) | "all-stop"(전팀 정지) | "" | None(판정 불가)."""
    pen = os.environ.get("FT_HEAD_LAG_PENALTY_SH") or os.path.join(HERE, "ft-penalty.sh")
    try:
        r = subprocess.run(["bash", pen, "check", team], capture_output=True, text=True, timeout=PENALTY_S, env=dict(os.environ, FT_ROOT=root))
        if r.returncode == 3:
            return "penalty"
        if r.returncode:
            raise OSError(f"penalty check rc={r.returncode}")
        from ft_stall_detect import all_stop   # r1371 표식 읽기 «한 곳»(ALL_STOP.json 1개 · 원장은 안 본다)
        kind, _since, why = all_stop(Path(root))
    except (OSError, subprocess.SubprocessError, ImportError) as e:
        warn(f"정지 판정 불가 {team}: {e}")
        return None
    if kind == "on":
        return "all-stop"
    if kind == "off":
        return ""
    warn(f"정지 판정 불가 {team}: all-stop {why}")
    return None


def gate(root, team, m, item, st, memo):
    """True = 보내도 된다 · False = 정지 팀(그 받는이에게 쪽지 0 + held[m] 기록 → 재개 뒤 그 받는이에게 1회)."""
    if team not in memo:   # 한 실행 안에서 팀당 1회만 판정·1줄만 인쇄(INFO 줄 수 = 보류된 팀 수)
        kind = memo[team] = stopped_team(root, team)
        if kind is None:
            warn(f"정지 판정 불가 — 그대로 발신({team})")
        elif kind:
            print(f"INFO 정지 팀 {team} 알림 0({kind})")
    kind = memo[team]
    if not kind:   # "" = 정지 아님 · None = 판정 불가(안전 쪽 = 발신)
        return True
    rec = st.setdefault(item["real"], {"ts": 0, "n": 0})
    rec["held"] = {**(rec.get("held") or {}), m: kind}   # 받는이별 보류 · ts 0 = «아직 안 보냄»(재개 뒤 6시간 규칙에 걸리지 않게)
    return False


def plan(root, stale, st, by, minutes, now, remind):
    """→ {master: [뒤처진 워크트리…]} — R836(워크트리 1회·6시간 재알림) · 문턱 · r1492(팀 단위 정지 보류)를 한 자리에서 판정."""
    groups, memo = {}, {}
    for s in stale:
        rec = st.get(s["real"]) or {}
        if s["secs"] < minutes * 60 or (rec.get("n", 0) >= 2 and not rec.get("held")):   # 보류가 남았으면 재개 판정은 팀 단위로
            continue
        for team in sorted({t for t in map(team_of, by[s["real"]]) if t}):
            m = master_of(root, team)
            got = (m in (rec.get("acked") or [])) if "acked" in rec else True   # 옛 기록(acked 없음) = 워크트리 단위 6시간 규칙 그대로
            if not m or (got and now - rec.get("ts", 0) < remind):
                continue
            if gate(root, team, m, s, st, memo):
                groups.setdefault(m, []).append(s)
    return groups


def record(rec, seq, masters, now):
    """발신 성공 1건 반영 — 이번에 보낸 받는이의 held 만 지운다(같은 워크트리의 다른 팀 보류 보존 · R836 n/ts 규칙 유지)."""
    held = {k: v for k, v in (rec.get("held") or {}).items() if k not in masters}
    out = {"seq": seq, "ts": now, "n": rec.get("n", 0) + 1, "acked": sorted(set(rec.get("acked") or []) | masters)}
    return dict(out, held=held) if held else out
