"""r2275 keeper 카드 전이 증거 감시 — 반례 ①~⑧(카드 r2275-card-transition-evidence-watch · 사전 DA#28 APPROVE-DESIGN).
r1812 대역(World · 임시 BYZ·팩 리포 · 가짜 mbox) · 시계 = World.t(카드 시각은 실제 커밋 시각 기준으로 앞당김) · 실 리포·실 mbox 0 · sleep 0.
감시 파일이 없으면(기준판) keeper 바퀴 1회로 대신 잰다 = 알림 0(Red) · R2275_FT2=<ft2 폴더> 로 대상 바꿈(기준판 대조 · 변이 사본).
"""
import datetime
import importlib.util
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path

import pytest

kw = importlib.util.module_from_spec(importlib.util.spec_from_file_location("keeper_world_r2275", str(Path(__file__).with_name("keeper_world_r1812.py"))))
kw.__spec__.loader.exec_module(kw)
FT2 = Path(os.environ.get("R2275_FT2") or kw.FT2)
TW, HOUR, NOW0 = FT2 / "adapters" / "pi" / "transition_watch.py", 3600, datetime.datetime.fromisoformat(kw.NOW).timestamp()   # 장부 done 시각 = FT_NOW
DONE = "\n- 2026-11-18T16:04:00 · ft2 card_stage 대기→완성(ft2 complete)\n"


def world(tmp, mp, ft2=FT2):   # 대역 1벌 + 감시 모듈(없으면 None = 기준판)
    (tmp / "empty").mkdir(parents=True)
    w = kw.World(tmp, mp, ft2=ft2)
    tw = ft2 / "adapters" / "pi" / "transition_watch.py"
    w.T = kw._mod(tw, "tw_%d" % id(w)) if tw.exists() else None
    return w
def card(w, stage, stem, body="", files=None):   # 카드 1장(또는 여러 장) = ops/main-base 커밋 1개
    files = files or {"design/harness/indices/%s/%s.md" % (stage, stem): "# 인덱스: %s\n- 상태: %s\n%s" % (stem, stage, body)}
    return w.commit("byz", files, "ops/main-base")
def pack(w, doc):   # 팩 커밋 1개(doc = 카드 문서만) → 임시 팩 clone 에도 받음
    sha = w.commit("pack", {"design/harness/indices/완성/d%s.md" % os.urandom(3).hex(): "x"} if doc else {"p%s.txt" % os.urandom(3).hex(): "x"}, "main")
    kw._git(w.tmp / "pack", "fetch", "-q", "origin")
    return sha
def land(sha):
    return "- 착지: %s (ai-feature-pack origin/main · PR #1 · ft-merge-land)\n" % sha
def at(w, sec):   # 주입 시계 = 지금 + sec(카드 커밋 시각 = 실제 지금) · 하루 정리 표식도 같이(생존 검사 쪽지 0)
    w.t = time.time() + sec
    os.utime(w.state / "disk-alarm.log", (w.t, w.t))
def once(w, k=None, **kv):   # 감시 1회(keeper 객체 유지 · 쪽지 몫 되돌림) · 기준판 = keeper 바퀴 1회
    if w.T is None:
        w.round()
        return None
    kw._git(w.root, "fetch", "-q", "origin")
    k = k or w.keeper()
    k.notify_used = 0
    w.T.check(k, **kv)
    return k
def sends(w):   # 가짜 mbox 기록 중 전이 감시 쪽지
    return [x for x in kw._lines(str(w.mbox) + ".log") if x.startswith("send ") and "카드 전이 감시" in x]
def cells(w, k):   # 카드마다 첫 일치 칸 이름(위임 포함) · 기준판 = {}
    if w.T is None:
        return {}
    kw._git(w.root, "fetch", "-q", "origin")
    v = w.T.Watch(k or w.keeper())
    return {c["stem"]: (v.classify(c) or [("-",)])[0][0] for c in v.index()}
def claim(w, work, holder, rotation=False):
    for argv in ([] if rotation else [["submit", "--command", "c-" + work, "--body", "b", "--work", work]]) + [["claim", "--work", work, "--holder", holder] + (["--rotation", "true"] if rotation else [])]:
        assert w.CLI.run(argv + ["--root", str(w.root), "--team", "harness"])[1] == 0
def marker(w, holder, age):
    p = w.root / ".fable-team" / "state" / "pi-distill-pending" / holder.split("#")[0]
    kw._put(p, "seat=%s\n" % holder), os.utime(p, (w.t - age, w.t - age))


def c1(w):   # ① 위임 칸(대기 DA 5시간 · 진행 좌석 20분 · 승계 중) → 알림 0
    at(w, 5 * HOUR)
    card(w, "대기", "r9001-da-wait", "- 배정: 대기(DA · 2026-11-19)\n")
    card(w, "진행", "r9002-seat"), card(w, "진행", "r9003-succ")
    claim(w, "r9002-seat", "byz-harness-nano-r9002-seat#0"), claim(w, "r9003-succ", "byz-harness-nano-r9003-succ#0")
    kw._put(w.root / ".fable-team" / "seats-harness.json", {"_master": "M-harness", "byz-harness-nano-r9003-succ#0": {"_replaced_by": "byz-harness-nano-r9003-succ#1"}})
    k = once(w)
    assert sends(w) == [], sends(w)
    got = cells(w, k)
    assert w.T is None or (got["r9001-da-wait"], got["r9002-seat"], got["r9003-succ"]) == ("대기 · 배정", "진행 · 좌석 있음", "승계 중"), got
def c2(w, doc=False):   # ② 선행 = 완성 ∧ 구현 착지 · «풀림» 0 · 2시간 → 1통 · ③ doc=True(선행 착지 = 카드 문서만) → 선행 칸 0
    card(w, "완성", "r9010-base", land(pack(w, doc)))
    card(w, "대기", "r9011-next", "- 선행: r9010-base (착지 뒤)\n")
    at(w, 2 * HOUR)
    once(w)
    want = [] if doc else ["send M-harness ft2-keeper [크리티컬] 카드 전이 감시 · 선행 풀림 미반영 · harness 1장 — r9011-next ← r9010-base · 다음 수 = «풀림» 줄 또는 착수"]
    assert sends(w) == want, sends(w)
def c3(w):
    c2(w, doc=True)
def c4(w, rounds=1):   # ④ 완성 카드 · 마지막 착지 줄 = 카드 문서만 → «완성 증거 0» 1통(keeper 바퀴 1회 = 연결 확인)
    sha = pack(w, True)
    card(w, "완성", "r9020-doc-only", land(sha) + DONE)
    at(w, 0)
    for _ in range(rounds):
        w.round()
    want = "send M-harness ft2-keeper [크리티컬] 카드 전이 감시 · 완성 증거 0 · harness 1장 — 카드 문서만 %s · 다음 수 = 카드 착지 줄 확인(되돌림 = 팀장 판단)" % sha[:8]
    assert sends(w) == [want], sends(w)
def c5(w):   # ⑤ 장부 done F-sb-m6c… · 카드 대기 · 착지 줄 0 · 2시간 → «장부 완료 · 카드 열림 … -r2» 1통
    work = "F-sb-m6c-knowledge-read-switch"
    w.work(work, done=True, intent=False, turn=None)
    card(w, "대기", work)
    w.t = NOW0 + 2 * HOUR
    once(w)
    assert sends(w) == ["send M-harness ft2-keeper [크리티컬] 카드 전이 감시 · 장부 완료 · 카드 열림 · harness 1장 — %s · 다시 접수 = %s-r2 · 다음 수 = 다시 접수" % (work, work)], sends(w)
def c6a(w):   # ⑥ⓐ 진행 카드 · 착지 줄 = 카드 문서만 · 마지막 줄 30시간 → 진행 24시간 1통(완성 이동 권고 0)
    card(w, "진행", "r9030-progress", land(pack(w, True)))
    at(w, 30 * HOUR)
    once(w)
    got = sends(w)
    assert len(got) == 1 and "진행 24시간 · harness 1장 — r9030-progress 30시간" in got[0] and "완성" not in got[0], got
def c6b(w, new=False):   # ⑥ⓑ 나노 증류 미완 표식 40분 · 같은 work 새 claim 0 → «나노 승계 막힘» 1통 · ⓒ new=True(새 holder claim gen+1) → 0통
    card(w, "대기", "r9040-nano")
    claim(w, "r9040-nano", "byz-harness-nano-r9040-nano#0")
    new and claim(w, "r9040-nano", "byz-harness-nano-r9040-nano#1", rotation=True)
    at(w, 0)
    marker(w, "byz-harness-nano-r9040-nano#0", 40 * 60)
    once(w)
    want = [] if new else ["send M-harness ft2-keeper [크리티컬] 카드 전이 감시 · 진행 · 나노 승계 막힘 · harness 1장 — r9040-nano byz-harness-nano-r9040-nano#0 · 다음 수 = 나노 승계 막힘 · 2.0 승계 길 없음"]
    assert sends(w) == want, sends(w)
def c6c(w):
    c6b(w, new=True)
def c7a(w):   # ⑦ⓐ 같은 날 같은 지문 두 번째 → 0통 · 다음 날 → 1통
    card(w, "완성", "r9050-doc", land(pack(w, True)) + DONE)
    at(w, 0)
    k = once(w)
    k = once(w, k)
    assert len(sends(w)) == (1 if w.T else 0), sends(w)
    w.t += 86400
    once(w, k)
    assert len(sends(w)) == 2, sends(w)
def many(w, n, tag="r91"):   # 같은 팀 같은 칸(완성 증거 0) 카드 n 장 = 커밋 1개
    line = land(pack(w, True)) + DONE
    card(w, "", "", files={"design/harness/indices/완성/%s%02d-doc.md" % (tag, i): "# 인덱스\n" + line for i in range(n)})
def c7b(w):   # ⑦ⓑ 카드 20장 → 1통(수 20 + 이름 앞 10)
    many(w, 20)
    at(w, 0)
    once(w)
    got = sends(w)
    assert len(got) == 1 and "완성 증거 0 · harness 20장 — " in got[0] and got[0].count("카드 문서만") == 10, got
def c7c(w):   # ⑦ⓒ 장부 done ∧ 카드 대기 ∧ 배정 없음 5시간 → «장부 완료 · 카드 열림» 칸 1개만(위임 0)
    work = "r9060-done-wait"
    w.work(work, done=True, intent=False, turn=None)
    card(w, "대기", work, "- 배정: 없음\n")
    w.t = NOW0 + 5 * HOUR
    k = once(w)
    assert len(sends(w)) == 1 and "장부 완료 · 카드 열림" in sends(w)[0], sends(w)
    assert cells(w, k) == {work: "장부 완료 · 카드 열림"}
def c7d(w):   # ⑦ⓓ 예산을 넘어 두 바퀴에 걸친 20장 → 첫 바퀴 0통 · 끝난 바퀴 1통 · 같은 날 집합 4번 바뀜 → 3통에서 멈춤
    many(w, 20)
    at(w, 0)
    tick = iter(range(10 ** 6))
    k = once(w, clock=lambda: next(tick) * 0.6)
    assert sends(w) == [] and (w.T is None or 0 < len(k.state["transition"]["seen"]) < 20), sends(w)
    k = once(w, k)
    assert len(sends(w)) == (1 if w.T else 0), sends(w)
    for i in range(3):
        card(w, "완성", "r92%d-more" % i, land(pack(w, True)) + DONE)
        once(w, k)
    assert len(sends(w)) == 3, sends(w)
def c8(w):   # ⑧ --survey → 칸마다 1줄 · 쓰기 0 · 알림 0 · 70초 안 · git 실패 대역 = 칸마다 «판정 불가» · 알림 0
    many(w, 3)
    kw._git(w.root, "fetch", "-q", "origin")
    snap = lambda: sorted((str(p), p.stat().st_mtime) for p in w.root.rglob("*") if ".git" not in p.parts)   # noqa: E731
    before, t = snap(), time.monotonic()
    tw = w.ft2 / "adapters" / "pi" / "transition_watch.py"
    out = subprocess.run([sys.executable, str(tw), "--survey", "--root", str(w.root), "--pack", str(w.tmp / "pack")], capture_output=True, text=True, timeout=70, env=w.env)
    lines = out.stdout.splitlines()
    assert out.returncode == 0 and len(lines) == 10 and lines[0].startswith("전이 완성 증거 0 3 · harness:r9100-doc"), (out.stdout, out.stderr)
    assert snap() == before and sends(w) == [] and time.monotonic() - t < 70
    bad = subprocess.run([sys.executable, str(tw), "--survey", "--root", str(w.tmp / "empty")], capture_output=True, text=True, timeout=70, env=w.env)
    assert bad.returncode == 0 and all("판정 불가" in x for x in bad.stdout.splitlines()[:9]), bad.stdout


CASES = {"c1": c1, "c2": c2, "c3": c3, "c4": c4, "c5": c5, "c6a": c6a, "c6b": c6b, "c6c": c6c, "c7a": c7a, "c7b": c7b, "c7c": c7c, "c7d": c7d, "c8": c8}


def mutant(tmp, mp, pairs, case):
    """변이 1개 — ft2 사본(tmp/ft2)에 글자 바꿈 → 사례 FAIL 이어야 · 원본으로 같은 사례 1회 더 PASS."""
    copy = tmp / "ft2"
    shutil.copytree(FT2, copy, ignore=shutil.ignore_patterns("tests", "__pycache__"))
    path = copy / "adapters" / "pi" / "transition_watch.py"
    text = path.read_text(encoding="utf-8")
    for old, new in pairs:
        assert text.count(old) == 1, old
        text = text.replace(old, new)
    path.write_text(text, encoding="utf-8")
    with pytest.raises(AssertionError):
        case(world(tmp / "m", mp, ft2=copy))
    case(world(tmp / "o", mp))


@pytest.mark.parametrize("name", list(CASES))
def test_case(name, tmp_path, monkeypatch):
    CASES[name](world(tmp_path / "w", monkeypatch))
