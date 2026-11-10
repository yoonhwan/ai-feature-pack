#!/usr/bin/env python3
"""ft_api_outage.py — API 장애 구간 시작·끝 알림 + 오류로 끊긴 좌석 «복구 뒤 1회» 재개 (R146).

Claude Code 는 API 가 오류를 내면 그 턴을 «합성 오류 assistant(isApiErrorMessage) + system/turn_duration» 으로 0초에 끝낸다. 감시는 Claude 밖(ft-tick · bash)에서 돈다 — 장애 중엔 Claude 좌석(오케 포함)이 못 움직인다.

입력(stdin): `<좌석>\t<jsonl 경로>`(꼬리 1MB). 끊긴 좌석 = 마지막 대화 레코드가 오류 레코드 + 그 뒤 turn_duration.
  OUTAGE = 오류가 최근 --window-min(10)분 안 → [API 장애 시작] · RECOVERED = 마지막 오류 뒤 정상 assistant(model ≠ <synthetic>) →
  [API 장애 끝](해제 시각 = 오류 뒤 «첫» 정상 · 복구 순간에 고정) + 끊긴 좌석마다 [재개] 1통(오류 uuid 기록 · 장애 «중» 재개 0).
  r497: 정상은 «오류 문구 `for model <id>` 와 같은 바탕 모델»만 센다(모델 미상 = 아무 정상) · ft_model_swap 이 교대한 uuid 는 [재개] 0.
  시작·끝 = «수신자별 전역 1통»(<상태 폴더>/notify-<수신자>.json) · 재개 uuid = 좌석표별 상태 · 상태 없음·손상 = 기준선만(WARN).
분류 = «사용량 제한»(rate_limit·조직 거절·구독 비활성 — 판정 1633, 문구별 건수는 괄호) + «기타 API 오류».
해제 예상 = 문구의 `resets <시각>`·`retry after N` 근거 표시, 없으면 «미상 · 첫 제한 HH:MM»(+5시간 금지). 쪽지에 오류 본문 0.
mbox 실패 = stderr `ERROR …` + rc 1 · 상태는 발신 성공 뒤에만 전진(다음 틱이 이어서 재시도).
"""
import argparse
import json
import re
import subprocess
import sys
import time
from dataclasses import dataclass
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))  # 형제 모듈 — python -I 에서도 찾는다
from ft_api_outage_util import (CAUSES, cause_of, epoch as _epoch, eta_of, hhmm, is_error as _is_error,  # noqa: E402
                                is_logged_out, is_normal as _is_normal, locked, model_of, records as _records, reset_of)

SENDER = "ft-api-outage"


@dataclass(frozen=True)
class Cut:
    uuid: str
    ts: int
    cause: str
    stuck: bool
    reset: str
    model: str = ""  # r497: 오류 문구 `for model <id>` 의 바탕 id — 같은 모델이 돌아와야 그 Cut 이 복구다('' = 모델 미상 · 아무 정상)
    eta: int = 0     # r497: `retry after N` 해제 예상 epoch(0 = 근거 없음)


def back(cut: Cut, oks: list[tuple[int, str]]) -> bool:
    """오류 뒤 «그 Cut 의 바탕 모델» 정상 assistant 가 있나 — 다른 모델이 일한 것은 복구가 아니다(r497)."""
    return any(t > cut.ts and (not cut.model or m == cut.model) for t, m in oks)


def analyze(path: str) -> tuple[Cut | None, list[tuple[int, str]]]:
    """→ (마지막 오류 레코드 · stuck 여부 포함, 정상 assistant (시각, 바탕 모델) 전부)."""
    recs = _records(path)
    oks = [(_epoch(r), model_of(r)) for r in recs if _is_normal(r)]
    errs = [i for i, r in enumerate(recs) if _is_error(r)]
    if not errs:
        return None, oks
    i = errs[-1]
    conv = [r for r in recs[i + 1:] if r.get("type") in ("user", "assistant")]
    done = any(r.get("type") == "system" and r.get("subtype") == "turn_duration" for r in recs[i + 1:])
    ts = _epoch(recs[i])
    cause = "logged_out" if is_logged_out(recs[i]) else cause_of(recs[i])
    return Cut(str(recs[i].get("uuid", "")), ts, cause, not conv and done, reset_of(recs[i], ts), model_of(recs[i]), eta_of(recs[i], ts)), oks


class Outage:
    def __init__(self, args: argparse.Namespace):
        self.a = args
        self.nfile = Path(args.state).parent / ("notify-" + re.sub(r"[^A-Za-z0-9._-]", "_", args.notify) + ".json")

    def send(self, to: str, body: str) -> None:
        r = subprocess.run(["bash", self.a.mbox, "send", to, SENDER, body], capture_output=True, text=True, timeout=30)
        if r.returncode != 0:
            raise RuntimeError(f"mbox send to={to} rc={r.returncode}: {r.stderr.strip()[:120]}")

    def load(self, path: Path) -> dict[str, object] | None:
        try:
            st = json.loads(path.read_text(encoding="utf-8"))
            if isinstance(st, dict) and st.get("status") in ("OK", "OUTAGE", "RECOVERED"):
                return st  # pyright: ignore[reportUnknownVariableType]
            raise ValueError("unexpected shape")
        except FileNotFoundError:
            return None
        except (ValueError, OSError) as exc:
            print(f"WARN api_outage: state unreadable {path.name} ({exc}) — baseline only", file=sys.stderr)
            return None

    def swapped(self) -> set[str]:
        """r497 ft_model_swap 이 교대한 오류 uuid — 상태 없음 = 빈 집합 · 손상 = WARN + 빈 집합."""
        path = Path(self.a.swap_state or Path(self.a.state).parent.parent / "model-swap" / "state.json")
        try:
            return set(map(str, json.loads(path.read_text(encoding="utf-8")).get("swapped", [])))
        except FileNotFoundError:
            return set()
        except (ValueError, OSError, AttributeError) as exc:
            print(f"WARN api_outage: swap state unreadable {path} ({exc})", file=sys.stderr)
            return set()

    def save(self, path: Path, st: dict[str, object]) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        _ = path.write_text(json.dumps(st, ensure_ascii=False), encoding="utf-8")

    def start_msg(self, recent: dict[str, Cut], since: int) -> str:
        names = [n for n, _ in CAUSES]
        lim = sorted((c for c in recent.values() if c.cause in names), key=lambda c: c.ts)
        detail = " · ".join(f"{n} {sum(1 for c in lim if c.cause == n)}" for n in names)
        msg = f"[API 장애 시작 {hhmm(since)}] 끊긴 좌석 {len(recent)} · 사용량 제한 {len(lim)}({detail}) · 기타 API 오류 {len(recent) - len(lim)}"
        if lim:
            msg += f" · 해제 예상: {next((c.reset for c in lim if c.reset), '미상 · 첫 제한 ' + hhmm(lim[0].ts))}"
        return msg

    def announce(self, kind: str, st: dict[str, object], recent: dict[str, Cut], since: int, n_targets: int) -> bool:
        """수신자 공용 notify 의 load → send → save 를 잠금 1개로 — 못 얻으면 ERROR 1줄 + 발신 0 + False(건너뛰기 아님 · 다음 틱 재시도)."""
        with locked(Path(f"{self.nfile}.lock"), self.a.lock_timeout) as got:
            if not got:
                print(f"ERROR api_outage: notify lock wait {self.a.lock_timeout}s exceeded recipient={self.a.notify} event={kind}", file=sys.stderr)
                return False
            note = self.load(self.nfile) or {"status": "OK", "released": 0}
            if kind == "시작" and note["status"] == "OK" and since > int(note.get("released", 0)):  # pyright: ignore[reportArgumentType]
                self.send(self.a.notify, self.start_msg(recent, since))
                self.save(self.nfile, {"status": "OUTAGE", "since": since, "released": note.get("released", 0)})
            if kind == "끝" and note["status"] == "OUTAGE":
                rel, began = int(st.get("released", self.a.now)), int(note.get("since", st.get("since", 0)))  # pyright: ignore[reportArgumentType]
                self.send(self.a.notify, f"[API 장애 끝 {hhmm(rel)} · 약 {max(0, round((rel - began) / 60))}분] 재개 보낼 좌석 {n_targets}")
                self.save(self.nfile, {"status": "OK", "released": rel})
        return True

    def run(self, seats: dict[str, str]) -> None:
        res = {seat: analyze(path) for seat, path in seats.items()}
        for s, (c, _) in res.items():  # r849 — 로그인 풀린 좌석은 API 장애가 아니다: 시작·끝·[재개] 0(재개하면 0초 실패 턴만 또 생긴다 · 알림은 ft-stall-scan)
            if c is not None and c.cause == "logged_out":
                print(f"SKIP 재개 {s} — 로그아웃 좌석(재시작 필요)")
        cuts = {s: c for s, (c, _) in res.items() if c is not None and c.cause != "logged_out"}
        oks = [t for _, o in res.values() for t in o]
        last = max(cuts.values(), key=lambda c: c.ts) if cuts else None  # r497: «끝» = 가장 최근 오류의 모델이 돌아온 때
        sf = Path(self.a.state)
        st, last_err = self.load(sf), max((c.ts for c in cuts.values()), default=0)
        stuck = {s: c for s, c in cuts.items() if c.stuck}
        if st is None:
            self.save(sf, {"status": "OK", "resumed": [c.uuid for c in stuck.values()], "last_err": last_err})
            return
        resumed = list(map(str, st.get("resumed", [])))  # pyright: ignore[reportArgumentType,reportUnknownMemberType]
        st["last_err"] = last_err = max(int(st.get("last_err", 0)), last_err)  # pyright: ignore[reportArgumentType,reportUnknownMemberType]
        fresh = {s: c for s, c in stuck.items() if c.uuid not in resumed}
        recent = {s: c for s, c in fresh.items() if c.ts >= self.a.now - self.a.window_min * 60}
        if st["status"] == "OK" and recent:
            since = min(c.ts for c in recent.values())
            if not self.announce("시작", st, recent, since, 0):
                return  # 로컬 상태 전진 0 — 다음 틱이 이어서 재시도
            st.update(status="OUTAGE", since=since)
        after = [t for t, m in oks if t > last_err and (last is None or not last.model or m == last.model)]
        if st["status"] == "OUTAGE" and after:
            st.update(status="RECOVERED", released=min(after))  # 가장 최근 오류 뒤 «첫» 정상 — 이후 고정
        self.save(sf, st)
        if st["status"] != "RECOVERED": return  # noqa: E701  # GUARD:no-resume-during-outage
        swapped = self.swapped()
        targets = {s: c for s, c in fresh.items() if c.ts >= int(st.get("since", 0))}  # pyright: ignore[reportArgumentType]
        for s, c in list(targets.items()):  # r497: 교대된 좌석 · 제 모델이 아직 안 돌아온 좌석은 [재개] 0(같은 한도에 다시 막힌다)
            if c.uuid in swapped or not back(c, oks):
                print(f"SKIP 재개 {s} — {'교대됨' if c.uuid in swapped else (c.model or '?') + ' 복구 전'}")
                del targets[s]
        if not self.announce("끝", st, recent, 0, len(targets)):
            return  # 상태는 RECOVERED 로 남는다 — 다음 틱이 이어서 재시도
        for seat, cut in targets.items():  # 발신 실패는 raise — 상태는 RECOVERED 로 남아 다음 틱이 이어서 재시도
            self.send(seat, f"[재개] API 오류로 끊긴 턴({hhmm(cut.ts)}) — 마지막 지시 이어서")
            resumed.append(cut.uuid)  # GUARD:uuid-record
            st["resumed"] = resumed[-500:]
            self.save(sf, st)
        st["status"] = "OK"
        self.save(sf, st)


def main() -> int:
    ap = argparse.ArgumentParser()
    for flag in ("--state", "--mbox", "--notify"):
        _ = ap.add_argument(flag, required=True)
    _ = ap.add_argument("--now", type=int, default=int(time.time()))
    _ = ap.add_argument("--window-min", type=int, default=10)
    _ = ap.add_argument("--lock-timeout", type=float, default=7.0)  # 7초 룰
    _ = ap.add_argument("--swap-state", default="")  # r497 · 기본 = <상태 폴더>/../model-swap/state.json
    args = ap.parse_args()
    seats = dict(ln.rstrip("\n").split("\t", 1) for ln in sys.stdin if "\t" in ln)
    try:
        Outage(args).run(seats)
    except (RuntimeError, OSError, subprocess.SubprocessError) as exc:
        print(f"ERROR api_outage: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
