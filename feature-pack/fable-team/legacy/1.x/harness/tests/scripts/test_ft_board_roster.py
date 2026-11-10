"""R132a — 현역 세대 선정 (`ft_board_roster.select`) 회귀 ①~⑥ (제안서 §7-7). 실제 tmux·seat-resume 조회 0 — 임시 폴더만."""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[3] / "harness" / "bin"))
from ft_board_roster import select  # noqa: E402


def test_1_old_generation_alone_without_pointer_is_unknown(tmp_path: Path) -> None:
    seats = {"_master": "t-m#1", "t-m#1": {"role": "master"}, "t-da#0": {"role": "da"}}
    active, unknown = select(seats, {"t-m#1", "t-da#0"}, tmp_path)
    assert active == ["t-m#1"]
    assert "t-da#0" in unknown and unknown["t-da#0"] == "확인 불가(현역 근거 없음: 포인터·은퇴 표시 0 · 생존 t-da#0)"


def test_2_replaced_by_is_excluded_not_shown(tmp_path: Path) -> None:
    seats = {"_master": "t-m#1", "t-m#1": {"role": "master"}, "t-da#0": {"role": "da", "_replaced_by": "t-da#1"}}
    active, unknown = select(seats, {"t-m#1", "t-da#0"}, tmp_path)
    assert active == ["t-m#1"] and unknown == {}


def test_3_pointer_target_is_active_and_same_role_others_excluded(tmp_path: Path) -> None:
    seats = {"_arch": "t-arch#46", "t-arch#5": {"role": "arch"}, "t-arch#46": {"role": "arch"}}
    active, unknown = select(seats, {"t-arch#5", "t-arch#46"}, tmp_path)
    assert active == ["t-arch#46"] and unknown == {}


def test_4_two_generations_without_pointer_are_both_unknown(tmp_path: Path) -> None:
    seats = {"t-da#0": {"role": "da"}, "t-da#1": {"role": "da"}}
    active, unknown = select(seats, {"t-da#0", "t-da#1"}, tmp_path)
    assert active == []
    assert unknown["t-da#0"] == unknown["t-da#1"] == "확인 불가(현역 근거 없음: 포인터·은퇴 표시 0 · 생존 t-da#0, t-da#1)"


def test_5_nano_lineage_single_zero_is_active_but_not_with_gen_one(tmp_path: Path, monkeypatch) -> None:
    monkeypatch.setenv("FT_NANO_PREFIX", "t-temp-")
    seats = {"t-temp-a#0": {}, "t-n-b#0": {"role": "nano"}, "t-n-c#0": {"role": "nano"}, "t-n-c#1": {"role": "nano"}}
    active, unknown = select(seats, set(seats), tmp_path)
    assert active == ["t-n-b#0", "t-temp-a#0"]
    assert sorted(unknown) == ["t-n-c#0", "t-n-c#1"]


def test_6_seat_resume_record_excludes_row(tmp_path: Path) -> None:
    (tmp_path / "t-da#0.json").write_text("{}", encoding="utf-8")
    seats = {"t-da#0": {"role": "da"}, "t-da#1": {"role": "da"}}
    active, unknown = select(seats, {"t-da#0", "t-da#1"}, tmp_path)
    assert "t-da#0" not in active and "t-da#0" not in unknown
    assert unknown == {"t-da#1": "확인 불가(현역 근거 없음: 포인터·은퇴 표시 0 · 생존 t-da#1)"}


def test_rule1_beats_pointer_and_dead_rows_are_ignored(tmp_path: Path) -> None:
    """포인터가 가리키는 행이라도 `_replaced_by` 가 있으면 제외(위에서 걸리면 끝). tmux 에 없는 행은 어디에도 안 나온다."""
    seats = {"_arch": "t-arch#1", "t-arch#1": {"role": "arch", "_replaced_by": "t-arch#2"}, "t-arch#2": {"role": "arch"},
             "t-gone#0": {"role": "nano"}}
    active, unknown = select(seats, {"t-arch#1", "t-arch#2"}, tmp_path)
    assert active == [] and unknown == {}


def test_other_role_pointer_and_non_row_values_are_ignored(tmp_path: Path) -> None:
    """`_da` 포인터는 role=da 행에만 걸린다. `_hil_route`·`_label` 처럼 행 이름이 아닌 값은 포인터가 아니다."""
    seats = {"_da": "t-da#1", "_hil_route": "other-master#9", "_label": "x", "t-da#0": {"role": "da"}, "t-da#1": {"role": "da"}}
    active, unknown = select(seats, {"t-da#0", "t-da#1"}, tmp_path)
    assert active == ["t-da#1"] and unknown == {}


def test_10_1_stopped_old_generation_in_pointer_lineage_is_excluded(tmp_path: Path) -> None:
    """DA⑥ I2 반례 — `_da` 포인터 현역(role da)과 같은 계보의 닫힌 옛 세대(role stopped)는 살아 있어도 현역이 아니다."""
    seats = {"_da": "t-da#1", "t-da#1": {"role": "da"}, "t-da#0": {"role": "stopped"}}
    active, unknown = select(seats, {"t-da#0", "t-da#1"}, tmp_path)
    assert active == ["t-da#1"] and unknown == {}


def test_10_2_pointer_target_stays_active_even_if_stopped(tmp_path: Path) -> None:
    """포인터가 가리키는 행은 role 이 stopped/stop-ready 여도 현역 — 멈춘 현재 좌석(칸은 고정 문구)."""
    seats = {"_da": "t-da#1", "t-da#1": {"role": "stopped"}, "t-da#0": {"role": "da"}}
    active, unknown = select(seats, {"t-da#0", "t-da#1"}, tmp_path)
    assert active == ["t-da#1"] and unknown == {}


def test_10_3_stopped_row_without_pointer_is_unknown(tmp_path: Path) -> None:
    """포인터 밖 stopped/stop-ready 는 일반 행과 같이 규칙 1~3 — 계보에 근거가 없으면 확인 불가(나노 #0 예외만 그대로)."""
    seats = {"t-c#0": {"role": "stopped"}, "t-r#0": {"role": "stop-ready"}, "t-n#0": {"role": "nano"}}
    active, unknown = select(seats, set(seats), tmp_path)
    assert active == ["t-n#0"] and sorted(unknown) == ["t-c#0", "t-r#0"]


def test_non_role_key_never_promotes_a_stopped_row(tmp_path: Path) -> None:
    """`_hil_route` 처럼 role 이름이 아닌 키가 stopped 행을 가리켜도 포인터가 아니다."""
    seats = {"_hil_route": "t-c#0", "t-c#0": {"role": "stopped"}}
    active, unknown = select(seats, set(seats), tmp_path)
    assert active == [] and sorted(unknown) == ["t-c#0"]
