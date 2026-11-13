"""r1865 ft2 keeper 판정 닫기 목록 — `<팀 runtime>/keeper-verdict-close.tsv` (카드 반례 ①~⑩ · 변이 M1~M5).
대역 = r1812 keeper_world(임시 root·git 리포 · 가짜 tmux · 실 tmux·명부·runtime·kill 0 · sleep 0).
판정 원장 = 임시 byz 리포 origin/main 의 VERDICTS-planner-*.md · 우편 로그 = 임시 root 의 mailbox.log.jsonl(읽기 전용 대조).
기준판(목록 읽기 없음) = ① ② Red. 변이는 사본에서만 · 변이마다 원본으로 1회 더(PASS).
"""
import importlib.util, json, shutil  # noqa: E401
from pathlib import Path
import pytest

HERE = Path(__file__).resolve().parent


def _mod(name):
    spec = importlib.util.spec_from_file_location(name + "_r1865", str(HERE / (name + ".py")))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


kw, r1812 = _mod("keeper_world_r1812"), _mod("test_pi_keeper_r1812")
W, N, SEQ, DESK = "r9865", "9865", "296001", "byz-planner-desk-pi#150"
HOLDER = "byz-harness-nano-%s-t#0" % W
LEDGER = "design/teams/planner/VERDICTS-planner-225-20261104.md"


def _world(w, line=(W, "a1", "판정 " + N, "%s #%s" % (DESK, SEQ)), card=True, alive=True, ledger=None, mail=None, **work):
    """done 일 1개(착지 줄 없는 카드 또는 카드 0) · 목록 1줄 · 원장 행 · 우편 로그 행 · 세션 살아 있음·유휴·턴 끝."""
    w.enable()
    if card:
        w.card(W)
    holder = w.work(W, done=True, alive=alive, **work)
    row = ledger if ledger is not None else "| %s | 11-13 | 오빠 «네» · desk#150 #%s · %s 세션 닫기 |" % (N, SEQ, HOLDER)
    w.commit("byz", {LEDGER: "# 원장\n| 1 | x | 다른 일 |\n%s\n" % row}, "main")
    rec = mail if mail is not None else {"seq": int(SEQ), "from": DESK, "to": "byz-planner-master-pi#288", "body": "[HIL] %s 판정 닫기" % W}
    kw._put(w.root / ".fable-team" / "comm" / "mailbox.log.jsonl", '{"seq": 1, "from": "x", "body": "y"}\n' + json.dumps(rec, ensure_ascii=False) + "\n")
    if line is not None:
        kw._put(w.runtime() / "keeper-verdict-close.tsv", "# work\tattempt\t판정\t승인\n" + "\t".join(line) + "\n")
    return holder


def _mine(lines):
    return [x for x in lines if W in x]


def _closed(w, holder):
    lines = w.round()
    assert [x.split()[0] for x in _mine(lines)] == ["CLOSED-VERDICT", "RECEIPT"], lines
    assert "CLOSED-VERDICT harness %s %s 판정 %s %s #%s" % (W, holder, N, DESK, SEQ) in lines
    assert w.tmux("kill-session") == [["kill-session", "-t", "=" + holder]] and w.kinds("close_receipt") == 1


def _held(w, start, once=False):
    lines = _mine(w.round())
    assert len(lines) == 1 and lines[0].startswith("HELD harness %s %s" % (W, start)), lines
    assert w.tmux("kill-session") == [] and w.kinds("close_receipt") == 0
    if once:   # 같은 사유 두 바퀴째 새 줄 0
        assert _mine(w.round()) == [] and w.tmux("kill-session") == []
    return lines[0]


def c1(w):    # ① 착지 줄 없는 카드 + 목록 + 원장 행 + desk 승인 + 유휴·턴 끝·attached 0 → kill 1 · CLOSED-VERDICT · 영수
    _closed(w, _world(w))


def c2(w):    # ② 카드 후보 0(r1808c 꼴) + 목록 → 같음
    _closed(w, _world(w, card=False))


def c3(w):    # ③ Working → HELD · kill 0
    _world(w, pane="⠋ Working...\n")
    assert "Working" in _held(w, HOLDER)


def c4(w):    # ④ attached 1 → HELD 사람 화면 · kill 0
    _world(w)
    d = json.loads(w.tm.read_text(encoding="utf-8"))
    d["att"] = {HOLDER: 1}
    w.tm.write_text(json.dumps(d), encoding="utf-8")
    assert "사람 화면 attached=1" in _held(w, HOLDER)


def _bad(w, line):   # ⑤ 꼴 틀림 → HELD 판정 불가 1회 · kill 0
    _world(w, line=line)
    assert "판정 불가" in _held(w, HOLDER, once=True), line


def c5(w):    # ⑤ 3칸
    _bad(w, (W, "a1", "판정 " + N))


def c5b(w):   # ⑤′ 판정 abc
    _bad(w, (W, "a1", "판정 abc", "%s #%s" % (DESK, SEQ)))


def c5c(w):   # ⑤″ 승인 없음
    _bad(w, (W, "a1", "판정 " + N, "승인없음"))


def c6(w):    # ⑥ 없는 판정 번호 → HELD 승인 대조 · kill 0
    _world(w, line=(W, "a1", "판정 999999", "%s #%s" % (DESK, SEQ)))
    _held(w, "승인 대조")


def c7(w):    # ⑦ 없는 승인 seq(원장 행엔 있음) → HELD 승인 대조
    _world(w, line=(W, "a1", "판정 " + N, "임의좌석 #999999"), ledger="| %s | x | %s #999999 |" % (N, HOLDER))
    _held(w, "승인 대조")


def c8(w):    # ⑧ 다른 일의 승인 — 원장 holder 다름 · 로그 본문 work 다름 → HELD 승인 대조
    _world(w, ledger="| %s | x | %sx · #%s |" % (N, HOLDER, SEQ))
    _held(w, "승인 대조")


def c8b(w):
    _world(w, mail={"seq": int(SEQ), "from": DESK, "body": "%s5 판정 닫기" % W})
    _held(w, "승인 대조")


def c9(w):    # ⑨ 로그 from ≠ 넷째 칸 · 역할 nano → HELD 승인 대조
    _world(w, mail={"seq": int(SEQ), "from": "byz-planner-desk-pi#151", "body": W})
    _held(w, "승인 대조")


def c9b(w):
    nano = "byz-harness-nano-x#1"
    _world(w, line=(W, "a1", "판정 " + N, "%s #%s" % (nano, SEQ)), mail={"seq": int(SEQ), "from": nano, "body": W})
    _held(w, "승인 대조")


def c10(w):   # ⑩ 원장 git rc128(없는 ref) → HELD 못 읽음 · kill 0
    _world(w)
    kw._put(w.state / "directive-roots.tsv", "planner\t.\torigin/없는가지\tdesign/teams/planner/indices\n")
    assert "못 읽음" in _held(w, "승인 대조")


def _table(word):   # R1 — table 원장 줄(번호·시각·내용) · 내용이 word 로 시작
    return "| %s | 11-13 | %s · desk#150 #%s · %s 세션 닫기 |" % (N, word, SEQ, HOLDER)


def c11(w):   # ⑪ table «무효» 줄 → HELD · kill 0 · receipt 0
    _world(w, ledger=_table("무효"))
    assert "무효·철회" in _held(w, "승인 대조")


def c12(w):   # ⑫ table «철회» 줄 → 같음
    _world(w, ledger=_table("철회"))
    assert "무효·철회" in _held(w, "승인 대조")


def c13(w):   # ⑬ table 정상 승인 줄 → CLOSED-VERDICT 그대로
    _closed(w, _world(w, ledger=_table("승인")))


CASES = {"①": c1, "②": c2, "③": c3, "④": c4, "⑤": c5, "⑤′": c5b, "⑤″": c5c, "⑥": c6, "⑦": c7, "⑧": c8, "⑧′": c8b, "⑨": c9, "⑨′": c9b, "⑩": c10,
         "⑪": c11, "⑫": c12, "⑬": c13}
KC, KV = "adapters/pi/keeper_close.py", "adapters/pi/keeper_verdict.py"
MUTANTS = {"M1": (KC, "if self.held_attached(team, work, holder):", "if False:", c4),
           "M2": (KV, 'VERDICT.fullmatch(cells[2])', 'True', c5b),
           "M3": (KC, "if seen in (NOLINE, NOCARD):", "seen = seen or NOLINE\n        if True:", r1812.c4),
           "M4": (KV, "if not near(r\"[\\w#-]\", holder, body):", "if False:", c8),
           "M5": (KV, "return mailbox(k, seq, seat, work)", "return \"\"", c7),
           "M6": (KV, '"|".join(rest.split("|")[1:]).strip(" |")', 'rest.strip(" |")', c11),   # 시각 column 다시 남기기
           "M6′": (KV, '"|".join(rest.split("|")[1:]).strip(" |")', 'rest.strip(" |")', c12)}


@pytest.mark.parametrize("name", list(CASES))
def test_case(name, tmp_path, monkeypatch):
    CASES[name](kw.World(tmp_path, monkeypatch))


@pytest.mark.parametrize("name", list(MUTANTS))
def test_mutant(name, tmp_path, monkeypatch):
    rel, old, new, case = MUTANTS[name]
    tree = tmp_path / "m" / "ft2"
    shutil.copytree(kw.FT2, tree, ignore=shutil.ignore_patterns("tests", "__pycache__"))
    text = (tree / rel).read_text(encoding="utf-8")
    assert text.count(old) == 1, (name, old)
    (tree / rel).write_text(text.replace(old, new), encoding="utf-8")
    for sub in ("w1", "w2"):
        (tmp_path / sub).mkdir()
    with pytest.raises(AssertionError):
        case(kw.World(tmp_path / "w1", monkeypatch, tree))
    case(kw.World(tmp_path / "w2", monkeypatch))   # 원본으로 같은 사례 1회 더 = PASS
