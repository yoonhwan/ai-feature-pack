"""ft2 Slack 보충 회차 — 좌석·thread 커서 · 쪽 단위 재개 (r1585 · PR③ 셋째 장).

계약 줄 7·8·16. 커서는 (좌석, thread) 쌍마다 따로다 — 한 좌석이 여러 thread 를 맡아도 창을 다시 읽지 않고,
새 글이 0 인 pass 는 모델 호출 0 · 재로드 0 이다. 보충은 재시작·재연결 «사건» 때만 돌고 주기 폴링은 하지
않는다(변이 M6). 한 회차에 thread 마다 한 쪽(limit)만 읽고, 쪽이 남으면 그 thread 의 위치를 보존한 채 상태
«미완» 으로 멈춘다. 커서는 «연속으로 처리한 영수» 까지만 전진한다 — 영수 없는 행 뒤로는 밀지 않는다(변이 M5).
실패·gap 은 미완 기록이고 조용히 건너뛰지 않는다. 읽기는 대역 주입(`fetch`)이고 실 Slack 호출은 0 이다.
"""

import json
import os
import time

RESTART, RECONNECT = "restart", "reconnect"
REASONS = (RESTART, RECONNECT)
DONE, STALE, SKIPPED = "done", "미완", "건너뜀"
DISPATCHED, DUPLICATE = "dispatched", "duplicate"
PROCESSED = (DISPATCHED, DUPLICATE)  # 기존 영수도 «이미 처리» 다 — gap 오판 0(DA R3)
PAGE = 15

#: 이 장이 덮는 계약 줄 — 계약 낱말 그대로 적는다(시험이 사례 expect 낱말과 대조한다).
COVERS = {
    7: "보충 회차 = 재시작·재연결 사건 때만 · 허용 채널·활성 thread의 커서 이후를 제한된 묶음으로 · "
       "페이지가 남으면 위치 보존 후 재개 · 커서는 연속된 처리 영수까지만 · 실패/gap은 미완 기록",
    8: "좌석·thread별 커서 · 창 전체 다시 읽기 0",
    16: "유휴·중복·무변화 사건은 도구 안에서 끝 · 모델 호출·좌석 깨움·틱 상태 메시지 0",
}


class Cursors:
    """(좌석, thread) 별 마지막 처리 ts — 재기동은 이 파일에서 위치를 복원한다(계약 줄 8)."""
    def __init__(self, root, team="harness", clock=None):
        self.clock = clock or (lambda: time.strftime("%Y-%m-%dT%H:%M:%S"))
        data = os.path.join(os.path.abspath(str(root)), ".fable-team", "teams", team, "slack")
        os.makedirs(data, exist_ok=True)
        self.path = os.path.join(data, "cursors.jsonl")

    def entries(self):
        if not os.path.exists(self.path):
            return []
        with open(self.path, encoding="utf-8") as handle:
            return [json.loads(line) for line in handle if line.strip()]

    def of(self):
        """지금 유효한 커서 전부 — {(좌석, thread): ts}."""
        return {(row["seat"], row["thread"]): row["ts"] for row in self.entries()}

    def get(self, seat, thread):
        return self.of().get((str(seat), str(thread)), "")

    def advance(self, seat, thread, ts):
        """연속 처리 영수 1건만큼만 전진 — 새 글이 0 이면 커서는 그대로다."""
        if not ts or ts == self.get(seat, thread):
            return None
        with open(self.path, "a", encoding="utf-8") as handle:
            row = {"seat": str(seat), "thread": str(thread), "ts": str(ts), "schema": 1, "at": self.clock()}
            handle.write(json.dumps(row, ensure_ascii=False, sort_keys=True) + "\n")
            handle.flush()
            os.fsync(handle.fileno())
        return row


class Backfill:
    """보충 회차 1번 = 판정 1개. 상태는 `state` 한 낱말로만 말한다."""
    def __init__(self, root, *, route, fetch, cursors=None, team="harness", limit=PAGE, clock=None,
                 notify=None, on_step=None):
        self.route, self.fetch, self.team = route, fetch, team
        self.cursors = cursors or Cursors(root, team, clock=clock)
        self.limit = int(limit)
        self.notify, self.on_step = notify or (lambda row: None), on_step or (lambda name: None)
        self.clock = clock or (lambda: time.strftime("%Y-%m-%dT%H:%M:%S"))
        data = os.path.join(os.path.abspath(str(root)), ".fable-team", "teams", team, "slack")
        os.makedirs(data, exist_ok=True)
        self.path = os.path.join(data, "backfill.jsonl")
        self.steps = []

    def _step(self, name):
        self.steps.append(name)
        self.on_step(name)

    def _append(self, row):
        with open(self.path, "a", encoding="utf-8") as handle:
            handle.write(json.dumps(dict(row, schema=1, at=self.clock()), ensure_ascii=False, sort_keys=True) + "\n")
            handle.flush()
            os.fsync(handle.fileno())
        return row

    def run(self, reason, targets):
        """회차 1번. `targets` = [(좌석, channel, thread)]. 사건이 아니면 아무것도 읽지 않는다."""
        self.steps = []
        row = {"reason": str(reason), "state": DONE, "pages": 0, "dispatched": 0, "gap": None, "stale": []}
        if reason not in REASONS:  # 주기 폴링 0 — 사건이 아니면 회차를 만들지 않는다(변이 M6)
            return self._append(dict(row, state=SKIPPED, why="재시작·재연결 사건 아님"))
        for seat, channel, thread in targets:
            outcome = self._thread(str(seat), str(channel), str(thread), row)
            if outcome:
                row["stale"].append(outcome)
        if row["stale"]:
            row["state"] = STALE
            self.notify(row)
        return self._append(row)

    def _thread(self, seat, channel, thread, row):
        """thread 1곳 = 쪽 1장. 남았거나 실패면 미완 사유를 돌려준다(위치는 보존)."""
        after = self.cursors.get(seat, thread)
        try:
            page = self.fetch(channel, thread, after, self.limit)
        except Exception as exc:  # 실패 = 미완 기록 · 조용한 건너뛰기 0
            row["gap"] = "%s:%s %s" % (channel, thread, exc)
            self._step("gap")
            return "failed %s:%s" % (channel, thread)
        self._step("page")
        row["pages"] += 1
        rows = list((page or {}).get("rows") or [])
        more = str((page or {}).get("next") or "")
        for item in rows:
            if item.get("root"):
                continue  # thread root 글은 접수 때 이미 갔다 — 쪽 자리만 차지한다(사례 d3)
            if item.get("gap"):  # 구멍 = 그 자리에서 멈추고 미완 기록
                row["gap"] = "%s:%s %s" % (channel, thread, item.get("gap"))
                self._step("gap")
                return "gap %s:%s" % (channel, thread)
            verdict = self.route.route(dict(item, team=item.get("team") or self.team, channel=channel,
                                            thread_ts=thread))
            self._step("route")
            if verdict.get("state") not in PROCESSED:
                return "no_receipt %s:%s@%s" % (channel, thread, item.get("ts"))  # 커서를 밀지 않는다
            if verdict.get("state") == DISPATCHED:
                row["dispatched"] += 1
            self.cursors.advance(seat, thread, str(item.get("ts") or ""))  # 기존 영수도 위치를 복원한다(R3)
        if more:  # 쪽이 남았다 = 위치 보존(변이 M5) · 빈 쪽이라도 done 이 아니다(R3)
            return "more %s:%s" % (channel, thread)
        if not rows:  # 새 글 0 = 도구 안에서 끝난다 — 모델 호출·좌석 깨움 0(줄 16)
            self.route.route(None)
            self._step("idle")
        return None
