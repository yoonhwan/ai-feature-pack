"""r912 — «교대 불가» 알림 묶기·카운터(같은 좌석·같은 사유) 시험 ⓓⓔⓕⓖⓗ.

★r2 정정★ — 묶기(중복 억제)의 자리는 r838 blocked 게이트 그대로다(반송 r2: 창 억제를 새로 넣으면
r838 ⓡ2 «정상 뒤 재정지 = 새 1통» 이 깨진다). r912 가 더하는 것은 «시도 횟수» 기록과 꼬리뿐이고,
억제는 blocked 가 한다 — 그래서 ⓕ(dry-run)·ⓖ(손상 계보)·ⓗ(수신자 없음) 는 기준판과 같이 «안 보낸다».

픽스처 = test_model_swap.py 의 Fx(임시 루트 · 가짜 tmux/successor-open/mbox · 고정 시계). 실 tmux·실 mbox·~/.claude 조회 0.
"""

import json
import sys
from pathlib import Path

import pytest

from real_state_guard import guard_begin_module  # noqa: E402,F401  r541: 실 상태 지문 + git 밖 cwd(모듈 autouse)
from test_model_swap import ARCH, MASTER, N, PLANNER, Fx, _err, _limit, _ok

STATE = ("state", "model-swap-notify.json")


def _hil_scene(fx: Fx) -> Fx:
    """ARCH 정지 + 대체 모델 전부 정지 = «대체 모델 없음» HIL(카드 ⓓ·ⓔ 의 사유)."""
    fx.add(ARCH, _err("e1", N - 240, _limit()))
    fx.add("byz-x-nano-a#0", _err("o1", N - 300, _limit("claude-opus-5-5")))
    fx.add("byz-x-nano-b#0", _err("s1", N - 300, _limit("claude-sonnet-5-5")))
    return fx


def _hil_mail(fx: Fx) -> list[str]:
    return [m[2] for m in fx.mail() if m[2].startswith("[자동 교대 불가]")]


KEY = f"{ARCH.rsplit('#', 1)[0]}|대체 모델 없음(claude-fable-5-1 · model-fallback.tsv 끝)"   # 키 = 계보|이유


def _notify(fx: Fx) -> dict[str, dict[str, int]]:
    return json.loads(fx.ft.joinpath(*STATE).read_text(encoding="utf-8"))


def test_d_same_seat_same_reason_three_times_in_ten_minutes_is_one_mail(tmp_path):  # ⓓ
    fx = _hil_scene(Fx(tmp_path))
    for now in (N, N + 60, N + 120):
        r = fx.run(now)
        assert r.returncode == 0, r.stderr
        assert f"HIL {ARCH} 대체 모델 없음" in r.stdout   # 판정 자체는 매번 돈다(조용히 사라진 알림 0)
    assert len(_hil_mail(fx)) == 1 and fx.mail()[0][0] == PLANNER   # 10분 안 3번 → 1통(r838 blocked 게이트 + r912 카운터)
    assert _notify(fx) == {KEY: {"last": N, "n": 3}}   # 보낸 뒤 시도 2번 더 = 횟수 3 · 보낸 시각 그대로


def _restuck(fx: Fx) -> None:
    """r838 ⓡ2 꼴 — 알림 뒤 «정상 1턴»(blocked 닫힘) → 3분 뒤 다시 정지 · 대체 후보도 창 안 정지."""
    fx.add(ARCH, _ok("a-ok", N + 150, "claude-fable-5-1"))
    fx.add(ARCH, _err("e2", N + 180, _limit()))   # 재정지 — 실행 시각은 «정지 3분» 을 넘겨야 교대 판정이 돈다
    fx.add("byz-x-nano-a#0", _err("o2", N + 370, _limit("claude-opus-5-5")))   # 대체 후보도 «창 안 정지» 여야 HIL
    fx.add("byz-x-nano-b#0", _err("s2", N + 370, _limit("claude-sonnet-5-5")))


def test_d2_recovery_then_restuck_window_boundary(tmp_path):  # ⓓ' 회복→600초 안 재정지 = 0통 · 601초 = 1통(경계 양쪽)
    fx = _hil_scene(Fx(tmp_path))
    assert fx.run(N).returncode == 0 and len(_hil_mail(fx)) == 1
    _restuck(fx)
    r = fx.run(N + 599)   # 창(10분) 안 — 같은 좌석·같은 사유 = 알림 0통 · 횟수만
    assert r.returncode == 0, r.stderr
    assert len(_hil_mail(fx)) == 1, _hil_mail(fx)
    assert _notify(fx) == {KEY: {"last": N, "n": 2}}   # 보낸 시각 그대로 · 시도 2
    r = fx.run(N + 601)   # 창 밖 1초 — 새 1통 + 직전 창 횟수 꼬리
    assert r.returncode == 0, r.stderr
    hil = _hil_mail(fx)
    assert len(hil) == 2 and hil[1].endswith("· 직전 10분 2회"), hil
    assert _notify(fx) == {KEY: {"last": N + 601, "n": 1}}


def test_f_dry_run_sends_nothing(tmp_path):  # ⓕ 기준판과 같은 결과 — dry-run 은 mbox 를 부르지 않는다(반송 r2 ② 뒤집힘 방지)
    fx = _hil_scene(Fx(tmp_path))
    r = fx.run(N, "--dry-run")
    assert r.returncode == 0 and f"HIL {ARCH} 대체 모델 없음" in r.stdout and fx.mail() == []


def test_g_corrupt_blocked_lineage_sends_nothing(tmp_path):  # ⓖ r863 손상 계보 = 그 계보 알림 0(기준판 그대로)
    fx = _hil_scene(Fx(tmp_path))
    assert fx.run().returncode == 0 and len(_hil_mail(fx)) == 1
    sp = fx.ft / "state" / "model-swap" / "state.json"
    st = json.loads(sp.read_text(encoding="utf-8"))
    st["blocked"][KEY] = None   # 손상값
    _ = sp.write_text(json.dumps(st), encoding="utf-8")
    r = fx.run(N + 60)
    assert r.returncode == 0 and "ERROR model_swap: 알림 키 값 깨짐" in r.stderr
    assert len(_hil_mail(fx)) == 1   # 안 보냄(기준판 그대로)


def test_h_no_recipient_sends_nothing(tmp_path):  # ⓗ 수신자 없음(_master·_hil_route 0) = 안 보낸다(기준판 그대로)
    fx = _hil_scene(Fx(tmp_path))
    fx.seats.pop("_hil_route")
    fx.seats.pop("_master")
    r = fx.run()
    assert r.returncode == 0 and f"HIL {ARCH} 대체 모델 없음" in r.stdout and fx.mail() == []


def test_i_r912_counter_counts_attempts_that_were_suppressed(tmp_path):  # ⓓ 의 «횟수 3» 부기(안 보낸 시도도 센다)
    fx = _hil_scene(Fx(tmp_path))
    assert fx.run(N).returncode == 0 and len(_hil_mail(fx)) == 1
    assert _notify(fx) == {KEY: {"last": N, "n": 1}}          # 보냈다 → 시각 N · 횟수 1부턴
    assert fx.run(N + 60, "--dry-run").returncode == 0 and len(_hil_mail(fx)) == 1
    assert _notify(fx) == {KEY: {"last": N, "n": 2}}          # 창(10분) 안 반복 → 시각 그대로 · 횟수만 오른다
    assert fx.run(N + 120).returncode == 0 and len(_hil_mail(fx)) == 1
    assert _notify(fx) == {KEY: {"last": N, "n": 3}}


def test_e_different_seats_same_reason_each_get_a_mail(tmp_path):  # ⓔ 다른 좌석 = 묶기 0
    fx = Fx(tmp_path, reach=False)   # 골 원문 출처 0 → HIL «골 원문 출처 없음»
    fx.add(ARCH, _err("e1", N - 240, _limit()))                      # 같은 모델 2좌석 = 계정 전체 한도 판정(r838)을 피한다
    fx.add(MASTER, _err("m1", N - 240, _limit("claude-fable-5-1")))
    r = fx.run()
    assert r.returncode == 0, r.stderr
    hil = _hil_mail(fx)
    assert len(hil) == 2 and {m[0] for m in fx.mail()} == {PLANNER}
    assert any(ARCH in b for b in hil) and any(MASTER in b for b in hil)


def test_e2_successful_swap_notice_is_never_coalesced(tmp_path):  # ⓔ 실제 교대 성공 [자동 교대] 는 묶지 않는다
    fx = Fx(tmp_path)
    fx.add(ARCH, _err("e1", N - 240, _limit()))
    assert fx.run().returncode == 0
    n1 = len([m for m in fx.mail() if m[2].startswith("[자동 교대]")])
    assert n1 == 2   # master + hil_route 각각
    assert not (fx.ft.joinpath(*STATE)).exists()   # 교대 성공 경로는 묶기 상태를 쓰지 않는다


def test_state_file_broken_sends_anyway_with_warn(tmp_path):  # 상태 파일 고장 = 그냥 보낸다(조용히 안 보냄 0)
    fx = _hil_scene(Fx(tmp_path))
    p: Path = fx.ft.joinpath(*STATE)
    p.parent.mkdir(parents=True, exist_ok=True)
    _ = p.write_text("{broken", encoding="utf-8")
    r = fx.run()
    assert r.returncode == 0, r.stderr
    assert "WARN model_swap: 알림 상태 못 읽음" in r.stderr and len(_hil_mail(fx)) == 1


def test_state_file_unreadable_sends_anyway_with_warn(tmp_path):  # 읽기 실패 = 그냥 보낸다 + WARN(조용히 안 보냄 0)
    fx = _hil_scene(Fx(tmp_path))
    p: Path = fx.ft.joinpath(*STATE)
    p.parent.mkdir(parents=True, exist_ok=True)
    p.mkdir()   # 파일 자리에 디렉터리를 둬 «읽기 실패»(EISDIR)를 만든다
    r = fx.run()
    assert r.returncode == 0, r.stderr
    assert "WARN model_swap: 알림 상태 못 읽음" in r.stderr and len(_hil_mail(fx)) == 1


def test_i_first_send_fails_then_next_tick_sends_again(tmp_path):  # ⓘ 반송 r4 ② 첫 send rc3 = 저장 0 → 다음 틱(+60) 1통
    fx = _hil_scene(Fx(tmp_path))
    fx._fake("mbox", "exit 3")   # 첫 발신 거절(mbox rc3)
    r = fx.run(N)
    assert r.returncode == 1 and "ERROR model_swap: mbox send" in r.stderr, r.stderr
    assert _hil_mail(fx) == [] and not (fx.ft.joinpath(*STATE)).exists()   # 보낸 것처럼 저장하지 않는다
    fx._fake("mbox", f'echo "$2|$3|$4" >> "{fx.log}"')   # 다음 틱 = 정상 발신
    r = fx.run(N + 60)
    assert r.returncode == 0, r.stderr
    assert len(_hil_mail(fx)) == 1   # ★창(10분) 안인데도 1통★ — 거절된 발신은 «보낸 것» 이 아니다
    assert _notify(fx) == {KEY: {"last": N + 60, "n": 1}}


def test_j_window_save_failure_sends_anyway_with_warn(tmp_path, monkeypatch, capsys):  # ⓙ 창 안 저장 실패 = 그냥 보냄(침묵 0)
    sys.path.insert(0, str(Path(__file__).resolve().parents[3] / "harness" / "bin"))
    import ft_model_swap_account as acc_mod

    def boom(p, o):
        raise OSError("boom")

    monkeypatch.setattr(acc_mod, "write_atomic", boom)
    acc = acc_mod.Account.__new__(acc_mod.Account)
    acc.ft, acc.now = tmp_path / ".fable-team", N
    p: Path = acc.ft.joinpath(*STATE)
    p.parent.mkdir(parents=True, exist_ok=True)
    _ = p.write_text(json.dumps({KEY: {"last": N - 60, "n": 1}}), encoding="utf-8")   # 창(10분) 안 재정지
    assert acc.notify_tail(KEY, True) == (True, "")   # 저장이 안 되면 «안 보냄» 판정을 믿지 않는다 → 1통
    assert "WARN model_swap: 알림 상태 저장 실패" in capsys.readouterr().err


def test_j2_send_ok_then_save_failure_still_counts_as_sent(tmp_path, monkeypatch, capsys):  # 보낸 뒤 저장 실패 = WARN 만(발신 되돌리기 0)
    sys.path.insert(0, str(Path(__file__).resolve().parents[3] / "harness" / "bin"))
    import ft_model_swap_account as acc_mod

    def boom(p, o):
        raise OSError("boom")

    acc = acc_mod.Account.__new__(acc_mod.Account)
    acc.ft, acc.now = tmp_path / ".fable-team", N
    assert acc.notify_tail(KEY, True) == (True, "")   # 첫 알림 = 창 없음 · 저장은 send 뒤로 미룸
    monkeypatch.setattr(acc_mod, "write_atomic", boom)
    acc.notify_sent(KEY)   # send rc0 뒤 저장 — 실패해도 예외 없이 WARN 만
    assert "WARN model_swap: 알림 상태 저장 실패" in capsys.readouterr().err


@pytest.mark.parametrize("name", ["ft_model_swap.py", "ft_model_swap_account.py"])
def test_kit_pair_identical(name):  # 칸 3 «짝 사본 kit cmp0»
    here = Path(__file__).resolve().parents[3] / "harness"
    assert (here / "bin" / name).read_bytes() == (here / "kit" / "fable-team" / "bin" / name).read_bytes(), name
