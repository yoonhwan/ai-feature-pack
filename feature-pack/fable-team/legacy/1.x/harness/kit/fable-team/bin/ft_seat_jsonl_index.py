#!/usr/bin/env python3
"""좌석 이름 → 최신 jsonl 색인 (r571).

지금 판(ft-seat-status.sh `newest_jsonl_of` 인라인 파이썬)은 좌석 1석 조회마다 그 폴더의
jsonl «전부» 를 앞 1MB 씩 읽는다. 폴더에 jsonl 이 1만 개면 좌석당 5.7GB — 한 바퀴 61GB.
이름 레코드(agentName/customTitle)는 파일 앞에 한 번 쓰이면 바뀌지 않으므로,
폴더마다 «어느 경로가 어느 좌석 것인가» 를 색인 파일 1개에 적어 두고 다음부터는
새 파일·자란 파일의 «아직 안 읽은 앞부분» 만 더 읽는다. 답(최신 경로)은 같다.

usage: ft_seat_jsonl_index.py newest <폴더> <좌석>
env  : FT_SEAT_INDEX_DIR(기본 $HOME/.claude/state/seat-jsonl-index) · FT_SEAT_HEAD_BYTES(기본 1MB)
       FT_SEAT_INDEX_STATS=1 → stderr `READ <바이트> FILES <개수> NEW <개수> MS <밀리초>` 1줄
되돌림: 이 파일을 지우고 ft-seat-status.sh 를 .bak-r571 로 되돌린다(색인 파일도 지우면 처음 판).
"""
import errno
import fcntl
import json
import os
import re
import sys
import time

CAP = int(os.environ.get("FT_SEAT_HEAD_BYTES") or 1048576)
OVERLAP = 1024          # 이름 레코드가 읽기 경계에 걸려도 놓치지 않게 겹쳐 읽는다
LOCK_WAIT = 7.0         # 폴더당 잠금 대기 상한(초) — 넘으면 마지막 색인으로 답 + WARN
NAME_RE = re.compile(r'"(?:agentName|customTitle)":"([^"]*)"')


def index_dir():
    d = os.environ.get("FT_SEAT_INDEX_DIR")
    if not d:
        d = os.path.join(os.environ.get("HOME", "~"), ".claude", "state", "seat-jsonl-index")
    return os.path.expanduser(d)


def index_path(folder):
    return os.path.join(index_dir(), os.path.basename(os.path.normpath(folder)) + ".json")


def load(path):
    try:
        with open(path, "r", encoding="utf-8") as fh:
            data = json.load(fh)
        if not isinstance(data, dict):
            raise ValueError("dict 아님")
        return data
    except FileNotFoundError:
        return {}
    except (OSError, ValueError) as exc:
        sys.stderr.write("ERROR r571-index: 색인 읽기 실패(%s) — 처음부터 다시 만든다\n" % exc)
        return {}


def save(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".tmp%d" % os.getpid()
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(data, fh, ensure_ascii=False)
    os.replace(tmp, path)


def lock(fd):
    """폴더당 잠금 1개. 얻으면 True, LOCK_WAIT 초과면 False(마지막 색인으로 답한다)."""
    end = time.time() + LOCK_WAIT
    while True:
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            return True
        except OSError as exc:
            if exc.errno not in (errno.EAGAIN, errno.EACCES):
                raise
            if time.time() >= end:
                return False
            time.sleep(0.02)


def scan(folder, idx):
    """새 파일·자란 파일의 «아직 안 읽은 앞부분» 만 읽어 색인을 갱신한다(입력 색인은 안 고친다)."""
    stats = {"read": 0, "files": 0, "new": 0}
    fresh = {}
    try:
        entries = list(os.scandir(folder))
    except OSError:
        return idx, stats
    for ent in entries:
        if not ent.name.endswith(".jsonl"):
            continue
        try:
            st = ent.stat()
        except OSError:
            continue
        stats["files"] += 1
        old = idx.get(ent.path)
        if old is None:
            old = {"size": 0, "mtime": 0, "read": 0, "names": []}
            stats["new"] += 1
        elif st.st_size == old.get("size") and st.st_mtime == old.get("mtime"):
            fresh[ent.path] = old
            continue
        cap = min(CAP, st.st_size)
        start = min(old.get("read", 0), cap)
        if start < cap:                       # 아직 1MB 상한에 안 닿은 앞부분만 더 읽는다
            begin = max(0, start - OVERLAP)
            try:
                with open(ent.path, "rb") as fh:
                    fh.seek(begin)
                    chunk = fh.read(cap - begin)
            except OSError:
                fresh[ent.path] = old
                continue
            stats["read"] += len(chunk)
            stats["new"] += 1
            names = list(old.get("names") or [])
            for name in NAME_RE.findall(chunk.decode("utf-8", "replace")):
                if name and name not in names:
                    names.append(name)
            old = {"size": st.st_size, "mtime": int(st.st_mtime),
                   "read": begin + len(chunk), "names": names}
        else:                                 # 상한에 닿았다 — 크기·시각만 갱신
            old = dict(old, size=st.st_size, mtime=int(st.st_mtime))
        fresh[ent.path] = old
    return fresh, stats


def newest(folder, seat):
    t0 = time.time()
    ipath = index_path(folder)
    idx = load(ipath)
    stats = {"read": 0, "files": 0, "new": 0}
    if os.path.isdir(folder):
        try:
            os.makedirs(os.path.dirname(ipath), exist_ok=True)
            with open(ipath + ".lock", "a+") as lockfh:
                if lock(lockfh.fileno()):
                    idx = load(ipath)          # 잠금 안에서 다시 읽는다(다른 좌석이 방금 갱신했을 수 있다)
                    idx, stats = scan(folder, idx)
                    save(ipath, idx)
                else:
                    sys.stderr.write("WARN r571-index: 잠금 %.0f초 초과 %s — 마지막 색인으로 답한다\n"
                                     % (LOCK_WAIT, os.path.basename(folder)))
        except OSError as exc:
            sys.stderr.write("WARN r571-index: 색인 쓰기 실패(%s) — 이번 조회만 직접 읽는다\n" % exc)
            idx, stats = scan(folder, {})
    best = (0, "")
    for path, ent in idx.items():
        if seat in (ent.get("names") or []) and int(ent.get("mtime") or 0) > best[0]:
            best = (int(ent.get("mtime") or 0), path)
    if best[1]:
        print(best[1])
    if os.environ.get("FT_SEAT_INDEX_STATS") == "1":
        sys.stderr.write("READ %d FILES %d NEW %d MS %d\n"
                         % (stats["read"], stats["files"], stats["new"],
                            int((time.time() - t0) * 1000)))
    return 0


def main(argv):
    if len(argv) != 4 or argv[1] != "newest":
        sys.stderr.write("usage: %s newest <폴더> <좌석>\n" % argv[0])
        return 2
    return newest(argv[2], argv[3])


if __name__ == "__main__":
    sys.exit(main(sys.argv))
