"""r2058 ft2 keeper — 열기 실패(launch-failed) · 열기 멈춤(opening)이 쉼 줄 뒤에 조용히 남지 않는다 (카드 ft2-launch-failed-end · 계약 L1~L10).

사례 = ㉘가~카(끝 판독 · 착지 카드 · 나노 불가 표식) · ㉛가~라(opening 멈춤) · 변이 M11·M12·M13·M16·M30·M31.
대역 = r1812 keeper_world(임시 root · 두 ref · 가짜 tmux) + launch·record 스텁 + 가짜 mbox(peek·send) + 주입 시계.
실 tmux·실 runtime·실 명부·Slack 0 · sleep 0 · 네트워크 0(임시 bare 리포만).
기준판(팩 origin/main c7860542) FAIL = ㉘가 ㉘나 ㉘다 ㉘라 ㉘바 ㉘아 ㉘자 ㉘차 ㉛가 ㉛나 ㉛라 · 지킴 = ㉘마 ㉘사 ㉘카 ㉘타 ㉘파 ㉘하 ㉛다.
"""
import datetime
import importlib.util
import json
import sys
from pathlib import Path

import pytest

HERE = Path(__file__).resolve().parent
_spec = importlib.util.spec_from_file_location("keeper_world_r2058", str(HERE / "keeper_world_r1812.py"))
kw = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(kw)
FT2, T0, TEAM = kw.FT2, kw.T0, kw.TEAM
MBOX = '#!/bin/sh\nprintf "%s\\n" "$*" >> "$0.log"\nif [ "$1" = peek ]; then echo "pending=$(cat "$0.pending" 2>/dev/null || echo 0) scanned=1"; exit 0; fi\n' \
       'echo "STUB $1"\nexit "$(cat "$0.rc" 2>/dev/null || echo 0)"\n'
LS = 'if a[0] == "list-sessions": print("\\n".join(d["alive"])); sys.exit(0)\n'
HAS = ('if a[0] == "has-session" and os.path.exists(st + ".has_rc"):\n'
       '    sys.stderr.write("error connecting to tmux\\n"); sys.exit(int(open(st + ".has_rc").read()))\n')
LAUNCH = '''import json, os, sys
a, me = sys.argv[1:], os.path.abspath(__file__)
open(me + ".log", "a").write(json.dumps(a) + "\\n")
rc = int(open(me + ".rc").read()) if os.path.exists(me + ".rc") else 0
if rc == 0:
    st = os.environ["FAKE_TMUX"]; d = json.load(open(st)); d["alive"].append("byz-harness-nano-%s#0" % a[a.index("--work") + 1][:40]); json.dump(d, open(st, "w"))
print(json.dumps({"result": "접수 성공" if rc == 0 else "복구 필요"}))
sys.exit(rc)
'''
RECORD = '#!/bin/sh\nprintf "%s\\n" "$*" >> "$0.log"\nmkdir -p .fable-team/state/card-assign\nprintf \'{"state": "%s", "seat": "%s"}\' "$3" "$4" > ".fable-team/state/card-assign/$2.json"\n'


def stamp(t):
    return datetime.datetime.fromtimestamp(t).strftime("%Y-%m-%dT%H:%M:%S")


def world(tmp, mp, cards=None, ft2=FT2, nano_max="0", roster=None):
    """임시 세계 1개 — 가짜 tmux(list-sessions · has-session rc 주입) · 가짜 launch·record·mbox · 카드 루트 표 · 팀 켜기."""
    w = kw.World(tmp, mp, ft2)
    b = tmp / "bin"
    tm = kw.TMUX.replace("__PY__", sys.executable)
    i = tm.index('if a[0] == "kill-session"')
    kw._put(b / "tmux", tm[:i] + LS + HAS + tm[i:])
    kw._put(w.mbox, MBOX), w.mbox.chmod(0o755)
    kw._put(b / "launch.py", LAUNCH), kw._put(b / "record", RECORD), (b / "record").chmod(0o755)
    kw._put(b / "gh", "#!/bin/sh\necho '[]'\n"), (b / "gh").chmod(0o755)
    w.env.update(FT2_KEEPER_LAUNCH=str(b / "launch.py"), FT2_CARD_ASSIGN_BIN=str(b / "record"), FT2_GH=str(b / "gh"),
                 HOME=str(tmp / "home"), FT2_TEAM_NANO_MAX=nano_max, FT2_MAILBOX_DIR=str(tmp / "comm"),
                 FT2_SEAT_RESUME_DIR=str(tmp / "resume"), GIT_CONFIG_COUNT="1", GIT_CONFIG_KEY_0="core.quotepath",
                 GIT_CONFIG_VALUE_0="false")
    kw._put(w.state / "directive-roots.tsv", "harness\t.\torigin/main\tdesign/harness/indices\n")
    kw._put(w.state / "ft20-switch" / (TEAM + ".json"), "{}")   # 대상 팀 = switch 표 + runtime 폴더
    w.runtime().mkdir(parents=True, exist_ok=True)
    if cards:
        w.commit("byz", {"design/harness/indices/대기/%s.md" % s: "# 인덱스: %s\n%s- 상태: 대기\n" % (s, h) for s, h in cards.items()}, "main")
    if roster:
        kw._put(w.root / ".fable-team" / "seats-harness.json", roster)
    w.enable()
    return settle(w)


def cards(w, stem, body):
    """대기 카드 1장(팀 폴더) — git 커밋·push(고친 카드도 같은 길) · 임의 runtime 쓰기 0."""
    w.commit("byz", {"design/harness/indices/대기/%s.md" % stem: body}, "main")


def seat(w, work, state="failed", at=None, step="git add", reason="worktree 가 이미 있음", done=False):
    """나노 1석 = 접수 → 배정 → 전달 · launch intent(state·at·step·reason) · 세션 0(부재)."""
    holder = "byz-%s-nano-%s#0" % (TEAM, work)
    steps = [["submit", "--command", "c-" + work, "--body", "본문-" + work, "--work", work],
             ["assign", "--work", work, "--holder", holder, "--evidence", "v1,v2", "--resources", "R-" + work],
             ["deliver", "--work", work]] + ([["complete", "--work", work, "--attempt", "a1"]] if done else [])
    for argv in steps:
        out, rc = w.CLI.run(argv + ["--root", str(w.root), "--team", TEAM])
        assert rc == 0, out
    kw._put(w.state / "ft20-switch" / (TEAM + ".json"), "{}")
    body = {"FT2_HOLDER": holder, "state": state, "at": at or stamp(w.t), "base": "origin/main"}
    body.update({"step": step, "reason": reason} if state != "opening" else {})
    kw._put(w.runtime() / "launch" / ("%s@a1.intent" % work), body)
    return holder


def park(w, work, reason, attempt="a1"):
    """core park 1회 — 정상 꼴 쉼 줄을 세계에 만든다(임의 journal 쓰기 0)."""
    out, rc = w.CLI.run(["park", "--work", work, "--attempt", attempt, "--reason", reason, "--root", str(w.root), "--team", TEAM])
    assert rc == 0, out


def settle(w):
    """r1929 keeper 는 launch 를 기다리지 않는다 → 한 «바퀴» = 띄운 가짜 launch 가 끝날 때까지 기다렸다가 같은 keeper 로 다시."""
    base = w.round

    def round(k=None):
        k, more = k or w.keeper(), True
        while more:
            k.cache.pop("launching", None)
            base(k)
            more = k.cache.pop("spawned", [])
            [p.wait(25) for p in more]
        return k.lines

    w.round = round
    return w


def rnd(w, dt=0):
    """한 바퀴 — 시계 dt 초 앞으로 · 반환 = 로그 줄."""
    w.t += dt
    return w.round()


def has(lines, *words):
    return [x for x in lines if all(word in x for word in words)]


def kinds(w):
    return {kind: sum(1 for rec in w.journal() if rec["kind"] == kind) for kind in ("parked", "accept", "dispatch", "complete")}


def count(w, kind, work):
    return sum(1 for rec in w.journal() if rec["kind"] == kind and rec.get("work") == work)


def sent(w):
    return [x for x in kw._lines(str(w.mbox) + ".log") if x.startswith("send")]


def notes(w):
    return [x for x in kw._lines(str(w.mbox) + ".log") if "[다음 없음]" in x]


def launched(w):
    return [json.loads(x)[json.loads(x).index("--work") + 1] for x in kw._lines(str(w.tmp / "bin" / "launch.py") + ".log")]


def record(w):
    return kw._lines(str(w.tmp / "bin" / "record") + ".log")


def nextmod(k):
    return kw._mod(FT2 / "adapters" / "pi" / "keeper_next.py", "kn_r2058_%d" % id(k))


def c28a(w):   # ㉘가 L3 — intent failed · 세션 0 · owner 남음 · 착지 0 → park 1 · UNKNOWN launch-failed 1 · [긴급] 1 · PARKED 줄 0
    seat(w, "r9581")
    lines = rnd(w)
    assert kinds(w)["parked"] == 1, lines
    assert has(lines, "UNKNOWN harness r9581", "launch-failed", "git add"), lines
    assert not has(lines, "PARKED harness r9581"), lines
    assert len(sent(w)) == 1 and "launch-failed" in sent(w)[0], sent(w)
    assert not w.tmux("kill-session")


def c28b(w):   # ㉘나 L1·L4 — 다음 바퀴 → 건너뛰지 않음 · park 다시 0 · 판정 줄 반복 0 · stall 깨움 0
    c28a(w)
    before = len(sent(w))
    lines = rnd(w, dt=60)
    assert has(lines, "ROUND", "unknown=1"), lines   # 건너뛰지 않음 = 이 바퀴도 같은 work 를 본다
    assert not has(lines, "UNKNOWN harness r9581"), lines   # 판정 줄 반복 0(값 그대로)
    assert kinds(w)["parked"] == 1 and len(sent(w)) == before, (kinds(w), sent(w))
    assert not w.tmux("send-keys")   # stall 깨움·재배정 0


def c28c(w):   # ㉘다 L2 — 착지 줄 + «남은 범위: 없음» → 다음 바퀴 complete 1 · 닫기 호출 0 · 그 뒤 줄 0
    c28a(w)
    w.card("r9581", sha=w.pack_sha(), stage="완성")
    lines = rnd(w, dt=60)
    assert has(lines, "COMPLETED harness r9581"), lines
    assert not w.tmux("kill-session") and not kw._lines(str(w.close) + ".log"), (w.tmux("kill-session"), kw._lines(str(w.close) + ".log"))
    lines = rnd(w, dt=60)
    assert not has(lines, "r9581"), lines


def c28d(w):   # ㉘라 r2058 꼴 — 착지 봄 · «남은 범위» 줄 없음 → 매 바퀴 판정 대상 · 카드 고치면 complete
    c28a(w)
    sha = w.pack_sha()
    cards(w, "r9581", "# 인덱스: r9581\n- 착지: %s\n" % sha)
    assert has(rnd(w, dt=60), "UNKNOWN harness r9581 남은 범위", "줄 없음")
    assert has(rnd(w, dt=60), "UNKNOWN harness r9581 남은 범위")   # 매 바퀴 다시 본다
    cards(w, "r9581", "# 인덱스: r9581\n- 남은 범위: 없음\n- 착지: %s\n" % sha)
    assert has(rnd(w, dt=60), "COMPLETED harness r9581"), w.journal()
    assert not w.tmux("kill-session")


def c28e(w):   # ㉘마 L1 — idle-done 쉼은 지금처럼 건너뜀 · 줄 0
    seat(w, "r9585", state="opened")
    park(w, "r9585", "idle-done")
    lines = rnd(w)
    assert not has(lines, "r9585"), lines
    assert kinds(w)["parked"] == 1 and not sent(w) and not w.tmux("send-keys"), (kinds(w), sent(w))


def c28f(w):   # ㉘바 L5 — fill 후보 = 착지 카드 1 + 안 한 카드 1 → 안 한 카드만 submit · NEXT-SKIP 1줄 · 닫기 뒤 pick 도 같음
    a, b = "r9601-a", "r9602-b"
    cards(w, a, "# 인덱스: %s\n- 착지: %s\n- 상태: 대기\n" % (a, w.pack_sha()))
    cards(w, b, "# 인덱스: %s\n- 상태: 대기\n" % b)
    lines = rnd(w)
    assert has(lines, "NEXT-SKIP harness %s 이미 착지" % a), lines
    assert launched(w) == [b] and count(w, "accept", a) == 0, (launched(w), count(w, "accept", a))
    k = w.keeper()   # 닫기 길(close → keeper_next.close)이 부르는 것과 같은 함수
    k.cache["@round"] = {}
    got = nextmod(k).choose(k, TEAM)
    assert got and got[0] == b and not has(k.lines, "NEXT-SKIP"), (got, k.lines)


def c28g(w):   # ㉘사 L7 — 팀장 좌석(dispatch·intent 0) → 판정 줄 0 · park 0 · [긴급] 0
    d = json.loads(w.tm.read_text(encoding="utf-8"))
    d["alive"], d["pane"]["byz-harness-team-pi#7"] = d["alive"] + ["byz-harness-team-pi#7"], "✻ Working (3s)\n❯ "
    kw._put(w.tm, d)
    lines = rnd(w)
    assert not has(lines, "UNKNOWN harness - byz-harness-team-pi#7"), lines
    assert not has(lines, "UNKNOWN harness byz-harness-team-pi#7"), lines
    assert kinds(w)["parked"] == 0 and not w.tmux("kill-session") and not sent(w), (kinds(w), sent(w))


def c28h(w):   # ㉘아 L9 — 대기 2장 중 한 장 «- 배정: 대기(사람 · …)» → 그 카드 submit 0 · 다른 카드 submit 1
    a, b = "r9611-a", "r9612-b"
    cards(w, a, "# 인덱스: %s\n- 배정: 대기(사람 · 2026-11-16 00:00)\n- 상태: 대기\n" % a)
    cards(w, b, "# 인덱스: %s\n- 상태: 대기\n" % b)
    lines = rnd(w)
    assert count(w, "accept", a) == 0, lines
    assert launched(w) == [b], (launched(w), lines)


def c28i(w):   # ㉘자 L9 — 표식 카드뿐 → [다음 없음] 1통(막힌 사유별 사람 1)
    a = "r9613-a"
    cards(w, a, "# 인덱스: %s\n- 배정: 대기(사람 · 2026-11-16 00:00)\n- 상태: 대기\n" % a)
    lines = rnd(w)
    assert len(notes(w)) == 1 and "막힌 사유별 사람 1" in notes(w)[0], (notes(w), lines)
    assert count(w, "accept", a) == 0 and launched(w) == []


def c28j(w):   # ㉘차 L9·L1 — 표식 카드 · a1 launch-failed 쉼 · 원장 없음 → a2 dispatch 0
    a = "r9613-a"
    cards(w, a, "# 인덱스: %s\n- 배정: 대기(사람 · 2026-11-16 00:00)\n- 상태: 대기\n" % a)
    seat(w, a)   # a1 dispatch
    park(w, a, "launch-failed")
    lines = rnd(w)
    assert count(w, "dispatch", a) == 1, (count(w, "dispatch", a), lines)   # a2 다시 띄우기 0
    assert launched(w) == [] and not record(w), (launched(w), record(w))


def c28k(w):   # ㉘카 L9 — 원장 정지 = 막힘 · 카드 «- 배정: 좌석 …»·«없음» = 안 막음
    a, b, c = "r9614-a", "r9615-b", "r9616-c"
    cards(w, a, "# 인덱스: %s\n- 배정: 좌석 byz-harness-nano-r9614#0\n- 상태: 대기\n" % a)
    cards(w, b, "# 인덱스: %s\n- 배정: 없음\n- 상태: 대기\n" % b)
    cards(w, c, "# 인덱스: %s\n- 상태: 대기\n" % c)
    kw._put(w.state / "card-assign" / (a + ".json"), {"state": "waiting", "reason": "정지", "since": 1.0})
    rnd(w)
    assert count(w, "accept", a) == 0 and launched(w) == [b], (launched(w), count(w, "accept", a))


def c28t(w):   # ㉘타 (양성) — 원장 없음 · 카드 배정 줄 없음 · 선행 없음 → 고름(submit 1)
    a = "r9617-a"
    cards(w, a, "# 인덱스: %s\n- 상태: 대기\n" % a)
    rnd(w)
    assert launched(w) == [a] and count(w, "accept", a) == 1, (launched(w), count(w, "accept", a))


def c28p(w):   # ㉘파 (양성) — «- 배정: 대기(석 · …)» = 새 표식 아님 → 고름
    a = "r9618-a"
    cards(w, a, "# 인덱스: %s\n- 배정: 대기(석 · 2026-11-16 00:00)\n- 상태: 대기\n" % a)
    rnd(w)
    assert launched(w) == [a] and count(w, "accept", a) == 1, (launched(w), count(w, "accept", a))


def c28y(w):   # ㉘하 (양성) — 막힌 카드의 그 줄을 «- 배정: 없음» 으로 바꾼 다음 바퀴 → 다시 고름
    a = "r9619-a"
    cards(w, a, "# 인덱스: %s\n- 배정: 대기(사람 · 2026-11-16 00:00)\n- 상태: 대기\n" % a)
    rnd(w)
    assert launched(w) == [] and count(w, "accept", a) == 0
    cards(w, a, "# 인덱스: %s\n- 배정: 없음\n- 상태: 대기\n" % a)
    rnd(w, dt=60)
    assert launched(w) == [a] and count(w, "accept", a) == 1, (launched(w), count(w, "accept", a))


def c31a(w):   # ㉛가 L6 — opening 20분 · 세션 0(rc1) · owner 있음 · 잇는 중 아님 → park 1 · UNKNOWN launch-failed 1
    seat(w, "r9631", state="opening", at=stamp(w.t - 1200))
    lines = rnd(w)
    assert kinds(w)["parked"] == 1, lines
    assert has(lines, "UNKNOWN harness r9631", "launch-failed", "opening 20분"), lines
    assert not has(lines, "PARKED harness r9631") and len(sent(w)) == 1, (lines, sent(w))


def c31b(w):   # ㉛나 L6 — opening 5분 → 손 0
    seat(w, "r9632", state="opening", at=stamp(w.t - 300))
    lines = rnd(w)
    assert kinds(w)["parked"] == 0 and not w.tmux("kill-session") and not sent(w), (kinds(w), sent(w), lines)
    assert not has(lines, "launch-failed")


def c31c(w):   # ㉛다 L6 — opening 20분인데 fill_open(잇는 중) → 손 0
    seat(w, "r9633", state="opening", at=stamp(w.t - 1200))
    kw._put(w.state / "ft2-keeper" / "state.json", {"fill_open": {"%s|r9633" % TEAM: "a1"}})
    lines = rnd(w)
    assert kinds(w)["parked"] == 0 and not w.tmux("kill-session") and not sent(w), (kinds(w), lines)
    assert not has(lines, "launch-failed")


def c31d(w):   # ㉛라 L6 — opening 20분 · tmux 조회 실패(rc2) → park 0 · 판정 불가 1줄(부재로 읽지 않는다)
    seat(w, "r9634", state="opening", at=stamp(w.t - 1200))
    kw._put(str(w.tm) + ".has_rc", "2")
    lines = rnd(w)
    assert kinds(w)["parked"] == 0 and not w.tmux("kill-session"), (kinds(w), lines)
    assert has(lines, "판정 불가 harness", "r9634"), lines
    assert not has(lines, "UNKNOWN harness r9634"), lines


CASES = {"㉘가": c28a, "㉘나": c28b, "㉘다": c28c, "㉘라": c28d, "㉘마": c28e, "㉘바": c28f, "㉘사": c28g,
         "㉘아": c28h, "㉘자": c28i, "㉘차": c28j, "㉘카": c28k, "㉘타": c28t, "㉘파": c28p, "㉘하": c28y,
         "㉛가": c31a, "㉛나": c31b, "㉛다": c31c, "㉛라": c31d}
NEEDS = {name: dict(nano_max="1") for name in ("㉘바", "㉘아", "㉘자", "㉘차", "㉘카", "㉘타", "㉘파", "㉘하")}
NEEDS["㉘사"] = dict(roster={"_master": "M-harness", "byz-harness-team-pi#7": {"role": "stop-ready"}})


@pytest.mark.parametrize("name", list(CASES))
def test_case(name, tmp_path, monkeypatch):
    CASES[name](world(tmp_path, monkeypatch, **NEEDS.get(name, {})))
