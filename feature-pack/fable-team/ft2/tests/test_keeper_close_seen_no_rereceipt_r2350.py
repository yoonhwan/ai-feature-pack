"""r2350 ft2 keeper — 이미 닫기 영수를 받은 일(seen)을 다음 바퀴에 다시 영수하지 않는다(카드 계약 K1~K4 · 반례 ①~⑩ · 변이 M1~M6).
① 이미 영수한 일 + 다음 있음 = 영수 0 · RECEIPT-SEEN 1 · 배정 장부(record) 1 · handled 1(NEXT 1) · ② 그 영수가 60초 느림 → 그래도 handled 1(바퀴 안)
③ 처음 닫기(seen 없음) = submit 1 · 영수 1 · LAUNCHING · handled 0(r1929) · ④ ③ 다음 바퀴 = 영수 0 · record 1 · handled 1 · NEXT 1
⑤ 다음 빔 = 영수 0 · handled 1 · reconcile 0 · ⑥ 다음 좌석 없음 = reopen(LAUNCHING) · handled 0 · 영수 0 · ⑦ 좌석 판정 불가 = 1줄 · handled 0 · 영수 0
⑧ 새 카드 보류 + seen = 영수 0 · reconcile 1(보류는 새 고르기만 막는다) · ⑨ 영수만 있고 done 키 없음 = 영수 1(core _resume 이 배정·전달을 잇는다)
⑩ done 키 있어도 표식 없음 = 영수 1(core «켜기 전» HOLD) · reconcile 0.
대역 = r1812 keeper_world(임시 root·두 ref·가짜 tmux·주입 시계) + 가짜 launch(세션 1개 생김)·가짜 record(배정 장부 1줄) · 영수 호출 셈 = k.receipt 대역 ·
느림 = 주입 시계만(잠 0) · 실 tmux·실 keeper 상주·실 pi·네트워크 0 · 한 사례 = 바퀴 2개(첫 바퀴 = 닫기 영수 + 다음 카드 열기 · 둘째 바퀴 = seen).
기준판(팩 origin/main a8f0e3f0)= ①②④⑤⑥⑦⑧ Red. 변이 M1~M6 = 사본에서만 · 변이마다 원본으로 같은 사례 1회 더(반대 결과 대조)."""
import importlib.util
import json
import shutil
import sys
from pathlib import Path

import pytest

HERE = Path(__file__).resolve().parent
_spec = importlib.util.spec_from_file_location("keeper_world_r2350", str(HERE / "keeper_world_r1812.py"))
kw = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(kw)
FT2, TEAM = kw.FT2, kw.TEAM
FIN, NXT = "r9250", "r9251"   # FIN = 닫히는 일(착지 완성 카드 · 좌석 없음) · NXT = 닫기 뒤 열 다음 카드
KEY = "%s|%s@a1" % (TEAM, FIN)
DONE_KEY = "close:%s:keeper:%s@a1" % (TEAM, FIN)
LS = 'if a[0] == "list-sessions": print("\\n".join(d["alive"])); sys.exit(0)\n'
LAUNCH = '''import json, os, sys
a, me = sys.argv[1:], os.path.abspath(__file__)
open(me + ".log", "a").write(json.dumps(a) + "\\n")
rc = int(open(me + ".rc").read()) if os.path.exists(me + ".rc") else 0
if rc == 0:
    st = os.environ["FAKE_TMUX"]; d = json.load(open(st)); d["alive"].append("byz-harness-nano-%s#0" % a[a.index("--work") + 1][:40]); json.dump(d, open(st, "w"))
print(json.dumps({"result": "접수 성공" if rc == 0 else "복구 필요"}))   # r1929 실제 launch 처럼 결과 1줄(띄우기 로그)
sys.exit(rc)
'''
RECORD = '#!/bin/sh\nprintf "%s\\n" "$*" >> "$0.log"\nmkdir -p .fable-team/state/card-assign\nprintf \'{"state": "%s", "seat": "%s"}\' "$3" "$4" > ".fable-team/state/card-assign/$2.json"\n'


def nh(stem):
    return "byz-harness-nano-%s#0" % stem[:40]


def world(tmp, mp, ft2=FT2, cards=True, enable=True):
    """임시 root + 완성 카드(착지 줄) + 끝난 나노(배정·전달·완료 = 좌석 없음) · 대기 카드 1장(다음 카드) · 표식 = 켜짐."""
    w = kw.World(tmp, mp, ft2)
    b, tm = tmp / "bin", kw.TMUX.replace("__PY__", sys.executable)
    i = tm.index('if a[0] == "kill-session"')
    kw._put(b / "tmux", tm[:i] + LS + tm[i:])
    kw._put(b / "launch.py", LAUNCH), kw._put(b / "record", RECORD)
    w.env.update(FT2_KEEPER_LAUNCH=str(b / "launch.py"), FT2_CARD_ASSIGN_BIN=str(b / "record"), HOME=str(tmp / "home"),
                 FT2_TEAM_NANO_MAX="1", GIT_CONFIG_COUNT="1", GIT_CONFIG_KEY_0="core.quotepath", GIT_CONFIG_VALUE_0="false")
    kw._put(w.state / "directive-roots.tsv", "harness\t.\torigin/main\tdesign/harness/indices\n")
    if cards:
        w.commit("byz", {"design/harness/indices/대기/%s.md" % NXT: "# 인덱스: %s\n- 배정: 없음\n- 상태: 대기\n" % NXT}, "main")   # r2395 — 표식 줄 1개
    if enable:
        w.enable()
    w.card(FIN, sha=w.pack_sha(), stage="완성")
    w.work(FIN, done=True)
    return w


def spin(w, k):
    """한 바퀴 + 띄운 가짜 launch 가 끝날 때까지 기다린다(r1929 keeper 는 안 기다린다)."""
    lines = w.round(k)
    [p.wait(25) for p in k.cache.pop("spawned", [])]
    return lines


def first(w, mp=None):
    """첫 바퀴 = 닫기 영수 + 다음 카드 열기(LAUNCHING) · mp = 그 바퀴 keeper 의 close_next 를 끊는 대역(⑤⑨) · 반환 = (keeper, 로그 줄)."""
    k = w.keeper()
    if mp:   # 끊긴 바퀴 = 영수 journal 줄만 남는다(잡은 예외 = 그 바퀴 끝 · 다음 바퀴가 잇는다)
        crash(k, mp)
        with pytest.raises(RuntimeError):
            k.run_once()
        return k, k.lines
    return k, spin(w, k)


def again(w, *patches):
    """둘째 바퀴 = 이미 영수한 일(seen)을 다시 만나는 바퀴 · patch(k) = 이 바퀴만 손질(영수 셈·느림·probe)."""
    k = w.keeper()
    for patch in patches:
        patch(k)
    return k, spin(w, k)


def counter(slow=0.0):
    """영수 호출 셈(가짜 cli) · slow = 그 초만큼 느린 영수를 주입 시계로 흉내(잠 0 · 이번 바퀴 남은 몫을 줄인다)."""
    def patch(k):
        real, k.calls = k.receipt, []

        def receipt(*a, **kw):
            k.calls.append(a[1])
            k.start -= slow   # R1 예산 시계 = start + 구획 − monotonic → 느린 호출 1회만큼 뒤로
            return real(*a, **kw)
        k.receipt = receipt
    return patch


def probe_fix(seat, val):
    """그 좌석만 판정을 갈아끼운다(가짜 probe · 그 밖 좌석 = 실제 대역 그대로)."""
    def patch(k):
        real = k.probe
        k.probe = lambda s: val if s == seat else real(s)
    return patch


def crash(k, mp):
    """영수 내구화 직후(after_state) 한 번 끊는다 — 영수 journal 줄은 남고 배정·전달·handled 는 없다(첫 바퀴만).
    k = 이 바퀴가 쓸 keeper(모듈 사본마다 close_next 가 따로라 그 keeper 의 것만 바꾼다 · r1871 ⑩ 과 같은 대역)."""
    hit = []
    mod = k.receipt.__func__.__globals__["close_next"]
    orig = mod.CloseNext

    class Boom(orig):
        def __init__(self, *a, **kwargs):
            def step(name):
                if name == "after_state" and not hit:
                    hit.append(name)
                    raise RuntimeError("after_state")
            super().__init__(*a, on_step=step, **kwargs)
    mp.setattr(mod, "CloseNext", Boom)


def log(w, name):
    return kw._lines(str(w.tmp / "bin" / name) + ".log")


def records(w):
    return [x.split() for x in log(w, "record")]


def launched(w):
    return [json.loads(x)[json.loads(x).index("--work") + 1] for x in log(w, "launch.py")]


def receipts(w):
    return sum(r["kind"] == "close_receipt" for r in w.journal())


def counts(w, work):
    return [sum(r["kind"] == k and r.get("work") == work for r in w.journal()) for k in ("accept", "dispatch", "deliver")]


def handled(k):
    return sorted(x for x in k.state["handled"] if x == KEY)


def has(lines, *words):
    return [x for x in lines if all(word in x for word in words)]


def nexts(lines):
    return [x for x in lines if x.startswith("NEXT %s " % TEAM)]


def c1(w, mp):   # ① 이미 영수한 일 · 다음 있음 · 좌석 살아 있음 · 배정 장부 없음 → 영수 0 · RECEIPT-SEEN 1 · record 1 · handled 1 · NEXT 1
    first(w)
    k, lines = again(w, counter())
    assert k.calls == [], k.calls   # 기준판 = 영수 1
    assert len(has(lines, "RECEIPT-SEEN", TEAM, FIN)) == 1 and has(lines, "RECEIPT-UNSURE") == []
    assert records(w) == [["record", NXT, "seat", nh(NXT)]] and handled(k) == [KEY]
    assert len(has(nexts(lines), "%s -> %s" % (FIN, NXT))) == 1 and launched(w) == [NXT], lines


def c2(w, mp):   # ② ① 의 영수가 60초 느림 → 바퀴 예산 안에서 handled 1(기준판 = 잘림 · handled 0)
    first(w)
    k, lines = again(w, counter(slow=60))
    assert handled(k) == [KEY] and has(lines, "ROUND-CAP") == [], lines
    assert k.calls == [] and len(has(lines, "NEXT", TEAM, "%s -> %s" % (FIN, NXT))) == 1


def c3(w, mp):   # ③ 처음 닫기(seen 없음) → submit 1 · 영수 1 · LAUNCHING · handled 0(r1929 첫 바퀴) · RECEIPT-SEEN 0
    k, lines = first(w)
    assert receipts(w) == 1 and counts(w, NXT) == [1, 1, 1] and launched(w) == [NXT], lines
    assert handled(k) == [] and has(lines, "RECEIPT-SEEN") == [] and has(lines, "RECEIPT", TEAM)


def c4(w, mp):   # ④ ③ 다음 바퀴(seen 생김 · 좌석 alive) → 영수 0 · record 1 · handled 1 · NEXT 1
    first(w)
    k, lines = again(w, counter())
    assert k.calls == [] and handled(k) == [KEY] and records(w) == [["record", NXT, "seat", nh(NXT)]]
    assert len(has(nexts(lines), "%s -> %s" % (FIN, NXT))) == 1 and receipts(w) == 1


def c5(w, mp):   # ⑤ 영수만 있고 다음 빔(다음 카드 0 · 영수 줄 뒤 끊김) → 영수 0 · handled 1 · reconcile 0
    first(w, mp)
    assert receipts(w) == 1 and launched(w) == []
    k, lines = again(w, counter())
    assert k.calls == [] and handled(k) == [KEY]
    assert len(has(lines, "RECEIPT-SEEN", TEAM, FIN)) == 1 and nexts(lines) == [] and records(w) == []


def c6(w, mp):   # ⑥ 이미 영수한 일 · 다음 좌석 없음(+ 열기 자취 0) → reconcile 이 다시 연다(LAUNCHING) · handled 0 · 영수 0
    first(w)
    for p in (w.runtime() / "launch").glob("%s@*" % NXT):
        p.unlink()
    d = json.loads(w.tm.read_text(encoding="utf-8"))
    kw._put(w.tm, dict(d, alive=[x for x in d["alive"] if x != nh(NXT)]))
    k, lines = again(w, counter())
    assert k.calls == [] and handled(k) == [] and records(w) == []
    assert len(has(lines, "LAUNCHING")) == 1 and launched(w) == [NXT, NXT], lines


def c7(w, mp):   # ⑦ 이미 영수한 일 · 다음 좌석 판정 불가 → «판정 불가 … 다음 바퀴» 1줄 · handled 0 · 영수 0 · NEXT 0
    first(w)
    k, lines = again(w, counter(), probe_fix(nh(NXT), "판정 불가 · tmux has-session rc 2"))
    assert k.calls == [] and handled(k) == [] and records(w) == []
    assert len(has(lines, "판정 불가", TEAM, FIN)) == 1 and nexts(lines) == [], lines


def c8(w, mp):   # ⑧ 이미 영수한 일 · 새 카드 보류 켜짐 → 영수 0 · reconcile 1(보류는 새 고르기만 막는다)
    first(w)
    kw._put(w.state / "NEW_CARD_HOLD.json", {"reason": "사람", "until": "2026-11-14T00:00:00"})
    k, lines = again(w, counter())
    assert k.calls == [] and handled(k) == [KEY] and records(w) == [["record", NXT, "seat", nh(NXT)]]
    assert len(has(nexts(lines), "%s -> %s" % (FIN, NXT))) == 1, lines


def c9(w, mp):   # ⑨ 영수 줄만 있고 done 키 없음(전달 앞 끊김) → 영수 1(core _resume 이 배정·전달을 잇는다) · RECEIPT-SEEN 0
    first(w, mp)
    assert receipts(w) == 1 and counts(w, NXT) == [1, 0, 0], (receipts(w), counts(w, NXT))   # 접수(submit)만 있고 배정·전달 0
    k, lines = again(w, counter())
    assert k.calls == [FIN] and has(lines, "RECEIPT-SEEN") == []
    assert counts(w, NXT) == [1, 1, 1] and launched(w) == [NXT], lines


def c10(w, mp):   # ⑩ done 키는 있어도 표식(CLOSE-NEXT) 없음 → 영수 1(core «켜기 전» HOLD) · reconcile 0 · handled 0
    first(w)
    (w.root / ".fable-team" / "teams" / TEAM / "CLOSE-NEXT.enabled").unlink()
    k, lines = again(w, counter())
    assert k.calls == [FIN] and len(has(lines, "RECEIPT-HOLD", TEAM, FIN)) == 1, lines
    assert records(w) == [] and handled(k) == [] and nexts(lines) == []


CASES = {"①": c1, "②": c2, "③": c3, "④": c4, "⑤": c5, "⑥": c6, "⑦": c7, "⑧": c8, "⑨": c9, "⑩": c10}
KN = "adapters/pi/keeper_next.py"


def mutant(tmp_path, mp, pairs, case):
    """사본 ft2 의 변이(pairs = [(old, new)] · 각 old 1회) → 그 사례 FAIL · 원본으로 같은 사례 1회 더 = 통과(반대 결과 대조).
    자매 = test_keeper_close_seen_no_rereceipt_r2350_mut.py(변이 M1~M6 · 70초 나눔)."""
    tree = tmp_path / "m" / "ft2"
    shutil.copytree(FT2, tree, ignore=shutil.ignore_patterns("tests", "__pycache__"))
    text = (tree / KN).read_text(encoding="utf-8")
    for old, new in pairs:
        assert text.count(old) == 1, old
        text = text.replace(old, new)
    (tree / KN).write_text(text, encoding="utf-8")
    cards = case.__name__ != "c5"   # ⑤ = 다음 카드 0(다음 빔)
    for sub in ("w1", "w2"):
        (tmp_path / sub).mkdir()
    with pytest.raises(AssertionError):
        case(world(tmp_path / "w1", mp, tree, cards=cards), mp)
    case(world(tmp_path / "w2", mp, cards=cards), mp)


@pytest.mark.parametrize("name", list(CASES))
def test_case(name, tmp_path, monkeypatch):
    CASES[name](world(tmp_path / "w", monkeypatch, cards=name != "⑤"), monkeypatch)
