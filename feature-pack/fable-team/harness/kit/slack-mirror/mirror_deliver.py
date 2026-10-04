"""mirror_deliver — 스레드 루트·reply 게시와 «공유» (키 → thread_ts) 맵 (mbox 미러·GitHub 미러 공용).

D5 = 같은 이슈 스레드 합치기(오빠 18:1x): 두 launchd 프로세스가 같은 맵 파일을 쓴다.
«확인 → 루트 게시 → 저장» 을 flock 한 구간으로 묶어 같은 키의 루트가 둘 생기는 경쟁을 막는다.
"""
import fcntl
import json
import os
from collections.abc import Callable
from contextlib import contextmanager
from pathlib import Path
from typing import Iterator

import mirror_lib as lib

MAX_THREADS = 500  # 오래된 키부터 밀려난다(무한 증가 0)


@contextmanager
def _locked(path: Path) -> Iterator[None]:
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
    with _locked(path):
        threads = load_threads(path)
        if key in threads:
            return threads[key]
        threads[key] = make_root()
        while len(threads) > max_threads:
            del threads[next(iter(threads))]
        _save_threads(path, threads)
        return threads[key]


def seed_threads(path: Path, seed: dict[str, str]) -> None:
    """맵 파일이 아직 없을 때만 옛 state 의 맵으로 채운다(이전 판 → 공유 맵 이관)."""
    with _locked(path):
        if not path.exists() and seed:
            _save_threads(path, {str(k): str(v) for k, v in seed.items()})


class Deliverer:
    def __init__(self, api_base: str, token: str, channel: str, threads_path: Path, max_threads: int = MAX_THREADS):
        self.api_base, self.token, self.channel = api_base, token, channel
        self.threads_path, self.max_threads = threads_path, max_threads

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
            return found or self._post(lib.root_text(key, str(item.get("what", "")) or key))

        return ensure_thread(self.threads_path, key, make_root, self.max_threads)

    def send(self, item: dict[str, object], resume: bool = False) -> None:
        ts = self.thread_ts(item, resume)
        if resume:  # 조회가 실패하면 raise — 중복보다 지연
            if lib.has_marker(lib.thread_texts(self.api_base, self.token, self.channel, ts), str(item["id"])):
                return
        self._post(str(item["text"]), ts)
