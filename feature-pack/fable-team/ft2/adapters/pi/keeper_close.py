"""ft 2.0 keeper — B2 착지 끝 나노 세션 닫기 · B3 승계 끝 옛 좌석 닫기 (r1812 · keeper.py 가 섞어 쓴다).

kill = tmux 세션 1개씩(kill-server 0) · 대상 = launch intent 의 FT2_HOLDER 나노만 · 워크트리·가지·명부 행 삭제 0.
닫기 영수 = 공개 API CloseNext(probe).receipt 같은 프로세스 · 증거(v1·v2)는 만들지 않는다 → 다음 배정 0(팀장 몫).
B3 = 1.x ft-seat-close(가드 그대로) 1회 · 실패·HELD 는 10분 안 재시도 0.
"""
import glob
import importlib.util
import os
import re

FT2 = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
GIT_S, RETRY_S = 25, 600
BUSY = re.compile("Working|[⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏]")
OK = "접수 성공"


def _load(name):
    spec = importlib.util.spec_from_file_location("ft2_keeper_close_" + name, os.path.join(FT2, "core", name + ".py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


projection, close_next = _load("projection"), _load("close_next")


class Closing:
    def probe(self, seat):
        """tmux 부재 판독기 — rc1 + «can't find session»(서버 없음 포함) = absent · rc0 = alive · 그 밖 = 판정 불가 문자열."""
        rc, _, err = self.call([self.tmux, "has-session", "-t", "=" + seat])
        if rc == 1 and ("can't find session" in err or "no server running" in err):
            return "absent"
        if rc == 0:
            return "alive"
        return "판정 불가 · tmux has-session rc %s %s" % (rc, err)

    def close(self, team, work, attempt, row):
        """B2 — intent holder 나노 · 착지 조상 · pane 유휴 → kill 1 → 부재 확인 → 닫기 영수."""
        launch = os.path.join(projection.runtime_path(self.root, team), "launch")
        intent = self.read_json(os.path.join(launch, "%s@%s.intent" % (work, attempt)))
        holder, gen = intent.get("FT2_HOLDER"), row.get("gen") or 1
        if intent.get("state") != "opened" or not holder:
            return
        seen = self.landing(team, work)[2] or self.probe(holder)
        if seen == "alive":
            self.state["open"].setdefault(holder, {"team": team, "since": self.now()})
            if not self.idle(team, work, holder):
                return
            self.call([self.tmux, "kill-session", "-t", "=" + holder])
            seen = self.probe(holder)
            if seen != "absent":
                return self.log("HELD", team, "%s %s 부재 확인 없음(%s)" % (work, holder, seen))
            self.log("CLOSED-SESSION", team, "%s %s" % (work, holder))
        elif seen != "absent":
            return self.log("HELD", team, "%s %s %s" % (work, holder, seen))
        self.state["open"].pop(holder, None)
        self.receipt(team, work, attempt, holder, gen)

    def idle(self, team, work, holder):
        """pane 에 Working·스피너 없음 = 참 · capture 실패 = 판정 불가(거짓)."""
        rc, pane, _ = self.call([self.tmux, "capture-pane", "-p", "-t", "=" + holder])
        if rc != 0:
            return self.log("HELD", team, "%s %s 판정 불가 · capture rc %s" % (work, holder, rc))
        if BUSY.search(pane[-2000:]):
            return self.log("HELD", team, "%s %s Working" % (work, holder))
        return True

    def receipt(self, team, work, attempt, holder, gen, probe=None):
        """닫기 영수 1건 · 증거 () = 다음 배정 0. 영수·켜기 전 유보·재접수 = 다시 보지 않음(handled)."""
        node = close_next.CloseNext(self.root, team, probe=probe or self.probe)
        out = node.receipt(holder, gen, work, "keeper:%s@%s" % (work, attempt), holder, ())
        kind = {OK: "RECEIPT", "접수 거부": "RECEIPT-REFUSED"}.get(out.result)
        if kind is None:
            kind = "RECEIPT-HOLD" if "켜기 전" in out.reason else "RECEIPT-UNSURE"
        self.log(kind, team, "%s %s %s · %s" % (work, holder, out.result, out.reason))
        if kind in ("RECEIPT", "RECEIPT-HOLD") or "재접수" in out.reason:
            self.state["handled"]["%s|%s@%s" % (team, work, attempt)] = self.stamp()
        return out

    def retired(self):
        """B3② — 명부 `_replaced_by` 행 + 세션 생존 → ft-seat-close 1회."""
        for path in sorted(glob.glob(os.path.join(self.root, ".fable-team", "seats*.json"))):
            for seat, row in sorted(self.read_json(path).items()):
                new = row.get("_replaced_by") if isinstance(row, dict) else None
                if isinstance(new, str) and new and self.retire_one(path, seat, new) == "stop":
                    return

    def retire_one(self, path, seat, new):
        name = os.path.basename(path)[:-5]
        if self.probe(seat) != "alive":
            self.state["open"].pop(seat, None)
            return
        team = name[6:] if name.startswith("seats-") else "v65"
        self.state["open"].setdefault(seat, {"team": team, "since": self.now()})
        if self.now() - self.state["held"].get(seat, -RETRY_S) < RETRY_S:
            return
        if not self.close_bin:
            self.log("판정 불가", text="ft-seat-close 경로 없음(FT_SEAT_CLOSE_BIN) — B3 0")
            return "stop"
        argv = ["bash", self.close_bin, seat, "--reason", "retire -> " + new, "--seats", path]
        rc, out, err = self.call(argv, GIT_S)
        first = ((out or err).strip().splitlines() or [""])[0][:160]
        self.log("CLOSED-SEAT" if rc == 0 else "HELD-SEAT", name, "%s rc %s %s" % (seat, rc, first))
        self.state["held"][seat] = self.now()
        if rc == 0:
            self.state["held"].pop(seat)
            self.state["open"].pop(seat, None)
