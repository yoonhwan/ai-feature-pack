#!/usr/bin/env python3
# pyright: basic
"""ft_stall_scan.py [--dry-run] — 멈춘 좌석 4종을 세고(판정 = ft_stall_detect) 그 실행에서 처리한다 (R320b · 오빠 판정 2170 · 사전 DA r1 반영).

출력 1줄째 `stall=N a=.. b=.. c=.. d=.. seats=.. u=.. ts=..`(u = 판정 불가: UNKNOWN·TURN_END `-` · 처리 0) + 좌석별 1줄 `<종류> <좌석> <나이분> <근거>`.
나이 = 지금 − TURN_END(DURATION_MS 아님). a = 그 팀이 «지금 spawn 가능» 일 때만(팀 상한 미만 ∧ 정지 파일 없음 ∧ 페널티 아님).
처리(--dry-run 이면 0): a→master urgent · b→Escape+ring+쪽지 · c→planner [긴급] · d→받는이의 «가장 오래된 pending seq» ring.
★처리 단위 = 좌석(종류 무관) 10분에 1번(상태파일 + stall-scan.log 이중) · 직전 IDLE·attached 재확인 · attached 는 표시만★.
a·b·d 를 «처리한 뒤 다음 실행에도» 또 보면 ft-penalty.sh on (c 제외 · FT_STALL_PENALTY_AUTO=0 으로 끔 · 복구 팀 harness·planner 는 정지 대상 아님).
env(시험): FT_ROOT · FT_NOW · FT_SEAT_STATUS · FT_TMUX · FT_MBOX_SH · FT_INDEX_LINT · FT_MBOX_DIR · FT_STALL_STATE_DIR.
"""
import json
import os
import sys
import time
from pathlib import Path

import ft_penalty
from ft_stall_detect import IDLE_MIN, load_teams, pending_mail, policy_stop, run, spawn_capacity, waiting_cards
from ft_stall_seats import Seats
import ft_stall_state as stm

HERE = Path(__file__).resolve().parent
REPEAT_S = stm.REPEAT_S


class Scan:
    def __init__(self) -> None:
        self.root = ft_penalty.root()
        self.now = ft_penalty.now()
        self.status = os.environ.get("FT_SEAT_STATUS") or str(HERE / "ft-seat-status.sh")
        self.tmux = ["bash", os.environ["FT_TMUX"]] if os.environ.get("FT_TMUX") else ["tmux"]  # 시험 = 스텁 스크립트
        self.mbox = os.environ.get("FT_MBOX_SH") or str(self.root / ".fable-team/comm/mbox.sh")
        self.lint = os.environ.get("FT_INDEX_LINT") or str(HERE / "ft-index-lint.sh")
        self.sender = os.environ.get("FT_STALL_FROM", "ft-stall-scan")
        self.state_dir = Path(os.environ.get("FT_STALL_STATE_DIR") or ft_penalty.state_dir())
        self.comm = Path(os.environ.get("FT_MBOX_DIR") or self.root / ".fable-team/comm")
        self.live = self.sessions()
        self.cap_cmd = os.environ.get("FT_SEAT_CAP_PY") or str(HERE / "ft_seat_cap.py")
        self.notes: list[str] = []
        self.st = stm.load(self.state_dir)
        self.seats = Seats(self.status, self.now, self.st.setdefault("seats", {}))

    def sessions(self) -> dict[str, int]:
        live: dict[str, int] = {}
        for line in run([*self.tmux, "list-sessions", "-F", "#{session_name} #{session_attached}"])[1].splitlines():
            p = line.rsplit(" ", 1)
            if len(p) == 2 and p[1].isdigit():
                live[p[0]] = int(p[1])
        return live

    def turn(self, seat: str, fresh: bool = False) -> tuple[str, float | None]:
        if seat not in self.live:
            return "UNKNOWN", None
        i = self.seats.info(seat, force=fresh)
        return i["state"], i["end"]

    def idle_age(self, seat: str, fresh: bool = False) -> float | None:
        state, end = self.turn(seat, fresh)
        return (self.now - end) / 60 if state == "IDLE" and end is not None else None

    def flags(self, seat: str) -> dict:
        return self.seats.info(seat)

    def find(self, penalty: dict | None) -> tuple[list[dict], int]:
        out: list[dict] = []
        unknown = 0
        notes: list[str] = []
        exempt = ft_penalty.EXEMPT
        resumed = set((penalty or {}).get("resumed") or [])
        mail = pending_mail(self.comm, self.now)
        stop = policy_stop(self.root, self.now, os.environ.get("FT_SPAWN_HOLD_SH") or str(HERE / "ft-spawn-hold.sh"))

        def held(team: str) -> bool:  # 정지 중이고 재개 전인 팀 — 처리 0 (복구 팀은 대상 아님)
            return penalty is not None and team not in resumed and team not in exempt

        for t in load_teams(self.root):
            m = t["master"]
            # a — 그 팀이 지금 spawn 가능(유효 정지 아님 ∧ 페널티 중이면 재개된 팀 ∧ 실제 spawn 상한 판정 통과)일 때만. 정상 대기는 세지 않는다.
            cap = "ok"
            if m in self.live and not stop and not held(t["team"]):
                cap = spawn_capacity(self.root, t["team"], self.cap_cmd)
                if cap == "unknown":
                    unknown += 1
                    notes.append(f"a? {m} 상한 판정 불가(ft_seat_cap ERROR·없음) — a 세지 않음")
            if m in self.live and not stop and not held(t["team"]) and cap == "ok":
                age = self.idle_age(m)  # 싼 판정(캐시)이 먼저 — master 가 IDLE 3분+ 일 때만 카드 lint(카드당 프로세스)를 돈다
                n = waiting_cards(t["cards"], self.lint) if age is not None and age >= IDLE_MIN else 0
                if n and not self.flags(m)["rest"] and (self.idle_age(m, fresh=True) or 0) >= IDLE_MIN:
                    out.append(dict(kind="a", seat=m, team=t["team"], age=self.idle_age(m), why=f"대기 카드 {n}장 · master IDLE", n=n))
            for s in sorted(t["seats"]):
                if s not in self.live:
                    continue
                state, end = self.turn(s)
                if state == "UNKNOWN" or end is None and state == "IDLE":
                    unknown += 1
                    continue
                age = self.idle_age(s)
                if age is None or age < IDLE_MIN or self.flags(s)["rest"]:
                    continue
                if (self.flags(s)["future"] or s in mail) and self.idle_age(s, fresh=True) is None:  # 후보는 경로까지 다시 풀어 확인(새 jsonl 로 이어간 좌석 오탐 방지)
                    continue
                age = self.idle_age(s) or age
                if self.flags(s)["rest"]:
                    continue
                if self.flags(s)["future"]:
                    out.append(dict(kind="b", seat=s, team=t["team"], age=age, why="미래형 선언으로 끝나고 도구 0"))
                if s in mail:
                    out.append(dict(kind="d", seat=s, team=t["team"], age=age, why=f"미읽음 쪽지 seq={mail[s][0]} {mail[s][1]:.0f}분", seq=mail[s][0]))
        if stop:
            out.append(dict(kind="c", seat="harness", team="-", age=0.0, why=stop))
        for f in out:
            f["attached"] = self.live.get(f["seat"], 0) > 0
            f["held"] = held(f["team"])
        self.notes = notes
        return out, unknown

    def send(self, to: str, body: str, urgent: bool = True) -> None:
        run(["bash", self.mbox, "send", to, self.sender, body] + (["--urgent"] if urgent else []))

    def wake(self, seat: str, seq: int | None) -> bool:
        self.live = self.sessions()  # 직전 재확인 — 그 사이 attached 되거나 WORKING 이 됐으면 0
        if self.live.get(seat, 0) > 0 or self.idle_age(seat, fresh=True) is None or self.idle_age(seat) < IDLE_MIN:
            return False
        for line in run([*self.tmux, "list-panes", "-a", "-F", "#{session_name}|#{pane_id}"])[1].splitlines():
            name, _, pane = line.partition("|")
            if name == seat and pane:
                run([*self.tmux, "send-keys", "-t", pane, "Escape"])
                break
        run(["bash", self.mbox, "ring", seat] + ([str(seq)] if seq else []))
        return True

    def act(self, f: dict) -> str | None:
        k, seat = f["kind"], f["seat"]
        if k == "a":
            self.send(seat, f"[stall a] 대기 카드 {f['n']}장 · master IDLE {f['age']:.0f}분 — 빈 석 확인하고 지금 spawn (ft-stall-scan)")
        elif k == "b":
            if not self.wake(seat, None):
                return None
            self.send(seat, f"[stall b] 선언 뒤 정지 {f['age']:.0f}분 — 지금 도구를 불러라 (ft-stall-scan)", urgent=False)
        elif k == "d":
            if not self.wake(seat, f["seq"]):
                return None
        else:
            seat = next((t["master"] for t in load_teams(self.root) if t["team"] == "planner"), None)
            if not seat:
                return None
            self.send(seat, f"[긴급] 정지 중: {f['why']} — 기한·해제 조건 확인 · 지금 해제 가능한지 판단 (ft-stall-scan c)")
        return f"act={k} to={seat}"

    def run(self, dry: bool) -> int:
        pen = ft_penalty.load()
        found, unknown = self.find(pen)
        handled, prev = self.st.get("handled", {}), set(self.st.get("prev", []))
        keys = {f"{f['kind']}:{f['seat']}": f for f in found}
        counts = {k: sum(1 for f in found if f["kind"] == k) for k in "abcd"}
        trig = sorted(k for k, f in keys.items() if k[0] in "abd" and k in prev and f["seat"] in handled and not f["attached"] and not f["held"])
        lines = [f"stall={len(found)} a={counts['a']} b={counts['b']} c={counts['c']} d={counts['d']} seats={len(self.live)} u={unknown} ts={int(self.now)}"]
        lines += [f"{f['kind']} {f['seat']} {f['age']:.0f} {f['why']}" + (" (attached·처리 0)" if f["attached"] else " (정지 중 처리 0)" if f["held"] else "") for f in found]
        lines += self.notes
        print("\n".join(lines))
        if dry:
            return 0
        stamp = time.strftime("%Y-%m-%dT%H:%M:%S", time.localtime(self.now))
        log: list[str] = []
        d_seats = {f["seat"] for f in found if f["kind"] == "d"}
        for f in found:
            if f["kind"] == "b" and f["seat"] in d_seats:  # b+d 동시 = d 한 번(가장 오래된 pending seq ring · 새 send 생략)
                continue
            if f["attached"] or f["held"] or self.now - float(handled.get(f["seat"], 0)) < REPEAT_S or stm.recent_in_log(self.state_dir, f["seat"], self.now):
                continue
            res = self.act(f)
            if res:
                handled[f["seat"]] = self.now
                log.append(f"{stamp} {res} key={f['kind']}:{f['seat']} {f['why']}")
        if trig and pen is None and os.environ.get("FT_STALL_PENALTY_AUTO", "1") != "0":
            _ = ft_penalty.turn_on("같은 멈춤을 처리 뒤에도 또 감지: " + ",".join(trig))
            log.append(f"{stamp} penalty-on keys={','.join(trig)}")
        per_team = {}
        for t in load_teams(self.root):
            st_m, end_m = self.turn(t["master"]) if t["master"] in self.live else ("UNKNOWN", None)
            per_team[t["team"]] = {k: sum(1 for f in found if f["team"] == t["team"] and f["kind"] == k) for k in "abd"}
            per_team[t["team"]]["master_end"] = end_m if st_m == "IDLE" else None
        stm.save(self.state_dir, handled, sorted(keys), self.st["seats"])
        _ = (self.state_dir / "stall-scan.last.json").write_text(json.dumps({"ts": self.now, "c": counts["c"], "teams": per_team}), encoding="utf-8")
        with open(self.state_dir / "stall-scan.log", "a", encoding="utf-8") as fh:
            _ = fh.write("".join(x + "\n" for x in log) + lines[0] + "\n")
        return 0


def main(argv: list[str]) -> int:
    dry = "--dry-run" in argv
    state_dir = Path(os.environ.get("FT_STALL_STATE_DIR") or ft_penalty.state_dir())
    with stm.single_run(state_dir) as got:
        if not got:
            print("stall-scan 앞 실행이 아직 돈다 — 이번 틱 건너뜀")
            return 0
        return Scan().run(dry)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
