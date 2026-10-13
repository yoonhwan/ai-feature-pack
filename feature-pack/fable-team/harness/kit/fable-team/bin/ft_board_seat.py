"""ft-board 좌석 칸 — 좌석마다 `ft-seat-status.sh turn <좌석> --json` 1회로 칸 문자열·정지 분을 만든다 (판정 511·514 · 설계 §4-r2 Q1-r2 8행 표 · §4-r3).

분은 «state=IDLE ∧ source=jsonl ∧ turn_end 가 유효한 과거 시각» 한 행에서만 계산한다(지어낸 값 0). 나머지 상태는 관측 그대로 적는다.
`⚠`·stalled 는 그 행의 N ≥ 3 일 때만 — 단 완료 선언 꼬리가 `증거 있음` 이면 빠진다(정답 상태). 기다리는 것은 우편 기록의 `추정:` 만.
env: FT_BOARD_SEAT_STATUS(turn --json 스텁/경로 · 기본 <FT_BIN>/ft-seat-status.sh) · FT_BOARD_DONE_MIN(완료 선언 미처리 분 · 기본 10)
"""
import json
import os
import re
import subprocess
from datetime import datetime

import ft_board_env as env
from ft_board_mail import Mail
from ft_board_roster import select

STALL_MIN = 3


def turn_row(seat: str) -> dict:
    sh = os.environ.get("FT_BOARD_SEAT_STATUS", str(env.HERE / "ft-seat-status.sh"))
    try:
        r = subprocess.run(["bash", sh, "turn", seat, "--json"], capture_output=True, text=True, timeout=30)
    except subprocess.TimeoutExpired:
        return {"error": "turn 조회 시간 초과"}
    if r.returncode != 0:
        return {"error": f"turn 조회 실패 rc={r.returncode}"}
    try:
        row = json.loads(r.stdout)
        return {"state": str(row["state"]), "turn_end": row.get("turn_end"), "source": str(row.get("source")),
                **{k: row[k] for k in ("aborted", "reason") if k in row}}  # codex 행만 가진다(R132a)
    except (ValueError, KeyError, TypeError, AttributeError):
        return {"error": "출력 해석 실패"}


def _turn_end(raw, now: datetime) -> tuple[datetime | None, str]:
    if not raw:
        return None, "turn_end 없음"
    try:
        p = datetime.fromisoformat(str(raw).replace("Z", "+00:00"))
    except ValueError:
        return None, "turn_end 해석 실패"
    p = p.astimezone().replace(tzinfo=None) if p.tzinfo else p
    return (None, "미래 시각") if p > now else (p, "")


def cell(row: dict, now: datetime) -> tuple[str, int | None, str | None]:
    """(칸 문자열, ⚠ 정지 분 또는 None, 턴 끝 HH:MM 또는 None)"""
    if "error" in row:
        return f"확인 불가({row['error']})", None, None
    st, src = row["state"], row["source"]
    te, why = _turn_end(row["turn_end"], now)
    at = te.strftime("%H:%M") if te else None
    if st == "WORKING":
        return ("작업중(pane)" if src == "pane" else "작업중"), None, at
    if st == "UNKNOWN":
        return f"확인 불가({row.get('reason') or ('첫 턴 전' if src == 'jsonl' else '좌석 없음')})", None, None
    if st == "PENDING":
        return f"대기열 있음(턴 끝 {at or '확인 불가'})", None, at
    if st != "IDLE":
        return f"확인 불가(알 수 없는 상태 {st})", None, None
    if src not in ("jsonl", "codex"):
        return "대기(분 미상 · pane)", None, None
    if te is None:
        return f"대기(분 확인 불가: {why})", None, None
    n = int((now - te).total_seconds() // 60)
    return ("⚠" if n >= STALL_MIN else "") + f"정지 {n}분({'중단 · ' if row.get('aborted') else ''}턴 끝 {at})", (n if n >= STALL_MIN else None), at


def _tail(decl: dict) -> str:
    return f" · 완료 선언 #{decl['seq']}({decl['hhmm']} · {'증거 있음' if decl['evidence'] else '증거 없음'})"


class SeatCells:
    """한 팀 명부의 좌석 칸 — 좌석마다 turn 1회(메모). 칸 데이터는 collect dict 에 그대로 들어간다."""

    def __init__(self, seats: dict, alive: set, mail: Mail, now: datetime):
        self.seats, self.alive, self.mail, self.now, self._memo = seats, alive, mail, now, {}
        self.active, self.unknown = select(seats, alive)  # 현역 선정 = ft_board_roster.py (§7-7 — 근거 없는 생존은 «확인 불가» 로 드러낸다)

    def roster(self) -> list[str]:
        return sorted(self.active + list(self.unknown))

    def text(self, name: str) -> str:
        return self.get(name)["text"]

    def get(self, name: str) -> dict:
        if name not in self._memo:
            self._memo[name] = self._compute(name)
        return self._memo[name]

    def _compute(self, name: str) -> dict:
        if name in self.unknown:
            return {"text": self.unknown[name], "stalled": None, "turn_end": None, "decl": None, "wait": "", "unknown": True}
        role = (self.seats.get(name) or {}).get("role")
        fixed = {"stopped": "닫힘", "stop-ready": "정지레디"}.get(role) or ("" if name in self.alive else "정지(세션 없음)")
        if fixed:
            return {"text": fixed, "stalled": None, "turn_end": None, "decl": None, "wait": self.mail.wait(name, None)}
        row = turn_row(name)
        text, n, at = cell(row, self.now)
        why = text[len("확인 불가("):text.index(")")] if text.startswith("확인 불가(") else None  # 턴 조회 불가 사유 — rows() 가 감시 행으로 낸다(DA⑥ I1)
        decl = self.mail.declaration(name)
        if decl:
            if n and decl["evidence"]:
                text, n = text.removeprefix("⚠"), None
            text += _tail(decl) + (" · ⚠완료 뒤 작업" if row.get("state") == "WORKING" else "")
        te, _ = _turn_end(row.get("turn_end"), self.now)
        idle = int((self.now - te).total_seconds() // 60) if te and row.get("state") == "IDLE" and row.get("source") in ("jsonl", "codex") else None
        return {"text": text, "stalled": n, "turn_end": at, "decl": decl, "wait": self.mail.wait(name, decl),
                "working": row.get("state") == "WORKING", "idle_min": idle, "unknown_why": why}  # idle_min = teams 한 줄의 N(⚠ 임계와 무관한 원값)

    def all(self) -> dict:
        return {n: self.get(n) for n in self.roster() if n in self.alive}

    def rows(self) -> list[list[str]]:
        """stalled 행 — `확인 불가|좌석|-|사유` · `N분|좌석|턴 끝|기다림` · `완료 뒤 작업|좌석|#seq|HH:MM` · `완료 선언 미처리|받는 좌석|보낸 좌석 #seq|N분`"""
        done_min = int(os.environ.get("FT_BOARD_DONE_MIN", "10"))
        out = []
        for name, c in self.all().items():
            why = "현역 근거 없음(포인터·은퇴 표시 0)" if c.get("unknown") else c.get("unknown_why")
            if why:  # §7-7 «숨김 0» — 현역 근거 없는 좌석·턴 조회 불가 좌석도 master 감시에 나온다(분 열이 숫자가 아니라 --min 과 무관)
                out.append(["확인 불가", name, "-", why])
            d = c["decl"]
            if c["stalled"]:
                out.append([f"{c['stalled']}분", name, c["turn_end"] or "-", c["wait"]])
            if d and c.get("working"):
                out.append(["완료 뒤 작업", name, f"#{d['seq']}", c["turn_end"] or "확인 불가"])
            if d and d["evidence"] and self.since(d) >= done_min:
                out.append(["완료 선언 미처리", d["to"], f"{name} #{d['seq']}", f"{self.since(d)}분"])
        return out

    def since(self, decl: dict) -> int:
        return int((self.now - datetime.fromisoformat(decl["ts"])).total_seconds() // 60)

    def declared(self) -> list[dict]:
        """꼬리 `증거 있음` 좌석 — ⓪ `완료 선언` 열 재료"""
        return [{"seat": n, "min": self.since(c["decl"])} for n, c in self.all().items()
                if c["decl"] and c["decl"]["evidence"]]


def stalled_lines(d: dict, min_n: int) -> list[str]:
    out = []
    for t in d["teams"]:
        for r in t["stalled"]:
            m = re.fullmatch(r"(\d+)분", r[0])
            if m is None or int(m.group(1)) >= min_n:
                out.append("|".join(r))
    return out


def summary_cols(t: dict) -> str:
    """⓪ 팀 요약 뒤 두 열 — 정지(3분+) = ⚠ 좌석 수(0 아니면 첫 좌석) · 완료 선언 = 증거 있음 꼬리 좌석 수(0 아니면 첫 좌석 + 원 쪽지 뒤 N분)"""
    stalled = [r for r in t["stalled"] if re.fullmatch(r"\d+분", r[0])]
    done = t["declared"]
    a = f"{len(stalled)}" + (f"({stalled[0][1]})" if stalled else "")
    b = f"{len(done)}" + (f"({done[0]['seat']} · 원 쪽지 뒤 {done[0]['min']}분)" if done else "")
    return f" | 정지(3분+) {a} | 완료 선언 {b}"
