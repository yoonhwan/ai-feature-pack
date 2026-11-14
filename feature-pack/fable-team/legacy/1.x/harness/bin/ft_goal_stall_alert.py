"""ft_goal_stall_alert — 골 재조정 멈춤 요청 (r1945 A · 골 4 ⑬ «골 안 끝내는 문제» · ft-stall-scan.sh 120초 주기 재사용 · 새 시계 0).
마지막 성공 회차가 FT_GOAL_READJUST_MAX_H(26)시간 전이면 planner `_master` 에 [결정] 요청 1통 — 회차 요청 또는 멈춘 골 닫기·재조정 판정.
★회차를 돌리지 않는다★(오빠 10-22 «자동 시계 0» · 요청 쪽지만 자동) · 키 = 마지막 성공 run(같은 회차당 1통 · state/goal-stall-alert.json).
★엄격 읽기(DA R2)★ — 이름순 최신 회차 파일을 직접 JSON 으로 읽고, 깨졌으면 로그 1줄 · 쪽지 0(state.read() 는 깨진 최신 파일을 건너뛰고 옛 OK 를 준다) · 최근 시도가 «판정 빠짐»(r1945 B)이면 같은 쪽지에 1줄로 묶는다 · 판독 실패(회차·명부) = 로그 1줄 · 쪽지 0 · --dry-run = 본문만 출력(쪽지·키 0).
"""
import json
import subprocess
import sys
from datetime import datetime

import ft_goal_readjust_state as st
from ft_goal_readjust import _planner


def _log(d, line: str) -> int:
    try:
        with open(d / "goal-stall-alert.log", "a", encoding="utf-8") as fh:
            fh.write(f"{datetime.now():%Y-%m-%d %H:%M:%S} {line}\n")
    except OSError as e:
        return print(f"WARN 골 멈춤 요청 log 못 씀 {d}: {e} · {line}", file=sys.stderr) or 0
    return 0


def main(argv: list[str]) -> int:
    rounds, files = st.state_dir(), st.round_files()
    if rounds is None or not files:   # 루트 못 푼(판정 불가)·회차 0 = 쪽지 0
        return 0 if rounds else print("판정 불가 골 멈춤 요청 — 데이터 루트를 못 풀었다(쪽지 0)", file=sys.stderr) or 0
    d = rounds.parent
    try:
        latest = json.loads(files[-1].read_text(encoding="utf-8"))
    except (OSError, ValueError) as e:
        latest = e
    if not isinstance(latest, dict):
        return _log(d, f"판정 불가 최신 회차 파일 판독 실패 {files[-1].name}: {str(latest)[:80]} (쪽지 0)")
    state = st.read()
    ok = state.get("last_ok")
    hours = st._hours((ok or {}).get("finished"), st._now(None))
    if ok is None or hours is None or hours <= st._max_h():
        return 0
    key_file, key = d / "goal-stall-alert.json", str(ok.get("run"))
    try:
        if json.loads(key_file.read_text(encoding="utf-8")).get("key") == key:
            return 0
    except (OSError, ValueError, AttributeError):
        pass
    miss = st.missing(state)
    body = "\n".join([f"[결정] 골 재조정 없음 {int(hours)}시간 — 회차 요청(`ft-goal-readjust.sh --request \"<출처>\"`) 또는 멈춘 골 닫기·재조정 판정",
                      "비가역: 아니오 — 이 쪽지는 요청만(자동 회차 0 · 오빠 10-22) · 판정 줄은 planner·오빠",
                      f"선례: 골 4 ⑬(r1945) · 같은 마지막 성공 회차당 1통(key={key})",
                      "선택지: ① 회차 요청 ② 판정 원장에 «골 <n>행 닫기|재조정|유지(사유)» 줄",
                      f"머리: {st.header(state)}"] + ([f"{st.MISS} {len(miss)}행 {miss}"] if miss else []))
    if "--dry-run" in argv:
        print(body)
        return 0
    seat = _planner()
    if seat is None:
        return _log(d, f"판정 불가 planner 명부·mbox 판독 실패 key={key} (쪽지 0)")
    try:
        done = subprocess.run(["bash", str(seat[1]), "send", seat[0], "ft-goal-stall-alert", body], capture_output=True, text=True, timeout=7, check=False)
    except (OSError, subprocess.SubprocessError) as e:
        return _log(d, f"송신 실패 key={key}: {e}")
    if done.returncode != 0:
        return _log(d, f"송신 실패 key={key} rc={done.returncode}: {done.stderr.strip()[:120]}")
    key_file.write_text(json.dumps({"key": key, "at": f"{datetime.now():%Y-%m-%d %H:%M:%S}"}) + "\n", encoding="utf-8")
    return _log(d, f"보냄 key={key} {int(hours)}시간 {done.stdout.strip()[:60]}")


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
