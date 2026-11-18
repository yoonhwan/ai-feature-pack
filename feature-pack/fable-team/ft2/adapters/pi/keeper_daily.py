"""r2238 ft2 keeper — 하루 정리 생존 검사(O2~O4 · 카드 r2238-disk-regen-source-stop).

하루 정리(ft-disk-alarm.sh → ft-tmp-sweep · ft-accum-sweep)는 resource-watch 주기 작업이 부른다. 그 작업이 내려가면 정리도 멈추고
알리는 곳이 없었다. keeper 바퀴 끝(report 뒤)에서 check(k) 1회:
  · 하루 1회 표식 state.daily_sweep = 오늘이면 검사 0(O4) · 아니면 state/disk-alarm.log stat 1회
  · 표식은 «줄 0 판 · 판독 실패 판 · notify 가 True(또는 그날 지문 있음)» 에서만 쓴다 — notify False(한 바퀴 3통 상한 · 남은 몫 7초 아래 미룸)
    = 표식 0 → 다음 바퀴 다시 · 판정 불가 줄은 state.daily_sweep_line(줄 씀)으로 하루 1줄(DA#20 #334646 ⓑ)
  · 나이 ≥ FT_KEEPER_DAILY_STALE_D(기본 2)일 · 파일 없음 = «판정 불가 하루 정리 멈춤 <N>일(state/disk-alarm.log · 마지막 …)» 1줄
    + harness 쪽지 [긴급] 1통(keeper notify 길 = 받는 곳 차례 · 그날 지문 · 한 바퀴 3통 상한 · 상한 밖이면 다음 바퀴)
  · stat 실패 = «판정 불가 하루 정리 판독 실패» 1줄 · 쪽지 0
O3 읽기만 — stat 1회뿐(du·walk 0) · launchctl·정리 도구 부름 0 · 나이 < 문턱 = 로그·쪽지 0.
"""
import datetime
import os

STALE_D, DAY_S, TEAM = 2, 86400, "harness"
LOG = "state/disk-alarm.log"


def threshold(env):
    """FT_KEEPER_DAILY_STALE_D(일 · 양의 정수) · 비었거나 못 읽음 = 기본 2."""
    try:
        n = int(env.get("FT_KEEPER_DAILY_STALE_D") or STALE_D)
    except ValueError:
        return STALE_D
    return n if n > 0 else STALE_D


def check(k, stat=os.stat):
    """keeper 바퀴 끝 1회 — 반환 None."""
    day = k.stamp()[:10]
    if k.state.get("daily_sweep") == day:
        return None
    try:
        mtime = stat(os.path.join(k.root, ".fable-team", LOG)).st_mtime
    except FileNotFoundError:
        mtime = None
    except OSError:
        k.state["daily_sweep"] = day
        return k.log("판정 불가", text="하루 정리 판독 실패")
    age = None if mtime is None else int((k.now() - mtime) // DAY_S)
    if age is not None and age < threshold(k.env):
        k.state["daily_sweep"] = day
        return None
    last = "없음" if mtime is None else datetime.datetime.fromtimestamp(mtime).strftime("%Y-%m-%d %H:%M")
    text = "하루 정리 멈춤 %s일(%s · 마지막 %s)" % ("-" if age is None else age, LOG, last)
    if k.state.get("daily_sweep_line") != day:
        k.state["daily_sweep_line"] = day
        k.log("판정 불가", text=text)
    key = "daily-sweep|%s" % day
    if k.notify(TEAM, key, "[긴급] %s · 다음 수 = resource-watch 적재 확인(launchctl list com.byz.ft-resource-watch)" % text) or k.blocked(key):
        k.state["daily_sweep"] = day
    return None
