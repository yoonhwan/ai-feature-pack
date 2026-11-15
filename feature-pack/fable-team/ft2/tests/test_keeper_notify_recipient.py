"""r2065a 행 E keeper 쪽지 — 받는 곳 차례·묶음·실패 지문·한 바퀴 3통·도착 확인(장부 seq 경계)·명부 찾기
(카드 ft2-keeper-notify-recipient ㉚가~거 15칸 · 변이 M17·M18·M19·M23·M24·M25·M32·M33).

대역 = r1812 keeper_world(임시 root·가짜 tmux) + 가짜 mbox(python · 사례가 rc·장부에 붙일 줄을 정한다) + 가짜 clock(주입 w.t · sleep 0).
7초 상한 대역 = send 만 0.1초에 자르고 가짜 mbox 는 적재를 먼저 하고 0.3초 잔다(rc None = 7초 넘김 꼴 · 실 7초 대기 0).
실 tmux·실 runtime·실 우편함·네트워크 0 · 사례 1개 70초 안.
"""
import datetime
import importlib.util
import json
import shutil
import sys
from pathlib import Path

import pytest

_spec = importlib.util.spec_from_file_location("keeper_world_r2065", str(Path(__file__).with_name("keeper_world_r1812.py")))
kw = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(kw)
FT2, TEAM = kw.FT2, kw.TEAM

MBOX = r'''import json, os, sys, time
a = sys.argv[1:]
spec = json.load(open(os.environ["FAKE_MBOX"])) if os.path.exists(os.environ["FAKE_MBOX"]) else {}
open(os.environ["FAKE_MBOX"] + ".calls", "a").write(json.dumps(a, ensure_ascii=False) + "\n")
ledger, rows = spec.get("ledger"), spec.get("append") or []
if ledger and rows:   # 적재 = send 가 시간을 먹기 전에 끝난다(설계 §1 실측 꼴)
    have = [json.loads(x).get("seq") for x in open(ledger).read().splitlines() if x.strip()] if os.path.exists(ledger) else []
    seq = max([s for s in have if isinstance(s, int)] or [0])
    os.makedirs(os.path.dirname(ledger), exist_ok=True)
    with open(ledger, "a") as fh:
        for row in rows:
            seq += 1
            fh.write(json.dumps(dict(row, seq=seq), ensure_ascii=False) + "\n")
if spec.get("sleep"):
    time.sleep(spec["sleep"])
sys.exit(spec.get("rc") if isinstance(spec.get("rc"), int) else 0)
'''
BODY = ["[긴급] UNKNOWN chatbot r1 남은 범위", "[긴급] UNKNOWN chatbot r2 남은 범위",
        "[긴급] UNKNOWN chatbot r3 남은 범위", "[긴급] UNKNOWN chatbot r4 남은 범위",
        "[긴급] UNKNOWN chatbot r5 남은 범위", "[긴급] UNKNOWN chatbot r6 남은 범위"]


def world(tmp, mp, ft2=FT2):
    """임시 root + 가짜 tmux/쪽지 + 주입 시계 · 장부 자리 = <root>/.fable-team/comm/mailbox.log.jsonl(keeper 가 읽는 자리)."""
    w = kw.World(tmp, mp, ft2)
    impl = tmp / "bin" / "mbox_impl.py"
    kw._put(impl, MBOX)
    kw._put(w.mbox, '#!/bin/sh\nexec "%s" "%s" "$@"\n' % (sys.executable, impl)), w.mbox.chmod(0o755)
    w.spec = str(tmp / "mbox.spec")
    w.ledger = str(w.root / ".fable-team" / "comm" / "mailbox.log.jsonl")
    w.env.update(FAKE_MBOX=w.spec, HOME=str(tmp / "home"))
    return w


def spec(w, **kv):
    """가짜 mbox 사례 = rc · 잠든 초 · 장부에 붙일 줄(기본 장부 = root 쪽 comm)."""
    Path(w.spec).write_text(json.dumps(dict({"ledger": w.ledger}, **kv)), encoding="utf-8")


def calls(w):
    """가짜 mbox 가 받은 argv 목록 — ["send", 받는 곳, "ft2-keeper", 본문]."""
    path = Path(w.spec + ".calls")
    return [json.loads(x) for x in path.read_text(encoding="utf-8").splitlines()] if path.exists() else []


def sends(w, to=None):
    return [x for x in calls(w) if x[:1] == ["send"] and (to is None or x[1] == to)]


def roster(w, team, **cells):
    """시험 안에서 만든 명부(손 명부 0 · 임시 root 아래) — _master · _desk 칸."""
    kw._put(w.root / ".fable-team" / ("seats-%s.json" % team), cells)


def now_ts(w):
    """주입 시계의 «초» — 장부 ts 와 같은 초를 만드는 값(경계는 seq 로 가른다 · r3)."""
    return datetime.datetime.fromtimestamp(w.t).strftime("%Y-%m-%dT%H:%M:%S")


def line_row(w, body, to="M-harness", ts=None):
    """장부 1줄 꼴 — seq 는 가짜 mbox 가 붙인다."""
    return {"ts": now_ts(w) if ts is None else ts, "from": "ft2-keeper", "to": to, "body": body}


def ledger_write(w, rows):
    path = Path(w.ledger)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("".join(json.dumps(r, ensure_ascii=False) + "\n" for r in rows), encoding="utf-8")


def slow(w):
    """7초 상한 대역 — send 만 0.1초에 자른다(가짜 mbox 는 적재를 먼저 하고 0.3초 잔다) → rc None = «7초 넘김»."""
    k = w.keeper()
    real = k.call
    k.call = lambda argv, timeout=7, retry=0: real(argv, 0.1 if argv[2:3] == ["send"] else timeout, retry)
    return k


def round_(w, *steps, k=None):
    """한 바퀴 = keeper 잠금 안에서 state 읽기·쓰기(바퀴 사이 지문이 남는다) → steps → report(바퀴 끝 = 묶음·NOTIFY-DEFER flush)."""
    k = k or w.keeper()
    k.skip, k.halt = set(), False

    def body():
        for step in steps:
            step(k)
        k.report()
    k.locked(body)
    return k


def c_ga(w):   # ㉚가 _master·_desk 빈칸 · harness _master 있음 · [긴급] 3건 → harness 팀장에게 묶음 1통(3건·앞 3건) · 둘째 바퀴 0통 · 판정 불가 0줄
    roster(w, "chatbot", _master="", _desk=""), spec(w)
    k = round_(w, *[lambda k, i=i: k.notify("chatbot", "ga|%d" % i, BODY[i]) for i in range(3)])
    mail = sends(w)
    assert len(mail) == 1 and mail[0][1:3] == ["M-harness", "ft2-keeper"], mail
    assert "chatbot 팀장 없음" in mail[0][3] and "3건" in mail[0][3] and all(x in mail[0][3] for x in BODY[:3]), mail
    assert not [x for x in k.lines if "판정 불가" in x], k.lines
    round_(w, *[lambda k, i=i: k.notify("chatbot", "ga|뒤%d" % i, BODY[3 + i]) for i in range(3)])
    assert len(sends(w)) == 1, calls(w)   # 묶음 = 팀당 하루 1통


def c_na(w):   # ㉚나 명부 파일 없음(v65 아닌 팀) → ㉚가와 같음
    assert not (w.root / ".fable-team" / "seats-chatbot.json").exists(), "명부 없음 사례"
    spec(w)
    k = round_(w, *[lambda k, i=i: k.notify("chatbot", "na|%d" % i, BODY[i]) for i in range(3)])
    mail = sends(w)
    assert len(mail) == 1 and mail[0][1] == "M-harness" and "3건" in mail[0][3] and not [x for x in k.lines if "판정 불가" in x], (mail, k.lines)


def c_da(w):   # ㉚다 _master 빈칸 · _desk 있음 → desk 에게 묶음 1통 · harness 0통
    roster(w, "chatbot", _master="", _desk="D-chatbot"), spec(w)
    round_(w, *[lambda k, i=i: k.notify("chatbot", "da|%d" % i, BODY[i]) for i in range(3)])
    mail = sends(w)
    assert [x[1] for x in mail] == ["D-chatbot"] and "3건" in mail[0][3], mail


def c_ra(w):   # ㉚라 _master 있음 · send rc 3 → 판정 불가 1줄 · 실패 지문 · 둘째 바퀴 send 0 · 줄 0 · 날짜 바뀐 바퀴 send 1
    spec(w, rc=3)
    k = round_(w, lambda k: k.notify(TEAM, "ra|1", BODY[0]))
    assert len(sends(w)) == 1 and len([x for x in k.lines if x.startswith("판정 불가 harness 쪽지 3")]) == 1, k.lines
    k2 = round_(w, lambda k: k.notify(TEAM, "ra|1", BODY[0]))
    assert len(sends(w)) == 1 and not [x for x in k2.lines if "판정 불가" in x], k2.lines   # 같은 날 = 다시 시도 0 · 줄 0
    w.t += 86400
    round_(w, lambda k: k.notify(TEAM, "ra|1", BODY[0]))
    assert len(sends(w)) == 2, calls(w)   # 날짜가 바뀌면 1회 다시


def c_ma(w):   # ㉚마 _master 있음 · send 7초 초과 · 장부에 그 글 없음 → send 1회(재시도 0) · 판정 불가 1줄 · 그 뒤 ㉚라와 같음
    ledger_write(w, [dict(line_row(w, "다른 글"), seq=5)]), spec(w, sleep=0.3)
    k = round_(w, lambda k: k.notify(TEAM, "ma|1", BODY[0]), k=slow(w))
    assert len(sends(w)) == 1 and len([x for x in k.lines if x.startswith("판정 불가 harness 쪽지 None")]) == 1, k.lines
    k2 = round_(w, lambda k: k.notify(TEAM, "ma|1", BODY[0]), k=slow(w))
    assert len(sends(w)) == 1 and not [x for x in k2.lines if "판정 불가" in x], k2.lines
    w.t += 86400
    round_(w, lambda k: k.notify(TEAM, "ma|1", BODY[0]), k=slow(w))
    assert len(sends(w)) == 2, calls(w)


def c_ba(w):   # ㉚바 받는 곳 세 칸 모두 빈칸 → 판정 불가 … 받는 곳 없음 1줄 · 둘째 바퀴 0줄
    roster(w, "chatbot", _master="", _desk=""), roster(w, TEAM, _master=""), spec(w)
    k = round_(w, lambda k: k.notify("chatbot", "ba|1", BODY[0]))
    lines = [x for x in k.lines if x.startswith("판정 불가 chatbot 쪽지 받는 곳 없음")]
    assert len(lines) == 1 and not sends(w), k.lines
    k2 = round_(w, lambda k: k.notify("chatbot", "ba|1", BODY[0]))
    assert not [x for x in k2.lines if "판정 불가" in x] and not sends(w), k2.lines


def c_sa(w):   # ㉚사 [긴급] 6건이 한 바퀴에 → send 3 · NOTIFY-DEFER 1줄 · 다음 바퀴 send 3 · 지문 6
    spec(w)
    k = round_(w, *[lambda k, i=i: k.notify(TEAM, "sa|%d" % i, BODY[i]) for i in range(6)])
    defer = [x for x in k.lines if x.startswith("NOTIFY-DEFER")]
    assert len(sends(w)) == 3 and len(defer) == 1 and defer[0].endswith(" 3통 · 다음 바퀴"), (calls(w), k.lines)
    k2 = round_(w, *[lambda k, i=i: k.notify(TEAM, "sa|%d" % i, BODY[i]) for i in range(6)])
    assert len(sends(w)) == 6 and len([x for x in k2.state["sent"] if x.startswith("sa|")]) == 6, (calls(w), k2.state["sent"])
    assert not [x for x in k2.lines if x.startswith("NOTIFY-DEFER")], k2.lines


def c_aa(w):   # ㉚아 send rc 0 → 지금과 같음(NOTIFIED 1줄 · 지문) · 둘째 바퀴 0통 · rc 0 이면 장부를 안 읽는다
    spec(w, rc=0, append=[line_row(w, BODY[0])])
    k = round_(w, lambda k: k.notify(TEAM, "aa|1", BODY[0]))
    line = [x for x in k.lines if x.startswith("NOTIFIED")]
    assert len(sends(w)) == 1 and len(line) == 1 and line[0].startswith("NOTIFIED harness M-harness ") and "도착 확인" not in line[0], k.lines
    round_(w, lambda k: k.notify(TEAM, "aa|1", BODY[0]))
    assert len(sends(w)) == 1, calls(w)


def c_ja(w):   # ㉚자 send 7초 초과(rc None) · 경계보다 큰 seq 로 그 글 있음 → send 1회 · NOTIFIED(도착 확인 · rc None) · 성공 지문 · 같은 글 1통
    ledger_write(w, [dict(line_row(w, "다른 글"), seq=100)]), spec(w, sleep=0.3, append=[line_row(w, BODY[0])])
    k = round_(w, lambda k: k.notify(TEAM, "ja|1", BODY[0]), k=slow(w))
    line = [x for x in k.lines if x.startswith("NOTIFIED")]
    assert len(sends(w)) == 1 and len(line) == 1 and "(도착 확인 · rc None)" in line[0], k.lines
    assert not [x for x in k.lines if "판정 불가" in x], k.lines
    round_(w, lambda k: k.notify(TEAM, "ja|1", BODY[0]), k=slow(w))
    rows = [json.loads(x) for x in Path(w.ledger).read_text(encoding="utf-8").splitlines()]
    assert len(sends(w)) == 1 and len([r for r in rows if r.get("body") == BODY[0]]) == 1, calls(w)


def c_ca(w):   # ㉚차 send rc 3 · 경계보다 큰 seq 로 그 글 있음 → ㉚자와 같음(rc 3)
    ledger_write(w, [dict(line_row(w, "다른 글"), seq=100)]), spec(w, rc=3, append=[line_row(w, BODY[0])])
    k = round_(w, lambda k: k.notify(TEAM, "cha|1", BODY[0]))
    line = [x for x in k.lines if x.startswith("NOTIFIED")]
    assert len(sends(w)) == 1 and len(line) == 1 and "(도착 확인 · rc 3)" in line[0], k.lines
    assert not [x for x in k.lines if "판정 불가" in x], k.lines


def c_ka(w):   # ㉚카 send 7초 초과 · 우편함 장부 없음(못 읽음) → 실패 지문 · 판정 불가 … 도착 판독 불가 1줄 · 재시도 0
    spec(w, sleep=0.3)
    k = round_(w, lambda k: k.notify(TEAM, "ka|1", BODY[0]), k=slow(w))
    lines = [x for x in k.lines if x.startswith("판정 불가 harness 쪽지 None 도착 판독 불가")]
    assert len(sends(w)) == 1 and len(lines) == 1, k.lines
    round_(w, lambda k: k.notify(TEAM, "ka|1", BODY[0]), k=slow(w))
    assert len(sends(w)) == 1, calls(w)


def c_ta(w):   # ㉚타 팀 v65 · seats-v65.json 없음 · seats.json 에 _master → 그 팀장에게 1통 / 팀 cfo · seats-cfo.json 없음 = 명부 없음 → 다음 칸
    assert not (w.root / ".fable-team" / "seats-v65.json").exists(), "seats-v65.json 은 없는 것이 실측"
    kw._put(w.root / ".fable-team" / "seats.json", {"_master": "M-v65"})
    spec(w)
    round_(w, lambda k: k.notify("v65", "ta|1", BODY[0]))
    assert [x[1] for x in sends(w)] == ["M-v65"] and "팀장 없음" not in sends(w)[0][3], calls(w)   # v65 명부 = seats.json
    round_(w, lambda k: k.notify("cfo", "ta|2", BODY[1]))
    assert [x[1] for x in sends(w)] == ["M-v65", "M-harness"] and "팀장 없음" in sends(w)[1][3], calls(w)


def c_pa(w):   # ㉚파 같은 초 이전 글(안 셈) — 장부 seq 100 · ts T · 같은 글 → 경계 100 · 새 줄 0 → 도착 아님 · 실패 지문 · NOTIFIED 0줄
    ledger_write(w, [dict(line_row(w, BODY[0], ts=now_ts(w)), seq=100)]), spec(w, sleep=0.3)
    k = round_(w, lambda k: k.notify(TEAM, "pa|1", BODY[0]), k=slow(w))
    assert len(sends(w)) == 1 and not [x for x in k.lines if x.startswith("NOTIFIED")], k.lines
    assert [x for x in k.lines if x.startswith("판정 불가 harness 쪽지 None")], k.lines
    round_(w, lambda k: k.notify(TEAM, "pa|1", BODY[0]), k=slow(w))
    assert len(sends(w)) == 1, calls(w)


def c_ha(w):   # ㉚하 같은 초 새 글(셈) — 경계 100 → send 7초 초과 · 그 사이 seq 101 · ts T(같은 초) 같은 글 → NOTIFIED(도착 확인 · rc None) · 둘째 바퀴 0
    ledger_write(w, [dict(line_row(w, "다른 글"), seq=100)]), spec(w, sleep=0.3, append=[line_row(w, BODY[0], ts=now_ts(w))])
    k = round_(w, lambda k: k.notify(TEAM, "ha|1", BODY[0]), k=slow(w))
    line = [x for x in k.lines if x.startswith("NOTIFIED")]
    assert len(sends(w)) == 1 and len(line) == 1 and "(도착 확인 · rc None)" in line[0], k.lines
    round_(w, lambda k: k.notify(TEAM, "ha|1", BODY[0]), k=slow(w))
    assert len(sends(w)) == 1, calls(w)


def c_geo(w):  # ㉚거 경계 100 · 다른 글 250줄(seq 101~350) · 같은 글 0 → 도착 판독 불가 1줄(«없음» 아님) · 실패 지문 · 재시도 0
    ledger_write(w, [dict(line_row(w, "다른 글"), seq=100)])
    spec(w, sleep=0.3, append=[line_row(w, "다른 글 %d" % i) for i in range(250)])
    k = round_(w, lambda k: k.notify(TEAM, "geo|1", BODY[0]), k=slow(w))
    lines = [x for x in k.lines if x.startswith("판정 불가 harness 쪽지 None 도착 판독 불가")]
    assert len(sends(w)) == 1 and len(lines) == 1 and not [x for x in k.lines if x.startswith("NOTIFIED")], k.lines
    round_(w, lambda k: k.notify(TEAM, "geo|1", BODY[0]), k=slow(w))
    assert len(sends(w)) == 1, calls(w)


def c_deo(w):   # ㉚더(DA HOLD 310738 반례) 같은 날 A 알림 뒤 A 유지 + 새 후보 B → 그날 2통(A · 다음에 A+B) · B 알림 있음 · 열쇠는 처음 «안 보낸» 좌석
    a, b = "byz-harness-nano-A#0", "byz-harness-nano-B#0"
    spec(w)
    k = w.keeper()
    k.skip, k.halt, k.probe = set(), False, lambda seat: "alive"

    def one():
        k.state["open"][a] = {"team": TEAM, "since": w.t - 1900}   # 끝난 뒤 30분 넘게 열린 좌석
        k.report()
    k.locked(one)
    assert len(sends(w)) == 1 and a in sends(w)[0][3], calls(w)
    k2 = w.keeper()
    k2.skip, k2.halt, k2.probe = set(), False, lambda seat: "alive"

    def two():
        k2.state["open"][b] = {"team": TEAM, "since": w.t - 1900}   # A 는 그대로 · 새 후보 B
        k2.report()
    k2.locked(two)
    mail = sends(w)
    assert len(mail) == 2 and b in mail[1][3] and a not in mail[1][3], mail   # 기준판 = 2통 · B 있음(새 head 반례 = 1통 · B 없음)


CASES = {"㉚가": c_ga, "㉚나": c_na, "㉚다": c_da, "㉚라": c_ra, "㉚마": c_ma, "㉚바": c_ba, "㉚사": c_sa, "㉚아": c_aa,
         "㉚자": c_ja, "㉚차": c_ca, "㉚카": c_ka, "㉚타": c_ta, "㉚파": c_pa, "㉚하": c_ha, "㉚거": c_geo, "㉚더": c_deo}
KS, RS = "adapters/pi/keeper_report.py", "adapters/pi/launch_roster.py"
MUTANTS = {
    "M17": (KS, 'return ((own, "_master", False), (own, "_desk", True), (harness, "_master", True))', 'return ((own, "_master", False),)',
            ("㉚가", "㉚나", "㉚다")),
    "M18": (KS, '        self.state["sent"][key] = self.stamp() if ok else "fail|%s|%s" % (self.stamp()[:10], rc)',
            '        self.state["sent"][key] = self.stamp() if ok else None', ("㉚라", "㉚마", "㉚바")),
    "M19": (KS, '        if getattr(self, "notify_used", 0) >= SEND_CAP:', "        if False:", ("㉚사",)),
    "M23": (KS, '        return rc, "" if rc == 0 else self.arrived(self.tail_rows(), mark, to, body)',
            '        return rc, ""', ("㉚자", "㉚차")),
    "M24": ("core/roster.py", 'if team == "v65" else []', "if False else []", ("㉚타",)),
    "M25": (KS, 'self.call(["bash", self.mbox, "send", to, SENDER, body], CALL_S, retry=0)[0]',
            'self.call(["bash", self.mbox, "send", to, SENDER, body], CALL_S, retry=1)[0]', ("㉚자", "㉚마")),
    "M32": (KS, 'rec["seq"] > mark and', 'str(rec.get("ts") or "") >= self.stamp() and', ("㉚파",)),
    "M33": (KS, 'rec["seq"] > mark and', 'str(rec.get("ts") or "") > self.stamp() and', ("㉚하",)),
    "M34": (KS, '"%s|open|%s" % (day, fresh[0]) if fresh else ""', '"%s|open|%s" % (day, seats[0]) if fresh else ""', ("㉚더",)),
}


@pytest.mark.parametrize("name", list(CASES))
def test_case(name, tmp_path, monkeypatch):
    CASES[name](world(tmp_path, monkeypatch))


@pytest.mark.parametrize("name", list(MUTANTS))
def test_mutant(name, tmp_path, monkeypatch):
    path, old, new, cases = MUTANTS[name]
    tree = tmp_path / "m" / "ft2"
    shutil.copytree(FT2, tree, ignore=shutil.ignore_patterns("tests", "__pycache__"))
    text = (tree / path).read_text(encoding="utf-8")
    assert text.count(old) == 1, (name, old)
    (tree / path).write_text(text.replace(old, new), encoding="utf-8")
    for i, case in enumerate(cases):
        sub = tmp_path / ("w%d" % i)
        sub.mkdir()
        with pytest.raises(AssertionError):   # 변이 = 그 사례가 무너진다
            CASES[case](world(sub, monkeypatch, tree))
