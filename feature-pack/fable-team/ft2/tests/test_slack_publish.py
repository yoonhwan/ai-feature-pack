"""ft2 Slack 답 발행 시험 (r1582 · PR③ 둘째 장).
사례 대조(ⓗ): 21건 중 이 장은 6건(c4 c6 c7 d4 t2 t3) — 계약 낱말은 `CONTRACT-18.md` 대응표 원문, 결과 수치는 사례
`expect.observed.checks` 와 대조(c6·d4 는 «답 몫» 칸만 · `stored_posts` = 마커가 붙은 게시 의도 값 수). 변이: M1~M8(카드) ·
M9 재송 재검사 · M10 429 뒤 재시도 재검사 · M11 예산 초기화 · M12 거절 행이 답을 가림(DA R1~R3).
다음 장(초안 · 지우지 않는다): c1 c2 c3 c5 c8 d1 d2 d3 t1 t4 t5 f1 f2 f3 f4 — 수신 몫·재개·서식·인터뷰.
"""

import importlib.util
import json
import os
import re
import subprocess
import sys
from pathlib import Path

import pytest

FT2 = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ADAPTER = os.path.join(FT2, "adapters", "slack")
PUBLISH = os.path.join(ADAPTER, "publish.py")
CASES = Path(FT2, "contracts", "slack", "cases")
CONTRACT = Path(FT2, "contracts", "slack", "CONTRACT-18.md")
GUARD = os.path.join(FT2, "tools", "legacy_guard.py")
TEAM, W, C, TS = "harness", "TFAKE", "CFAKE", "1800000001.000100"
COMMAND = "slack:%s:%s:%s" % (W, C, TS)
SEAT_A, SEAT_B = "seat-a", "seat-b"
HANDLED = ("c4", "c6", "c7", "d4", "t2", "t3")
NEXT = ("c1", "c2", "c3", "c5", "c8", "d1", "d2", "d3", "t1", "t4", "t5", "f1", "f2", "f3", "f4")
NEXT_LINES = {1, 2, 3, 4, 5, 6, 7, 8, 9, 15, 16, 17, 18}


def _load(name, path):
    spec = importlib.util.spec_from_file_location("ft2_" + name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module

publish = _load("slack_publish", PUBLISH)
binding = _load("slack_binding", os.path.join(ADAPTER, "binding.py"))
CASES_BY_ID = {p.stem.split("-")[1].split("_")[0]: json.loads(p.read_text(encoding="utf-8"))
               for p in sorted(CASES.glob("*.json"))}


def _contract_rows():
    md = CONTRACT.read_text(encoding="utf-8").split("## 대응표", 1)[1].split("\n## ", 1)[0]
    return {int(number): text for number, text in re.findall(r"^\| (\d+) \| (.*?) \|", md, re.M)}


def _case(cid):
    """사례 1건 — 계약 낱말이 18줄 원문에 있고, 그 줄은 이 장 몫이거나 다음 장 줄이다."""
    case, rows = CASES_BY_ID[cid], _contract_rows()
    assert [w for w in case["expect"]["words"] if w not in " ".join(rows.values())] == []
    assert set(case["contract"]) - NEXT_LINES <= set(publish.COVERS)
    return case["expect"]["observed"]["checks"]


def _key(root=TS):
    return binding.thread_key(W, C, root)


def _binder(root):
    return binding.ThreadBinding(str(root), TEAM)


class _Band:  # Slack 전송 대역 — post·조회 응답을 시험이 정하고, 잠든 초를 그대로 기록한다
    def __init__(self, actions=(), answers=()):
        self.actions, self.answers = list(actions), list(answers)
        self.posts, self.waits, self.notify, self.lookups = [], [], [], []

    def post(self, root, text, marker):
        self.posts.append({"root": root, "text": text, "marker": marker})
        action = self.actions.pop(0) if self.actions else ("ok",)
        if action[0] == "rate":
            raise publish.RateLimited(action[1])
        if action[0] == "lost":
            raise publish.ResponseLost("응답 유실")
        return action[1] if len(action) > 1 else "1800000009.000100"

    def sleep(self, seconds):
        self.waits.append(round(float(seconds), 1))  # 실제로 잔 초(가짜 시계)

    def lookup(self, marker):
        self.lookups.append(marker)
        answer = self.answers.pop(0) if self.answers else publish.UNDECIDABLE
        if isinstance(answer, Exception):
            raise answer
        return answer

    def on_notify(self, row):
        self.notify.append(row)

def _publisher(root, band=None, cls=None, on_step=None):
    band = band or _Band()
    return (cls or publish.SlackPublish)(str(root), post=band.post, lookup=band.lookup, sleep=band.sleep,
                                        notify=band.on_notify, team=TEAM, on_step=on_step), band

def test_a_line10_single_thread_and_request_number(tmp_path):
    """ⓐ 줄 10 — 답은 binding thread 1곳 · 머리 요청 번호 = command 그대로(새 번호 0)."""
    root, other = tmp_path / "a", _key("1800000002.000100")
    _binder(root).bind(_key(), SEAT_A)
    _binder(root).bind(other, SEAT_A)
    publisher, band = _publisher(root)
    verdict = publisher.reply(_key(), COMMAND, "답 본문", SEAT_A, 1)
    head, marker, body = band.posts[0]["text"].split("\n")
    assert (verdict["state"], [post["root"] for post in band.posts], head, body, band.posts[0]["marker"]) == (
        "posted", [TS], COMMAND, "답 본문", marker)  # 머리 = 요청 번호 그대로 · 표식 1개로 조회·재송 판정
    assert {entry["root"] for entry in publisher.entries()} == {TS}  # 의도·시도·결과 모두 같은 thread
    mutant, m_band = _publisher(root, cls=_M1)  # M1: thread_ts 없이 채널에 게시
    mutant.reply(other, COMMAND, "답 본문", SEAT_A, 1)
    assert m_band.posts[0]["root"] != other.root

def test_b_c4_retry_after_once_then_visible_error(tmp_path):
    """ⓑ 줄 13 — 429 는 Retry-After 만큼 기다린 뒤 재시도 1 · 두 번째 429 = 보이는 오류 행."""
    checks, other = _case("c4"), _key("1800000002.000100")
    _binder(tmp_path / "b").bind(_key(), SEAT_A)
    _binder(tmp_path / "b").bind(other, SEAT_A)
    publisher, band = _publisher(tmp_path / "b")
    assert (publisher.reply(other, COMMAND, "첫 답", SEAT_A, 1)["state"], checks["first_ok"]) == ("posted", True)
    band.actions[:] = [("rate", 3.0), ("rate", 3.0)]
    with pytest.raises(publish.PostFailed) as caught:
        publisher.reply(_key(), COMMAND, "둘째 답", SEAT_A, 1)
    row, (want,) = caught.value.row, checks["errors_rows"]
    assert tuple(row[k] for k in want) == tuple(want[k] for k in want)
    assert (band.waits, row["waits"], checks["waits_requested_s"]) == (checks["waits_requested_s"],) * 3  # 대기·기록 일치
    errors = [entry["state"] for entry in publisher.entries()].count(publish.ERROR)
    assert (len(band.posts), row["attempts"], checks["second_raised"], errors) == (3, 2, True, 1)  # 세 번째 시도 0
    for cls in (_M2Wait, _M2Twice):
        m_root = tmp_path / ("m2-" + cls.__name__)
        _binder(m_root).bind(_key(), SEAT_A)
        mutant, m_band = _publisher(m_root, _Band(actions=[("rate", 3.0), ("rate", 3.0), ("ok",)]), cls=cls)
        raised = False
        try:
            mutant.reply(_key(), COMMAND, "답", SEAT_A, 1)
        except publish.PostFailed:
            raised = True
        assert not (raised and m_band.waits == checks["waits_requested_s"] and len(m_band.posts) == 2)

def test_c_t3_uncertain_and_four_resolve_paths(tmp_path):
    """ⓒ 줄 11 — 유실 = UNCERTAIN(자동 재송 0) → 조회 3값 · «반환» 판정 불가도 보존 + 알림 1(arch NG②)."""
    checks, undecidable = _case("t3"), _case("t3")["판정 불가"]
    paths = (("있음", publish.FOUND, "posted", checks["있음"]),
             ("없음 확인", publish.ABSENT, "resent", checks["없음 확인"]),
             ("판정 불가", Exception("조회 불명"), "undecidable", undecidable),
             ("판정 불가 반환", publish.UNDECIDABLE, "undecidable", undecidable))
    for name, answer, want, want_checks in paths:
        root = tmp_path / ("t3-" + name)
        _binder(root).bind(_key(), SEAT_A)
        publisher, band = _publisher(root, _Band(actions=[("lost",)], answers=[answer]))
        first = publisher.reply(_key(), COMMAND, "답 본문", SEAT_A, 1)
        assert (first["state"], first["post_calls"], want_checks["first"]) == ("uncertain", 1, "uncertain")
        verdict = publisher.resolve(_key())
        markers = {entry["marker"] for entry in publisher.entries() if entry.get("marker")}
        assert (verdict["resolve"], len(band.posts), verdict["post_calls"], len(markers)) == (
            want, want_checks["post_calls"], want_checks["post_calls"], want_checks["stored_posts"])
        again = publisher.resolve(_key())  # 재기동 뒤에도 같은 판정 · 추가 게시 0
        assert (again["resolve"], len(band.posts), len(band.notify)) == (want, want_checks["post_calls"], int(want == "undecidable"))
    for name, cls in (("m3", _M3), ("m4", _M4), ("m4b", _M4b)):
        _binder(tmp_path / name).bind(_key(), SEAT_A)
        mutant, m_band = _publisher(tmp_path / name, _Band(actions=[("lost",)], answers=[Exception("조회 불명")]),
                                    cls=cls)
        mutant.reply(_key(), COMMAND, "답", SEAT_A, 1)
        verdict = mutant.resolve(_key())
        assert (verdict["resolve"], len(m_band.posts), len(m_band.notify)) != ("undecidable", 1, 1)

def test_d_c7_owner_chain_old_generation_rejected(tmp_path):
    """ⓓⓔ 줄 12 — 승계(gen+1) 뒤 옛 세대 답 거절·새 세대만 게시 · 두 번째 bind 는 거절(owner 불변)."""
    checks = _case("c7")
    root = tmp_path / "c7"
    assert _binder(root).bind(_key(), "seat")["owner"] == "seat#1"
    assert _binder(root).handover(_key(), "seat")["owner"] == "seat#2"
    publisher, band = _publisher(root)
    (want,), stale = checks["errors"], publisher.reply(_key(), COMMAND, "옛 답", "seat", 1)
    assert (tuple(stale[k] for k in want) == tuple(want[k] for k in want), stale["state"], stale["posts"], len(band.posts), checks["old_blocked"]) == (True, "refused", 0, 0, True)
    fresh = publisher.reply(_key(), COMMAND, "새 답", "seat", 2)
    assert (fresh["state"], len(band.posts), checks["new_ok"], checks["posts"]) == ("posted", 1, True, 1)
    m_root = tmp_path / "m5"  # M5: 세대 대조를 빼면 이름이 같은 옛 세대가 게시한다
    m_binder = _binder(m_root)
    m_binder.bind(_key(), "seat")
    m_binder.handover(_key(), "seat")
    m_binder.handover(_key(), "seat")
    assert m_binder.get(_key()).owner == "seat#3"
    mutant, m_band = _publisher(m_root, cls=_M5)
    assert (mutant.reply(_key(), COMMAND, "옛 답", "seat", 1)["state"], len(m_band.posts)) != ("refused", 0)
    checks2, (want2) = _case("t2"), _case("t2")["errors"]  # ⓔ 줄 12 = 같은 thread 두 번째 bind 거절
    t2 = _binder(tmp_path / "t2")
    first2, second2 = t2.bind(_key(), SEAT_A), t2.bind(_key(), SEAT_B)
    assert (first2["state"], second2["state"], second2["k"]) == ("bound", checks2["second_owner"], want2[0]["k"])
    assert (tuple(second2[k] for k in want2[0]) == tuple(want2[0][k] for k in want2[0]),
            t2.get(_key()).owner) == (True, checks2["owner_now"])
    overwrite = _M6(tmp_path / "m6", TEAM)  # M6: 두 번째 bind 가 덮어쓰기
    overwrite.bind(_key(), SEAT_A)
    overwrite.bind(_key(), SEAT_B)
    assert overwrite.get(_key()).owner != checks2["owner_now"]


def test_f_c6_d4_closed_binding_has_no_owner(tmp_path):
    """ⓕ 줄 14 — 닫히면 담당 없음 · 옛 담당 답 거절 · 재개 = gen 2 · 새 담당 답만 게시(답 몫 칸만)."""
    checks6, checks4 = _case("c6"), _case("d4")
    binder = _binder(tmp_path / "c6")
    binder.bind(_key(), "seat")
    binder.close(_key())
    now = binder.get(_key())
    publisher, band = _publisher(tmp_path / "c6")
    refused = publisher.reply(_key(), COMMAND, "옛 답", "seat", 1)
    assert (now.open, now.owner, refused["state"], len(band.posts), checks6["old_owner_reply_posted"]) == (checks6["binding_open"], checks6["owner_after_close"], "refused", 0, False)
    binder = _binder(tmp_path / "d4")
    binder.bind(_key(), "seat")
    binder.close(_key())
    assert (binder.reopen(_key(), "seat")["gen"], checks4["reopen_gen"]) == (2, 2)
    publisher, band = _publisher(tmp_path / "d4")
    old = publisher.reply(_key(), COMMAND, "옛 답", "seat", 1)
    assert (old["state"], len(band.posts), checks4["old_owner_reply"]) == ("refused", 0, False)
    new = publisher.reply(_key(), COMMAND, "새 답", "seat", 2)
    assert (new["state"], band.posts[0]["root"], checks4["new_owner_posted"]) == ("posted", TS, True)
    m_binder = _binder(tmp_path / "m7")  # M7: 닫힌 binding 답 허용
    m_binder.bind(_key(), "seat")
    m_binder.close(_key())
    mutant, m_band = _publisher(tmp_path / "m7", cls=_M7)
    assert (mutant.reply(_key(), COMMAND, "옛 답", "seat", 1)["state"], len(m_band.posts)) != ("refused", 0)

def test_g_intent_before_post_crash_lookup_first(tmp_path):
    """ⓖ 게시 의도가 post 앞 · crash 뒤 재기동은 표식 조회 먼저(바로 재송 0)."""
    assert _crash_run(tmp_path / "g", "after_intent").returncode == 9
    publisher, band = _publisher(tmp_path / "g")
    (intent,) = publisher.entries()
    assert (intent["state"], intent["command"], intent["gen"], intent["marker"]) == (
        "intent", COMMAND, 1, publish.marker_for(_key(), COMMAND))
    band.answers[:] = [publish.FOUND]
    verdict = publisher.resolve(_key())
    assert (verdict["state"], verdict["via"], band.posts, band.lookups) == ("posted", "lookup", [], [intent["marker"]])
    assert _crash_run(tmp_path / "m8", "after_post", "m8").returncode == 9  # M8: 의도를 post 뒤로
    mutant, _ = _publisher(tmp_path / "m8", cls=_M8)
    assert "intent" not in [entry["state"] for entry in mutant.entries()]  # 표식 없음 = 이중 게시 근거 없음

def test_j_r1_rechecks_before_resend_and_retry(tmp_path):
    """NG①·DA R1①② — 재송과 429 뒤 재시도 직전에 binding 재검사 · 변경 뒤 게시 0(첫 시도 1회만)."""
    changes = (("handover", "stale_owner", lambda b: b.handover(_key(), "seat")),
               ("close", "reply_refused", lambda b: b.close(_key())))
    for step, kind, change in changes:
        _binder(tmp_path / step).bind(_key(), "seat")  # 재송 경로: 유실 뒤 resolve
        lost, lost_band = _publisher(tmp_path / step, _Band(actions=[("lost",)], answers=[publish.ABSENT]))
        lost.reply(_key(), COMMAND, "답", "seat", 1)
        change(lost.binding)
        assert (lost.resolve(_key())["state"], len(lost_band.posts)) == ("refused", 1)
        _binder(tmp_path / ("l-" + step)).bind(_key(), "seat")  # 재시도 경로: 429 대기 중 변경
        retry, retry_band = _publisher(tmp_path / ("l-" + step), _Band(actions=[("rate", 3.0)]))
        retry.sleep = lambda seconds, change=change: change(retry.binding)
        verdict = retry.reply(_key(), COMMAND, "답", "seat", 1)
        assert (verdict["state"], verdict["k"], len(retry_band.posts)) == ("refused", kind, 1)
    _binder(tmp_path / "m9").bind(_key(), "seat")  # M9: 재송 재검사 빼기
    mutant, m_band = _publisher(tmp_path / "m9", _Band(actions=[("lost",)], answers=[publish.ABSENT]), cls=_M9)
    mutant.reply(_key(), COMMAND, "답", "seat", 1)
    mutant.binding.close(_key())
    assert (mutant.resolve(_key())["state"], len(m_band.posts)) != ("refused", 1)
    _binder(tmp_path / "m10").bind(_key(), "seat")  # M10: 429 뒤 재시도 재검사 빼기
    mutant, m_band = _publisher(tmp_path / "m10", _Band(actions=[("rate", 3.0)]), cls=_M10)
    mutant.sleep = lambda seconds: mutant.binding.close(_key())
    assert (mutant.reply(_key(), COMMAND, "답", "seat", 1)["state"], len(m_band.posts)) != ("refused", 1)

def test_k_r2_attempt_budget_restored_from_ledger(tmp_path):
    """DA R2 — 첫 429 대기 경계에서 죽어도 재기동이 예산을 장부에서 복원한다(누적 post ≤ 2)."""
    root = tmp_path / "r2"
    assert _crash_run(root, "after_wait").returncode == 9  # 자식은 post 1회(429) 뒤 대기에서 죽었다
    publisher, band = _publisher(root, _Band(actions=[("rate", 3.0)], answers=[publish.ABSENT]))
    attempts = [entry for entry in publisher.entries() if entry["state"] == publish.ATTEMPT]
    assert (len(attempts), attempts[0]["post_calls"]) == (1, 1)  # 장부에 시도 1회가 남아 예산이 1로 복원된다
    with pytest.raises(publish.PostFailed) as caught:
        publisher.resolve(_key())
    assert (len(band.posts), caught.value.row["attempts"], caught.value.row["k"]) == (1, 2, "post_failed")
    _binder(tmp_path / "m11").bind(_key(), "seat")  # M11: 예산 초기화(장부 무시)
    mutant, m_band = _publisher(tmp_path / "m11", _Band(actions=[("rate", 3.0), ("rate", 3.0)], answers=[publish.ABSENT]), cls=_M11)
    mutant._append({"state": publish.ATTEMPT, "root": TS, "key": list(_key()), "command": COMMAND, "owner": "seat#1",
                    "gen": 1, "marker": publish.marker_for(_key(), COMMAND), "body": "답", "post_calls": 1})
    with pytest.raises(publish.PostFailed):
        mutant.resolve(_key())
    assert len(m_band.posts) != 1  # 장부에 이미 1회가 있는데 예산 2를 새로 쓰면 2회가 나간다

def test_m_r3_refusal_does_not_hide_unsettled_answer(tmp_path):
    """DA R3 — 옛 세대 거절 행이 유효한 미확정 답을 가리지 않는다(resolve 가 표식을 조회한다)."""
    root = tmp_path / "r3"
    binder = _binder(root)
    binder.bind(_key(), "seat")
    binder.handover(_key(), "seat")  # 유효 세대 = seat#2
    publisher, band = _publisher(root, _Band(actions=[("lost",)], answers=[publish.FOUND]))
    publisher.reply(_key(), COMMAND, "유효한 답", "seat", 2)  # gen2 = UNCERTAIN
    stale = publisher.reply(_key(), COMMAND, "옛 답", "seat", 1)  # gen1 = 거절
    assert (stale["state"], len(band.posts)) == ("refused", 1)
    verdict = publisher.resolve(_key())
    assert (verdict["state"], verdict["via"], band.posts[0]["text"].split("\n")[2]) == ("posted", "lookup", "유효한 답")
    m_binder = _binder(tmp_path / "m12")  # M12: 거절 행이 답을 가린다
    m_binder.bind(_key(), "seat")
    m_binder.handover(_key(), "seat")
    mutant, m_band = _publisher(tmp_path / "m12", _Band(actions=[("lost",)], answers=[publish.FOUND]), cls=_M12)
    mutant.reply(_key(), COMMAND, "유효한 답", "seat", 2)
    mutant.reply(_key(), COMMAND, "옛 답", "seat", 1)
    assert (mutant.resolve(_key())["state"], m_band.lookups) != ("posted", [publish.marker_for(_key(), COMMAND)])

def test_i_cases_listed_and_invariants():
    """ⓗⓘ 사례 21건 목록 보존·이 장 몫 줄 10~14 · core·receive.py 쓰기 0 · legacy_guard rc0 · 비밀값 0."""
    header = Path(__file__).read_text(encoding="utf-8").split('"""')[1]
    covered = set(publish.COVERS) | NEXT_LINES
    assert sorted(HANDLED + NEXT) == sorted(CASES_BY_ID) and len(CASES_BY_ID) == 21
    assert [cid for cid in HANDLED + NEXT if cid not in header] == []
    assert [cid for cid in HANDLED if set(CASES_BY_ID[cid]["contract"]) - covered] == []
    assert {10, 11, 12, 13, 14} <= set(publish.COVERS) and [_case(cid) for cid in HANDLED]
    changed = subprocess.run(["git", "-C", FT2, "status", "--porcelain", "--", "core", "adapters/slack/receive.py"], capture_output=True, text=True, timeout=25)
    guard = subprocess.run([sys.executable, "-I", GUARD], capture_output=True, timeout=25)
    source = Path(PUBLISH).read_text(encoding="utf-8") + Path(ADAPTER, "binding.py").read_text(encoding="utf-8")
    assert (changed.stdout.strip(), guard.returncode) == ("", 0)
    assert re.compile(r"xox[abposre]-|xapp-\d").search(source) is None
    assert [name for name in ("subprocess", "urllib", "requests", "socket") if name in source] == []

def _mutant(**methods):
    return type("_Mutant", (publish.SlackPublish,), methods)

def _m1_init(self, *args, **kwargs):  # M1 — thread_ts 없이 채널에 게시(실 호출만 채널로)
    post = kwargs.pop("post")
    publish.SlackPublish.__init__(self, *args, **dict(kwargs, post=lambda root, text, marker: post(None, text, marker)))

def _m3_reply(self, key, command, body, seat=None, gen=None):  # M3 — 유실을 실패로 보고 자동 재송
    verdict = publish.SlackPublish.reply(self, key, command, body, seat, gen)
    uncertain = verdict["state"] == publish.UNCERTAIN
    return self._post(key, command, body, seat, gen, None, prior=verdict["post_calls"]) if uncertain else verdict

def _m5_refusal(self, key, command, seat, gen):  # M5 — owner 세대(gen) 대조를 뺀다
    now = self.binding.get(key)
    if now is None or not now.open:
        return self._refused(key, command, "reply_refused", reason="닫히면 담당 없음 = 답 거절")
    return None if seat == now.seat else self._refused(key, command, "stale_owner", owner=now.owner)

def _m8_reply(self, key, command, body, seat=None, gen=None):  # M8 — 게시 의도 기록을 post 뒤로
    verdict = self._post(key, command, body, seat, gen, None)
    self._step("after_post")
    self._append({"state": publish.INTENT, "key": list(key), "command": command, "body": body,
                  "marker": publish.marker_for(key, command)})
    return verdict

_M1 = _mutant(__init__=_m1_init)
_M2Wait = _mutant(__init__=lambda self, *a, **k: publish.SlackPublish.__init__(self, *a, **dict(k, sleep=None)))
_M2Twice = _mutant(MAX_POSTS=3)  # M2 — 세 번째 시도
_M3 = _mutant(reply=_m3_reply)
_answer = publish.SlackPublish._lookup  # 변이 기준 = 원 구현
_M4 = _mutant(_lookup=lambda self, entry: publish.ABSENT if _answer(self, entry) == publish.UNDECIDABLE else _answer(self, entry))
_M4b = _mutant(_lookup=lambda self, entry: publish.FOUND if _answer(self, entry) == publish.FOUND else publish.ABSENT)
_M5 = _mutant(_refusal=_m5_refusal)
_M6 = type("_Mutant", (binding.ThreadBinding,),
           {"bind": lambda self, key, seat: self._write(key, seat, 1 if self.get(key) is None else self.get(key).gen,
                                                        True, binding.BOUND)})  # M6 — 두 번째 bind 덮어쓰기
_M7 = _mutant(_refusal=lambda self, key, command, seat, gen: None  # M7 — 닫힌 binding 답 허용
              if (self.binding.get(key) is None or not self.binding.get(key).open)
              else publish.SlackPublish._refusal(self, key, command, seat, gen))
_M8 = _mutant(reply=_m8_reply)
_M9 = _mutant(_gate=lambda self, key, command, seat, gen, via, call: None  # M9 — 재송 재검사 빼기
              if via == publish.RESENT else publish.SlackPublish._gate(self, key, command, seat, gen, via, call))
_M10 = _mutant(_gate=lambda self, key, command, seat, gen, via, call: None  # M10 — 429 뒤 재시도 재검사 빼기
               if call > 1 else publish.SlackPublish._gate(self, key, command, seat, gen, via, call))
_M11 = _mutant(_post=lambda self, key, command, body, seat=None, gen=None, owner=None,  # M11 — 예산 초기화
               via=publish.POSTED, prior=0: publish.SlackPublish._post(self, key, command, body, seat, gen, owner,
                                                                      via, 0))
_M12 = _mutant(latest=lambda self: {tuple(e["key"]): e for e in self.entries() if e.get("key")})  # M12 — 거절이 답 가림

def _crash_run(root, step, cls=""):
    return subprocess.run([sys.executable, os.path.abspath(__file__), str(root), step, cls],
                          env=dict(os.environ, FT2_PUBLISH_CHILD="1"), capture_output=True, timeout=25)

def _child_main(argv):
    """자식 = 의도 기록 직후·429 대기 직후(또는 M8 은 post 직후) 스스로 죽는다."""
    root, step, cls = argv[0], argv[1], argv[2]
    band = _Band(actions=[("rate", 3.0)] if step == "after_wait" else [])

    def exit_at(name):
        if name == step:
            os._exit(9)
    _binder(root).bind(_key(), SEAT_A)
    publisher, _ = _publisher(root, band, cls=_M8 if cls == "m8" else publish.SlackPublish, on_step=exit_at)
    publisher.reply(_key(), COMMAND, "본문", SEAT_A, 1)
    return 0

if __name__ == "__main__":
    sys.exit(0 if os.environ.get("FT2_PUBLISH_CHILD") != "1" else _child_main(sys.argv[1:]))
