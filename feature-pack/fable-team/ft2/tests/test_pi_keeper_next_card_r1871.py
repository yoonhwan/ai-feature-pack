"""r1871 ft2 keeper 다음 카드 — 닫기 영수 자리에서 같은 팀 대기 카드 1장을 submit·영수(next)·launch·record (반례 ①~⑫ · Ⓓ · 변이 M1~M7).
대역 = r1812 keeper_world(임시 root·git·가짜 tmux) + list-sessions · 가짜 launch(세션 1개 생김) · 가짜 record(배정 원장 seat).
실 tmux·명부·ft2 원장·Slack·설치 0 · sleep 0. 기준판(keeper_close 가 영수 () 만) = ① ⑨ ⑩ ⑫ Red. 변이는 사본에서만 · 원본으로 1회 더.
"""
import importlib.util, json, shutil, sys  # noqa: E401
from pathlib import Path
import pytest

HERE = Path(__file__).resolve().parent
_spec = importlib.util.spec_from_file_location("keeper_world_r1871", str(HERE / "keeper_world_r1812.py"))
kw = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(kw)
W1, W2, A, B, C = "r9871", "r9872", "r9001-a", "r9002-b", "r9000-c"
URG, BOTH = "- 긴급: 예\n", "- 대상: 팩 feature-pack/x.py · BYZ .fable-team/y\n"
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
def settle(w):
    """r1929 keeper 는 launch 를 기다리지 않는다 → 옛 시험의 «한 바퀴» = 띄운 가짜 launch 가 끝날 때까지 기다렸다가 같은 keeper 로 한 바퀴 더(판독·record)."""
    base = w.round
    def round(k=None):
        k, more = k or w.keeper(), True
        while more:
            k.cache.pop("launching", None)   # 여는 중 칸 = 바퀴(프로세스)마다 새로
            base(k)
            more = k.cache.pop("spawned", [])
            [p.wait(25) for p in more]
        return k.lines
    w.round = round
    return w
def world(tmp, mp, cards=None, enable=True, ft2=kw.FT2):
    """대기 카드 {stem: 머리 줄} · 카드 루트 표 harness 행 · 닫힐 일 W1(착지 카드 완성/ · 세션 없음)."""
    w = kw.World(tmp, mp, ft2)
    b, tm = tmp / "bin", kw.TMUX.replace("__PY__", sys.executable)
    i = tm.index('if a[0] == "kill-session"')
    kw._put(b / "tmux", tm[:i] + LS + tm[i:])
    kw._put(b / "launch.py", LAUNCH), kw._put(b / "record", RECORD)
    w.env.update(FT2_KEEPER_LAUNCH=str(b / "launch.py"), FT2_CARD_ASSIGN_BIN=str(b / "record"), HOME=str(tmp / "home"), FT2_TEAM_NANO_MAX="1",   # r1913 닫기 1장으로 꽉 참 = fill 0(닫기 길만 본다)
                 GIT_CONFIG_COUNT="1", GIT_CONFIG_KEY_0="core.quotepath", GIT_CONFIG_VALUE_0="false")   # 가짜 HOME = 실 ~/.claude 문턱 읽기 0
    kw._put(w.state / "directive-roots.tsv", "harness\t.\torigin/main\tdesign/harness/indices\n")
    if cards:
        w.commit("byz", {"design/harness/indices/대기/%s.md" % s: "# 인덱스: %s\n%s- 상태: 대기\n" % (s, h) for s, h in cards.items()}, "main")
    if enable:
        w.enable()
    close(w, W1)
    return settle(w)
def close(w, work):
    w.card(work, sha=w.pack_sha(), stage="완성")
    w.work(work, done=True)
def log(w, name):
    return kw._lines(str(w.tmp / "bin" / name) + ".log")
def launched(w):
    return [json.loads(x)[json.loads(x).index("--work") + 1] for x in log(w, "launch.py")]
def notes(w):
    return [x for x in kw._lines(str(w.mbox) + ".log") if "[다음 없음]" in x]
def count(w, kind, work):
    return sum(r["kind"] == kind and r.get("work") == work for r in w.journal())
def receipts(w):
    return [r for r in w.journal() if r["kind"] == "close_receipt"]
def ledger(w, stem):
    return json.loads((w.state / "card-assign" / (stem + ".json")).read_text(encoding="utf-8"))
def crash_at_state(w, mp, k):   # ⑩ — 영수 내구화 직후(after_state) 중단(첫 1회)
    mod, hit = k.receipt.__func__.__globals__["close_next"], []
    orig = mod.CloseNext

    class Boom(orig):
        def __init__(self, *a, **kwargs):
            def step(name):
                if name == "after_state" and not hit:
                    hit.append(name)
                    raise RuntimeError("after_state")
            super().__init__(*a, on_step=step, **kwargs)
    mp.setattr(mod, "CloseNext", Boom)
def c1(w, mp=None):   # ① 대기 2(긴급 1) → 긴급 1장 submit·assign·deliver·launch 1 · NEXT 1줄 · 원장 seat
    lines = w.round()
    assert "NEXT harness %s -> %s %s" % (W1, B, nh(B)) in lines, lines
    assert launched(w) == [B] and ledger(w, B) == {"state": "seat", "seat": nh(B)}
    assert [count(w, k, B) for k in ("accept", "dispatch", "deliver")] == [1, 1, 1] and count(w, "accept", A) == 0
    assert w.round().count("NEXT harness %s -> %s %s" % (W1, B, nh(B))) == 0 and launched(w) == [B]
def c9(w, mp=None):   # ⑨ 최초 영수 1줄에 next·새 holder · 영수 줄 수 1
    w.round()
    assert [(r.get("next"), r.get("holder")) for r in receipts(w)] == [(B, nh(B))]
def c2(w, mp=None):   # ② 고를 카드 0 → [다음 없음] 1통 · 같은 날 두 번째 바퀴(다른 일 닫힘) 0통
    assert any(x.startswith("RECEIPT harness %s" % W1) for x in w.round()) and len(notes(w)) == 1
    close(w, W2)
    w.t += 60
    assert any(x.startswith("RECEIPT harness %s" % W2) for x in w.round()) and len(notes(w)) == 1 and launched(w) == []
def c3(w, mp=None):   # ③ 표식 없음 → 다음 카드 0 · RECEIPT-HOLD
    assert any(x.startswith("RECEIPT-HOLD harness %s" % W1) for x in w.round())
    assert count(w, "accept", B) == 0 and launched(w) == [] and notes(w) == []
def c4(w, mp=None):   # ④ 사유 «사람» 1장뿐 → [다음 없음] 1통(사유별 수)
    w.round()
    assert len(notes(w)) == 1 and "막힌 사유별 사람 1" in notes(w)[0] and launched(w) == []
def c5(w, mp=None):   # ⑤ 팀 PAUSED → 0(쪽지도 0)
    w.round()
    assert launched(w) == [] and count(w, "accept", B) == 0 and notes(w) == []
def c7(w, mp=None):   # ⑦ launch rc2 → «복구 필요» 1줄 · record 0 · 다음 바퀴 재시도 0
    kw._put(w.tmp / "bin" / "launch.py.rc", "2")
    assert any(x.startswith("HELD-NEXT harness %s -> %s" % (W1, B)) and "복구 필요" in x for x in w.round())
    w.round()   # r1913 — 빈 칸은 fill 이 다른 장(A)으로 채운다 · B 재시도·B record 만 0
    assert launched(w).count(B) == 1 and not any(B in x for x in log(w, "record"))
def c8(w, mp=None):   # ⑧ 대상에 팩·BYZ 둘 다(긴급) → 건너뛰고 다음 카드
    assert "판정 불가 harness %s 대상 팩·BYZ 둘 다 — 건너뜀" % B in w.round() and launched(w) == [A]
def cD(w, mp=None):   # Ⓓ 배정 원장 seat(ft2 owner 없음) → 같은 카드 두 번 배정 0
    w.round()
    assert launched(w) == [A] and count(w, "accept", B) == 0
def c10(w, mp):       # ⑩ 영수 직후 중단 → 같은 사건 재접수 = 저장 next 로 launch 1 · record seat · 새 고르기 0 · 영수 1줄
    k = w.keeper()
    crash_at_state(w, mp, k)
    with pytest.raises(RuntimeError):
        k.run_once()
    assert len(receipts(w)) == 1 and count(w, "dispatch", B) == 0 and launched(w) == []
    w.commit("byz", {"design/harness/indices/대기/%s.md" % C: "# 인덱스: %s\n%s" % (C, URG)}, "main")
    assert "NEXT harness %s -> %s %s" % (W1, B, nh(B)) in w.round()
    assert launched(w) == [B] and ledger(w, B)["seat"] == nh(B) and count(w, "accept", C) == 0 and len(receipts(w)) == 1
    return k
def c11(w, mp):       # ⑪ ⑩ 뒤 한 바퀴 더 → launch 0 · record 0
    c10(w, mp)
    w.round()
    assert launched(w) == [B] and len(log(w, "record")) == 1
def c12(w, mp):       # ⑫ launch 성공 직후 record 전 중단 → 다음 바퀴 launch 0 · record 1 · 새 고르기 0
    k = w.keeper()
    real = k.call
    mp.setattr(k, "call", lambda argv, *a, **kv: (_ for _ in ()).throw(RuntimeError("stop")) if "record" in argv else real(argv, *a, **kv))
    try:
        w.round(k)   # r1929 바퀴 1 띄움 → 끝난 뒤 바퀴 2 record 자리에서 중단
        raise AssertionError("record 자리 중단 0")
    except RuntimeError:
        pass
    assert launched(w) == [B] and log(w, "record") == []
    w.commit("byz", {"design/harness/indices/대기/%s.md" % C: "# 인덱스: %s\n%s" % (C, URG)}, "main")
    assert "NEXT harness %s -> %s %s" % (W1, B, nh(B)) in w.round()
    assert launched(w) == [B] and len(log(w, "record")) == 1 and count(w, "accept", C) == 0
def cR2(w, mp):       # R2 영수 직후 중단 → PAUSED → 재개 바퀴 launch 0 · 저장 next 유지 · handled 0 → 허용 뒤 같은 사건 launch 1
    k = w.keeper()
    crash_at_state(w, mp, k)
    with pytest.raises(RuntimeError):
        k.run_once()
    paused = w.state / "harness-tick" / "PAUSED"
    kw._put(paused, "판정 1 · 2026-11-13T09:00:00 · 시험용 팀 정지 표식\n")
    assert not any(x.startswith("NEXT ") for x in w.round()) and launched(w) == [] and log(w, "record") == []
    assert [r.get("next") for r in receipts(w)] == [B]
    paused.unlink()
    assert "NEXT harness %s -> %s %s" % (W1, B, nh(B)) in w.round() and launched(w) == [B] and len(receipts(w)) == 1
def cR3(w, mp=None):  # R3 나노 상한 못 정함(키 없음·비숫자) → 새 실행 0 · 판정 불가 줄 · 영수는 지금처럼 1
    lines = w.round()
    assert any(x.startswith("판정 불가 harness 나노 상한") for x in lines), lines
    assert launched(w) == [] and count(w, "accept", B) == 0 and notes(w) == [] and len(receipts(w)) == 1
def cR3c(w, mp=None):  # R3′ env 없고 루트 thresholds.env 에 값 → 그 값으로 상한 검사 뒤 launch 1
    w.round()
    assert launched(w) == [B]
def nokey(w):
    w.env.pop("FT2_TEAM_NANO_MAX")
def badkey(w):
    w.env["FT2_TEAM_NANO_MAX"] = "없음"
def rootkey(w):
    w.env.pop("FT2_TEAM_NANO_MAX")
    kw._put(w.root / ".fable-team" / "thresholds.env", "FT_DISTILL_WARN=1\nFT2_TEAM_NANO_MAX=1\n")
def pre6(w):          # ⑥ 팀 나노 수 = 상한 → 0
    w.env["FT2_TEAM_NANO_MAX"] = "1"
    d = json.loads(w.tm.read_text(encoding="utf-8"))
    kw._put(w.tm, dict(d, alive=d["alive"] + ["byz-harness-nano-zz#0"]))
TWO = {A: "", B: URG}
CASES = {"①": (c1, TWO, None), "②": (c2, None, None), "③": (c3, TWO, "off"), "④": (c4, {A: ""}, "사람"), "⑤": (c5, TWO, "paused"),
         "⑥": (c5, TWO, pre6), "⑦": (c7, TWO, None), "⑧": (c8, {A: "", B: URG + BOTH}, None), "Ⓓ": (cD, TWO, "seat"),
         "⑨": (c9, TWO, None), "⑩": (c10, TWO, None), "⑪": (c11, TWO, None), "⑫": (c12, TWO, None),
         "R2": (cR2, TWO, None), "R3": (cR3, TWO, nokey), "R3″": (cR3, TWO, badkey), "R3′": (cR3c, TWO, rootkey)}
def run(name, tmp, mp, ft2=kw.FT2):
    case, cards, pre = CASES[name]
    w = world(tmp, mp, cards, enable=pre != "off", ft2=ft2)
    if pre == "사람":
        kw._put(w.state / "card-assign" / (A + ".json"), {"state": "waiting", "reason": "사람", "since": 1.0})
    if pre == "seat":
        kw._put(w.state / "card-assign" / (B + ".json"), {"state": "seat", "seat": "byz-harness-nano-old#0"})
    if pre == "paused":
        kw._put(w.state / "harness-tick" / "PAUSED", "판정 1 · 2026-11-13T09:00:00 · 시험용 팀 정지 표식\n")
    if callable(pre):
        pre(w)
    case(w, mp)
KN = "adapters/pi/keeper_next.py"
MUTANTS = {"M1": ("ready.append(((not urgent,", "ready.append(((False,", "①"),
           "M2": ('"%s|next-none|%s" % (k.stamp()[:10], team)', '"%s|next-none|%s" % (k.stamp(), team)', "②"),
           "M3": ('if not os.path.exists(os.path.join(k.root, ".fable-team", "teams", team, "CLOSE-NEXT.enabled")) or ', "if ", "③"),
           "M4": ('block = "배정됨" if led.get("state") == "seat" or stem in owners else', 'block = "배정됨" if stem in owners else', "Ⓓ"),
           "M5": ("        pick = choose(k, team) if gates(k, team) else None",
                  "        k.receipt(team, work, attempt, holder, gen, mark=False)\n        pick = choose(k, team) if gates(k, team) else None", "⑨"),
           "M6": ('stem, nh = seen.get("next"),', "stem, nh = (choose(k, team) or [None])[0],", "⑩"),
           "M7": ("    if need[1]:", "    if need[0] and need[1]:", "⑫"),
           "M8": ('FT2_TEAM_NANO_MAX=")), "")', 'FT2_TEAM_NANO_MAX=")), "99")', "R3"),
           "M9": ("if pick is None and not gates(k, team):", "if False:", "R2")}


@pytest.mark.parametrize("name", list(CASES))
def test_case(name, tmp_path, monkeypatch):
    run(name, tmp_path, monkeypatch)


@pytest.mark.parametrize("name", list(MUTANTS))
def test_mutant(name, tmp_path, monkeypatch):
    old, new, case = MUTANTS[name]
    tree = tmp_path / "m" / "ft2"
    shutil.copytree(kw.FT2, tree, ignore=shutil.ignore_patterns("tests", "__pycache__"))
    text = (tree / KN).read_text(encoding="utf-8")
    assert text.count(old) == 1, (name, old)
    (tree / KN).write_text(text.replace(old, new), encoding="utf-8")
    for sub in ("w1", "w2"):
        (tmp_path / sub).mkdir()
    with pytest.raises(AssertionError):
        run(case, tmp_path / "w1", monkeypatch, tree)
    run(case, tmp_path / "w2", monkeypatch)   # 원본으로 같은 사례 1회 더 = PASS
