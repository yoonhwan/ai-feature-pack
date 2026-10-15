"""ft_key_rotate_io.py — 키 교체 도구의 파일 계층: 활성 줄 파싱 · 원자 교체 · 백업 · 되돌림 (R195). 값은 어디에도 출력하지 않는다."""

import glob
import os
import subprocess
import tempfile
import time

from ft_key_rotate_lines import swap_line

ZSH, ENV = "zshrc", "env"
STAMP = "%Y%m%d-%H%M%S"


def file_paths(kinds):
    """파일 종류(ZSH/ENV) 목록 → 실제 경로(심링크는 풀어서). 시험 훅: HOME · FT_KEY_ROTATE_ENV."""
    home = os.path.expanduser("~/.zshrc")
    env = os.environ.get("FT_KEY_ROTATE_ENV")
    if not env and ENV in kinds:
        r = subprocess.run(
            [
                "git",
                "-C",
                os.path.dirname(os.path.abspath(__file__)),
                "rev-parse",
                "--path-format=absolute",
                "--git-common-dir",
            ],
            capture_output=True,
            text=True,
        )
        top = r.stdout.strip()
        if r.returncode or not os.path.isabs(top):
            raise ValueError("루트 .env 위치를 git 에서 못 찾음 — FT_KEY_ROTATE_ENV 로 지정")
        env = os.path.join(os.path.dirname(top), ".env")
    where = {ZSH: home, ENV: env}
    return [os.path.realpath(where[f]) for f in kinds]


def snapshot(path):
    """(바이트, st_mode&0o7777) — 되돌림·완료 판정의 단위(바이트와 권한 둘 다)."""
    with open(path, "rb") as f:
        data = f.read()
    return data, os.stat(path).st_mode & 0o7777


def write_one(path, data, mode):
    """같은 폴더 mkstemp(0600) → 쓰기·fsync → chmod(staging) → os.replace. replace 뒤 작업 0. 예외면 staging 삭제 후 raise."""
    fd, tmp = tempfile.mkstemp(
        prefix=os.path.basename(path) + ".tmp-keyrotate-", dir=os.path.dirname(path)
    )
    try:
        with os.fdopen(fd, "wb") as f:
            f.write(data)
            f.flush()
            os.fsync(f.fileno())
        os.chmod(tmp, mode)
        os.replace(tmp, path)
    except BaseException:
        if os.path.exists(tmp):
            os.unlink(tmp)
        raise


def write_backup(path, data):
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, "wb") as f:
        f.write(data)
        f.flush()
        os.fsync(f.fileno())


def restore_all(snaps, bks):
    """스냅샷과 (바이트, 권한) 이 다른 파일만 스냅샷으로 되돌림 — 파일마다 try · 쓴 뒤 재검증. 못 한 경로 목록을 돌려주고 'ERROR 복구 필요' 줄을 출력한다(값 0)."""
    stuck = []
    for p, want in snaps.items():
        try:
            try:
                cur = snapshot(p)
            except OSError:
                cur = None
            if cur != want:
                write_one(p, *want)
                if snapshot(p) != want:
                    raise OSError("복구 검증 불일치")
        except Exception:
            stuck.append(p)
            bk = bks.get(p)
            print(
                "ERROR 복구 필요 file=%s backup=%s" % (p, bk if bk and os.path.exists(bk) else "-"),
                flush=True,
            )
    return stuck


def apply_edits(key, edits, make_backup):
    """edits=[(경로, 새 전문)]. 쓰기 «전» 파일마다 스냅샷 확보 → 차례로 write_one → 예외면 전 대상(실패 파일 포함)을 스냅샷으로 되돌림.
    하나라도 못 되돌리면 백업 보존 + RuntimeError(rc≠0). 전부 원상일 때만 이번 회차 백업 정리."""
    snaps = {p: snapshot(p) for p, _ in edits}
    ts = time.strftime(STAMP) + "%06d" % (time.time() * 1e6 % 1e6)
    bks = {p: "%s.bak-keyrotate-%s-%s" % (p, key, ts) for p, _ in edits} if make_backup else {}
    try:
        for p, text in edits:
            if p in bks:
                write_backup(bks[p], snaps[p][0])
            write_one(p, text.encode("utf-8"), snaps[p][1])
    except Exception as e:
        stuck = restore_all(snaps, bks)
        if not stuck:
            for b in bks.values():
                if os.path.exists(b):
                    os.unlink(b)
        raise RuntimeError(
            "쓰기 실패(%s) — %s"
            % (
                type(e).__name__,
                "되돌리지 못한 파일 %d개 — 백업 보존" % len(stuck)
                if stuck
                else "모든 파일을 원문(바이트·권한)으로 되돌림",
            )
        )
    return list(bks.values())


def apply_all(key, files, new, make_backup):
    """파일마다 활성 줄만 새 값으로 바꾼 전문을 만들어(쓰기 전) apply_edits 로 적용."""
    return apply_edits(key, [(p, swap_line(p, key, new)) for p in files], make_backup)


def latest_backup(path, key):
    found = sorted(glob.glob("%s.bak-keyrotate-%s-*" % (glob.escape(path), key)))
    return found[-1] if found else None
