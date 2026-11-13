"""ft 2.0 keeper — B4 보고 = 닫기까지 · 팀 master 쪽지 (r1812 · keeper.py 가 섞어 쓴다).

끝난 뒤 30분 넘게 열린 좌석 = state.open(처음 본 시각) 중 지금도 살아 있는 것 · 쪽지는 같은 열쇠 1회(하루 같은 좌석 1회).
"""
import os

CALL_S, OPEN_S = 7, 1800


class Reporting:
    def notify(self, team, key, body):
        """팀 master 에 쪽지 1통(7초 + 재시도 1) · 같은 열쇠 재발신 0 · 실패 = 판정 불가 1줄."""
        if key in self.state["sent"] or team in self.skip:   # r1835 K4 — 제외 팀 쪽지 0
            return False
        roster = self.read_json(os.path.join(self.root, ".fable-team", "seats-%s.json" % team))
        master = roster.get("_master")
        rc = "_master 없음"
        if master:
            rc = self.call(["bash", self.mbox, "send", master, "ft2-keeper", body], CALL_S, retry=1)[0]
        if rc != 0:
            return self.log("판정 불가", team, "쪽지 %s — %s" % (rc, body[:80]))
        self.state["sent"][key] = self.stamp()
        self.log("NOTIFIED", team, "%s %s" % (master, body[:120]))
        return True

    def report(self):
        """B4 — 끝난 뒤 30분 넘게 열린 좌석 N 1줄 · N>0 = 팀 master [크리티컬] 1통(하루 같은 좌석 1회)."""
        late, day = {}, self.stamp()[:10]
        for seat, seen_at in sorted(self.state["open"].items()):
            if {seen_at.get("team"), (seat.split("-") + [""])[1]} & self.skip:   # r1835 K4 — probe 전 · open 행 보존
                continue
            seen = self.probe(seat)
            if seen == "absent":
                self.state["open"].pop(seat)
            elif self.now() - seen_at["since"] > OPEN_S and seen == "alive":
                late.setdefault(seen_at["team"], []).append(seat)
        line = "손 닫기 후보 %d(끝난 뒤 30분 넘게 열린 좌석)" % sum(map(len, late.values()))
        for team, seats in sorted(late.items()):
            fresh = [seat for seat in seats if "%s|open|%s" % (day, seat) not in self.state["sent"]]
            body = "[크리티컬] %s · %s %s" % (line, team, " ".join(fresh))
            if fresh and self.notify(team, "%s|open|%s" % (day, fresh[0]), body):
                self.state["sent"].update({"%s|open|%s" % (day, seat): self.stamp() for seat in fresh})
        return line
