"""ft 2.0 keeper — B4 보고 = 닫기까지 · 팀 master 쪽지 (r1812 · keeper.py 가 섞어 쓴다).

끝난 뒤 30분 넘게 열린 좌석 = state.open(처음 본 시각) 중 지금도 살아 있는 것 · 쪽지는 같은 열쇠 1회(하루 같은 좌석 1회).
r2065 행 E(카드 ft2-keeper-notify-recipient · 설계 DESIGN-pE-keeper-notify-no-recipient r3) —
E1 받는 곳 차례 = 그 팀 `_master` → 그 팀 `_desk` → harness `_master`(처음으로 값이 있는 한 곳) · E2 대신 받는 곳에는 팀당 하루 1통 묶음 ·
E3 실패도 그날 지문(같은 열쇠 재시도 0 · 날짜가 바뀌면 1회) · E5 통마다 7초·재시도 0·한 바퀴 3통 ·
E6 세 칸 다 빈칸 = «받는 곳 없음» 그날 1줄 · E7 7초를 넘긴 send 는 우편함 장부 seq 경계로 도착 확인 · E8 명부 경로는 launch_roster 한 함수.
"""
import collections
import importlib.util
import json
import os

CALL_S, OPEN_S = 7, 1800
SEND_CAP, WIN = 3, 200          # r2065 E5 한 바퀴 3통 · E7 저장 끝 200줄
SEND_FAILS, ALERT_TRIES = 2, 3   # r2098 R8 send 시간 초과 2회 = 그 바퀴 남은 쪽지 미룸 · R12 알림 실제 시도 상한 3회
HARNESS, SENDER = "harness", "ft2-keeper"
HERE = os.path.dirname(os.path.abspath(__file__))


def _load(path, alias):
    spec = importlib.util.spec_from_file_location(alias, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


roster = _load(os.path.join(HERE, "launch_roster.py"), "ft2_keeper_report_roster")


class Reporting:
    def cells(self, team):
        """E1 차례 = (명부 경로, 칸 이름, 대신 받는 곳인가) · E8 명부 경로는 launch_roster.roster_path 한 함수가 정한다."""
        own, harness = roster.roster_path(self.root, team), None if team == HARNESS else roster.roster_path(self.root, HARNESS)
        return ((own, "_master", False), (own, "_desk", True), (harness, "_master", True))

    def recipients(self, team):
        """E1 처음으로 값이 있는 한 곳만(두 곳 동시 0) → (받는 곳, 대신 받는 곳인가) · 세 칸 다 빈칸 = ("", True)."""
        for path, cell, stand in self.cells(team):
            book = self.read_json(path) if path else {}
            if book.get(cell):
                return book[cell], stand
        return "", True

    def ledger(self):
        """E7 우편함 장부 자리 = <root>/.fable-team/comm/mailbox.log.jsonl (slack/wiring.landed 와 같은 파일 · 읽기만)."""
        return os.path.join(self.root, ".fable-team", "comm", "mailbox.log.jsonl")

    @staticmethod
    def _row(text):
        try:
            rec = json.loads(text)
        except ValueError:
            return None
        return rec if isinstance(rec, dict) else None

    def tail_rows(self):
        """장부 끝 200줄 → list[dict] · 못 읽음 = None(판독 불가)."""
        try:
            with open(self.ledger(), encoding="utf-8") as handle:
                tail = collections.deque(handle, WIN)
        except (OSError, ValueError):
            return None
        return [rec for rec in (self._row(line) for line in tail) if rec is not None]

    def boundary(self):
        """E7-1 seq 경계 = send 직전 장부 끝 200줄의 정수 seq 최댓값 · seq 없는 줄은 건너뜀 · 못 잡음 = None."""
        rows = self.tail_rows()
        found = [] if rows is None else [rec["seq"] for rec in rows if isinstance(rec.get("seq"), int)]
        return max(found) if found else None

    def arrived(self, seen, mark, to, body, sender=SENDER):
        """E7-3 도착 판정 = 경계보다 큰 seq 줄 중 «보낸 이 · 받는 곳 · 본문 첫 줄» 이 같은 줄이 있나.
        반환 = «있음» | «없음» | «창 밖»(경계~창 사이를 못 봤다) | «판독 불가»(경계·장부 없음).
        sender 인자 = 이 규칙을 같이 쓰는 다른 어댑터(r2065 행 G Slack 깨움)의 보낸 이."""
        if seen is None or mark is None:
            return "판독 불가"
        head = (body or "").splitlines()[:1]
        for rec in seen:
            if isinstance(rec.get("seq"), int) and rec["seq"] > mark and rec.get("from") == sender and rec.get("to") == to \
                    and (rec.get("body") or "").splitlines()[:1] == head:
                return "있음"
        seqs = [rec["seq"] for rec in seen if isinstance(rec.get("seq"), int)]
        return "창 밖" if seqs and min(seqs) > mark + 1 else "없음"

    def budget(self, team):
        """E5 한 바퀴 3통 — 넘으면 지문을 쓰지 않고 다음 바퀴 · NOTIFY-DEFER 는 바퀴 끝 flush 1줄(값이 바뀔 때만)."""
        self.deferred = getattr(self, "deferred", {})
        if getattr(self, "notify_used", 0) >= SEND_CAP:
            self.deferred[team] = self.deferred.get(team, 0) + 1
            return False
        self.notify_used = getattr(self, "notify_used", 0) + 1
        return True

    def send(self, to, body):
        """E5·E7 통 1개 — 7초 1회(재시도 0) · send 직전 seq 경계 1회 · rc≠0 이면 장부에서 도착 확인(rc 0 = 뒤 읽기 0).
        반환 = (rc, «있음»|«없음»|«창 밖»|«판독 불가»|"") — rc None = 7초 넘김 · R8 예산 미룸 = («defer», "")(호출 0 · 지문·횟수 미소비)."""
        if self.stopping():   # R8 시간 초과 2회 · R2 문(남은 몫 < 7초) = 시작 0
            return "defer", ""
        mark = self.boundary()
        rc = self.call(["bash", self.mbox, "send", to, SENDER, body], CALL_S, retry=0)[0]
        if rc is None:   # R8 — 한 바퀴 send 시간 초과 2회 = 그 바퀴 남은 쪽지 미룸
            self.send_fails = getattr(self, "send_fails", 0) + 1
            self.send_stop = self.send_fails >= SEND_FAILS
        return rc, "" if rc == 0 else self.arrived(self.tail_rows(), mark, to, body)

    def stopping(self):
        """R8 — 이 바퀴는 더 보내지 않는다(시간 초과 2회 · 남은 몫 < 7초)."""
        left = self.left()
        return bool(getattr(self, "send_stop", False) or (left is not None and left < CALL_S))

    def defer(self, team):
        """R8 — 미룬 쪽지 1통 = 지문·횟수 미소비 · 바퀴 끝 NOTIFY-DEFER 1줄(깂이 바뀔 때만)."""
        self.deferred = getattr(self, "deferred", {})
        self.deferred[team] = self.deferred.get(team, 0) + 1

    def alerts(self):
        """R12 보내기 — report 구획 머리 · 앞에서부터 1줄 1회 시도(수신자 순환) · 성공 = 지움 + FULL-ALERT 1줄 ·
        실실제 시도 실패 = tries +1 + mark + 그 받는 곳의 줄 전부를 맨 뒤로 · 3회 = 지움 + 판정 불가 1줄 + ft2-full-alert.jsonl 1줄."""
        rows = self.state.get("alert_out") or []
        if not rows:
            return
        row, to, body = rows[0], rows[0].get("to", ""), rows[0].get("body", "")
        if self.stopping():   # R12 ⑧ 지손 전에 미룸 = tries 0 · 순서 그대로 · mark 그대로
            return
        mark = row.get("mark")
        if mark and self.arrived(self.tail_rows(), mark, to, body, "ft2-full-alert") == "있음":   # 늦게 닿은 알림 = 다시 보내기 0
            rows.remove(row)
            self.log("FULL-ALERT", to, "%s (도착 확인 · rc -)" % body[:60])
            return
        mark = self.boundary()
        rc = self.call(["bash", self.mbox, "send", to, "ft2-full-alert", body], CALL_S, retry=0)[0]
        if rc == 0 or self.arrived(self.tail_rows(), mark, to, body, "ft2-full-alert") == "있음":
            rows.remove(row)
            self.log("FULL-ALERT", to, "%s%s" % (body[:60], " (도착 확인 · rc %s)" % rc if rc != 0 else ""))
            return
        row["tries"] = int(row.get("tries") or 0) + 1
        row["mark"] = "" if mark is None else mark
        mine = [r for r in rows if r.get("to") == to]   # 그 받는 곳의 줄 전부를 순서 그대로 뒤로(끊긴 사람은 다음 사람 뒤)
        self.state["alert_out"] = [r for r in rows if r.get("to") != to] + mine
        if row["tries"] >= ALERT_TRIES:   # R12 — 3회 뒤 = 지움 + 판정 불가 1줄 + jsonl 1줄(조용한 유실 0)
            self.state["alert_out"] = [r for r in self.state["alert_out"] if r is not row]
            self.log("판정 불가", text="꽉 참 알림 3회 실패 %s" % to)
            path = row.get("log") or os.path.join(self.root, ".fable-team", "state", "ft2-full-alert.jsonl")
            os.makedirs(os.path.dirname(path), exist_ok=True)
            with open(path, "a", encoding="utf-8") as fh:
                fh.write(json.dumps({"to": to, "rc": rc, "head": body[:120], "tries": row["tries"]}, ensure_ascii=False) + "\n")

    def blocked(self, key):
        """E3 지문 있음 = 다시 보내지 않는다 · fail|<날짜>| 은 그날만(날짜가 바뀌면 1회 다시 시도)."""
        got = self.state["sent"].get(key)
        return got is not None and (not str(got).startswith("fail|") or str(got).split("|")[1] == self.stamp()[:10])

    def finish(self, team, key, to, rc, seen, body):
        """E3·E7 결과 — rc 0 이거나 장부에 그 글이 있으면 성공 지문 · 아니면 fail|<날짜>|<rc> 지문(그날 재시도 0) · 판정 줄 그날 1줄."""
        ok = rc == 0 or seen == "있음"
        self.state["sent"][key] = self.stamp() if ok else "fail|%s|%s" % (self.stamp()[:10], rc)
        if ok:
            self.log("NOTIFIED", team, "%s%s %s" % (to, " (도착 확인 · rc %s)" % rc if seen == "있음" else "", body[:120]))
            return True
        self.log("판정 불가", team, "쪽지 %s%s — %s" % (rc, " 도착 판독 불가" if seen in ("창 밖", "판독 불가") else "", body[:80]))
        return False

    def stand_in(self, team, body):
        """E2 대신 받는 곳에는 글마다 보내지 않는다 — state.undelivered[팀] 에 쌓고 바퀴 끝 묶음 1통(팀당 하루 1통)."""
        heads = (body or "").splitlines()[:1] or [""]
        self.state.setdefault("undelivered", {}).setdefault(team, []).append(heads[0][:60])
        return True

    def notify(self, team, key, body):
        """팀 쪽지 1통 — E1 받는 곳 차례 · E2 대신 받는 곳 = 묶음 · E3 실패도 그날 지문 · E5 3통 상한 · E6 받는 곳 없음 · E7 도착 확인.
        반환 = 그날 지문을 썼나(True = 이 열쇠로 다시 보내지 않는다) — 상한 밖(False)이면 지문 0 · 다음 바퀴 다시."""
        if team in self.skip or self.blocked(key):   # r1835 K4 — 제외 팀 쪽지 0
            return False
        to, stand = self.recipients(team)
        if not to:   # E6 세 칸 다 빈칸 = 그날 1줄 · E3 과 같은 실패 지문
            return self.finish(team, key, "", "받는 곳 없음", "", body)
        if stand:
            return self.stand_in(team, body)
        if not self.budget(team):   # E5 상한 밖 = 지문 0 · 다음 바퀴(바퀴 끝 NOTIFY-DEFER 1줄)
            return False
        rc, seen = self.send(to, body)
        if rc == "defer":   # R8 미룸 = 지문·횟수 미소비 · 다음 바퀴
            self.notify_used = max(0, getattr(self, "notify_used", 1) - 1)
            self.defer(team)
            return False
        return self.finish(team, key, to, rc, seen, body)

    def alert_rows(self):
        return list(self.state.get("alert_out") or [])

    def flush(self):
        """바퀴 끝(report) — E2 대신 받는 곳 묶음 1통(팀당 하루 1통) · E5 NOTIFY-DEFER 1줄(값이 바뀔 때만)."""
        day, defer = self.stamp()[:10], getattr(self, "deferred", {})
        for team, book in sorted(self.state.setdefault("undelivered", {}).items()):
            key = "%s|undelivered|%s" % (day, team)
            to, stand = self.recipients(team)
            # 팀장이 다시 섰거나 · 오늘 몫은 이미 보냈거나 · 제외 팀이면 쌓기만 한다
            if book and stand and to and team not in (self.skip or ()) and not self.blocked(key):
                if self.stopping() or not self.budget(team):   # R8·E5 = 미룸(이 바퀴 더 보내기 0)
                    break
                text = "[긴급] %s 팀장 없음 · 못 전한 keeper 판정 %d건 · 앞 3건: %s" % (team, len(book), " · ".join(book[:3]))
                rc, seen = self.send(to, text)
                if rc == "defer":
                    self.notify_used = max(0, getattr(self, "notify_used", 1) - 1)
                    self.defer(team)
                    break
                if self.finish(team, key, to, rc, seen, text):
                    del book[:]   # 간 것은 지운다 — 다음 묶음 = 그 뒤에 쌓인 것
        for team, n in sorted(defer.items()):
            if self.state.setdefault("defer", {}).get(team) != n:
                self.state["defer"][team] = n
                self.log("NOTIFY-DEFER", team, "%d통 · 다음 바퀴" % n)
        for team in [name for name in self.state.get("defer", {}) if name not in defer]:   # 0 으로 돌아간 팀은 지운다(다음에 또 1줄)
            self.state["defer"].pop(team)
        self.deferred = {}

    def report(self):
        """B4 — R12 alert_out 보내기 = 구획 머리 · 끝난 뒤 30분 넘게 열린 좌석 N 1줄 · N>0 = 팀 master [크리티컬] 1통 ·
        R4 rep_cursor = 끊긴 좌석부터 이름순 · R3 끊기면 쪽지는 다음 바퀴 · flush 는 끊겨도 한다."""
        late, day = {}, self.stamp()[:10]
        self.alerts()   # R12 — 보내는 손은 report 구획에서만 문을 지난다
        seats = sorted(self.state["open"])
        cur = (self.state.get("rep_cursor") or {}).get("seat") or ""
        if cur in seats:
            seats = seats[seats.index(cur):]
        elif cur:
            self.state.pop("rep_cursor", None)   # 그 좌석이 사라졌다 = 지우고 처음부터
        try:
            for seat in seats:
                self.report_seat = seat
                seen_at = self.state["open"][seat]
                if {seen_at.get("team"), (seat.split("-") + [""])[1]} & self.skip:   # r1835 K4 — probe 전 · open 행 보존
                    continue
                seen = self.probe(seat)
                if seen == "absent":
                    self.state["open"].pop(seat)
                elif self.now() - seen_at["since"] > OPEN_S and seen == "alive":
                    late.setdefault(seen_at["team"], []).append(seat)
            line = "손 닫기 후보 %d(끝난 뒤 30분 넘게 열린 좌석)" % sum(map(len, late.values()))
            for team, seats_late in sorted(late.items()):
                fresh = [seat for seat in seats_late if "%s|open|%s" % (day, seat) not in self.state["sent"]]
                first = "%s|open|%s" % (day, fresh[0]) if fresh else ""   # 열쇠 = 처음 «안 보낸» 좌석(DA 310738 반례)
                body = "[크리티컬] %s · %s %s" % (line, team, " ".join(fresh))
                if fresh and self.notify(team, first, body):
                    got = self.state["sent"].get(first) or self.stamp()
                    self.state["sent"].update({("%s|open|%s" % (day, seat)): got for seat in fresh})
        finally:
            self.flush()   # R3 끊겨도 미룬 쪽지·NOTIFY-DEFER 줄은 남긴다
        self.state.pop("rep_cursor", None)   # R4 끊김 없이 다 돌았다
        return line
