"""mirror_team_roots — 팀 뿌리 글의 «이벤트 원장» + 공용 잠금 안의 통째로 다시 그리기 (판정 623 · 카드 설계 r2-B).

원장 `byz_team_roots.json` = {roots: {team:<팀>:<날짜>: {events: {이벤트 id: {...}}, fail: bool}}}. 이벤트 id = 미러 글 id → 같은 id 는 두 번 반영되지 않는다(멱등).
공용 잠금 `byz_team_roots.lock`(두 미러 공용) 안에서만 ①읽기 ②이벤트 추가 ③원자 저장 ④팀 뿌리 글 update ⑤planner 뿌리 글 update.
뿌리 글 ts 는 스레드 맵(Deliverer.ensure_thread) 정본 — 호출자가 잠금 «밖» 에서 확보해 넘긴다(두 잠금 중첩 0).
update 실패 = stderr ERROR + 원장 fail 표시 → 그 팀의 다음 답글 꼬리 1줄 · 다음 성공 렌더가 통째로 맞춘다(조용한 누락 0).
"""
import fcntl
import json
import re
import sys
from collections.abc import Iterator
from contextlib import contextmanager
from pathlib import Path

import mirror_lib as lib
import mirror_team as mt
import mirror_team_render as rd

KEEP_DAYS = 3  # 원장 무한 증가 0 — 오래된 팀·날짜 칸은 버린다
FAIL_TAIL = "(팀 목록 갱신 실패 — 다음 글에서 다시 그림)"


class TeamRoots:
    def __init__(self, state_dir: Path, api_base: str, token: str, channel: str, router: mt.Router):
        self.state_path, self.lock_path = state_dir / "byz_team_roots.json", state_dir / "byz_team_roots.lock"
        self.api_base, self.token, self.channel, self.router = api_base, token, channel, router

    # --- 판정·글 모양 ----------------------------------------------------------------------
    def route(self, item: dict[str, object]) -> mt.Route:
        return self.router.route(item)

    def root_text(self, post_key: str) -> str:
        """루트를 처음 올릴 때의 글 — 이후 record 가 통째로 다시 쓴다."""
        _, team, day = post_key.split(":", 2)
        st = self._load()
        if team == mt.PLANNER:
            return rd.render_planner(day, self._day_buckets(st, day), post_key)
        return rd.render_team(team, day, st["roots"].get(post_key, {}), post_key)

    def reply_text(self, item: dict[str, object], route: mt.Route) -> str:
        """세부 글 = 지금 글 그대로 + 머리표 뒤에 «쉬운 이슈 제목 ·» (이슈 글) · 라벨 없음 줄 · 지난 갱신 실패 꼬리."""
        lines = str(item["text"]).split("\n")
        m = re.fullmatch(r"#(\d+)", str(item.get("key", "")))
        if m:
            title = rd.issue_title(self._load()["roots"].get(route.post_key, {}), int(m.group(1))) or f"#{m.group(1)}"
            head = re.match(r"^\[[^\]]+\] ", lines[0])
            cut = head.end() if head else 0
            lines[0] = f"{lines[0][:cut]}{lib.esc(title)} · {lines[0][cut:]}"
        if route.note:
            lines.insert(1, route.note)
        if self._load()["roots"].get(route.post_key, {}).get("fail"):
            lines.append(FAIL_TAIL)
        return "\n".join(lines)

    # --- 원장 ------------------------------------------------------------------------------
    @contextmanager
    def _locked(self) -> Iterator[None]:
        self.lock_path.parent.mkdir(parents=True, exist_ok=True)
        with open(self.lock_path, "w") as lk:
            fcntl.flock(lk, fcntl.LOCK_EX)
            yield

    def _load(self) -> dict:
        try:
            st = json.loads(self.state_path.read_text(encoding="utf-8"))
        except FileNotFoundError:
            return {"roots": {}}
        except (ValueError, OSError) as e:
            raise lib.MirrorError(f"팀 뿌리 글 원장 읽기 실패: {self.state_path} ({type(e).__name__})") from e
        st.setdefault("roots", {})
        return st

    @staticmethod
    def _day_buckets(st: dict, day: str) -> dict[str, dict]:
        return {k.split(":")[1]: v for k, v in st["roots"].items() if k.endswith(f":{day}")}

    def _event(self, item: dict[str, object], route: mt.Route, link: str | None) -> dict[str, object]:
        m = re.fullmatch(r"#(\d+)", str(item.get("key", "")))
        question = isinstance(item.get("question"), dict)
        what = str(item.get("what") or "")
        return {"issue": int(m.group(1)) if m else None, "key": str(item.get("key", "")), "kind": str(item.get("kind") or ("hil" if question else "report")),
                "at": self.router.clock(), "title": what, "what": what, "pr": item.get("num") if item.get("kind") == "merged" else None,
                "sha": item.get("sha"), "link": link}

    def _permalink(self, ts: str) -> str | None:
        try:
            return str(lib.api_call(self.api_base, self.token, "chat.getPermalink", {"channel": self.channel, "message_ts": ts}, get=True)["permalink"])
        except lib.MirrorError as e:
            print(f"ERROR: 결정 기다림 질문 링크 조회 실패: {e} — 링크 없이 목록에 올림", file=sys.stderr)
            return None

    def _update(self, ts: str, text: str) -> bool:
        try:
            lib.api_call(self.api_base, self.token, "chat.update", {"channel": self.channel, "ts": ts, "text": text})
            return True
        except lib.MirrorError as e:
            print(f"ERROR: 팀 뿌리 글 chat.update 실패 ts={ts}: {e} — 다음 글에서 다시 그림", file=sys.stderr)
            return False

    def record(self, item: dict[str, object], route: mt.Route, roots: dict[str, str], question_ts: str | None = None) -> None:
        """이벤트를 원장에 넣고(멱등) 팀 뿌리 글·planner 뿌리 글을 «원장 전체» 로 다시 그린다. 저장 실패 = raise(그 글 처리 중단 · pending 재시도)."""
        link = self._permalink(question_ts) if question_ts else None
        with self._locked():
            st, key = self._load(), route.post_key
            bucket = st["roots"].setdefault(key, {"events": {}})
            if str(item["id"]) not in bucket["events"]:
                bucket["events"][str(item["id"])] = self._event(item, route, link)
            floor = mt.day_of(self.router.clock() - KEEP_DAYS * 86400)
            st["roots"] = {k: v for k, v in st["roots"].items() if k.rsplit(":", 1)[1] >= floor}
            lib.save_state(self.state_path, st)
            ok = self._update(roots[key], rd.render_team(route.team, route.day, bucket, key)) if route.team != mt.PLANNER else True
            pk = route.planner_key
            ok = self._update(roots[pk], rd.render_planner(route.day, self._day_buckets(st, route.day), pk)) and ok
            if bool(bucket.get("fail")) == (not ok):
                return
            bucket["fail"] = not ok
            lib.save_state(self.state_path, st)
