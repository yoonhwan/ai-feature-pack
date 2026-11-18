"""카드 r2264 — keeper 가 «원장 done ∧ 카드 완성 폴더»(wide_landed done-card-완성)로 닫는 좌석도 턴이 닫혔으면 무활동 300초 문턱을 쓴다.

계약 C1~C3 · 반례 ①~⑦ · ③b · 구현 DA ⓕ(착지 참 · 열린 턴 · 3700초 = WORKING landed-wait).
대역 = test_done_seat_short_idle.py 의 r1812 keeper_world 세계(가짜 tmux · 가짜 ps · 임시 pi jsonl · 주입 시계 · sleep 0 · 네트워크 0).
기준판(팩 origin/main 411ba88e) Red = ① 하나 — 나머지는 지킴(기준판과 같은 결과).
"""
import importlib.util
from pathlib import Path

import pytest

_spec = importlib.util.spec_from_file_location("short_idle_r2264", str(Path(__file__).with_name("test_done_seat_short_idle.py")))
si = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(si)
kw, has, two, nano, mail, MASTER = si.kw, si.has, si.two, si.nano, si.mail, si.MASTER


def old_line(w, work, stage="완성"):
    """옛 착지 줄 — 착지 sha = BYZ main 커밋(뒤에 여는 nano 의 base_sha 조상) → landing() = «옛 착지 줄(attempt 전)»."""
    w.card(work, sha=w.commit("byz", {}, "main"), stage=stage)


def done_card(w, work, age=400, turn="stop"):
    """r1812 꼴 — 원장 done · 카드 indices/완성 · 옛 착지 줄 · 턴 = turn · 무활동 age 초."""
    old_line(w, work)
    return nano(w, work, done=True, age=age, turn=turn)


def shut(w, lines, work):
    return has(lines, "CLOSED-ENDING harness %s" % work, "done-card-완성") and len(w.tmux("kill-session")) == 1


def c1(w):   # ① done · 완성 · 옛 착지 줄 · stop · 400초 · CPU idle → kill · CLOSED-ENDING landed done-card-완성(기준판 Red = WORKING landed-wait)
    done_card(w, "r9701")
    lines = two(w)
    assert shut(w, lines, "r9701"), lines


def c2(w):   # ② 같은 세계 · 200초 → WORKING landed-wait(문턱 아래)
    done_card(w, "r9702", age=200)
    lines = two(w)
    assert has(lines, "WORKING harness r9702", "landed-wait") and not w.tmux("kill-session"), lines


def c3(w):   # ③ 같은 세계 · 400초 · 마지막 줄 toolUse → WORKING landed-wait(열린 턴 = PARK_IDLE 문턱 아래)
    done_card(w, "r9703", turn="toolUse")
    lines = two(w)
    assert has(lines, "WORKING harness r9703", "landed-wait") and not w.tmux("kill-session"), lines


def c3b(w):   # ③b 같은 세계 · 3700초 · 마지막 줄 toolUse → UNKNOWN waiting-input(열린 턴 = PARK_IDLE 길 · 알림 유지)
    done_card(w, "r9713", age=3700, turn="toolUse")
    lines = two(w)
    assert has(lines, "UNKNOWN harness r9713", "waiting-input") and not w.tmux("kill-session"), lines


def c4(w):   # ④ 같은 세계 · 400초 · 막는 미읽음 1 → UNKNOWN mail-pending(A1 짧은 문턱 미읽음 판독)
    holder = done_card(w, "r9704")
    mail(w, holder, [(3301, 10, MASTER, "[긴급] r9704 확인 부탁드립니다")])
    lines = two(w)
    assert has(lines, "UNKNOWN harness r9704", "mail-pending") and not w.tmux("kill-session"), lines


def c5(w):   # ⑤ wide «cherry-all-in-base»(done 0 · 상태 머리 «중단:» = 끝 → close 길) · 400초 → WORKING(PARK_IDLE 그대로)
    sha, body = w.commit("byz", {}, "main"), "# 인덱스: r9705\n- 착지: %s\n\n## 상태\n- 중단: 시험\n"
    for ref in ("main", "ops/main-base"):
        w.commit("byz", {"design/harness/indices/진행/r9705-x.md": body % sha}, ref)
    nano(w, "r9705", age=400)
    w.commit("byz", {}, "main")   # 부모를 바꿔 가지 커밋과 sha 가 겹치지 않게(같은 초 · 같은 tree = 같은 sha)
    w.commit("byz", {"x.txt": "r9705"}, "main")   # 가지 커밋과 같은 patch = git cherry «-»
    kw._git(w.tmp / "wt" / "r9705", "fetch", "-q", "origin")
    lines = two(w)
    assert has(lines, "WORKING harness r9705") and not w.tmux("kill-session"), lines
    assert not has(lines, "cherry-all-in-base"), lines


def c6(w):   # ⑥ 착지 줄 참 · stop · 400초 → 닫힘(DONE_IDLE 기존 길)
    si.landed(w, "r9706", age=400)
    lines = two(w)
    assert has(lines, "COMPLETED harness r9706") and len(w.tmux("kill-session")) == 1, lines


def c6f(w):   # 구현 DA ⓕ 착지 참 · toolUse · 3700초 → WORKING landed-wait(착지 참 길 식 그대로)
    si.landed(w, "r9716", age=3700, turn="toolUse")
    lines = two(w)
    assert has(lines, "WORKING harness r9716", "landed-wait") and not w.tmux("kill-session"), lines


def c7(w):   # ⑦ 착지 0 · wide 빈값 · 400초 → WORKING(PARK_IDLE)
    si.park_ready(w, "r9707", age=400)
    lines = two(w)
    assert has(lines, "WORKING harness r9707") and not w.tmux("kill-session") and w.kinds("parked") == 0, lines


CASES = {"①": c1, "②": c2, "③": c3, "③b": c3b, "④": c4, "⑤": c5, "⑥": c6, "ⓕ": c6f, "⑦": c7}


@pytest.mark.parametrize("name", list(CASES))
def test_case(name, tmp_path, monkeypatch):
    CASES[name](si.world(tmp_path, monkeypatch))
