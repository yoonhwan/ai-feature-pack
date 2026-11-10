"""ft-tick-line 의 좌석 턴 읽기 — 좌석→jsonl 경로 캐시 + `turn --file` 직접 호출 + I/O 계측 (PLAN D2 부하 계약 · 교정 F5).

ft_board_seat.turn_row 를 대체한다(SeatCells 는 모듈 전역 turn_row 를 호출 시점에 찾는다). 경로 해석(`ft-seat-status.sh jsonl <좌석>` =
프로젝트 jsonl 전수 순회)은 캐시가 없거나 낡았을 때만 1회:
  캐시 <FT_TICK_OUT_DIR>/seat-jsonl.json = {좌석: {path, mtime, dir, dir_mtime, resolved, scanned}} · 전수 재해석 조건 = 캐시 없음 · 경로 파일 없음 ·
  mtime 역행 · 해석 후 TTL 초과(FT_TICK_PATH_TTL 초 · 기본 1800 — 보조 상한).
  부모 디렉터리 mtime 이 바뀌었으면(= 새 파일 생성/삭제/rename · 그 폴더는 그 워크트리의 «모든 세션» jsonl 이라 자주 바뀐다) 전수 재해석이 아니라
  «새로 생긴 파일만» 본다: scandir 로 stat 만(파일 열기 0) → 생성시각 > 캐시 scanned 인 *.jsonl 의 앞 HEAD_BYTES 만 읽어 좌석명 needle 매칭
  (ft-seat-status.sh newest_jsonl_of 와 같은 needle·같은 상한) → 매칭 중 mtime 최신이 캐시 경로보다 최신이면 교체. 다른 디렉터리의 변화는 무시.
jsonl 이 없는 좌석(codex 등)은 옛 경로 `turn <좌석> --json`(pane 스피너)로 되돌린다 — 부정 캐시({path: null})로 TTL 동안 jsonl 전수 순회를 다시 하지 않는다.
좌석 상태만 필요하므로 `--no-reported`(끝 레코드 1개면 멈춤 — 긴 턴에서 1MB 확장 방지).
통계 files·bytes(read_bytes + 새 파일 앞 읽기 합)·ms·resolve(전수 재해석 수)·scan(stat 한 파일 수)·new(앞을 읽은 새 파일 수)는 stats 로 모아 틱이 stderr 1줄 `io: …` 로 낸다.
"""
import json
import os
import subprocess
import time
from pathlib import Path

import ft_board_env as env
import ft_board_seat

TTL_DEFAULT = 1800
HEAD_BYTES_DEFAULT = 1048576  # ft-seat-status.sh FT_SEAT_HEAD_BYTES 기본과 같다


def needles(seat: str) -> tuple[bytes, bytes]:
    """좌석명 레코드 needle — ft-seat-status.sh newest_jsonl_of 의 needles 와 글자까지 같아야 한다(F5b-R5 가 같은 파일을 고르는지 본다)."""
    b = seat.encode()
    return (b'"agentName":"' + b + b'"', b'"customTitle":"' + b + b'"')


def fresh_match(d: str, seat: str, since: float, stats=None, memo: dict | None = None) -> str | None:
    """d 안에서 생성시각 > since 인 *.jsonl 만 앞 HEAD_BYTES 를 읽어 좌석 needle 매칭 → mtime 최신 경로. stat 은 폴더당 1회(memo)."""
    cap = int(os.environ.get("FT_SEAT_HEAD_BYTES", HEAD_BYTES_DEFAULT))
    memo = memo if memo is not None else {}
    if d not in memo:
        ents = []
        with os.scandir(d) as it:
            for e in it:
                if e.name.endswith(".jsonl"):
                    try:
                        st = e.stat()
                    except OSError:
                        continue
                    ents.append((e.path, getattr(st, "st_birthtime", st.st_ctime), st.st_mtime))
        memo[d] = (ents, {})
        if stats is not None:
            stats.scan += len(ents)
    ents, heads = memo[d]
    want, best = needles(seat), None
    for path, born, mtime in ents:
        if born <= since:
            continue
        if path not in heads:
            try:
                with open(path, "rb") as fh:
                    heads[path] = fh.read(cap)
            except OSError:
                continue
            if stats is not None:
                stats.new += 1
                stats.bytes += len(heads[path])
        if any(n in heads[path] for n in want) and (best is None or mtime > best[0]):
            best = (mtime, path)
    return best[1] if best else None


class Stats:
    files = bytes = resolve = scan = new = 0
    ms = 0.0

    def line(self) -> str:
        return f"io: files={self.files} bytes={self.bytes} ms={int(self.ms)} resolve={self.resolve} scan={self.scan} new={self.new}"


def _run(args: list[str], timeout: int = 30):
    sh = os.environ.get("FT_BOARD_SEAT_STATUS", str(env.HERE / "ft-seat-status.sh"))
    return subprocess.run(["bash", sh, *args], capture_output=True, text=True, timeout=timeout)


def install(out_dir: Path, stats: Stats) -> None:
    cache_path = out_dir / "seat-jsonl.json"
    try:
        cache = json.loads(cache_path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        cache = {}
    ttl = int(os.environ.get("FT_TICK_PATH_TTL", TTL_DEFAULT))
    dirty = []

    memo: dict = {}  # 틱 1회 안에서 폴더 scandir·새 파일 앞 읽기를 좌석끼리 공유한다

    def valid(seat: str, ent) -> str | None:
        try:
            p = Path(ent["path"])
            if not p.is_file() or p.stat().st_mtime < ent["mtime"] or time.time() - ent["resolved"] > ttl:
                return None
            started = time.time()
            dm = p.parent.stat().st_mtime
            if dm == ent["dir_mtime"]:
                return str(p)
            found = fresh_match(str(p.parent), seat, ent.get("scanned", ent["resolved"]), stats, memo)
            if found and Path(found).stat().st_mtime > p.stat().st_mtime:
                p = Path(found)
            ent.update(path=str(p), mtime=p.stat().st_mtime, dir_mtime=dm, scanned=started)
            dirty.append(seat)
            return str(p)
        except (KeyError, TypeError, OSError):
            return None

    def turn_row(seat: str) -> dict:
        try:
            ent = cache.get(seat)
            if isinstance(ent, dict) and ent.get("path") is None and time.time() - ent.get("resolved", 0) <= ttl:
                return ft_board_seat_turn_row_legacy(seat)  # 부정 캐시 — jsonl 없는 좌석은 TTL 동안 전수 순회를 다시 하지 않는다
            path = valid(seat, ent)
            if path is None:
                stats.resolve += 1
                r = _run(["jsonl", seat], 30)
                path = r.stdout.strip().splitlines()[0] if r.returncode == 0 and r.stdout.strip() else None
                if path is None:  # jsonl 없는 좌석(또는 해석 실패) → 옛 경로(pane) · 실패면 그 rc 가 이유
                    cache[seat] = {"path": None, "resolved": time.time()}; dirty.append(seat)
                    return ft_board_seat_turn_row_legacy(seat)
                pp = Path(path)
                cache[seat] = {"path": path, "mtime": pp.stat().st_mtime, "dir": str(pp.parent), "dir_mtime": pp.parent.stat().st_mtime,
                               "resolved": time.time(), "scanned": time.time()}
                dirty.append(seat)
            t0 = time.monotonic()
            r = _run(["turn", "--file", path, "--json", "--no-reported"], 30)
            stats.ms += (time.monotonic() - t0) * 1000
        except subprocess.TimeoutExpired:
            return {"error": "turn 조회 시간 초과"}
        except OSError as e:
            return {"error": f"jsonl 읽기 실패({e.__class__.__name__})"}
        if r.returncode != 0:
            return {"error": f"turn 조회 실패 rc={r.returncode}"}
        try:
            row = json.loads(r.stdout)
            stats.files += 1
            stats.bytes += int(row.get("read_bytes") or 0)
            return {"state": str(row["state"]), "turn_end": row.get("turn_end"), "source": str(row.get("source"))}
        except (ValueError, KeyError, TypeError, AttributeError):
            return {"error": "출력 해석 실패"}

    def save() -> None:
        if dirty:
            out_dir.mkdir(parents=True, exist_ok=True)
            tmp = cache_path.with_suffix(".tmp")
            tmp.write_text(json.dumps(cache, ensure_ascii=False), encoding="utf-8")
            os.replace(tmp, cache_path)

    ft_board_seat_turn_row_legacy = ft_board_seat.turn_row
    ft_board_seat.turn_row = turn_row
    stats.save = save
