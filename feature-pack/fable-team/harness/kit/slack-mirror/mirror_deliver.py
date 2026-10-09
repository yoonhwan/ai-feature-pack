"""mirror_deliver — 스레드 루트·reply 게시와 «공유» (키 → thread_ts) 맵 (mbox 미러·GitHub 미러 공용).

D5 = 같은 이슈 스레드 합치기(오빠 18:1x): 두 launchd 프로세스가 같은 맵 파일을 쓴다.
«확인 → 루트 게시 → 저장» 을 flock 한 구간으로 묶어 같은 키의 루트가 둘 생기는 경쟁을 막는다.
"""
import fcntl
import json
import os
import sys
from collections.abc import Callable
from contextlib import contextmanager
from pathlib import Path
from typing import Iterator

import mirror_lib as lib

MAX_THREADS = 500  # 오래된 키부터 밀려난다(무한 증가 0)


@contextmanager
def locked(path: Path) -> Iterator[None]:
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(str(path) + ".lock", "w") as lk:
        fcntl.flock(lk, fcntl.LOCK_EX)
        yield


def load_threads(path: Path) -> dict[str, str]:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        return {str(k): str(v) for k, v in dict(data.get("threads", {})).items()}
    except FileNotFoundError:
        return {}
    except (ValueError, OSError, AttributeError) as e:
        raise lib.MirrorError(f"스레드 맵 읽기 실패: {path} ({type(e).__name__})") from e


def _save_threads(path: Path, threads: dict[str, str]) -> None:
    tmp = path.with_suffix(".tmp")
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump({"threads": threads}, f, ensure_ascii=False)
        f.flush()
        os.fsync(f.fileno())
    os.replace(tmp, path)


def ensure_thread(path: Path, key: str, make_root: Callable[[], str], max_threads: int = MAX_THREADS) -> str:
    """키의 thread_ts — 없으면 make_root() 로 루트를 올리고 저장한다(한 구간 flock)."""
    with locked(path):
        threads = load_threads(path)
        if key in threads:
            return threads[key]
        threads[key] = make_root()
        while len(threads) > max_threads:
            del threads[next(iter(threads))]
        _save_threads(path, threads)
        return threads[key]


def existing_thread(path: Path, key: str) -> str | None:
    """키의 thread_ts — 있을 때만(없으면 None · 루트를 만들지 않는다). 맵 잠금 안에서 읽는다."""
    with locked(path):
        return load_threads(path).get(key)


def seed_threads(path: Path, seed: dict[str, str]) -> None:
    """맵 파일이 아직 없을 때만 옛 state 의 맵으로 채운다(이전 판 → 공유 맵 이관)."""
    with locked(path):
        if not path.exists() and seed:
            _save_threads(path, {str(k): str(v) for k, v in seed.items()})


class Deliverer:
    def __init__(self, api_base: str, token: str, channel: str, threads_path: Path, max_threads: int = MAX_THREADS, teams=None):
        self.api_base, self.token, self.channel = api_base, token, channel
        self.threads_path, self.max_threads = threads_path, max_threads
        self.teams = teams  # mirror_team_roots.TeamRoots — 없으면 지금처럼 키(이슈·좌석)마다 뿌리 글

    def _post(self, text: str, thread_ts: str | None = None) -> str:
        return lib.post(self.api_base, self.token, self.channel, text, thread_ts)

    def _find_root(self, key: str) -> str | None:
        marker = lib.root_marker(key)
        for ts, text in lib.channel_roots(self.api_base, self.token, self.channel):
            if lib.has_marker([text], marker):
                return ts
        return None

    def thread_ts(self, item: dict[str, object], resume: bool) -> str:
        key = str(item.get("key", lib.OTHER_KEY))

        def make_root() -> str:  # 루트만 올라가고 죽은 경우를 되찾는다(resume)
            found = self._find_root(key) if resume else None
            return found or self._post(lib.root_text(key, str(item.get("what", "")) or key, str(item["url"]) if item.get("url") else None))

        return ensure_thread(self.threads_path, key, make_root, self.max_threads)

    def has_thread(self, key: str) -> bool:
        """reply_only 대상 스레드가 있나 — 팀 모드면 원래 키 스레드(결정 요청) 또는 오늘 그 팀 뿌리 글."""
        if existing_thread(self.threads_path, key) is not None:
            return True
        return self.teams is not None and existing_thread(self.threads_path, self.teams.route({"key": key}).post_key) is not None

    def _reply(self, item: dict[str, object], ts: str, resume: bool, text: str) -> None:
        if resume:  # 조회가 실패하면 raise — 중복보다 지연
            if lib.has_marker(lib.thread_texts(self.api_base, self.token, self.channel, ts), str(item["id"])):
                return
        self._post(text, ts)

    def _team_root(self, post_key: str, resume: bool) -> str:
        return (self._find_root(post_key) if resume else None) or self._post(self.teams.root_text(post_key))

    def _send_team(self, item: dict[str, object], resume: bool) -> None:
        """r2-A/B: 게시 스레드는 «팀·날짜 뿌리 글»(결정 요청만 원래 키 스레드) · 맵 잠금 → 답글 → 공용 잠금(원장 + 뿌리 글 다시 그림) 순서, 두 잠금 중첩 0."""
        key, route = str(item.get("key", lib.OTHER_KEY)), self.teams.route(item)
        if item.get("reply_only"):
            ts = existing_thread(self.threads_path, key) or existing_thread(self.threads_path, route.post_key)
            if ts is None:
                print(f"WARN reply_only 스레드 없음 key={key} id={item.get('id')} — 올리지 않음", file=sys.stderr)
                return
            return self._reply(item, ts, resume, str(item["text"]))
        question = isinstance(item.get("question"), dict)
        roots = {k: ensure_thread(self.threads_path, k, lambda k=k: self._team_root(k, resume), self.max_threads) for k in route.root_keys}
        ts = self.thread_ts(item, resume) if question else roots[route.post_key]
        self._reply(item, ts, resume, self.teams.reply_text(item, route))
        self.teams.record(item, route, roots, ts if question else None)  # 재시작에서 resume 마커로 일찍 돌아와도 항상 실행 — 이벤트 id 멱등

    def send(self, item: dict[str, object], resume: bool = False) -> None:
        if self.teams is not None:
            return self._send_team(item, resume)
        if item.get("reply_only"):  # 새 글 0 — 기존 스레드에 답글만. 맵에 키가 없으면 0줄(설계상 «안 올림» · resume 도 같은 길)
            ts = existing_thread(self.threads_path, str(item.get("key", lib.OTHER_KEY)))
            if ts is None:
                print(f"WARN reply_only 스레드 없음 key={item.get('key')} id={item.get('id')} — 올리지 않음", file=sys.stderr)
                return
        else:
            ts = self.thread_ts(item, resume)
        self._reply(item, ts, resume, str(item["text"]))
