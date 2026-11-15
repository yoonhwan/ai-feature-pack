"""ft2 keeper — 새 카드 보류 설정 1개(state/NEW_CARD_HOLD.json)가 keeper 의 카드 고르기 두 곳만 막는다 (판례 ㉗가~㉗사 · 변이 M14~M15).
대역 = r1812 keeper_world(임시 root·git·가짜 tmux) + 가짜 launch·record + 임시 bin 의 1.x 승계 도구 대역(㉗사) ·
실 tmux·명부·runtime·설치 0 · sleep 0 · 사례 1개 70초 안. 기준판(NEW_CARD_HOLD 판독 없음) = ㉗가·㉗나·㉗라·㉗바 Red.
변이는 사본에서만 돌리고 원본으로 같은 사례를 1회 더 돌린다.
"""
import importlib.util, json, os, shutil, subprocess, sys  # noqa: E401
from pathlib import Path

import pytest

HERE = Path(__file__).resolve().parent
_spec = importlib.util.spec_from_file_location("keeper_world_r2101", str(HERE / "keeper_world_r1812.py"))
kw = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(kw)

TEAM, OTHER, A, B, P, W1 = kw.TEAM, "planner", "r9101-a", "r9102-b", "r9201-p", "r9100-w1"
REASON, UNTIL = "2.0 랜딩 전 — 새 카드 0", "2.0 완료 판정"
HOLD = {"reason": REASON, "by": "byz-aifp-master-pi#0", "at": "2026-11-16T05:00:00", "until": UNTIL}
HELD = "NEW-CARD-HOLD %s %s · until %s" % (TEAM, REASON, UNTIL)
LAUNCH = '''#!__PY__
import json, os, sys
a, me = sys.argv[1:], os.path.abspath(__file__)
open(me + ".log", "a").write(json.dumps(a) + "\\n")
rc = int(open(me + ".rc").read()) if os.path.exists(me + ".rc") else 0
if rc == 0:
    st = os.environ["FAKE_TMUX"]; d = json.load(open(st))
    d["alive"].append("byz-%s-nano-%s#0" % (a[a.index("--team") + 1], a[a.index("--work") + 1][:40])); json.dump(d, open(st, "w"))
print(json.dumps({"result": "접수 성공" if rc == 0 else "복구 필요"}))
sys.exit(rc)
'''
RECORD = ('#!/bin/sh\nprintf "%s\\n" "$*" >> "$0.log"\nmkdir -p .fable-team/state/card-assign\n'
          'if [ "$3" = seat ]; then printf \'{"state": "seat", "seat": "%s"}\' "$4"; else printf \'{"state": "%s", "reason": "%s"}\' "$3" "$4"; fi'
          ' > ".fable-team/state/card-assign/$2.json"\n')
# ── ㉗사 대역: 임시 bin 에 1.x 승계 도구 사본(ft-successor-open.sh) + 형제 도구 스텁 + 가짜 tmux/tmuxc/pgrep ──
SO = kw.OLD / "bin" / "ft-successor-open.sh"
SO_TMUX = r'''#!__PY__
import json, os, sys
st, a = os.environ["FAKE_TMUX"], sys.argv[1:]
d = json.load(open(st))
name = a[a.index("-t") + 1].lstrip("=").rstrip(":") if "-t" in a else ""
open(st + ".log", "a").write(json.dumps(a) + "\n")
if a[0] == "has-session": sys.exit(0 if name in d["alive"] else 1)
if a[0] == "list-panes": sys.stdout.write("%s\n" % d.get("pid", "100")); sys.exit(0)
if a[0] == "show-environment": sys.exit(0)
if a[0] == "display-message" and "#{pane_current_path}" in a[-1]: sys.stdout.write(d["cwd"] + "\n"); sys.exit(0)
sys.exit(0)
'''
SO_TMUXC = r'''#!__PY__
import json, os, sys
st, a = os.environ["FAKE_TMUX"], sys.argv[1:]
d = json.load(open(st))
if a[0] == "open":
    d["alive"].append(a[a.index("--name") + 1]); json.dump(d, open(st, "w"))
sys.exit(0)
'''
SO_PGREP = "#!__PY__\nimport sys\nsys.exit(0)\n"
SO_BODY = "골 1줄\n골 2줄\n골 3줄\n목적 0 = 없음\n열린 칸 감시: 없음\n"
SO_GOV = "<!-- S17-BOOT-BEGIN -->\n승계 지침 블록 1줄\n<!-- S17-BOOT-END -->\n"
SO_FILES = {
    "ft-spawn-hold.sh": "#!/bin/sh\nexit 0\n",
    "ft-name-lint.sh": "#!/bin/sh\nexit 0\n",
    "ft-reclaim-capped.sh": "ft_reclaim_capped() { return 0; }\n",
    "ft-resource-gate.sh": "#!/bin/sh\nexit 0\n",
    "ft-all-stop.sh": "#!/bin/sh\nexit 0\n",
    "ft_teamset.py": "import sys\nsys.exit(0)\n",
    "ft-seat-open-work.py": "import sys\nsys.exit(1)\n",   # rc1 = 받을 일 있음(승계 그대로)
    "ft-send-verified.sh": "#!/bin/sh\necho \"SENT $1\"\necho \"seq=42\"\nexit 0\n",
    "ft-reach-check.sh": "#!/bin/sh\nexit 0\n",
    "ft-seat-retire.sh": "#!/bin/sh\necho \"retire-stub $*\"\nexit 0\n",
    "ft-inbox.py": "import sys\nsys.exit(0)\n",
    "mbox.sh": "#!/bin/sh\nexit 0\n",
    "mbox_doorbell.sh": "#!/bin/sh\n",
}


def nh(team, stem):
    return "byz-%s-nano-%s#0" % (team, stem[:40])


def round_all(w):
    """r1929 keeper 는 launch 를 기다리지 않는다 → 띄운 가짜 launch 가 끝날 때까지 기다린 뒤 같은 keeper 로 한 바퀴 더."""
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


def world(tmp, mp, cards=None, cap="4", live=0, enable=True, ft2=kw.FT2):
    """대기 카드 {팀: {stem: 머리 줄}} · 빈 나노 live 개 · HOME = 임시(실 ~/.claude 문턱 읽기 0)."""
    w = kw.World(tmp, mp, ft2)
    b = tmp / "bin"
    kw._put(b / "launch.py", LAUNCH.replace("__PY__", sys.executable)), kw._put(b / "record", RECORD), (b / "record").chmod(0o755)
    w.env.update(FT2_KEEPER_LAUNCH=str(b / "launch.py"), FT2_CARD_ASSIGN_BIN=str(b / "record"), HOME=str(tmp / "home"),
                 FT2_TEAM_NANO_MAX=cap, GIT_CONFIG_COUNT="1", GIT_CONFIG_KEY_0="core.quotepath", GIT_CONFIG_VALUE_0="false")
    kw._put(w.state / "directive-roots.tsv", "".join("%s\t.\torigin/main\tdesign/%s/indices\n" % (t, t) for t in sorted(cards)))
    w.commit("byz", {"design/%s/indices/대기/%s.md" % (t, s): "# 인덱스: %s\n%s- 상태: 대기\n" % (s, h)
                     for t, mine in cards.items() for s, h in mine.items()}, "main")
    kw._put(w.tm, {"alive": ["byz-%s-nano-live%d#0" % (TEAM, n) for n in range(live)], "pane": {}})
    for team in cards:
        kw._put(w.state / "ft20-switch" / (team + ".json"), "{}"), (w.root / ".fable-team" / "teams" / team / "runtime").mkdir(parents=True, exist_ok=True)
    [w.enable(t) for t in cards] if enable else None
    w.kdir = w.state / "ft2-keeper"
    round_all(w)
    return w


def hold(w, body=None):
    """설정 파일 1개 — body 없으면 HOLD(정상) · "빈" = 빈 파일 · "JSON" = JSON 아님 · "이유없음" = reason 없음."""
    path = w.state / "NEW_CARD_HOLD.json"
    text = {"빈": "", "JSON": "새 카드 보류\n", "이유없음": json.dumps({"by": "x", "until": "y"})}.get(body) if isinstance(body, str) else json.dumps(body or HOLD, ensure_ascii=False)
    kw._put(path, text)


def launched(w):
    return [json.loads(x)[json.loads(x).index("--work") + 1] for x in kw._lines(str(w.tmp / "bin" / "launch.py") + ".log")]


def ledger(w, stem):
    path = w.state / "card-assign" / (stem + ".json")
    return json.loads(path.read_text(encoding="utf-8")) if path.exists() else {}


def receipts(w):
    return [r for r in w.journal() if r["kind"] == "close_receipt"]


def count(w, kind, work, team=TEAM):
    return sum(r["kind"] == kind and r.get("work") == work for r in w.journal(team))


def hold_lines(k, kind="NEW-CARD-HOLD"):
    return [x for x in k.lines if x.startswith(kind)]


def close_work(w, work):
    w.card(work, sha=w.pack_sha(), stage="완성")
    w.work(work, done=True)


def c_ga(w, mp):        # ㉗가 파일 있음 · 빈 칸 · 대기 1 · 두 바퀴 → fill 0 · journal 그대로 · NEW-CARD-HOLD 1줄(둘째 0줄)
    hold(w)
    k, before = w.keeper(), len(w.journal())
    assert w.round(k) and hold_lines(k) == [HELD], k.lines
    assert launched(w) == [] and len(w.journal()) == before and ledger(w, A) == {}, k.lines
    n = len(k.lines)
    w.round(k)
    assert [x for x in k.lines[n:] if x.startswith("NEW-CARD-HOLD")] == [] and launched(w) == [] and len(w.journal()) == before, k.lines[n:]


def c_gna(w, mp):       # ㉗나 파일 있음 · 나노 닫기 1 → 닫기 영수 1 · 다음 카드 배정 0 · submit 0
    hold(w)
    close_work(w, W1)
    k = w.keeper()
    assert w.round(k) and len(receipts(w)) == 1 and receipts(w)[0].get("next") in (None, ""), (receipts(w), k.lines)
    assert count(w, "accept", B) == 0 and launched(w) == [] and HELD in k.lines, k.lines


def c_gda(w, mp):       # ㉗다 파일 있음 · fill_open 에 잇는 열기 1 → reconcile 그대로(launch 1 · record seat)
    hold(w)
    w.work(A, intent=False)   # 전달 attempt a1 만 만들고 의도 파일은 두지 않는다(열기 전 상태)
    kw._put(w.kdir / "state.json", {"fill_open": {"%s|%s" % (TEAM, A): "a1"}})
    k = w.keeper()
    assert w.round(k) and launched(w) == [A] and ledger(w, A) == {"state": "seat", "seat": nh(TEAM, A)}, k.lines
    assert "NEXT harness fill:%s -> %s %s" % (A, A, nh(TEAM, A)) in k.lines


def c_gla(w, mp):       # ㉗라 깨진 파일(빈 파일·JSON 아님) → fill 0 · 판정 불가 1줄 · 두 바퀴째 0줄
    for body in ("빈", "JSON"):
        hold(w, body)
        (w.kdir / "state.json").unlink(missing_ok=True)   # 재기동 = 기억 없음(사례마다 1줄 다시)
        k, before = w.keeper(), len(w.journal())
        lines = w.round(k)
        assert len([x for x in lines if x.startswith("판정 불가") and "NEW_CARD_HOLD" in x]) == 1, (body, lines)
        assert launched(w) == [] and count(w, "accept", A) == 0 and len(w.journal()) == before, (body, lines)


def c_gma(w, mp):       # ㉗마 파일 없음 → 지금 동작 그대로(fill 1장) · 보류 줄 0
    k = w.keeper()
    assert w.round(k) and launched(w) == [A] and ledger(w, A) == {"state": "seat", "seat": nh(TEAM, A)}, k.lines
    assert hold_lines(k) == [] and hold_lines(k, "판정 불가") == []


def c_gba(w, mp):       # ㉗바 두 팀 · 파일 1개 → 두 팀 모두 fill 0 · 팀마다 1줄
    hold(w)
    k, before = w.keeper(), len(w.journal())
    assert w.round(k) and launched(w) == [] and len(w.journal()) == before, k.lines
    assert hold_lines(k) == ["NEW-CARD-HOLD %s %s · until %s" % (t, REASON, UNTIL) for t in sorted((TEAM, OTHER))], k.lines
    assert count(w, "accept", A) == 0 and count(w, "accept", P, OTHER) == 0


def so_world(tmp, mp, with_hold):
    """㉗사 — 팀장 개설 도구(ft-successor-open.sh)를 임시 bin 사본 + 형제 스텁으로 1회 돌린다(실 도구 사본 = 대역 아님)."""
    tmp.mkdir(parents=True, exist_ok=True)
    w = world(tmp, mp, cards={TEAM: {A: ""}})
    b, wt = tmp / "sobin", w.root
    b.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(SO, b / "ft-successor-open.sh")
    for name, body in SO_FILES.items():
        kw._put(b / name, body.replace("__PY__", sys.executable))
    for name in SO_FILES:
        if name.endswith((".sh",)):
            (b / name).chmod(0o755)
    kw._put(b / "tmux", SO_TMUX.replace("__PY__", sys.executable)), (b / "tmux").chmod(0o755)
    kw._put(b / "tmuxc", SO_TMUXC.replace("__PY__", sys.executable)), (b / "tmuxc").chmod(0o755)
    kw._put(b / "pgrep", SO_PGREP.replace("__PY__", sys.executable)), (b / "pgrep").chmod(0o755)
    kw._put(tmp / "so-body.md", SO_BODY), kw._put(tmp / "so-gov.md", SO_GOV)
    kw._put(w.tm, {"alive": [], "pane": {}, "pid": "100", "cwd": str(wt)})
    old = "byz-%s-nano-x#0" % TEAM
    kw._put(w.state / ("seats-%s.json" % TEAM), {"_master": "byz-%s-master-pi#0" % TEAM, "byz-%s-master-pi#0": {"role": "master"}, old: {"role": "nano"}})
    if with_hold:
        hold(w)
    env = dict(w.env, PATH=str(b) + os.pathsep + w.env["PATH"], FT_ROOT=str(w.root), FT_RES_ROOT=str(w.root),
               FT_SO_WAIT_MAX="1", FT_SO_POLL="0", FT_SO_BUDGET="40", FT_SO_SEND_RESERVE="1", FT_RECLAIM="0",
               FT_SEND_VERIFIED=str(b / "ft-send-verified.sh"), FT_REACH_CHECK=str(b / "ft-reach-check.sh"),
               FT_MBOX_SH=str(b / "mbox.sh"), FT_SEAT_RETIRE=str(b / "ft-seat-retire.sh"),
               FT_SEAT_OPEN_WORK=str(b / "ft-seat-open-work.py"), FT_GOV_MD=str(tmp / "so-gov.md"), FT_NAME_LINT=str(b / "ft-name-lint.sh"), HOME=str(tmp / "home"))
    (w.state / "ft20-switch" / (TEAM + ".json")).unlink(missing_ok=True)   # 1.x 승계 도구 = 2.0 전환 표식 있으면 스스로 멈춘다(이 사례 = H7 경계만 본다)
    (w.root / ".fable-team" / "comm").mkdir(parents=True, exist_ok=True)
    out = subprocess.run(["bash", str(b / "ft-successor-open.sh"), old, str(wt), "--name", "byz-%s-nano-x#1" % TEAM,
                          "--agent", "pi", "--model", "opengateway/deepseek/deepseek-v4.1-flash-ultrafast",
                          "--body-file", str(tmp / "so-body.md")], env=env, capture_output=True, text=True, timeout=70, cwd=str(wt))
    return (out, str(w.root), str(w.tmp))



def c_gsa(w, mp):       # ㉗사 파일 있음 · 팀장 개설 1회 → 파일 없을 때와 같은 rc·출력 + 실행 파일 참조 = keeper 쪽뿐
    base = Path(str(w.root)).parent / "so-base"   # ㉗사는 자기 세계 둘(파일 없음·있음)을 따로 만든다
    base.mkdir(parents=True, exist_ok=True)
    a0, r0, t0 = so_world(base / "no" / "w", mp, False)
    a1, r1, t1 = so_world(base / "yes" / "w", mp, True)
    assert a0.returncode == a1.returncode == 0, (a0.returncode, a0.stdout, a0.stderr, a1.returncode, a1.stdout, a1.stderr)
    def norm(x, r, t):   # 경로만 지운다(세계마다 다르다)
        return x.replace(r, "<ROOT>").replace(t, "<TMP>")
    assert norm(a0.stdout, r0, t0) == norm(a1.stdout, r1, t1), (a0.stdout, a1.stdout)
    assert norm(a0.stderr, r0, t0) == norm(a1.stderr, r1, t1), (a0.stderr, a1.stderr)
    assert "OK successor=byz-%s-nano-x#1 seq=42" % TEAM in a0.stdout, a0.stdout   # 실제로 열고 보낸 판(조기 REJECT 아님)
    names = ["legacy/1.x/harness/bin/ft-successor-open.sh", "legacy/1.x/skill/scripts/ft-successor-open.sh"]
    texts = [kw.FT2.parent / n for n in names] + sorted((kw.FT2 / "adapters").rglob("*.py")) + sorted(kw.FT2.glob("tools/*"))
    refs = [p for p in texts if p.is_file() and "NEW_CARD_HOLD" in p.read_text(encoding="utf-8", errors="replace")]
    assert [p.name for p in refs] == ["keeper_next.py"], refs   # H7 경계 = 이 파일을 읽는 실행 파일은 keeper 쪽뿐


CASES = {"㉗가": (c_ga, {TEAM: {A: ""}}),
         "㉗나": (c_gna, {TEAM: {B: ""}}),
         "㉗다": (c_gda, {TEAM: {A: ""}}),
         "㉗라": (c_gla, {TEAM: {A: ""}}),
         "㉗마": (c_gma, {TEAM: {A: ""}}),
         "㉗바": (c_gba, {TEAM: {A: ""}, OTHER: {P: ""}}),
         "㉗사": (c_gsa, {TEAM: {A: ""}})}


def run(name, tmp, mp, ft2=kw.FT2):
    case, cards = CASES[name]
    w = world(tmp, mp, cards=cards, cap="9" if name == "㉗바" else "4", ft2=ft2)
    case(w, mp)


KN = "adapters/pi/keeper_next.py"
MUTANTS = {"M14": (KN, "    if new_card_hold(k, team):   # r2101 H3 — 보류 = 새 카드 고르기만 멈춘다(위 이어 열기·settle·닫기는 그대로)\n        return None\n",
                        "", ("㉗가", "㉗바")),
           "M15": (KN, "    if seen is None and not new_card_hold(k, team):", "    if seen is None:", ("㉗나",))}


@pytest.mark.parametrize("name", list(CASES))
def test_case(name, tmp_path, monkeypatch):
    run(name, tmp_path, monkeypatch)


@pytest.mark.parametrize("name", list(MUTANTS))
def test_mutant(name, tmp_path, monkeypatch):
    rel, old, new, cases = MUTANTS[name]
    tree = tmp_path / "m" / "ft2"
    shutil.copytree(kw.FT2, tree, ignore=shutil.ignore_patterns("tests", "__pycache__"))
    text = (tree / rel).read_text(encoding="utf-8")
    assert text.count(old) == 1, (name, old)
    (tree / rel).write_text(text.replace(old, new), encoding="utf-8")
    for n in cases:   # 변이판 = 그 사례가 Red
        (tmp_path / "m" / n).mkdir(parents=True)
        with pytest.raises(AssertionError):
            run(n, tmp_path / "m" / n, monkeypatch, tree)
    for n in cases:   # 원본 = 같은 사례 PASS
        (tmp_path / "w" / n).mkdir(parents=True)
        run(n, tmp_path / "w" / n, monkeypatch)
