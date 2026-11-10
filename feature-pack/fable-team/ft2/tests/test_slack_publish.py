"""ft2 Slack 답 발행 시험 (r1582 · PR③ 둘째 장).
사례 대조(ⓗ): 21건 중 이 장은 6건(c4 c6 c7 d4 t2 t3) — 계약 낱말은 `CONTRACT-18.md` 대응표 원문, 결과 수치는 사례
`expect.observed.checks` 와 대조한다. c6·d4 는 «답 몫» 칸만(수신 몫 = pending_seen_by_next·states·last_entrance
는 다음 장). 표식 기록 수(`stored_posts`) = «마커가 붙은 게시 의도» 의 서로 다른 값 수(모형 = 게시 1건).
변이 = M1~M8(카드 §변이) · M4b(조회가 UNDECIDABLE 을 «반환») · M9(재송 직전 재검사 빼기 · DA R1 NG①).
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


class _Band:
    """Slack 전송 대역 — post·조회 응답을 시험이 정하고, 잠든 초를 그대로 기록한다."""
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
        self.waits.append(round(float(seconds), 1))

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
    assert (verdict["state"], [post["root"] for post in band.posts]) == ("posted", [TS])
    assert (head, body, band.posts[0]["marker"]) == (COMMAND, "답 본문", marker)  # 표식 1개로 조회·재송 판정
    assert [entry["root"] for entry in publisher.entries()] == [TS, TS]  # 의도 · 결과
    mutant, m_band = _publisher(root, cls=_M1ChannelOnly)  # M1: thread_ts 없이 채널에 게시
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
    assert (band.waits, row["waits"], checks["waits_requested_s"]) == (checks["waits_requested_s"],) * 3
    assert (len(band.posts), row["attempts"], checks["second_raised"]) == (3, 2, True)  # 세 번째 시도 0
    assert [entry["state"] for entry in publisher.entries()].count(publish.ERROR) == 1  # 오류 행은 남는다
    for cls in (_M2IgnoreWait, _M2RetryTwice):
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
    """ⓒ 줄 11 — 유실 = UNCERTAIN(자동 재송 0) → 조회 3값 · «반환» 판정 불가도 보존 + 알림 1(DA NG②)."""
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
        assert (verdict["resolve"], len(band.posts), verdict["post_calls"]) == (
            want, want_checks["post_calls"], want_checks["post_calls"])
        assert (len(markers), want_checks["stored_posts"]) == (1, 1)  # 표식 하나 · 재송도 같은 표식
        again = publisher.resolve(_key())  # 재기동 뒤에도 같은 판정 · 추가 게시 0
        assert (again["resolve"], len(band.posts)) == (want, want_checks["post_calls"])
        assert len(band.notify) == (1 if want == "undecidable" else 0)  # 사람 알림은 판정 불가에만
    for name, cls in (("m3", _M3AutoResend), ("m4", _M4UndecidableAsAbsent), ("m4b", _M4bReturnAsAbsent)):
        _binder(tmp_path / name).bind(_key(), SEAT_A)
        mutant, m_band = _publisher(tmp_path / name, _Band(actions=[("lost",)], answers=[Exception("조회 불명")]), cls=cls)
        mutant.reply(_key(), COMMAND, "답", SEAT_A, 1)
        verdict = mutant.resolve(_key())
        assert (verdict["resolve"], len(m_band.posts), len(m_band.notify)) != ("undecidable", 1, 1)


def test_d_c7_owner_chain_old_generation_rejected(tmp_path):
    """ⓓ 줄 12 — 승계(gen+1) 뒤 옛 세대 답은 거절 행 · 새 세대 답만 게시 1."""
    checks = _case("c7")
    root = tmp_path / "c7"
    assert _binder(root).bind(_key(), "seat")["owner"] == "seat#1"
    assert _binder(root).handover(_key(), "seat")["owner"] == "seat#2"
    publisher, band = _publisher(root)
    (want,), stale = checks["errors"], publisher.reply(_key(), COMMAND, "옛 답", "seat", 1)
    assert tuple(stale[k] for k in want) == tuple(want[k] for k in want)
    assert (stale["state"], stale["posts"], len(band.posts), checks["old_blocked"]) == ("refused", 0, 0, True)
    fresh = publisher.reply(_key(), COMMAND, "새 답", "seat", 2)
    assert (fresh["state"], len(band.posts), checks["new_ok"], checks["posts"]) == ("posted", 1, True, 1)
    m_root = tmp_path / "m5"  # M5: 세대 대조를 빼면 이름이 같은 옛 세대가 게시한다
    m_binder = _binder(m_root)
    m_binder.bind(_key(), "seat")
    m_binder.handover(_key(), "seat")
    m_binder.handover(_key(), "seat")
    assert m_binder.get(_key()).owner == "seat#3"
    mutant, m_band = _publisher(m_root, cls=_M5NameOnly)
    verdict = mutant.reply(_key(), COMMAND, "옛 답", "seat", 1)
    assert (verdict["state"], len(m_band.posts)) != ("refused", 0)


def test_e_t2_second_owner_bind_rejected(tmp_path):
    """ⓔ 줄 12 — 같은 thread 두 번째 bind = rejected · owner 불변(교체는 명시 승계로만)."""
    checks = _case("t2")
    (want,) = checks["errors"]
    binder = _binder(tmp_path / "t2")
    first, second = binder.bind(_key(), SEAT_A), binder.bind(_key(), SEAT_B)
    assert (first["state"], second["state"], second["k"]) == ("bound", checks["second_owner"], want["k"])
    assert tuple(second[k] for k in want) == tuple(want[k] for k in want)
    assert binder.get(_key()).owner == checks["owner_now"]
    m_binder = _M6Overwrite(tmp_path / "m6", TEAM)  # M6: 두 번째 bind 가 덮어쓰기
    m_binder.bind(_key(), SEAT_A)
    m_binder.bind(_key(), SEAT_B)
    assert m_binder.get(_key()).owner != checks["owner_now"]


def test_f_c6_d4_closed_binding_has_no_owner(tmp_path):
    """ⓕ 줄 14 — 닫히면 담당 없음 · 옛 담당 답 거절 · 재개 = gen 2 · 새 담당 답만 게시(답 몫 칸만)."""
    checks6, checks4 = _case("c6"), _case("d4")
    binder = _binder(tmp_path / "c6")
    binder.bind(_key(), "seat")
    binder.close(_key())
    now = binder.get(_key())
    publisher, band = _publisher(tmp_path / "c6")
    refused = publisher.reply(_key(), COMMAND, "옛 답", "seat", 1)
    assert (now.open, now.owner) == (checks6["binding_open"], checks6["owner_after_close"])
    assert (refused["state"], len(band.posts), checks6["old_owner_reply_posted"]) == ("refused", 0, False)
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
    mutant, m_band = _publisher(tmp_path / "m7", cls=_M7AllowClosed)
    assert (mutant.reply(_key(), COMMAND, "옛 답", "seat", 1)["state"], len(m_band.posts)) != ("refused", 0)


def test_g_intent_before_post_crash_lookup_first(tmp_path):
    """ⓖ 게시 의도가 post 앞 · crash 뒤 재기동은 표식 조회 먼저(바로 재송 0)."""
    assert _crash_run(tmp_path / "g", "after_intent").returncode == 9
    publisher, band = _publisher(tmp_path / "g")
    (intent,) = publisher.entries()
    assert (intent["state"], intent["command"], intent["gen"]) == ("intent", COMMAND, 1)
    assert intent["marker"] == publish.marker_for(_key(), COMMAND)
    band.answers[:] = [publish.FOUND]
    verdict = publisher.resolve(_key())
    assert (verdict["state"], verdict["via"], band.posts, band.lookups) == ("posted", "lookup", [], [intent["marker"]])
    assert _crash_run(tmp_path / "m8", "after_post", "m8").returncode == 9  # M8: 의도를 post 뒤로
    mutant, _ = _publisher(tmp_path / "m8", cls=_M8PostFirst)
    states = [entry["state"] for entry in mutant.entries()]
    assert (states, states == ["intent"]) == (["posted"], False)  # 표식 없음 = 이중 게시를 막을 근거가 없다


def test_j_ng1_resolve_rechecks_binding_before_resend(tmp_path):
    """NG① (DA R1) — 유실 뒤 resolve 전에 승계·닫힘이 있었으면 재송 0 · 거절 행만."""
    changes = (("handover", "stale_owner", lambda b: b.handover(_key(), "seat")),
               ("close", "reply_refused", lambda b: b.close(_key())))
    for step, kind, change in changes:
        _binder(tmp_path / step).bind(_key(), "seat")
        publisher, band = _publisher(tmp_path / step, _Band(actions=[("lost",)], answers=[publish.ABSENT]))
        publisher.reply(_key(), COMMAND, "답", "seat", 1)
        change(publisher.binding)  # 답이 유실된 사이 담당이 바뀌거나 채널이 닫혔다
        verdict = publisher.resolve(_key())
        assert (verdict["state"], verdict["k"], len(band.posts)) == ("refused", kind, 1)
    _binder(tmp_path / "m9").bind(_key(), "seat")  # M9: 재송 직전 재검사 빼기
    mutant, m_band = _publisher(tmp_path / "m9", _Band(actions=[("lost",)], answers=[publish.ABSENT]),
                                cls=_M9NoRecheck)
    mutant.reply(_key(), COMMAND, "답", "seat", 1)
    mutant.binding.close(_key())
    assert (mutant.resolve(_key())["state"], len(m_band.posts)) != ("refused", 1)


def test_h_cases_listed_and_lines_covered():
    """ⓗ 사례 21건 목록 보존 · 이 장 몫 계약 줄 10~14 · 다음 장 목록을 지우지 않는다."""
    header = Path(__file__).read_text(encoding="utf-8").split('"""')[1]
    covered = set(publish.COVERS) | NEXT_LINES
    assert sorted(HANDLED + NEXT) == sorted(CASES_BY_ID) and len(CASES_BY_ID) == 21
    assert [cid for cid in HANDLED + NEXT if cid not in header] == []
    assert [cid for cid in HANDLED if set(CASES_BY_ID[cid]["contract"]) - covered] == []
    assert {10, 11, 12, 13, 14} <= set(publish.COVERS) and [_case(cid) for cid in HANDLED]


def test_i_invariants_no_core_write_no_secret_no_network():
    """ⓘ core·receive.py 쓰기 0 · legacy_guard rc0 · 비밀값 0 · 네트워크 직접 호출 0."""
    changed = subprocess.run(["git", "-C", FT2, "status", "--porcelain", "--", "core",
                              "adapters/slack/receive.py"], capture_output=True, text=True, timeout=25)
    guard = subprocess.run([sys.executable, "-I", GUARD], capture_output=True, timeout=25)
    source = Path(PUBLISH).read_text(encoding="utf-8") + Path(ADAPTER, "binding.py").read_text(encoding="utf-8")
    assert (changed.stdout.strip(), guard.returncode) == ("", 0)
    assert re.compile(r"xox[abposre]-|xapp-\d").search(source) is None
    assert [name for name in ("subprocess", "urllib", "requests", "socket") if name in source] == []


class _M1ChannelOnly(publish.SlackPublish):  # M1 — thread_ts 없이 채널에 게시
    def _post(self, key, command, body, seat, gen, owner, via=publish.POSTED, prior=0):
        return super()._post(key._replace(root=None), command, body, seat, gen, owner, via=via, prior=prior)


class _M2IgnoreWait(publish.SlackPublish):  # M2 — Retry-After 무시(즉시 재시도)
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **dict(kwargs, sleep=None))  # 기다리지 않는다


class _M2RetryTwice(publish.SlackPublish):  # M2 — 재시도 2회(세 번째 시도)
    MAX_POSTS = 3


class _M3AutoResend(publish.SlackPublish):  # M3 — 응답 유실을 실패로 보고 자동 재송
    def reply(self, key, command, body, seat=None, gen=None):
        verdict = super().reply(key, command, body, seat, gen)
        if verdict["state"] == publish.UNCERTAIN:
            return self._post(key, command, body, seat, gen, None, prior=verdict["post_calls"])
        return verdict


class _M4UndecidableAsAbsent(publish.SlackPublish):  # M4 — «판정 불가»(예외 갈래)를 «없음 확인» 으로
    def _lookup(self, entry):
        answer = super()._lookup(entry)
        return publish.ABSENT if answer == publish.UNDECIDABLE else answer


class _M4bReturnAsAbsent(publish.SlackPublish):  # NG② — «반환» 판정 불가를 없음 확인으로
    def _lookup(self, entry):
        return publish.FOUND if super()._lookup(entry) == publish.FOUND else publish.ABSENT


class _M5NameOnly(publish.SlackPublish):  # M5 — owner 세대(gen) 대조를 뺀다
    def _refusal(self, key, command, seat, gen):
        now = self.binding.get(key)
        if now is None or not now.open:
            return self._refused(key, command, "reply_refused", reason="닫히면 담당 없음 = 답 거절")
        return None if seat == now.seat else self._refused(key, command, "stale_owner", owner=now.owner)


class _M6Overwrite(binding.ThreadBinding):  # M6 — 두 번째 bind 가 덮어쓰기
    def bind(self, key, seat):
        now = self.get(key)
        return self._write(key, seat, 1 if now is None else now.gen, True, binding.BOUND)


class _M7AllowClosed(publish.SlackPublish):  # M7 — 닫힌 binding 의 답을 허용
    def _refusal(self, key, command, seat, gen):
        now = self.binding.get(key)
        return None if now is None or not now.open else super()._refusal(key, command, seat, gen)


class _M8PostFirst(publish.SlackPublish):  # M8 — 게시 의도 기록을 post 뒤로
    def reply(self, key, command, body, seat=None, gen=None):
        verdict = self._post(key, command, body, seat, gen, None)
        self._step("after_post")
        self._append({"state": publish.INTENT, "key": list(key), "command": command, "body": body,
                      "marker": publish.marker_for(key, command)})
        return verdict


class _M9NoRecheck(publish.SlackPublish):  # NG① — 재송 직전 binding 재검사를 뺀다
    def _resend(self, key, command, body, seat, gen, owner, entry):
        return self._post(key, command, body, seat, gen, owner, via=publish.RESENT, prior=entry.get("post_calls", 0))


def _crash_run(root, step, cls=""):
    return subprocess.run([sys.executable, os.path.abspath(__file__), str(root), step] + ([cls] if cls else []),
                          env=dict(os.environ, FT2_PUBLISH_CHILD="1"), capture_output=True, timeout=25)


def _child_main(argv):
    """자식 = 게시 의도 기록 직후(또는 M8 은 post 직후) 스스로 죽는다."""
    root, step = argv[0], argv[1]
    cls = _M8PostFirst if len(argv) > 2 and argv[2] == "m8" else publish.SlackPublish
    def exit_at(name):
        if name == step:
            os._exit(9)
    _binder(root).bind(_key(), SEAT_A)
    publisher, band = _publisher(root, cls=cls, on_step=exit_at)
    publisher.reply(_key(), COMMAND, "본문", SEAT_A, 1)
    return 0


if __name__ == "__main__":
    sys.exit(0 if os.environ.get("FT2_PUBLISH_CHILD") != "1" else _child_main(sys.argv[1:]))
