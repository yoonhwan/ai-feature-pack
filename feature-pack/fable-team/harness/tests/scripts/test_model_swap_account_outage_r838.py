"""r838 — 계정 전체 한도 때 자동 교대 보류 1통 · 좌석 «교대 불가» = (계보 · 이유) 키 1통 · 쪽지 머리 [HIL] 0 · api-outage 장애 중 발신 0 (ⓐⓑⓒⓖⓗⓙ).

test_model_swap 의 임시 루트·가짜 tmux·mbox·successor-open 그대로 — 실 좌석·실 mbox 0 · 외부 호출 0.
"""

import json
from pathlib import Path

from real_state_guard import guard_begin_module  # noqa: E402,F401  r541: 실 상태 지문 + git 밖 cwd(모듈 autouse)
from test_model_swap import ARCH, MASTER, N, PLANNER, Fx, _err, _iso, _limit, _ok

PM = "byz-x-pm-claude#4"
HOLD_HEAD = "[자동 교대 보류] 계정 전체 한도 — 정지 좌석 3 · 교대 0 · 풀리면 ft_api_outage 재개"


def _fx(tmp: Path) -> Fx:
    fx = Fx(tmp)
    fx.seats["_pm"], fx.seats[PM] = PM, {"role": "pm", "agent": "claude", "model": "claude-sonnet-5-5[1m]"}
    fx.sessions.append(PM)
    return fx


def _all_limited(fx: Fx, tag: str, at: int) -> None:  # 역할 좌석 3 = 모델 3종 다 한도
    fx.add(ARCH, _err(f"a{tag}", at, _limit("claude-fable-5-1")))
    fx.add(MASTER, _err(f"m{tag}", at - 10, _limit("claude-opus-5-5")))
    fx.add(PM, _err(f"p{tag}", at - 20, _limit("claude-sonnet-5-5")))


def _outage_state(fx: Fx, status: str, since: int) -> None:
    d = fx.ft / "state" / "api-outage"
    d.mkdir(parents=True, exist_ok=True)
    _ = (d / "seats.json").write_text(json.dumps({"status": status, "resumed": [], "since": since}), encoding="utf-8")


def _heads(fx: Fx) -> list[str]:
    return [m[2] for m in fx.mail()]


def test_a_account_limit_one_hold_note_no_swap_no_per_seat(tmp_path):  # ⓐ ⓗ
    fx = _fx(tmp_path)
    _all_limited(fx, "1", N - 240)
    r = fx.run()
    assert r.returncode == 0, r.stderr
    assert "HOLD" in r.stdout and "PLAN" not in r.stdout and not fx.argv.exists()
    assert [(m[0], m[2]) for m in fx.mail()] == [(PLANNER, HOLD_HEAD)]
    _all_limited(fx, "2", N + 30)  # 같은 장애 · 좌석이 다시 시도해 새 uuid
    assert fx.run(N + 300).returncode == 0
    assert _heads(fx) == [HOLD_HEAD] and not any(h.startswith("[HIL]") for h in _heads(fx))


def test_b_two_limited_but_normal_after_is_regular_swap(tmp_path):  # ⓑ(나) «정상 0» 이 빠지면 보류로 바뀐다
    fx = _fx(tmp_path)
    fx.add(ARCH, _err("a1", N - 240, _limit("claude-fable-5-1")))
    fx.add(MASTER, _err("m1", N - 250, _limit("claude-opus-5-5")))
    fx.add("byz-x-nano-b#0", _ok("s1", N - 30, "claude-sonnet-5-5"))
    r = fx.run()
    assert r.returncode == 0 and "HOLD" not in r.stdout
    assert f"PLAN swap {ARCH} -> byz-x-arch-claude#8 model claude-fable-5-1 -> claude-sonnet-5-5[1m]" in r.stdout
    assert not any(h.startswith("[자동 교대 보류]") for h in _heads(fx))


def test_c_recovery_closes_then_new_outage_new_note(tmp_path):  # ⓒ
    fx = _fx(tmp_path)
    _all_limited(fx, "1", N - 240)
    assert fx.run().returncode == 0 and fx.run(N + 60).returncode == 0
    assert _heads(fx) == [HOLD_HEAD]
    for seat, model in ((ARCH, "claude-fable-5-1"), (MASTER, "claude-opus-5-5"), (PM, "claude-sonnet-5-5")):
        fx.add(seat, _ok(f"ok-{seat}", N + 120, model))
    r = fx.run(N + 180)
    assert r.returncode == 0 and "HOLD" not in r.stdout and _heads(fx) == [HOLD_HEAD]
    _all_limited(fx, "3", N + 400)
    assert fx.run(N + 700).returncode == 0
    assert _heads(fx) == [HOLD_HEAD, HOLD_HEAD] and not fx.argv.exists()


def test_g_same_seat_no_fallback_one_note_per_block_key(tmp_path):  # ⓖ ⓗ
    fx = Fx(tmp_path)

    def block(tag: str, at: int) -> None:  # 대체 모델(opus·sonnet)도 나노에서 한도 · 역할 정지 = ARCH 1
        fx.add(ARCH, _err(f"a{tag}", at, _limit()))
        fx.add("byz-x-nano-a#0", _err(f"o{tag}", at - 10, _limit("claude-opus-5-5")))
        fx.add("byz-x-nano-b#0", _err(f"s{tag}", at - 20, _limit("claude-sonnet-5-5")))

    block("1", N - 240)
    assert f"HIL {ARCH} 대체 모델 없음" in fx.run().stdout
    block("2", N + 50)  # 같은 막힘 · 새 uuid
    assert f"HIL {ARCH} 대체 모델 없음" in fx.run(N + 300).stdout
    stuck = [h for h in _heads(fx) if h.startswith("[자동 교대 불가]")]
    assert len(stuck) == 1 and stuck[0].startswith(f"[자동 교대 불가] {ARCH} · 대체 모델 없음") and "필요한 결정" in stuck[0]
    fx.add(ARCH, _ok("a-ok", N + 400, "claude-fable-5-1"))
    assert fx.run(N + 450).returncode == 0  # 풀림 → 키 삭제
    block("3", N + 500)
    assert fx.run(N + 800).returncode == 0
    assert len([h for h in _heads(fx) if h.startswith("[자동 교대 불가]")]) == 2
    assert not any(h.startswith("[HIL]") for h in _heads(fx)) and not fx.argv.exists()


def test_j_api_outage_on_sends_nothing(tmp_path):  # ⓙ
    fx = _fx(tmp_path)
    _outage_state(fx, "OUTAGE", N - 260)
    _all_limited(fx, "1", N - 240)
    for now in (N, N + 300):
        r = fx.run(now)
        assert r.returncode == 0 and "HOLD" in r.stdout and "PLAN" not in r.stdout
    assert fx.mail() == [] and not fx.argv.exists()


def test_j2_api_outage_but_other_model_normal_is_single_model_swap(tmp_path):  # ⓙ 보정 — 장애 표식이 모델 하나 한도여도 켜진다 · 그 뒤 정상이 있으면 계정 한도 아님
    fx = Fx(tmp_path)
    _outage_state(fx, "OUTAGE", N - 240)
    fx.add(ARCH, _err("a1", N - 240, _limit()))
    fx.add(MASTER, _ok("m1", N - 30, "claude-opus-5-5"))
    r = fx.run()
    assert r.returncode == 0 and "HOLD" not in r.stdout
    assert f"PLAN swap {ARCH} -> byz-x-arch-claude#8 model claude-fable-5-1 -> claude-opus-5-5[1m]" in r.stdout


def test_j3_api_outage_ok_state_is_regular_rule(tmp_path):  # ⓒ 장애 끝(OK) = 지금 규칙
    fx = Fx(tmp_path)
    _outage_state(fx, "OK", N - 240)
    fx.add(ARCH, _err("a1", N - 240, _limit()))
    assert "PLAN swap" in fx.run().stdout


# r838 r2 — 외부 DA⑥ r1 HOLD 반례 5 (REWORK-r838-r2.md) · ⓡ1~ⓡ4 = 여기 · ⓡ5 = test_successor_open.sh
def _retry(uid: str, at: int) -> list[dict[str, object]]:  # 사용자 재시도만 — 정상 assistant 0
    return [{"type": "user", "uuid": uid, "timestamp": _iso(at), "message": {"role": "user", "content": "다시"}}]


def test_r1_user_retry_only_keeps_outage_key_one_note(tmp_path):  # ⓡ1 후보 없음·재시도 기록은 장애 키를 안 지운다
    fx = _fx(tmp_path)
    _all_limited(fx, "1", N - 240)
    assert fx.run().returncode == 0 and _heads(fx) == [HOLD_HEAD]
    for seat in (ARCH, MASTER, PM):
        fx.add(seat, _retry(f"r-{seat}", N + 60))
    r = fx.run(N + 120)
    assert r.returncode == 0, r.stderr
    _all_limited(fx, "2", N + 200)
    assert fx.run(N + 420).returncode == 0
    assert _heads(fx) == [HOLD_HEAD] and not fx.argv.exists()


def test_r2_normal_then_restuck_between_checks_new_note(tmp_path):  # ⓡ2 알린 시각 뒤 정상 → 그 구간 끝 · 지금 정지 = 새 1통
    """★r912 r3 — r838 ⓡ2 의 «새 1통» 은 r912 창(10분) 밖에서만 성립한다★

    r912 가 «같은 좌석·같은 사유가 마지막 알림 뒤 10분 안에 또 정지하면 0통» 을 더했으므로,
    같은 픽스처에서 실행 시각만 바꿔 «창 안 = 1통 유지 · 창 밖 = 2통» 두 경계를 함께 본다.
    """
    fx = Fx(tmp_path)

    def block(tag: str, at: int) -> None:
        fx.add(ARCH, _err(f"a{tag}", at, _limit()))
        fx.add("byz-x-nano-a#0", _err(f"o{tag}", at - 10, _limit("claude-opus-5-5")))
        fx.add("byz-x-nano-b#0", _err(f"s{tag}", at - 20, _limit("claude-sonnet-5-5")))

    def notes() -> int:
        return len([h for h in _heads(fx) if h.startswith("[자동 교대 불가]")])

    block("1", N - 240)
    assert fx.run().returncode == 0
    fx.add(ARCH, _ok("a-ok", N + 60, "claude-fable-5-1"))  # 검사 사이 정상 → 곧 다시 정지
    block("2", N + 120)
    r = fx.run(N + 300)   # ★r912 창(10분) 안 재정지 = 알림 0통★
    assert r.returncode == 0, r.stderr
    assert notes() == 1
    r = fx.run(N + 700)   # ★창 밖(601초 이상) = 새 1통★
    assert r.returncode == 0, r.stderr
    assert notes() == 2


def test_r3_same_model_two_role_seats_is_single_model_swap(tmp_path):  # ⓡ3 같은 모델 2석 = 모델 하나 한도 → r497 교대
    fx = Fx(tmp_path)
    fx.add(ARCH, _err("a1", N - 240, _limit("claude-fable-5-1")))
    fx.add(MASTER, _err("m1", N - 250, _limit("claude-fable-5-1")))
    r = fx.run()
    assert r.returncode == 0, r.stderr
    assert "HOLD" not in r.stdout and f"PLAN swap {ARCH} -> byz-x-arch-claude#8 model claude-fable-5-1 -> claude-opus-5-5[1m]" in r.stdout
    assert not any(h.startswith("[자동 교대 보류]") for h in _heads(fx))


def test_r4_bad_api_outage_state_error_no_swap(tmp_path):  # ⓡ4 상태 모양 어긋남 = ERROR · 교대 0 · rc≠0
    for i, bad in enumerate(({"status": "OUTAGE"}, {"status": "BOGUS", "since": N - 300}, {"status": "OUTAGE", "since": 0})):
        fx = Fx(tmp_path / str(i))
        d = fx.ft / "state" / "api-outage"
        d.mkdir(parents=True)
        _ = (d / "seats.json").write_text(json.dumps(bad), encoding="utf-8")
        fx.add(ARCH, _err("a1", N - 240, _limit()))
        r = fx.run()
        assert r.returncode != 0 and "ERROR model_swap" in r.stderr and "api-outage" in r.stderr, (bad, r.stdout, r.stderr)
        assert "PLAN" not in r.stdout and not fx.argv.exists() and fx.mail() == [], bad


# r838 r3 — DA⑥ r2 HOLD 3 재설계(REWORK-r838-r3.md) · ⓡ6·ⓡ8 = 여기 · ⓡ7 = test_successor_open.sh · ⓡ8' = test_ft_api_outage.py
def _no_model(uid: str, at: int, flag: str, model: str = "") -> list[dict[str, object]]:  # 모델 응답 아닌 assistant(요약·메타)
    msg: dict[str, object] = {"content": [{"type": "text", "text": "요약"}], **({"model": model} if model else {})}
    return [{"type": "assistant", "uuid": uid, "timestamp": _iso(at), flag: True, "message": msg}]


def test_r6_seat_key_kept_on_user_retry_closed_only_by_normal_turn(tmp_path):  # ⓡ6 «교대 불가» 키 = 정상 턴만 닫음
    fx = Fx(tmp_path)

    def block(tag: str, at: int) -> None:
        fx.add(ARCH, _err(f"a{tag}", at, _limit()))
        fx.add("byz-x-nano-a#0", _err(f"o{tag}", at - 10, _limit("claude-opus-5-5")))
        fx.add("byz-x-nano-b#0", _err(f"s{tag}", at - 20, _limit("claude-sonnet-5-5")))

    stuck = lambda: len([h for h in _heads(fx) if h.startswith("[자동 교대 불가]")])  # noqa: E731
    block("1", N - 240)
    assert fx.run().returncode == 0 and stuck() == 1
    fx.add(ARCH, _retry("a-retry", N + 60))  # 사용자 재시도만 — 이번 검사에 «정지 아님»
    assert fx.run(N + 120).returncode == 0
    block("2", N + 200)
    assert fx.run(N + 420).returncode == 0 and stuck() == 1
    fx.add(ARCH, _ok("a-ok", N + 500, "claude-fable-5-1"))  # 정상 턴 1 → 닫힘
    block("3", N + 560)
    r = fx.run(N + 800)
    assert r.returncode == 0, r.stderr
    assert stuck() == 2


def test_r8_summary_or_meta_record_does_not_close_outage(tmp_path):  # ⓡ8 요약(model 없음)·메타(model 있음) = 정상 턴 아님
    fx = _fx(tmp_path)
    _all_limited(fx, "1", N - 240)
    assert fx.run().returncode == 0 and _heads(fx) == [HOLD_HEAD]
    fx.add(ARCH, _no_model("a-sum", N + 60, "isCompactSummary"))
    fx.add(MASTER, _no_model("m-meta", N + 60, "isMeta", "claude-opus-5-5"))
    fx.add(PM, _no_model("p-side", N + 60, "isSidechain", "claude-sonnet-5-5"))
    r = fx.run(N + 120)
    assert r.returncode == 0 and "PLAN" not in r.stdout and not fx.argv.exists(), r.stdout
    assert json.loads((fx.ft / "state" / "model-swap" / "state.json").read_text(encoding="utf-8"))["outage_open"] != 0
    _all_limited(fx, "2", N + 200)
    assert fx.run(N + 420).returncode == 0
    assert _heads(fx) == [HOLD_HEAD] and not fx.argv.exists()


# r838 r4 — DA⑥ r3 HOLD 2(REWORK-r838-r4.md) · 키 값 {at 알린 시각, seen 마지막 정지 본 시각} · 24시간 = seen 기준 · 살아 있는 계보 0 에도
def test_r9_day_clock_counts_from_last_seen_stuck_not_notice(tmp_path):  # ⓡ9 정지 유지로 하루 넘김 → 잠깐 소멸 → 같은 한도 복귀 = 합 1통
    fx = Fx(tmp_path)

    def block(tag: str, at: int) -> None:
        fx.add(ARCH, _err(f"a{tag}", at, _limit()))
        fx.add("byz-x-nano-a#0", _err(f"o{tag}", at - 10, _limit("claude-opus-5-5")))
        fx.add("byz-x-nano-b#0", _err(f"s{tag}", at - 20, _limit("claude-sonnet-5-5")))

    stuck = lambda: len([h for h in _heads(fx) if h.startswith("[자동 교대 불가]")])  # noqa: E731
    block("1", N - 240)
    assert fx.run().returncode == 0 and stuck() == 1
    block("2", N + 86200)  # 정상 0 · 같은 정지 유지
    assert f"HIL {ARCH}" in fx.run(N + 86401).stdout
    fx.sessions.remove(ARCH)  # 소멸
    assert fx.run(N + 86402).returncode == 0
    fx.sessions.append(ARCH)  # 복귀 · 같은 한도
    block("3", N + 86450)
    r = fx.run(N + 86650)
    assert r.returncode == 0 and f"HIL {ARCH}" in r.stdout, r.stdout + r.stderr
    assert stuck() == 1


def test_r9b_outage_key_closes_after_day_with_no_live_lineage(tmp_path):  # ⓡ9b 전 좌석 소멸 → 하루 넘음 → 새 계보 3석 한도 = 새 보류 1통(합 2)
    fx = _fx(tmp_path)
    _all_limited(fx, "1", N - 240)
    assert fx.run().returncode == 0 and _heads(fx) == [HOLD_HEAD]
    fx.sessions.clear()  # 전 좌석 소멸
    assert fx.run(N + 86500).returncode == 0
    new = {"_arch": ("byz-y-arch-claude#1", "claude-fable-5-1"), "_master": ("byz-y-master-claude#1", "claude-opus-5-5"), "_pm": ("byz-y-pm-claude#1", "claude-sonnet-5-5")}
    for role, (seat, model) in new.items():
        fx.seats[role], fx.seats[seat] = seat, {"role": role[1:], "agent": "claude", "model": model}
        fx.sessions.append(seat)
        fx.add(seat, _err(f"n-{seat}", N + 86600 - len(fx.sessions), _limit(model)))
    r = fx.run(N + 86900)
    assert r.returncode == 0 and "HOLD" in r.stdout, r.stdout + r.stderr
    assert _heads(fx) == [HOLD_HEAD, HOLD_HEAD] and not fx.argv.exists()


# r863 — 알림 키 값 손상(null · {} · "x" · []) = ERROR 1줄 + 그 키 그대로(지우기·덮어쓰기 0) · 그 실행 그 계보 알림 0
def _st(fx: Fx) -> dict[str, object]:
    return json.loads((fx.ft / "state" / "model-swap" / "state.json").read_text(encoding="utf-8"))


def _corrupt(fx: Fx, field: str, key: str, bad: object) -> None:
    st = _st(fx)
    if key:
        st[field][key] = bad  # pyright: ignore[reportIndexIssue]
    else:
        st[field] = bad
    _ = (fx.ft / "state" / "model-swap" / "state.json").write_text(json.dumps(st), encoding="utf-8")


def _errs(r) -> int:
    return len([ln for ln in r.stderr.splitlines() if ln.startswith("ERROR model_swap: 알림 키 값 깨짐")])


def _block(fx: Fx, tag: str, at: int) -> None:  # ARCH 정지 · 대체 모델(opus·sonnet)도 나노에서 한도 → «교대 불가»
    fx.add(ARCH, _err(f"a{tag}", at, _limit()))
    fx.add("byz-x-nano-a#0", _err(f"o{tag}", at - 10, _limit("claude-opus-5-5")))
    fx.add("byz-x-nano-b#0", _err(f"s{tag}", at - 20, _limit("claude-sonnet-5-5")))


def _stuck(fx: Fx) -> int:
    return len([h for h in _heads(fx) if h.startswith("[자동 교대 불가]")])


def test_k1_corrupt_blocked_value_kept_one_note(tmp_path):  # ⓐ blocked 값 손상 → 같은 정지 다음 실행 알림 합 1 · ERROR 1줄 · 값 그대로 · 생존 좌석 0 도 같음
    for i, bad in enumerate((None, {}, "x", [])):
        fx = Fx(tmp_path / str(i))
        _block(fx, "1", N - 240)
        assert fx.run().returncode == 0 and _stuck(fx) == 1
        (key,) = list(_st(fx)["blocked"])  # pyright: ignore[reportArgumentType]
        _corrupt(fx, "blocked", key, bad)
        _block(fx, "2", N + 50)
        r = fx.run(N + 300)
        assert r.returncode == 0 and _stuck(fx) == 1 and _errs(r) == 1, (bad, r.stdout, r.stderr)
        assert _st(fx)["blocked"] == {key: bad}, bad
        fx.sessions.clear()  # 생존 좌석 0
        r = fx.run(N + 360)
        assert r.returncode == 0 and _errs(r) == 1 and _st(fx)["blocked"] == {key: bad}, (bad, r.stderr)


def test_k2_corrupt_outage_open_value_kept_one_hold_note(tmp_path):  # ⓑ outage_open 값 손상 → 같은 한도 다음 실행 보류 합 1 · ERROR 1줄 · 값 그대로
    for i, bad in enumerate(({}, None, "x")):
        fx = _fx(tmp_path / str(i))
        _all_limited(fx, "1", N - 240)
        assert fx.run().returncode == 0 and _heads(fx) == [HOLD_HEAD]
        _corrupt(fx, "outage_open", "", bad)
        _all_limited(fx, "2", N + 30)
        r = fx.run(N + 300)
        assert r.returncode == 0 and "HOLD" in r.stdout and _errs(r) == 1, (bad, r.stdout, r.stderr)
        assert _heads(fx) == [HOLD_HEAD] and _st(fx)["outage_open"] == bad and not fx.argv.exists(), bad


def test_k3_corrupt_key_isolated_other_key_closes_and_notes(tmp_path):  # ⓒ 다른 계보의 손상 키가 있어도 정상 키 닫힘·알림은 지금처럼
    fx = Fx(tmp_path)
    _block(fx, "1", N - 240)
    assert fx.run().returncode == 0 and _stuck(fx) == 1
    _corrupt(fx, "blocked", "byz-y-arch-claude|대체 모델 없음(x)", None)
    fx.add(ARCH, _ok("a-ok", N + 400, "claude-fable-5-1"))
    r = fx.run(N + 450)  # 정상 키 = 닫힘
    assert r.returncode == 0 and _errs(r) == 1 and list(_st(fx)["blocked"]) == ["byz-y-arch-claude|대체 모델 없음(x)"], r.stderr  # pyright: ignore[reportArgumentType]
    _block(fx, "3", N + 500)
    r = fx.run(N + 800)
    assert r.returncode == 0 and _stuck(fx) == 2 and _errs(r) == 1, r.stdout + r.stderr


def test_k4_unencodable_value_keeps_state_file_bytes(tmp_path):  # r863 r2 — 단독 surrogate 값 → 저장 실패여도 state.json 바이트 그대로(자르고 쓰기 0)
    fx = _fx(tmp_path)
    _all_limited(fx, "1", N - 240)
    assert fx.run().returncode == 0 and _heads(fx) == [HOLD_HEAD]
    _corrupt(fx, "outage_open", "", "\ud800")
    _corrupt(fx, "blocked", "byz-y-arch-claude|대체 모델 없음(x)", "\ud800")
    path = fx.ft / "state" / "model-swap" / "state.json"
    before = path.read_bytes()
    fx.sessions.clear()  # 생존 좌석 0
    r = fx.run(N + 300)
    assert path.read_bytes() == before and "ERROR model_swap" in r.stderr, (r.returncode, r.stderr)
    assert not list(path.parent.glob("state.json.tmp-*"))  # 임시 파일 남김 0
