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
r1647 f 문구 = 크론 요구 0(#274576 주기 크론 0 정책) · 마지막 발신 머리 `[다음 없음` + ft-seat-open-work rc0(받을 일 0) 인 «닫기 대기 팀장» 은 f 0통 + 노트 1줄(새 일이 들어오면 다시 센다).
r1371 — 전팀 정지 표식(ft_stall_detect.all_stop · 스캔 처음 1회) on 이면 a·f 경보 0 + «보류 <a|f> <팀> — 전팀 정지(since HH:MM)» 노트 · h 는 ft_stall_headline.headline_alerts 가 같은 표식으로 보류 · c·e·l 은 그대로(정지 중에도 보여야 하는 것).
"""
import json
import os
import shlex
import sys
import time
from pathlib import Path

import ft_card_assign_pause as pause
from ft_api_outage_util import epoch, records  # r1882 — pi jsonl 꼬리·timestamp 읽기 한 벌
import ft_headline_seats as headline_seats
import ft_penalty
import ft_stall_headline as headline
from ft_stall_detect import IDLE_MIN, all_stop, all_stop_note, agent_sessions, api_outage, card_gate, ctx_pct, lead_alert, lead_heartbeat_min, lead_names, load_teams, off_roster_live, pending_mail, policy_stop, run, spawn_capacity, waiting_cards, RefUnavailable
from ft_stall_seats import Seats
import ft_stall_state as stm
from ft_nano_record_auto import land_close

HERE = Path(__file__).resolve().parent
REPEAT_S = stm.REPEAT_S
G_MIN_S = 120  # r1882 g — pi 오류 턴이 이만큼 지나야 «오류 멈춤»


def pi_error_at(path: str) -> float | None:
    """r1882 — pi jsonl(꼬리 1MB) 마지막 assistant 가 오류(stopReason=error·errorMessage)면 그 바깥 timestamp epoch · 아니거나 못 읽으면 None(처리 0)."""
    try:
        last = [r for r in records(path) if r.get("type") == "message" and r["message"].get("role") == "assistant"][-1]
        return epoch(last) if last["message"].get("stopReason") == "error" or "errorMessage" in last["message"] else None
    except (OSError, IndexError, KeyError, TypeError, AttributeError):
        return None


def _last_sent(comm: Path, names: set[str]) -> str:
    """r1647 — 현역 팀장이 «마지막으로 보낸» 쪽지 본문(안 읽은 큐 + 읽은 로그 끝 4MB · 가장 큰 seq).
    쪽지 0·읽기 실패 = "" — «판단 못 함» 은 닫기 대기가 아니다(부르는 쪽은 지금 흐름 그대로 간다)."""
    best, body = -1, ""
    for p in (comm / "mailbox.jsonl", comm / "mailbox.log.jsonl"):
        try:
            with open(p, "rb") as fh:
                off = max(0, fh.seek(0, os.SEEK_END) - (4 << 20))
                fh.seek(off)
                raw = fh.read()
        except OSError:
            continue
        for line in raw.decode("utf-8", "replace").splitlines()[1 if off else 0:]:  # 4MB 앞을 잘랐을 때만 첫 줄이 조각
            try:
                r = json.loads(line)
                seq = int(r.get("seq") or 0)
            except (ValueError, TypeError, AttributeError):
                continue
            if r.get("from") in names and seq > best:
                best, body = seq, str(r.get("body") or "")
    return body


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
        self.open_work = os.environ.get("FT_SEAT_OPEN_WORK") or str(HERE / "ft-seat-open-work.py")  # r1647 받을 일 판정 정본
        self.ps = ["bash", os.environ["FT_PS"]] if os.environ.get("FT_PS") else ["ps"]
        self.ctx_cmd = os.environ.get("FT_CTX_CMD") or str(HERE / "ft-claude-context.sh")
        self.e_min = float(os.environ.get("FT_STALL_E_IDLE_MIN") or 30)
        self.notes: list[str] = []
        self.loggedout: list[tuple[str, str | None, float | None]] = []  # r849 (좌석, 팀 _master, 첫 실패 epoch)
        self.recovered: set[str] = set()  # r849 — 이번 scan 에 정상 턴(IDLE·WORKING)으로 읽힌 좌석(로그아웃 칸 지움)
        self.st = stm.load(self.state_dir)
        self.nudged = stm.nudged_load(self.st)  # r1238 A-r4b-1 — 카드 stem → 마지막 a 재촉 epoch(저장본에서 복원)
        self.lint_cache = stm.lint_load(self.st)  # r1392 — 카드 stem → {oid, lint, v, at}(저장본에서 복원 · 이번 판정이 더한다)
        self.lint_seen: set[str] = set()  # r1392 — 이번 실행에 ref 트리에서 본 대기 카드 stem(안 본 장을 지우지 않는다)
        self.lint_unread = 0  # r1392 — 이번 실행에 대기 카드를 못 읽은 팀 수(0 일 때만 캐시에서 사라진 카드를 지운다)
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

    def lint_store(self) -> dict[str, dict]:
        """r1392 — 저장할 lint 칸: 대기 폴더를 떠난 카드(stem)는 뺀다. 이번 실행에 대기 카드를 못 읽은 팀이 있으면 지우지 않는다(그 팀 카드는 아직 대기 중일 수 있다 · 조용한 캐시 삭제 0)."""
        if self.lint_unread == 0:
            for stem in [k for k in self.lint_cache if k not in self.lint_seen]:
                del self.lint_cache[stem]
        return self.lint_cache

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

        astop, astop_since, astop_why = all_stop(self.root)  # r1371 — 전팀 정지 표식 1회(스캔 처음) · on 이면 f·a·h 경보 보류 · 못 읽으면 경보 그대로
        self.astop = (astop, astop_since)  # 처리 단계(h)가 같은 값을 쓴다(조회 1회)
        if astop == "unknown":
            notes.append(f"판정 불가 ALL_STOP {astop_why}")  # 조용한 보류 0 — 모르면 지금처럼 보낸다

        def keep(item: dict) -> None:  # r1371 — 전팀 정지면 «세되 발신 0»: 요약 줄에 «(전팀 정지 처리 0)» + 보류 노트 1줄
            if astop == "on":
                item["all_stop"] = True
                notes.append(all_stop_note(item["kind"], item["team"], astop_since))
            out.append(item)

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
                self.lint_unread += 1
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
                names, u, missed = [], 0, 0
                if age is not None and age >= IDLE_MIN:
                    try:
                        names, u, missed = waiting_cards(t["cards"], self.lint, self.root, self.now, self.nudged, notes,
                                                         cache=self.lint_cache, seen=self.lint_seen, budget=stm.lint_budget)
                    except RefUnavailable as e:  # r1330 A4 — 기준 ref 트리를 못 읽음: 그 팀 a 0 + 판정 불가 1줄(조용한 0 아님)
                        unknown += 1
                        self.lint_unread += 1
                        notes.append(f"a? {t['team']} 대기 카드 판정 불가 — {e}")
                    else:
                        if missed:  # r1392 — 실행당 lint 예산(D/2)에 걸린 장: a 후보 0 · 조용한 0 이 아니라 «다음 실행» 1줄
                            notes.append(f"a? {t['team']} lint 미판정 {missed}장 — 다음 실행")
                else:
                    self.lint_unread += 1
                if names and not self.flags(m)["rest"] and (self.idle_age(m, fresh=True) or 0) >= IDLE_MIN:
                    n = len(names)
                    listed = f"대기 카드 {n}장({', '.join(names[:5])}{f' +{n - 5}' if n > 5 else ''}) · 선행 미판정 {u}장 제외"
                    keep(dict(kind="a", seat=m, team=t["team"], age=self.idle_age(m), why=f"{listed} · master IDLE", listed=listed, cards=list(names)))
            for s in sorted(t["seats"], key=lambda x: (x not in leads, x)):  # 현역 팀장 먼저(팀당 1통은 _master 것)
                stm.progress(len(self.live))  # r1282 — 좌석마다 판정 기한 검사
                if s not in self.live:
                    continue
                state, end = self.turn(s)
                if state == "LOGGEDOUT":  # r849 — 쉬는 좌석 아님(a·b·d 0) · 팀장 1통은 act_l
                    self.loggedout.append((s, t["master"], end))
                    continue
                if state == "UNAVAILABLE":  # r1882 g — pi 모델 일시 오류로 끝난 턴(판정 = ft_seat_pi_turn 그대로 · RATELIMITED·UNKNOWN 은 지금 그대로)
                    at = pi_error_at(self.seats.info(s)["path"])
                    if at is not None and self.now - at >= G_MIN_S:
                        out.append(dict(kind="g", seat=s, team=t["team"], age=(self.now - at) / 60, why=f"pi 오류 멈춤 {time.strftime('%H:%M:%S', time.localtime(at))}", sig=f"{s}@{at:.0f}", lead=t["master"] if t["master"] != s else next((x["master"] for x in teams if x["diag"] == "OK" and x["team"] == "planner"), None)))
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
                        if self.closed_wait(s, leads, notes):  # r1647 — 닫기 대기 팀장([다음 없음] + 받을 일 0) = [멈춤] 0통
                            supp["f"].add(t["team"])
                            note = f"보류 f {t['team']} — [다음 없음] · 받을 일 0"
                            if note not in notes:  # 같은 «팀» 노트만 중복 판정 — 팀마다 1줄(계약 ⓐ · 팀장 둘이어도 1줄)
                                notes.append(note)
                            continue
                        if hold or lag is not None and min(lead_heartbeat_min() + 1 if hba is None else hba, lag) <= lead_heartbeat_min():  # r1238 B — 심박 나이 = min(심박, 끝 뒤 경과)
                            supp["f"].add(t["team"])
                            continue
                        keep(dict(kind="f", seat=s, team=t["team"], key=f"f:{t['team']}", age=age, hb_age=hba, seq=mail[s][0] if s in mail else None,
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
        headline_found, headline_unknown, headline_notes = headline.find(self.root, teams, self.now, stop)  # h 보류 판정은 headline_alerts(같은 표식)
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

    def act_g(self, found: list[dict], stamp: str) -> list[str]:
        """r1882 g — 서명(좌석@오류 시각) 처음 = 직전 재확인 뒤 고정 [재개] 큐 적재 + 표준 ring 1회 · 둘째 = 계보 현역 master(자기 자신이면 planner) [멈춤] 1통 · 셋째부터 0 · 서명 파일 state/stall-scan.g.json."""
        path, keep, log = self.state_dir / "stall-scan.g.json", {}, []
        try:
            sigs = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            sigs = {}
        for f in (x for x in found if x["kind"] == "g" and (x["sig"] in sigs or self.turn(x["seat"], fresh=True)[0] == "UNAVAILABLE")):  # 처음이면 직전 재확인(그 사이 새 턴 = 0)
            n = sigs.get(f["sig"], 0)
            keep[f["sig"]], at = min(n + 1, 2), f["why"].rsplit(" ", 1)[1]
            if n == 0:
                self.send(f["seat"], f"[재개] 모델 일시 오류로 턴이 끝났다({at}) · 마지막 일을 이어서", urgent=False)
                run(["bash", self.mbox, "ring", f["seat"]])
            elif n == 1 and f["lead"]:
                self.send(f["lead"], f"[멈춤] {f['seat']} pi 모델 일시 오류({at}) 뒤 깨워도 멈춤 · 재개·인계 판단 (ft-stall-scan g)")
            log += [f"{stamp} act=g seat={f['seat']} n={n + 1} to={f['seat'] if n == 0 else f['lead']} {f['why']}"] if n < 2 else []
        _ = path.write_text(json.dumps(keep), encoding="utf-8")
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

    def closed_wait(self, seat: str, names: set[str], notes: list[str]) -> bool:
        """r1647 — 팀장 «닫기 대기»: 마지막 발신 머리 `[다음 없음` ∧ ft-seat-open-work rc0(받을 일 0) → f 0통.
        판단 못 하면 False = 지금 흐름(경보) 그대로 · open-work 판정 불가면 노트 1줄."""
        if not _last_sent(self.comm, names).lstrip().startswith("[다음 없음"):
            return False
        rc, _out = run([sys.executable, self.open_work, seat, "--root", str(self.root), "--mbox-dir", str(self.comm)], timeout=7)
        if rc not in (0, 1):
            notes.append(f"f? {seat} 받을 일 판정 불가(rc={rc}) — 닫기 대기 판정 0 · f 그대로")
        return rc == 0

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
        elif k in ("b", "f"):  # f = r1001 팀장 심박 끊김 — 깨우고 정리 쪽지 1통(r1647: 크론 요구 뺀 · 주기 크론 0 정책 #274576)
            if not self.wake(seat, f.get("seq")):
                return None
            self.send(seat, f"[stall b] 선언 뒤 정지 {f['age']:.0f}분 — 지금 도구를 불러라 (ft-stall-scan)" if k == "b"
                      else f"[멈춤] {seat} {f['why']} — 지금 한 일 정리 1통 보내라 (BOOT 16 · ft-stall-scan)",
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
            if f["kind"] != "a" or f.get("all_stop"):  # r1371 — 전팀 정지 중엔 card-flow 호출 0(발신 0 이면 상한 판정도 필요 없다)
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

    def auto_close(self) -> list[str]:
        """r1670 ⓔ — FT_NANO_AUTO_CLOSE=1 일 때만 close-due 의 «갈래=승인» 줄마다 닫기 1회. 한 회차 상한 = 줄 수 · 같은 좌석 실패는 같은 HEAD 동안 재시도 0 · 꺼짐(기본 0) = 지금 그대로(호출 0)."""
        if os.environ.get("FT_NANO_AUTO_CLOSE") != "1":
            return []
        due = os.environ.get("FT_NANO_CLOSE_DUE") or str(HERE / "ft-nano-close-due.sh")
        close = os.environ.get("FT_NANO_CLOSE") or str(HERE / "ft-nano-close.sh")
        rc, out = run(["bash", due, "--all"], {**os.environ, "FT_NANO_AUTO_CLOSE": "1"}, 70)
        if rc not in (0, 3):   # r1701 ② — rc=3(판정 불가 1석 이상)이어도 «갈래=승인» 줄은 닫는다(1석이 전 팀 자동 닫기를 막던 자리)
            return [f"판정 불가 auto-close close-due rc={rc} — 닫기 0"]
        sf = self.state_dir / "nano-auto-close.json"
        try:
            tried: dict[str, str] = json.loads(sf.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            tried = {}
        stamp = time.strftime("%Y-%m-%dT%H:%M:%S", time.localtime(self.now))
        lines: list[str] = []
        due = [x for x in out.splitlines() if x.startswith("닫기 차례 ")]
        if rc == 3:   # r1701 ② — 판정 불가 좌석은 이름·사유를 1줄씩 남기고 나머지 «닫기 차례» 는 그대로 처리한다
            for u in [x for x in out.splitlines() if x.startswith("판정 불가 ")]:
                u = u[len("판정 불가 "):]
                seat, _, why = u.partition(" ")
                lines.append(f"{stamp} 판정 불가 auto-close {seat} {why}".rstrip())
        # ★r1759 A1·A2·A3★ 닫기 도구는 «데이터 루트(self.root · FT_ROOT)» 안에서 부른다 — launchd 작업 폴더(팩)·팩 나노 worktree 를 물려주면
        #   닫기 도구가 팩을 루트로 보고 팀 env 를 못 찾는다. 데이터 루트가 없거나 폴더가 아니면 부르지 않는다(하드 룰 20 · tried 갱신 0).
        root = getattr(self, "root", None)   # 단위 시험이 __init__ 을 건너뛰면 없음 = 지금 그대로(cwd 상속)
        cwd = Path(root) if root else None
        root_why = f"데이터 루트 없음({cwd})" if cwd is not None and not cwd.is_dir() else ""
        if root_why:
            return lines + [f"{stamp} 판정 불가 auto-close {(x.split() + ['', '', ''])[2]} {root_why}" for x in due]
        for ln in [x for x in due if "갈래=승인" in x]:
            seat = ln.split()[2] if len(ln.split()) > 2 else ""
            head = next((t[4:] for t in ln.split() if t.startswith("set=")), "")
            cmd = ln.split(" — ", 1)[1] if " — " in ln else ""
            if not seat or not head or not cmd.startswith("bash ") or " --approved " not in cmd:
                lines.append(f"{stamp} 판정 불가 auto-close 줄 해석 실패 — {ln[:120]}")
                continue
            if tried.get(seat) == head:
                continue
            crc, cout = run(["bash", close, *shlex.split(cmd)[2:]], {**os.environ, "FT_NANO_AUTO_CLOSE": "1"}, 70, cwd=cwd)
            rows = cout.strip().splitlines()
            closed = next((x for x in rows if x.startswith("CLOSED")), "")   # r1735 — 성공 = «CLOSED 로 시작하는 줄»(첫 줄 순서 의존 0)
            if crc == 0 and closed:   # r1735 A3 — rc≠0 은 CLOSED 줄이 있어도 실패(rc 우선)
                tried.pop(seat, None)
                lines.append(f"{stamp} auto-close {closed} set={head}")
            else:
                tried[seat] = head
                why = next((x for x in rows if not x.startswith("INFO")), (rows or [""])[0])[:120]   # r1735 A2 — INFO 줄은 사유가 아니다
                lines.append(f"{stamp} auto-close 실패 {seat} rc={crc} — {why}")
        for ln in [x for x in due if "갈래=착지기록" in x]:  # r1717 A11 — 기록이 다 선 착지 갈래(열쇠 = 좌석·set·rec)
            lines += land_close(ln, tried, stamp, close, run, self.root)
        try:
            sf.parent.mkdir(parents=True, exist_ok=True)
            (sf.parent / (sf.name + ".tmp")).write_text(json.dumps(tried), encoding="utf-8")
            os.replace(sf.parent / (sf.name + ".tmp"), sf)
        except OSError as e:
            lines.append(f"{stamp} WARN auto-close 상태 파일 쓰기 실패: {e}")
        return lines

    def record_notify(self, stamp: str) -> list[str]:
        """r1717 A4 ⓑ — 착지 뒤 «정리 차례» 장부의 열린 줄마다 쪽지(1회·재촉 1회 셈은 도구 몫) · FT_NANO_AUTO_CLOSE 와 무관 · rc≠0 = 로그 1줄."""
        tool = os.environ.get("FT_NANO_RECORD") or str(HERE / "ft-nano-record.sh")
        rc, _out = run(["bash", tool, "notify"], {**os.environ, "FT_ROOT": str(self.root)}, 25)
        return [] if rc == 0 else [f"{stamp} 판정 불가 record-notify rc={rc}"]

    def run(self, dry: bool) -> int:
        pen = ft_penalty.load()
        found, unknown = self.find(pen)
        stm.judge_done()  # r1282 — 판정 끝 기한 검사(넘으면 처리 0 · 저장 0) · 이후는 처리 단계(호출별 timeout 만)
        found, unknown = self.gate_a(found, unknown)  # r1238 A — 처리 단계 첫 일(keys·counts·trig 전)
        handled, prev = self.st.get("handled", {}), set(self.st.get("prev", []))
        keys = {f"{f['kind']}:{f['seat']}": f for f in found if f["kind"] != "h"}
        counts = {k: sum(1 for f in found if f["kind"] == k) for k in "abcdefgh"}
        trig = sorted(k for k, f in keys.items() if k[0] in "abd" and k in prev and f["seat"] in handled and not f["attached"] and not f["held"])
        lines = [f"stall={len(found) - counts['h']} a={counts['a']} b={counts['b']} c={counts['c']} d={counts['d']} e={counts['e']} seats={len(self.live)} u={unknown} ts={int(self.now)} l={len(self.loggedout)} f={counts['f']} h={counts['h']} g={counts['g']}"]
        lines += [f"{f['kind']} {f['seat']} {f['age']:.0f} {f['why']}" + ("" if f["kind"] in ("e", "h", "g") else " (attached·처리 0)" if f["attached"] else " (전팀 정지 처리 0)" if f.get("all_stop") else " (정지 중 처리 0)" if f["held"] else "") for f in found]
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
            log += self.act_g(found, stamp)  # r1882 — pi 오류 멈춤 · 서명으로만(10분 창·attached 무관)
            headline_notes = headline.headline_alerts(self.root, self.comm, found, self.live, self.now, self.send_headline, self.astop)  # r1371 — 같은 표식(조회 1회)
            for note in headline_notes:
                print(note)
        for f in found:
            if cell_err or f["kind"] in ("e", "h", "g") or f["kind"] == "b" and f["seat"] in d_seats:  # b+d 동시 = d 한 번(가장 오래된 pending seq ring · 새 send 생략)
                continue
            key = f.get("key", f["seat"])  # r1001 r3 — 팀장 경보 억제 키 = 팀(대상 좌석이 바뀌어도 같은 팀 10분 0통)
            if f["attached"] or f["held"] or f.get("all_stop") or self.now - float(handled.get(key, 0)) < REPEAT_S or f["kind"] != "f" and stm.recent_in_log(self.state_dir, f["seat"], self.now):
                continue
            res = self.act(f)
            if res:
                handled[key] = self.now
                log.append(f"{stamp} {res} key={f['kind']}:{f['seat']} {f['why']}")
        log += [f"{stamp} {e}" for e in self.errs]
        log += self.record_notify(stamp)  # r1717 A4 ⓑ — auto_close 앞 1회
        ac = self.auto_close()  # r1670 ⓔ — FT_NANO_AUTO_CLOSE=1 일 때만(기본 0 = 로그·출력 그대로)
        if ac:
            log += ac
            print("\n".join(ac))
        self.critical(ac)  # r1718 A2ⓑ·A8 — 밀린 [크리티컬] 배출 · 되풀이 판정 불가 알림(r1718-mut:drain)
        log += [f"{stamp} {n}" for n in self.notes if n.startswith(("보류 — API 장애", "유예 — API 장애", "보류 ", "판정 불가 ALL_STOP"))]  # r1238 B·r1371 — 감시기 로그에 남는 증거 줄(실사건 확인용)
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
        stm.save(self.state_dir, handled, sorted(keys), self.st["seats"], self.nudged, self.now, lint=self.lint_store())
        _ = (self.state_dir / "stall-scan.last.json").write_text(json.dumps({"ts": self.now, "c": counts["c"], "teams": per_team}), encoding="utf-8")
        with open(self.state_dir / "stall-scan.log", "a", encoding="utf-8") as fh:
            _ = fh.write("".join(x + "\n" for x in log) + lines[0] + "\n")
        for note in headline_seats.draft(self.root, load_teams(self.root, warn=False), self.seats, set(self.live), self.now):  # r1290 — 처리·저장을 끝낸 뒤에만 초안 1줄씩
            print(note)
        return 0

    def critical(self, ac: list[str]) -> None:
        """r1718 A2ⓑ·A8 — 회차마다 밀린 [크리티컬] 배출 1회(FT_NANO_AUTO_CLOSE 무관) · 같은 (좌석·사유) «판정 불가» 가 연속 N 회차면 desk 1통. 셈 = state/nano-auto-close-unjudged.json(그 좌석이 판정되면 0)."""
        tool, cf, cur, env = str(HERE / "ft-critical-notify.sh"), self.state_dir / "nano-auto-close-unjudged.json", {}, {**os.environ, "FT_MBOX": self.mbox, "FT_MBOX_DIR": str(self.comm)}
        if os.environ.get("FT_CRITICAL_OFF") == "1" or not os.path.isfile(tool):
            return
        try:
            old = dict(json.loads(cf.read_text(encoding="utf-8")))
        except (OSError, ValueError, TypeError):
            old = {}
        for seat, _, why in (ln.partition(" 판정 불가 auto-close ")[2].partition(" ") for ln in ac if "#" in ln.partition(" 판정 불가 auto-close ")[2].split(" ")[0]):
            k = seat + "\t" + why.split(" 단계:")[0]  # 열쇠 = 좌석 + «단계:» 꼬리를 떼 사유 · 이번 회차에 없는 열쇠는 cur 에 안 들어가 셈 0(r1718-mut:count)
            cur[k] = {"n": old.get(k, {}).get("n", 0) + 1, "t0": old.get(k, {}).get("t0", int(self.now))}
            if cur[k]["n"] >= int(os.environ.get("FT_CRITICAL_UNJUDGED_N") or 5):
                _ = run(["bash", tool, "ft-stall-scan", seat, "--event", f"{k.split(chr(9))[1]}:{cur[k]['t0']}", "--what", f"판정 불가 {why} {cur[k]['n']}회 연속", "--next", "그 좌석 ft-nano-close-due --why 1회 → arch", "--where", seat], env, 15)
        try:
            _ = cf.write_text(json.dumps(cur, ensure_ascii=False), encoding="utf-8") if cur != old else 0
        except OSError as e:
            print(f"WARN 판정 불가 셈 파일 쓰기 실패: {e}")
        _ = run(["bash", tool, "--drain"], env, 15)


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
        keep = None if dry else (lambda: held and stm.save_seats(state_dir, held[0].st["seats"], held[0].lint_store()))
        return stm.judged(go, state_dir, keep)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
