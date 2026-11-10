"""ft-docker-test-reap.sh — 주인(pytest pid) 죽은 «시험 라벨» 컨테이너만 `rm -f -v` (R352 · DA⑥ r1 H1~H3 교정).
가짜 docker·가짜 ps 만 쓴다 — 실 docker·실 프로세스 접촉 0 · 시험에 GIT_* 를 걸지 않는다(BOOT 25).
"""

import os
import subprocess

import pytest
from ft_git_helpers import BIN

HEX64 = "a" * 64
START = "Sat Oct 18 01:00:00 2026"
OTHER_START = "Sun Oct 19 09:00:00 2026"
OTHER_PROC = f"    1 {START}\n"   # ps 목록은 «비어 있지 않다» — 그 pid 만 없다

DOCKER_STUB = r"""#!/bin/bash
D="$FAKE_DIR"; echo "$*" >> "$D/calls"
[ -e "$D/hang" ] && exec sleep 30
case "$1" in
  ps) cat "$D/ps_out" 2>/dev/null;;
  inspect)
    id="${@: -1}"
    if [ -e "$D/inspect_$id" ]; then cat "$D/inspect_$id"
    elif [ -e "$D/inspect_fail_$id" ]; then echo "boom: daemon unreachable" >&2; exit 1
    else echo "Error: No such object: $id" >&2; exit 1; fi;;
  rm)
    id="${@: -1}"
    [ -e "$D/rm_gone_$id" ] && { echo "Error response from daemon: No such container: $id" >&2; exit 1; }
    exit "$(cat "$D/rm_rc" 2>/dev/null || echo 0)";;
esac
"""
# 시각 표시는 TZ=UTC 일 때만 정상 — 리퍼가 TZ 를 고정하지 않으면 ps_all_wrongtz 가 나온다. ps_rc 파일 = 오류 rc(출력 없음)
PS_STUB = r"""#!/bin/bash
D="$FAKE_DIR"
[ -e "$D/ps_rc" ] && exit "$(cat "$D/ps_rc")"
f="$D/ps_all"; { [ "$TZ" = UTC ] && [ "$LC_ALL" = C ]; } || f="$D/ps_all_wrongtz"
cat "$f" 2>/dev/null
"""


@pytest.fixture
def world(tmp_path):
    for name, body in (("docker", DOCKER_STUB), ("ps", PS_STUB)):
        (tmp_path / name).write_text(body)
        (tmp_path / name).chmod(0o755)
    (tmp_path / "ps_all").write_text(OTHER_PROC)
    return tmp_path


def _list(world, *rows):
    """rows = (id, name, pid, start) — docker ps 가 돌려주는 목록. 각 ID 의 inspect 는 목록과 같은 라벨 + 익명 볼륨 1개."""
    (world / "ps_out").write_text("".join(f"{i}|{n}|{pid}|{start}|sid\n" for i, n, pid, start in rows))
    for i, _n, pid, start in rows:
        (world / f"inspect_{i}").write_text(f"1|{pid}|{start}|{HEX64} named-vol\n")


def _alive(world, pid, start=START):
    (world / "ps_all").write_text(OTHER_PROC + f"  {pid} {start}\n")


def _reap(world, *args, docker=None, call_s="7"):
    env = {**os.environ, "FAKE_DIR": str(world), "FT_DOCKER": docker or str(world / "docker"), "FT_PS": str(world / "ps"), "FT_DOCKER_REAP_CALL_S": call_s}
    return subprocess.run(["bash", str(BIN / "ft-docker-test-reap.sh"), *args], capture_output=True, text=True, env=env)


def _calls(world):
    path = world / "calls"
    return path.read_text().splitlines() if path.exists() else []


def _removed(world):
    return [c for c in _calls(world) if c.startswith("rm ")]


def test_alive_owner_is_left_alone(world):
    _list(world, ("id1", "pg-1", 111, START))
    _alive(world, 111)

    r = _reap(world, "--kill")

    assert r.returncode == 0, r.stderr
    assert _removed(world) == []


def test_dead_owner_is_removed_by_id_with_volume_count(world):
    _list(world, ("id2", "pg-2", 222, START))

    r = _reap(world, "--kill")

    assert r.returncode == 0, r.stderr
    assert _removed(world) == ["rm -f -v id2"]   # ⓜ3 — 이름이 아니라 ID
    assert "컨테이너 1 제거" in r.stdout and "익명(추정) 볼륨 1" in r.stdout


def test_reused_pid_with_other_start_time_counts_as_dead(world):
    _list(world, ("id3", "pg-3", 333, START))
    _alive(world, 333, OTHER_START)   # ⓝ3 — 같은 pid 가 다른 프로세스로 살아 있음

    _reap(world, "--kill")

    assert _removed(world) == ["rm -f -v id3"]


def test_label_without_owner_pid_is_never_removed(world):
    _list(world, ("id4", "odd-1", "", ""))

    r = _reap(world, "--kill")

    assert r.returncode == 0
    assert _removed(world) == []


def test_default_is_dry_run_and_listing_filters_by_test_label(world):
    _list(world, ("id5", "pg-4", 444, START))

    r = _reap(world)

    assert r.returncode == 0 and _removed(world) == []
    assert "DRY" in r.stdout
    assert any("--filter label=byz.test=1" in c for c in _calls(world) if c.startswith("ps "))


def test_docker_missing_is_rc20_with_one_stderr_line(world):
    r = _reap(world, docker=str(world / "no-such-docker"))

    assert r.returncode == 20
    assert len(r.stderr.strip().splitlines()) == 1 and r.stderr.startswith("ERROR")


def test_docker_hang_hits_call_limit_rc20(world):
    (world / "hang").write_text("")

    r = _reap(world, "--kill", call_s="1")

    assert r.returncode == 20
    assert r.stderr.startswith("ERROR")


def test_failed_rm_is_rc20_not_silent(world):    # ⓞ3
    _list(world, ("id6", "pg-5", 555, START))
    (world / "rm_rc").write_text("1")

    r = _reap(world, "--kill")

    assert r.returncode == 20 and "pg-5" in r.stderr


# --- H1: 이름 재사용·ID 소멸 -------------------------------------------------------------------------------------------------

def test_label_changed_since_listing_is_skipped(world):    # ⓜ1 — 목록 뒤 그 ID 가 라벨 없는 컨테이너로 바뀐 경우(같은 이름 재사용 포함)
    _list(world, ("id7", "pg-7", 777, START))
    (world / "inspect_id7").write_text("||| \n")

    r = _reap(world, "--kill")

    assert r.returncode == 0 and _removed(world) == []
    assert "라벨이 목록 때와 다름" in r.stderr


def test_container_vanished_after_listing_is_a_clean_skip(world):    # ⓜ2 / ⓞ2
    _list(world, ("id8", "pg-8", 888, START))
    (world / "inspect_id8").unlink()   # inspect → «No such object»

    r = _reap(world, "--kill")

    assert r.returncode == 0 and _removed(world) == []
    assert "컨테이너 0 제거" in r.stdout


def test_rm_that_finds_nothing_is_a_clean_skip(world):    # ⓞ2 — inspect 뒤 --rm 으로 사라져 rm 이 «No such container»
    _list(world, ("id9", "pg-9", 999, START))
    (world / "rm_gone_id9").write_text("")

    r = _reap(world, "--kill")

    assert r.returncode == 0 and "컨테이너 0 제거" in r.stdout


# --- H2: 주인 조회 실패 ≠ 죽음 · 시각 비교 고정 --------------------------------------------------------------------------

def test_ps_error_is_unknown_owner_rc20_and_nothing_removed(world):    # ⓝ1
    _list(world, ("id10", "pg-10", 111, START))
    (world / "ps_rc").write_text("1")

    r = _reap(world, "--kill")

    assert r.returncode == 20 and _removed(world) == []
    assert len(r.stderr.strip().splitlines()) == 1 and r.stderr.startswith("ERROR")


def test_empty_ps_listing_is_unknown_owner_not_death(world):
    _list(world, ("id11", "pg-11", 111, START))
    (world / "ps_all").write_text("")

    r = _reap(world, "--kill")

    assert r.returncode == 20 and _removed(world) == []


def test_start_time_compare_is_pinned_to_utc_and_c_locale(world):    # ⓝ2 — 리퍼가 TZ·LC_ALL 을 고정하지 않으면 시각 문자열이 달라져 «재사용» 으로 오판
    _list(world, ("id12", "pg-12", 121, START))
    _alive(world, 121)
    (world / "ps_all_wrongtz").write_text(OTHER_PROC + f"  121 {OTHER_START}\n")

    r = _reap(world, "--kill", )

    assert r.returncode == 0 and _removed(world) == []


def test_empty_start_label_is_skipped_with_warn(world):    # ⓝ4
    _list(world, ("id13", "pg-13", 131, ""))

    r = _reap(world, "--kill")

    assert r.returncode == 0 and _removed(world) == []
    assert "WARN" in r.stderr and "byz.owner_start" in r.stderr


# --- H3: inspect 실패 은폐 · CALL_S 검증 ----------------------------------------------------------------------------------

def test_inspect_error_is_rc20_and_not_removed(world):    # ⓞ1
    _list(world, ("id14", "pg-14", 141, START))
    (world / "inspect_id14").unlink()
    (world / "inspect_fail_id14").write_text("")

    r = _reap(world, "--kill")

    assert r.returncode == 20 and _removed(world) == []
    assert "inspect 실패" in r.stderr


@pytest.mark.parametrize("value", ["30", "0", "abc"])
def test_call_limit_is_clamped_to_seven_with_warn(world, value):    # ⓞ4
    _list(world, ("id15", "pg-15", 151, START))

    r = _reap(world, "--kill", call_s=value)

    assert r.returncode == 0 and _removed(world) == ["rm -f -v id15"]
    assert "WARN" in r.stderr and "7 사용" in r.stderr
