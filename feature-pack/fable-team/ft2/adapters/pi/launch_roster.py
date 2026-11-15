"""r1983 ft2 launch 가 연 좌석 → 팀 명부(r2058 L10 = `roster_path(root, team)` 한 함수 · seats-<팀>.json → 없고 v65 면 seats.json) 에 행 1개(tmux 살아 있음 «뒤» 1회 · launch.py finish 만 부른다).

정의는 `core/roster.py` 한 곳 — 이 파일은 그것을 경로로 묶어 같은 이름 `roster_path` 로 낸다(코어는 어댑터를 읽지 않는다 · L11).

꼴 = 1.x ft_roster_lib load/dump 와 같다(순서 보존 읽기 · indent 2 · tmp → fsync → 권한 복사 → replace).
ft2 launch 끼리는 팀 런타임 `launch/roster.lock` 하나로 읽기~replace 를 묶는다 · 1.x writer(ft-seat-retire 등)와 동시 갱신은 보증 밖.
이미 행 있음 = 바이트 손 0 · 명부 없음·손상·꼴 아님·쓰기 실패 = 생성·쓰기 0 + «판정 불가 명부» 1구(stderr 1줄 · launch 결과는 그대로).
"""
import collections
import importlib.util
import fcntl
import json
import os
import shutil
import sys

_HERE = os.path.dirname(os.path.abspath(__file__))


def _load(path, alias):
    spec = importlib.util.spec_from_file_location(alias, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


roster_path = _load(os.path.join(os.path.dirname(os.path.dirname(_HERE)), "core", "roster.py"), "ft2_launch_roster_core").roster_path   # L11 정의 1곳 = core/roster.py · 어댑터가 경로로 묶어 같은 이름으로 낸다(코어 → 어댑터 방향 0)


def index_of(root, row, work):
    """card_row(repo, ref, 카드 폴더) → 진행 카드 경로(root 기준 상대) · 표 행 없음 = None."""
    return os.path.relpath(os.path.join(row[0], row[2], "진행", work + ".md"), root) if row else None


def dump(path, data):
    """1.x ft_roster_lib.dump 와 같은 쓰기 — 쓰다 죽어도 원본 무손상."""
    tmp = path + ".tmp-" + str(os.getpid())
    with open(tmp, "w", encoding="utf-8") as handle:
        json.dump(data, handle, ensure_ascii=False, indent=2)
        handle.write("\n")
        handle.flush()
        os.fsync(handle.fileno())
    shutil.copymode(path, tmp)
    os.replace(tmp, path)


def write_row(path, holder, row):
    """잠금 안에서 1회 — (결과 1구). 행 = holder 키 · 이미 있으면 손 0."""
    try:
        with open(path, encoding="utf-8") as handle:
            data = json.load(handle, object_pairs_hook=collections.OrderedDict)
    except FileNotFoundError:
        return "판정 불가 명부 없음 %s — 생성 0" % path
    except (OSError, ValueError) as exc:
        return "판정 불가 명부 못 읽음 %s — 쓰기 0 · %s" % (path, str(exc).splitlines()[0][:120])
    if not isinstance(data, dict):
        return "판정 불가 명부 꼴 아님 %s — 쓰기 0" % path
    if holder in data:
        return "행 있음 — 손 0"
    data[holder] = row
    dump(path, data)
    return "행 추가"


def enroll(env, worktree, card, lock_dir):
    """launch 성공 뒤 1회 → 결과 1구(launch 결과 dict 의 roster 칸) · 판정 불가 = stderr 에도 1줄."""
    root, team, holder = env["FT2_ROOT"], env["FT2_TEAM"], env["FT2_HOLDER"]
    row = collections.OrderedDict((("role", "nano"), ("agent", "pi"), ("work", env["FT2_WORK"]), ("attempt", env["FT2_ATTEMPT"]),
                                   ("index", index_of(root, card, env["FT2_WORK"])), ("worktree", worktree), ("source", "ft2-launch")))
    path = roster_path(root, team) or os.path.join(root, ".fable-team", "seats-%s.json" % team)   # L10 명부 찾기 한 함수(v65 = seats.json) · 둘 다 없으면 지금 꼴 경로 = write_row 가 «명부 없음» 1구(생성 0)
    try:
        with open(os.path.join(lock_dir, "roster.lock"), "a") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            note = write_row(path, holder, row)
    except OSError as exc:
        note = "판정 불가 명부 쓰기 실패 %s — %s" % (path, str(exc).splitlines()[0][:120])
    if note.startswith("판정 불가"):
        sys.stderr.write(note + "\n")
    return note
