#!/usr/bin/env python3
# pyright: basic
"""ft_stall_scan.py [--dry-run] — 멈춘 좌석 4종을 세고(판정 = ft_stall_detect) 그 실행에서 처리한다 (R320b · 오빠 판정 2170 · 사전 DA r1 반영).

출력 1줄째 `stall=N a=.. b=.. c=.. d=.. e=.. seats=.. u=.. ts=..`(u = 판정 불가: UNKNOWN·TURN_END `-` · 처리 0) + 좌석별 1줄 `<종류> <좌석> <나이분> <근거>`.
나이 = 지금 − TURN_END(DURATION_MS 아님). a = 그 팀이 «지금 spawn 가능» 일 때만(팀 상한 미만 ∧ 정지 파일 없음 ∧ 페널티 아님).
처리(--dry-run 이면 0): a→master urgent · b→Escape+ring+쪽지 · c→planner [긴급] · d→받는이의 «가장 오래된 pending seq» ring.
★처리 단위 = 좌석(종류 무관) 10분에 1번(상태파일 + stall-scan.log 이중) · 직전 IDLE·attached 재확인 · attached 는 표시만★.
a·b·d 를 «처리한 뒤 다음 실행에도» 또 보면 ft-penalty.sh on (c 제외 · FT_STALL_PENALTY_AUTO=0 으로 끔 · 복구 팀 harness·planner 는 정지 대상 아님).
r525 e = 명부 루프가 안 본 tmux 라이브 좌석(교대 표시·명부 밖) ∧ claude|codex ∧ IDLE ≥ FT_STALL_E_IDLE_MIN(30) ∧ (ctx ≥ 90 ∨ [완료·휴식] 없음)
→ planner + 계보 현역 master 에 [정지] 1통 · 같은 서명(좌석·IDLE 시작 시각) 재알림 0 · 깨우기·kill 0 · 요약 줄 d= 뒤 e= 칸.
r849(재설계 r4 · r3) l = 로그아웃 좌석 — 쪽지는 «로그아웃 구간당 1통», 키 = 칸(state/stall/logged-out.<좌석 계보>) 하나(프로세스 시작 시각·첫 실패 시각·pid 를 키에 안 쓴다 · DA⑥ r2 반례 1) · r3(DA⑥ r3 반례 3·4): 칸은 «발신 전에» 세우고 발신 rc≠0 이면 지운다 · 칸 자리가 파일이 아니면(폴더 등) ERROR 1줄 + 그 좌석 발신 0.
r1001 f = 팀장 심박 끊김 — 현역 role=master 좌석들의 b·d 를 «팀 단위» 로 묶고 판정은 ft_stall_detect.lead_alert 하나만 쓴다(신선 = 그 팀 0통 · 끊김·없음 = `[멈춤]` 1통 · 판정 불가 = u + 처리 0) · env FT_ROOT · FT_NOW · FT_SEAT_STATUS · FT_TMUX · FT_MBOX_SH · FT_INDEX_LINT · FT_MBOX_DIR · FT_STALL_STATE_DIR · FT_PS · FT_CTX_CMD · FT_LEAD_HEARTBEAT_MIN · FT_STALL_HEARTBEAT_BUDGET · FT_STALL_PAUSED_SKIP(0 = 정지 표식 팀 판정 끔).
"""
import json
import os
import sys
import time
from pathlib import Path

import ft_card_assign_pause as pause
import ft_headline_seats as headline_seats
import ft_penalty
import ft_stall_headline as headline
from ft_stall_detect import IDLE_MIN, agent_sessions, api_outage, card_gate, ctx_pct, lead_alert, lead_heartbeat_min, lead_names, load_teams, off_roster_live, pending_mail, policy_stop, run, spawn_capacity, waiting_cards, RefUnavailable
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
        self.ps = ["bash", os.environ["FT_PS"]] if os.environ.get("FT_PS") else ["ps"]
        self.ctx_cmd = os.environ.get("FT_CTX_CMD") or str(HERE / "ft-claude-context.sh")
        self.e_min = float(os.environ.get("FT_STALL_E_IDLE_MIN") or 30)
        self.notes: list[str] = []
        self.loggedout: list[tuple[str, str | None, float | None]] = []  # r849 (좌석, 팀 _master, 첫 실패 epoch)
        self.recovered: set[str] = set()  # r849 — 이번 scan 에 정상 턴(IDLE·WORKING)으로 읽힌 좌석(로그아웃 칸 지움)
        self.st = stm.load(self.state_dir)
        self.nudged = stm.nudged_load(self.st)  # r1238 A-r4b-1 — 카드 stem → 마지막 a 재촉 epoch(저장본에서 복원)
        self.flow = os.environ.get("FT_CARD_FLOW_SH") or str(HERE / "ft-card-flow.sh")
        self.errs: list[str] = []  # r1238 A-r4b-2 — 처리 단계 로그 꼬리(발신 실패 등)
        self.seats = Seats(self.status, self.now, self.st.setdefault("seats", {}))
        self.flags = self.seats.info  # r1001 — 얇은 위임 하나로 줄인다(동작 동일)

    def sessions(self) -> dict[str, int]:
        live: dict[str, int] = {}
        for line in run([*self.tmux, "list-sessions", "-F", "#{session_name} #{session_attached}"])[1].splitlines():
            name, _, att = line.rpartition(" ")
            if name and att.isdigit():
                live[name] = int(att)
        return live

    def turn(self, seat: str, fresh: bool = False) -> tuple[str, float | None]:
        i = self.seats.info(seat, force=fresh) if seat in self.live else {"state": "UNKNOWN", "end": None}
        return i["state"], i["end"]

    def idle_age(self, seat: str, fresh: bool = False) -> float | None:
        state, end = self.turn(seat, fresh)
        return (self.now - end) / 60 if state == "IDLE" and end is not None else None

    def find(self, penalty: dict | None) -> tuple[list[dict], int]:
        out: list[dict] = []
        unknown = 0
        notes: list[str] = []
        exempt = ft_penalty.EXEMPT
        resumed = set((penalty or {}).get("resumed") or [])
        mail = pending_mail(self.comm, self.now)
        stop = policy_stop(self.root, self.now, os.environ.get("FT_SPAWN_HOLD_SH") or str(HERE / "ft-spawn-hold.sh"))
        if stop and stop.startswith("ERROR"):
            notes.append(f"{stop} — a 독촉 0")  # 판정기가 죽었으면 a 를 세지 않는다

        pcache: dict[str, bool] = {}  # r1307 — 팀 정지 표식(.fable-team/state/<팀>-tick/PAUSED · r1291 정본) 판정 캐시(이번 scan 안 1회 · 넘어 남는 상태 0)
        def paused(team: str) -> bool:  # r1307 on = 정지 중 · q = 막지 않음 + WARN 1줄(지역 notes — self.notes 대입에 덮이지 않게 · 하드 룰 20)
            if team != "-" and team not in pcache and os.environ.get("FT_STALL_PAUSED_SKIP", "1") != "0":
                try:
                    st, why, _ts, _v = pause.team_paused(self.root, team)
                except Exception as e:  # noqa: BLE001 — 판정 불가도 «막지 않음»(하드 룰 20)
                    st, why = "q", f"판정 불가 {e.__class__.__name__}"
                pcache[team] = st == "on"
                if st == "q":
                    notes.append(f"WARN 정지 표식 판정 불가 — 경보 보냄({team} · {why})")
            return pcache.get(team, False)
        def held(team: str) -> bool:  # 정지 중이고 재개 전인 팀 — 처리 0 (복구 팀은 대상 아님 · r1307 표식 팀 포함)
            return (penalty is not None and team not in resumed and team not in exempt) or paused(team)

        ob = api_outage(self.root, self.now)  # r1238 B — API 장애 상태(읽기 전용 · 정본 ft-api-outage). 장애 중이면 b·d·f 보류 · 끝 뒤 15분은 나이를 «끝 시각» 부터 센다
        notes += ob["notes"]
        hold = ob["since"] is not None
        rel = ob["released"]
        lag = (self.now - rel) / 60 if not hold and rel is not None and 0 <= self.now - rel < lead_heartbeat_min() * 60 else None  # 끝 뒤 경과 분(유예 중일 때만)
        supp: dict[str, set[str]] = {"b": set(), "d": set(), "f": set()}  # 보류·유예로 out 에 안 넣은 것(b·d = 좌석 · f = 팀) — 셈만

        def quiet(age: float) -> bool:  # 장애 중이거나 끝 뒤 유예(나이 = min(나이, 끝 뒤 경과) < 심박 임계)
            return hold or lag is not None and min(age, lag) < lead_heartbeat_min()

        teams, hbd = load_teams(self.root), {}
        for t in teams:
            if t["diag"] != "OK":
                unknown += 1
                continue
            m = t["master"]
            leads = lead_names(self.root, m)  # 현역 role=master 전부 — 승계 직후 옛·새 둘 다
            if m in self.live and not stop and t["master_stop"]:  # r428 — 정지 레디 팀은 노는 게 맞다: a 대신 c(정지 파일 0 알림)
                out.append(dict(kind="c", seat=m, team=t["team"], age=0.0, why="정지 레디(명부 role=stop-ready)인데 정지 파일 0 — `ft-spawn-hold.sh set` 필요 · 독촉 0", stopready=True))
            # a — 그 팀이 지금 spawn 가능(유효 정지 아님 ∧ 정지 레디 아님 ∧ 페널티 중이면 재개된 팀 ∧ 실제 spawn 상한 판정 통과)일 때만. 정상 대기는 세지 않는다.
            cap = "ok"
            can_a = m in self.live and not stop and not t["master_stop"] and not held(t["team"])
            if can_a:
                cap = spawn_capacity(self.root, t["team"], self.cap_cmd)
                if cap == "unknown":
                    unknown += 1
                    notes.append(f"a? {m} 상한 판정 불가(ft_seat_cap ERROR·없음) — a 세지 않음")
            if can_a and cap == "ok":
                age = self.idle_age(m)  # 싼 판정(캐시)이 먼저 — master 가 IDLE 3분+ 일 때만 카드 lint(카드당 프로세스)를 돈다
                names, u = [], 0
                if age is not None and age >= IDLE_MIN:
                    try:
                        names, u = waiting_cards(t["cards"], self.lint, self.root, self.now, self.nudged, notes)
                    except RefUnavailable as e:  # r1330 A4 — 기준 ref 트리를 못 읽음: 그 팀 a 0 + 판정 불가 1줄(조용한 0 아님)
                        unknown += 1
                        notes.append(f"a? {t['team']} 대기 카드 판정 불가 — {e}")
                if names and not self.flags(m)["rest"] and (self.idle_age(m, fresh=True) or 0) >= IDLE_MIN:
                    n = len(names)
                    listed = f"대기 카드 {n}장({', '.join(names[:5])}{f' +{n - 5}' if n > 5 else ''}) · 선행 미판정 {u}장 제외"
                    out.append(dict(kind="a", seat=m, team=t["team"], age=self.idle_age(m), why=f"{listed} · master IDLE", listed=listed, cards=list(names)))
            for s in sorted(t["seats"], key=lambda x: (x not in leads, x)):  # 현역 팀장 먼저(팀당 1통은 _master 것)
                stm.progress(len(self.live))  # r1282 — 좌석마다 판정 기한 검사
                if s not in self.live:
                    continue
                state, end = self.turn(s)
                if state == "LOGGEDOUT":  # r849 — 쉬는 좌석 아님(a·b·d 0) · 팀장 1통은 act_l
                    self.loggedout.append((s, t["master"], end))
                    continue
                if state in ("IDLE", "WORKING"):  # r849 — 정상 턴 = 로그아웃 아님(칸 지움) · UNKNOWN 은 칸 그대로
                    self.recovered.add(s)
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
                if s in leads and not t["master_stop"]:  # r1001 — 현역 팀장 b·d 는 «팀 단위 심박» 만 본다
                    alert, hba, undec = hbd.setdefault(t["team"], lead_alert(self.root, self.comm, m, self.now))
                    if undec:  # 판정 불가 = 조용한 «경보 0» 아님(u 칸 · 처리 0)
                        unknown += 1
                        notes.append(f"f? {s} 팀장 심박 판정 불가 — b·d·f 세지 않음")
                    elif alert and not any(x["kind"] == "f" and x["team"] == t["team"] for x in out):  # 신선 = 0통 · 팀당 1통
                        if hold or lag is not None and min(lead_heartbeat_min() + 1 if hba is None else hba, lag) <= lead_heartbeat_min():  # r1238 B — 심박 나이 = min(심박, 끝 뒤 경과)
                            supp["f"].add(t["team"])
                            continue
                        out.append(dict(kind="f", seat=s, team=t["team"], key=f"f:{t['team']}", age=age, hb_age=hba, seq=mail[s][0] if s in mail else None,
                                        why="팀장 " + (f"심박 없음(최근 {lead_heartbeat_min():g}분 [정리] 0)" if hba is None else f"심박 {hba:.0f}분")))
                    continue
                if self.flags(s)["future"]:
                    if quiet(age):
                        supp["b"].add(s)
                    else:
                        out.append(dict(kind="b", seat=s, team=t["team"], age=age, why="미래형 선언으로 끝나고 도구 0"))
                if s in mail and quiet(age):
                    supp["d"].add(s)
                elif s in mail:
                    out.append(dict(kind="d", seat=s, team=t["team"], age=age, why=f"미읽음 쪽지 seq={mail[s][0]} {mail[s][1]:.0f}분", seq=mail[s][0]))
        if stop:
            out.append(dict(kind="c", seat="harness", team="-", age=0.0, why=stop))  # 정지 1건 = 하네스 전체
        out += self.find_e(teams)
        headline_found, headline_unknown, headline_notes = headline.find(self.root, teams, self.now, stop)
        out += headline_found
        unknown += headline_unknown
        notes += headline_notes
        for f in out:
            f["attached"] = self.live.get(f["seat"], 0) > 0
            f["held"] = held(f["team"])
        cnt = " · ".join(f"{k} {len(v)}" for k, v in supp.items())
        if hold:  # r1238 B — 장애 중: b·d·f 는 out 에 안 넣고 셈만(스캔마다 1줄 · 장애 끝나면 사라짐)
            notes.append(f"보류 — API 장애 중(since {time.strftime('%H:%M', time.localtime(ob['since']))}) · {cnt}")
        elif lag is not None and any(supp.values()):  # 끝 뒤 유예에서 실제로 막은 게 있을 때만
            notes.append(f"유예 — API 장애 끝 {time.strftime('%H:%M', time.localtime(rel))} 뒤 {lag:.0f}분(심박 임계 {lead_heartbeat_min():g}분 안) · {cnt}")
        self.notes = notes
        return out, unknown

    def find_e(self, teams: list[dict]) -> list[dict]:
        """r525 e — 판정만. ctx 는 IDLE 문턱을 넘은 후보만 잰다(못 재면 «ctx ?» · 판정은 [완료·휴식] 유무로만)."""
        cands = off_roster_live(self.root, self.live, teams)
        agents = agent_sessions(self.tmux, self.ps) if cands else set()
        out: list[dict] = []
        for s, lineage, tag in cands:
            if s in agents and self.turn(s)[0] == "LOGGEDOUT":  # r849 — 교대 표시·명부 밖 좌석도 로그아웃이면 계보 현역 master 1통(act_l)
                self.loggedout.append((s, lineage, self.turn(s)[1]))
                continue
            if s in agents and self.turn(s)[0] in ("IDLE", "WORKING"):
                self.recovered.add(s)
            age = self.idle_age(s) if s in agents else None
            if age is None or age < self.e_min:
                continue
            pct, rest = ctx_pct(self.ctx_cmd, s), self.flags(s)["rest"]
            if rest and (pct is None or pct < 90):
                continue
            why = tag + ("" if rest else " · 열린 일") + (f" · ctx {pct}%" if pct is not None else " · ctx ?")
            out.append(dict(kind="e", seat=s, team="-", age=age, why=why, lineage=lineage, sig=str(self.turn(s)[1])))
        return out

    def act_e(self, found: list[dict], stamp: str) -> list[str]:
        """e 알림 — planner + 계보 현역 master · 서명(좌석 → IDLE 시작 시각)이 같으면 0 · 서명 파일 = state/stall-scan.e.json."""
        path = self.state_dir / "stall-scan.e.json"
        try:
            sigs = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            sigs = {}
        planner = next((t["master"] for t in load_teams(self.root) if t["diag"] == "OK" and t["team"] == "planner"), None)
        log: list[str] = []
        for f in found:
            if f["kind"] != "e" or sigs.get(f["seat"]) == f["sig"]:
                continue
            to = [x for x in dict.fromkeys([planner, f["lineage"]]) if x]
            for x in to:
                self.send(x, f"[정지] {f['seat']} 쉬는 {f['age']:.0f}분 · {f['why']} · 깨우기/닫기/인계는 받는 쪽 판단 (ft-stall-scan e)")
            sigs[f["seat"]] = f["sig"]
            log.append(f"{stamp} act=e seat={f['seat']} notify={','.join(to) or '-'} {f['why']}")
        _ = path.write_text(json.dumps({s: v for s, v in sigs.items() if s in self.live}), encoding="utf-8")
        return log

    def cell(self, seat: str) -> Path:
        """r849(재설계 r4) — 로그아웃 구간 칸 = state/stall/logged-out.<좌석 계보> · 실재하면 «이미 알렸다»(구간당 1통) · 시작 시각·pid 를 키에 안 쓴다(DA⑥ r2 반례 1)."""
        return self.state_dir / "stall" / f"logged-out.{seat}"

    def cells_clear(self, stamp: str) -> str | None:
        """r849 — 칸 폴더 준비 + 이번 scan 에 정상 턴(IDLE·WORKING)으로 읽힌 좌석의 칸 지움(못 읽은 scan = 칸 그대로) · 실패 = ERROR 1줄 + 이번 scan 발신 0."""
        d = self.state_dir / "stall"
        try:
            d.mkdir(parents=True, exist_ok=True)
            _ = (d / ".probe").write_text("", encoding="utf-8")
            (d / ".probe").unlink()
            for s in sorted(self.recovered):
                self.cell(s).unlink(missing_ok=True)
        except OSError as e:
            return f"{stamp} act=l ERROR 상태 칸 {d} 쓰기·지우기 실패 {e.__class__.__name__} — 이번 scan 발신 0 · 다음 scan 재시도"
        return None

    def act_l(self, stamp: str) -> list[str]:
        """r849 로그아웃 좌석 — 팀 _master 1통 · 칸 없음 → 발신 · 칸 있음 → 0통(로그아웃 구간당 1통).
        재설계 r3: 칸은 «발신 전에» 세우고 발신 rc≠0 이면 지운다.
        팀장 없음·자기 자신·명부 못 읽음 = 로그 1줄(칸 0 — 알린 것이 없다)."""
        log: list[str] = []
        for f in sorted((self.root / ".fable-team").glob("seats*.json")):  # load_teams 는 깨진 명부를 조용히 건너뛴다 — 그 좌석은 로그아웃 판정을 못 받는다
            try:
                _ = json.loads(f.read_text(encoding="utf-8"))
            except (OSError, ValueError):
                log.append(f"{stamp} act=l ERROR 명부 못 읽음 {f.name} — 그 명부 좌석 로그아웃 판정 0")
        for seat, master, end in self.loggedout:
            first = time.strftime("%m-%d %H:%M", time.localtime(end)) if end else "?"
            if not (master and master != seat):
                log.append(f"{stamp} act=l seat={seat} first={first} — 알릴 팀장 없음(_master {master or '없음'})")
                continue
            cell = self.cell(seat)
            if cell.is_file():
                continue
            try:  # 발신 전에 칸을 세운다 — 이 기록이 안 되면 발신 0(같은 구간 2통 방지)
                _ = cell.write_text(f"first={first} master={master}\n", encoding="utf-8")
            except OSError as e:
                log.append(f"{stamp} act=l ERROR 칸 쓰기 실패 {cell} {e.__class__.__name__} — 이번 scan 발신 0 · 다음 scan 재시도")
                continue
            rc = self.send(master, f"[로그아웃 좌석] {seat} · 첫 실패(보이는 범위 최초) {first} · 재개 = 재시작(zombie-clean resume / claude-hr.sh --resume) · 깨우기 0 (ft-stall-scan r849)")
            if rc != 0:  # 발신 실패 = 칸을 지워 다음 scan 재시도(칸을 남기면 그 구간은 영영 0통)
                try:
                    cell.unlink(missing_ok=True)
                except OSError as e:
                    log.append(f"{stamp} act=l ERROR 칸 지우기 실패 {cell} {e.__class__.__name__} — 다음 scan 발신 0")
                    continue
                log.append(f"{stamp} act=l ERROR 발신 실패 rc={rc} to={master} seat={seat} — 칸 지움 · 다음 scan 재시도")
                continue
            log.append(f"{stamp} act=l to={master} seat={seat} first={first}")
        return log

    def send(self, to: str, body: str, urgent: bool = True) -> int:
        return run(["bash", self.mbox, "send", to, self.sender, body] + (["--urgent"] if urgent else []))[0]

    def send_headline(self, to: str, body: str) -> tuple[int, bool]:
        cmd = ["bash", self.mbox, "send", to, "ft-stall-scan", body, "--urgent"]
        rc, out = run(cmd, timeout=7)
        return rc, rc == 99 and "timed out" in out.lower()

    def wake(self, seat: str, seq: int | None) -> bool:
        self.live = self.sessions()  # 직전 재확인 — 그 사이 attached 되거나 WORKING 이 됐으면 0
        age = self.idle_age(seat, fresh=True)  # r638 — 한 번만 새로 읽는다(캐시를 다시 읽으면 그 사이 WORKING → None < float TypeError)
        if self.live.get(seat, 0) > 0 or age is None or age < IDLE_MIN:
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
            rc = self.send(seat, f"[stall a] {f['listed']} · master IDLE {f['age']:.0f}분 — 빈 석 확인하고 지금 spawn (ft-stall-scan)")
            if rc != 0:  # r1238 A-r4b-2 — 발신 성공만 처리·재촉으로 기록(실패 = 다음 스캔 다시 후보)
                self.errs.append(f"a 발신 실패 rc={rc} to={seat} team={f['team']}")
                return None
            for n in f.get("cards", []):
                self.nudged[n] = self.now
        elif k == "d":
            if not self.wake(seat, f["seq"]):
                return None
        elif k in ("b", "f"):  # f = r1001 팀장 심박 끊김 — 깨우고 정리 쪽지 1통 + 크론 다시 걸기(r1152) 요구
            if not self.wake(seat, f.get("seq")):
                return None
            self.send(seat, f"[stall b] 선언 뒤 정지 {f['age']:.0f}분 — 지금 도구를 불러라 (ft-stall-scan)" if k == "b"
                      else f"[멈춤] {seat} {f['why']} — 지금 한 일 정리 1통 보내라 · CronList 로 체크 크론 확인 — "
                           "없거나 주기가 10분이 아니면 CronCreate 10분 틱으로 다시 걸고 [정리] 에 cron=<id> (BOOT 16 · ft-stall-scan)",
                      urgent=False)
        else:
            seat = next((t["master"] for t in load_teams(self.root) if t["diag"] == "OK" and t["team"] == "planner"), None)
            if not seat:
                return None
            if f.get("stopready"):
                return self.stopready_note(seat, f)
            self.send(seat, f"[긴급] 정지 중: {f['why']} — 기한·해제 조건 확인 · 지금 해제 가능한지 판단 (ft-stall-scan c)")
        return f"act={k} to={seat}"

    def stopready_note(self, planner: str, f: dict) -> str | None:
        """r428 — 정지 파일 없이 정지 레디로만 멈춘 팀 → planner 1통 · 팀당 하루 1회(표식 state/stall-scan.stopready-<날짜> 에 팀 이름)."""
        mark = self.state_dir / f"stall-scan.stopready-{time.strftime('%Y%m%d', time.localtime(self.now))}"
        if f["team"] in (mark.read_text(encoding="utf-8").split() if mark.exists() else []):
            return None
        self.send(planner, f"[정지 파일 0] {f['team']} master {f['seat']} 명부 role=stop-ready 인데 SPAWN_HOLD 없음 — 정지면 `ft-spawn-hold.sh set --verdict …` · 아니면 명부 정정 (ft-stall-scan c · 하루 1회)", urgent=False)
        with open(mark, "a", encoding="utf-8") as fh:
            _ = fh.write(f["team"] + "\n")
        return f"act=c to={planner}"

    def gate_a(self, found: list[dict], unknown: int) -> tuple[list[dict], int]:
        """r1238 A-r4-2 — 처리 단계 첫 일: a 후보 팀마다 card-flow --gate 1회(호출 7초 · 판정 기한 밖). rc 0 = a 유지 · rc 4 = a 뺌 + «a 보류» · 그 밖·시간 초과 = a 뺌 + «a? … 실패(rc N)».
        keys·counts·trig 계산 «전» 에 걸러, 걸러진 a 는 penalty 재료·handled 가 아니다(A-r4-4). 다른 갈래(b·c·d·e·f·h)는 그대로."""
        kept: list[dict] = []
        for f in found:
            if f["kind"] != "a":
                kept.append(f)
                continue
            rc = card_gate(self.root, f["team"], self.flow)
            if rc == 0:
                kept.append(f)
            elif rc == 4:
                self.notes.append(f"a 보류 {f['team']} — 카드 상한(card-flow rc 4)")
            else:
                unknown += 1
                self.notes.append(f"a? {f['team']} 카드 상한 확인 실패(rc {rc}) — a 0")
        return kept, unknown

    def run(self, dry: bool) -> int:
        pen = ft_penalty.load()
        found, unknown = self.find(pen)
        stm.judge_done()  # r1282 — 판정 끝 기한 검사(넘으면 처리 0 · 저장 0) · 이후는 처리 단계(호출별 timeout 만)
        found, unknown = self.gate_a(found, unknown)  # r1238 A — 처리 단계 첫 일(keys·counts·trig 전)
        handled, prev = self.st.get("handled", {}), set(self.st.get("prev", []))
        keys = {f"{f['kind']}:{f['seat']}": f for f in found if f["kind"] != "h"}
        counts = {k: sum(1 for f in found if f["kind"] == k) for k in "abcdefh"}
        trig = sorted(k for k, f in keys.items() if k[0] in "abd" and k in prev and f["seat"] in handled and not f["attached"] and not f["held"])
        lines = [f"stall={len(found) - counts['h']} a={counts['a']} b={counts['b']} c={counts['c']} d={counts['d']} e={counts['e']} seats={len(self.live)} u={unknown} ts={int(self.now)} l={len(self.loggedout)} f={counts['f']} h={counts['h']}"]
        lines += [f"{f['kind']} {f['seat']} {f['age']:.0f} {f['why']}" + ("" if f["kind"] in ("e", "h") else " (attached·처리 0)" if f["attached"] else " (정지 중 처리 0)" if f["held"] else "") for f in found]
        lines += [f"l {s} 첫 실패 {e if e is None else int(e)} 로그아웃(재개 = 재시작)" for s, _, e in self.loggedout]
        lines += self.notes
        print("\n".join(lines))
        if dry:
            return 0
        stamp = time.strftime("%Y-%m-%dT%H:%M:%S", time.localtime(self.now))
        log: list[str] = []
        cell_err = self.cells_clear(stamp) if (self.loggedout or self.recovered) else None  # r849 — 칸이 안 써지면 이번 scan 발신 0
        if cell_err:
            log.append(cell_err)
        d_seats = {f["seat"] for f in found if f["kind"] == "d"}
        if not cell_err:
            log += self.act_e(found, stamp)  # e 는 알림만 — attached·페널티·10분 창과 무관, 서명으로만 1회
            log += self.act_l(stamp)  # r849 — 로그아웃 좌석 팀장 1통 · 칸(좌석 계보)으로만 1회
            headline_notes = headline.headline_alerts(self.root, self.comm, found, self.live, self.now, self.send_headline)
            for note in headline_notes:
                print(note)
        for f in found:
            if cell_err or f["kind"] in ("e", "h") or f["kind"] == "b" and f["seat"] in d_seats:  # b+d 동시 = d 한 번(가장 오래된 pending seq ring · 새 send 생략)
                continue
            key = f.get("key", f["seat"])  # r1001 r3 — 팀장 경보 억제 키 = 팀(대상 좌석이 바뀌어도 같은 팀 10분 0통)
            if f["attached"] or f["held"] or self.now - float(handled.get(key, 0)) < REPEAT_S or f["kind"] != "f" and stm.recent_in_log(self.state_dir, f["seat"], self.now):
                continue
            res = self.act(f)
            if res:
                handled[key] = self.now
                log.append(f"{stamp} {res} key={f['kind']}:{f['seat']} {f['why']}")
        log += [f"{stamp} {e}" for e in self.errs]
        log += [f"{stamp} {n}" for n in self.notes if n.startswith(("보류 — API 장애", "유예 — API 장애"))]  # r1238 B — 감시기 로그에 남는 증거 줄(실사건 확인용)
        if trig and pen is None and os.environ.get("FT_STALL_PENALTY_AUTO", "1") != "0":
            _ = ft_penalty.turn_on("같은 멈춤을 처리 뒤에도 또 감지: " + ",".join(trig))
            log.append(f"{stamp} penalty-on keys={','.join(trig)}")
        per_team = {}
        for t in load_teams(self.root, warn=False):
            if t["diag"] != "OK":
              per_team[t["team"]] = {"diag": t["diag"]}
              continue
            st_m, end_m = self.turn(t["master"]) if t["master"] in self.live else ("UNKNOWN", None)
            per_team[t["team"]] = {k: sum(1 for f in found if f["team"] == t["team"] and f["kind"] == k) for k in "abdf"}
            per_team[t["team"]]["master_end"] = end_m if st_m == "IDLE" else None
        stm.save(self.state_dir, handled, sorted(keys), self.st["seats"], self.nudged, self.now)
        _ = (self.state_dir / "stall-scan.last.json").write_text(json.dumps({"ts": self.now, "c": counts["c"], "teams": per_team}), encoding="utf-8")
        with open(self.state_dir / "stall-scan.log", "a", encoding="utf-8") as fh:
            _ = fh.write("".join(x + "\n" for x in log) + lines[0] + "\n")
        for note in headline_seats.draft(self.root, load_teams(self.root, warn=False), self.seats, set(self.live), self.now):  # r1290 — 처리·저장을 끝낸 뒤에만 초안 1줄씩
            print(note)
        return 0


def main(argv: list[str]) -> int:
    dry = "--dry-run" in argv
    state_dir = Path(os.environ.get("FT_STALL_STATE_DIR") or ft_penalty.state_dir())
    stm.begin()  # r1282 — 판정 기한 D 의 기준 시각 = main() 진입
    with stm.single_run(state_dir) as got:
        if not got:
            print("stall-scan 앞 실행이 아직 돈다 — 이번 틱 건너뜀")
            return 0
        held: list[Scan] = []  # r1282 단계 2 — 판정 불가로 끝나도 좌석 캐시(seats 칸)만 저장 · --dry-run 은 쓰기 0

        def go() -> int:
            held.append(Scan())
            return held[0].run(dry)
        keep = None if dry else (lambda: held and stm.save_seats(state_dir, held[0].st["seats"]))
        return stm.judged(go, state_dir, keep)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
