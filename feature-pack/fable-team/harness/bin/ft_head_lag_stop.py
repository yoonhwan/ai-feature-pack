#!/usr/bin/env python3
"""ft_head_lag_stop.py — r1492: «이 팀, 지금 쪽지를 받아도 되나» 판정 한 곳(ft_head_lag.py 가 발신 «직전» 부른다 · 읽기 전용 · 모델 0 · 새 상태 0).
정지 표식의 정본을 재사용한다 — ⓐ `ft-penalty.sh check <팀>`(R320b · spawn 이 쓰는 판정기 · rc3 = 재개 전) ⓑ `ft_stall_detect.all_stop`(r1371 전팀 정지 표식 읽기 «한 곳»).
→ "penalty" · "all-stop" · ""(정지 아님) · None(판정 불가 — 부르는 쪽이 지금처럼 발신한다: 못 보면 조용히 안 보내는 쪽이 아니라 WARN + 발신이 안전).
env: FT_HEAD_LAG_PENALTY_SH(시험 — 판정기 자리 치환) · 자식에게는 root 를 FT_ROOT 로 넘긴다(리포 밖 cwd 에서도 같은 state 를 본다).
"""
import os
import subprocess
from pathlib import Path

from ft_head_lag_seats import warn

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


def gate(root, team, item, st, memo):
    """True = 보내도 된다 · False = 정지 팀(쪽지 0 + st 에 held 기록 → 재개 뒤 첫 실행에 1회 발신)."""
    if team not in memo:   # 한 실행 안에서 팀당 1회만 판정·1줄만 인쇄(INFO 줄 수 = 보류된 팀 수)
        kind = memo[team] = stopped_team(root, team)
        if kind is None:
            warn(f"정지 판정 불가 — 그대로 발신({team})")
        elif kind:
            print(f"INFO 정지 팀 {team} 알림 0({kind})")
    kind = memo[team]
    if not kind:   # "" = 정지 아님 · None = 판정 불가(안전 쪽 = 발신)
        return True
    st[item["real"]] = {"ts": 0, "n": st.get(item["real"], {}).get("n", 0), "held": kind}   # ts 0 = «아직 안 보냄»(재개 뒤 6시간 규칙에 걸리지 않게)
    return False
