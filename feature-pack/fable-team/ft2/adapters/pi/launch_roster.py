"""r1983 ft2 launch 가 연 좌석 → 팀 명부 `<root>/.fable-team/seats-<팀>.json` 에 행 1개(tmux 살아 있음 «뒤» 1회 · launch.py finish 만 부른다).

꼴 = 1.x ft_roster_lib load/dump 와 같다(순서 보존 읽기 · indent 2 · tmp → fsync → 권한 복사 → replace).
ft2 launch 끼리는 팀 런타임 `launch/roster.lock` 하나로 읽기~replace 를 묶는다 · 1.x writer(ft-seat-retire 등)와 동시 갱신은 보증 밖.
이미 행 있음 = 바이트 손 0 · 명부 없음·손상·꼴 아님·쓰기 실패 = 생성·쓰기 0 + «판정 불가 명부» 1구(stderr 1줄 · launch 결과는 그대로).
"""
import collections
import fcntl
import json
import os
import shutil
import sys


def index_of(root, row, work):
    """card_row(repo, ref, 카드 폴더) → 진행 카드 경로(root 기준 상대) · 표 행 없음 = None."""
    return os.path.relpath(os.path.join(row[0], row[2], "진행", work + ".md"), root) if row else None


def roster_path(root, team):
    """r2065 E8 명부 찾기 한 함수 — `<root>/.fable-team/seats-<팀>.json` 이 있으면 그 파일 · 없고 팀이 v65 면 `seats.json` · 그 밖 = None(명부 없음).

    인자 = (루트 경로, 팀 이름) · 반환 = 절대 경로 또는 None · 못 읽는 명부는 부르는 쪽이 다음 칸으로 간다(여기서 읽지 않는다).
    부르는 곳 = keeper_report.notify(팀 명부·harness 명부) · r2065 뒤 카드(ft2-launch-failed-end L10 · Slack 깨움 재전송)도 이 함수를 쓴다.
    """
    names = ["seats-%s.json" % team] + (["seats.json"] if team == "v65" else [])   # v65 팀 명부 = seats.json(seats-v65.json 은 없다 · 실측 2026-11-16)
    for name in names:
        path = os.path.join(root, ".fable-team", name)
        if os.path.exists(path):
            return path
    return None


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
    path = os.path.join(root, ".fable-team", "seats-%s.json" % team)
    try:
        with open(os.path.join(lock_dir, "roster.lock"), "a") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            note = write_row(path, holder, row)
    except OSError as exc:
        note = "판정 불가 명부 쓰기 실패 %s — %s" % (path, str(exc).splitlines()[0][:120])
    if note.startswith("판정 불가"):
        sys.stderr.write(note + "\n")
    return note
