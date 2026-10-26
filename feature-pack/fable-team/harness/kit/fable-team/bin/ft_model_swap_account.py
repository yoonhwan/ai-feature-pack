"""ft_model_swap_account.py — ft_model_swap 의 계정 전체 한도 판정(r838 · 200줄 상한으로 분리 · Swap 이 상속).

(가) api-outage 장애 중 ∧ 시작 뒤 정상 0 → 교대 0 · 발신 0 · (나) 최근 10분 «교대 표의 서로 다른 모델 2개 이상» 역할 정지 ∧ 첫 정지 뒤 정상 0 → 보류 장애당 1통.
api-outage 상태 모양 어긋남 = raise(ERROR · 그 회차 교대 0 · fail-closed · r2 ④).
"""
# pyright: reportAttributeAccessIssue=false, reportUnknownMemberType=false
import json
import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))  # 형제 모듈 — python -I 에서도 찾는다
from ft_api_outage import Cut  # noqa: E402
from ft_api_outage_util import base_model, hhmm  # noqa: E402

WINDOW = 10 * 60
NOTIFY_WIN = 10 * 60   # r912 «교대 불가» 묶기 창 — 같은 좌석·같은 사유면 이 창에 1통
CLOSE = object()  # close_keys 의 «닫힘» 표지 — 손상 값(None 포함)과 겹치지 않게
Row = dict[str, object]


def as_kv(v: object) -> dict[str, int] | None:
    """r838 r4 알림 키 값 {at 알린 시각, seen 마지막 정지 본 시각} · 옛 정수 = at=seen=그 값 · 그 밖 = None(손상)."""
    if type(v) is int and v > 0:
        return {"at": v, "seen": v}
    if isinstance(v, dict) and all(type(v.get(k)) is int for k in ("at", "seen")):  # pyright: ignore[reportUnknownMemberType]
        return {"at": v["at"], "seen": v["seen"]}  # pyright: ignore[reportUnknownVariableType]
    return None


def write_atomic(path: Path, obj: object) -> None:
    """r863 r2 상태 파일 저장 = 직렬화 먼저(실패 = raise · 파일 손대기 0) → 같은 폴더 임시 파일 쓰기·fsync → os.replace · 실패 = 임시 파일만 지우고 raise."""
    data = json.dumps(obj, ensure_ascii=False).encode("utf-8")
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(f"{path.name}.tmp-{os.getpid()}")
    try:
        with open(tmp, "wb") as f:
            _ = f.write(data)
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp, path)
    except BaseException:
        tmp.unlink(missing_ok=True)
        raise


def shut(v: object) -> bool:  # outage_open 닫힘 = 키 없음 또는 정수 0(close_keys 가 쓰는 값) · None·{}·False 는 손상(열림 취급 아님)
    return type(v) is int and v == 0


class Account:
    _pend: "tuple[Path, dict[str, object]] | None" = None   # r912: send 뒤에 저장할 (경로, 상태) — notify_tail 이 채운다
    def read_key(self, name: str, v: object) -> dict[str, int] | None:
        """r863 알림 키 값 읽기는 여기 하나 — 손상 = ERROR 1줄(실행·키당 1) + None · 부르는 쪽 = 그 키 그대로(지우기·덮어쓰기 0) · 그 계보 알림 0."""
        if (kv := as_kv(v)) is None and name not in self.bad:
            self.bad.add(name)
            print(f"ERROR model_swap: 알림 키 값 깨짐 {name}={str(v)[:40]} — 키 그대로 · 이번 실행 그 계보 알림 0", file=sys.stderr)
        return kv

    def mute(self, key: str) -> bool:  # 이번 실행 손상 키와 같은 계보(키 = «계보|이유» · 장애 키 = outage_open)
        return any(n.split("|", 1)[0] == key.split("|", 1)[0] for n in self.bad)

    def hil_gate(self, key: str, to: object) -> tuple[bool, str]:
        """«교대 불가» 를 보낼지 + 꼬리 — r838 blocked · r863 손상 계보 · dry-run · 수신자 없음 = 안 보낸다.

        ★r3 재설계★ r838 blocked 가 «정지 사건당 1통» 을 이미 막는다. r912 가 더하는 창(10분)은
        «정상 회복 뒤 10분 안 재정지» 에만 적용한다 — 같은 좌석·같은 사유가 그 창 안에서 다시
        정지하면 알림 0통 · 시도 횟수만 오르고, 601초(=창 밖)면 새 1통 + 꼬리 « · 직전 10분 N회».
        """
        blocked = self.st["blocked"]
        ok = not (isinstance(blocked, dict) and key in blocked) and not self.mute(key) and isinstance(to, str) and not self.a.dry_run
        send_now, tail = self.notify_tail(key, ok)
        return (ok and send_now), tail

    def notify_sent(self, key: str) -> None:
        """★send 가 rc0 으로 «끝난 뒤» 에만 부른다★ (반송 r4 ②) — 보낸 시각=now · 횟수 1 저장.

        저장이 send «앞» 에 있으면 mbox rc3 로 거절된 알림이 «보낸 것» 으로 남아 창(10분) 내내
        침묵한다(DA⑥ 실측: 첫 발신 실패 뒤 N+60~599 가 0통). 저장 실패 = WARN 만(발신은 이미 했다).
        """
        if self._pend is None:
            return
        p, st = self._pend
        self._pend = None
        st[key] = {"last": self.now, "n": 1}
        _ = self._notify_save(p, st)

    def notify_tail(self, key: str, sending: bool) -> tuple[bool, str]:
        """r912 «교대 불가» 창(10분) 묶기 — (지금 보낼까, 꼬리).

        같은 좌석·같은 사유(키 = 계보|이유)가 마지막 알림 뒤 창(10분) 안에 또 정지하면 알림 0통이고
        횟수(n)만 오른다 — 창 밖(601초)에서 보낼 때 꼬리 « · 직전 10분 N회». 첫 알림은 절대 안 막는다
        (last 0 = 창 없음). 못 보낸 시도(blocked·손상·dry-run·수신자 없음)도 n 에 센다.
        값 = {키: {last 보낸 시각, n 그 뒤 시도 수}}. 읽기·쓰기 실패 = 꼬리 없이 그냥 보낸다 +
        WARN(조용히 안 보냄 0 · 상태 파일이 발신을 막는 길 0).

        ★«보낼 때» 는 저장하지 않는다★ — last=now 는 send rc0 뒤 notify_sent 가 쓴다(반송 r4 ②).
        창 안 «안 보냄» 도 저장이 성공했을 때만 — 저장이 실패하면 그 판정을 믿을 수 없으므로 그냥 보낸다(r4 ③).
        """
        p = self.ft / "state" / "model-swap-notify.json"
        self._pend = None
        try:
            raw = json.loads(p.read_text(encoding="utf-8"))
            st = raw if isinstance(raw, dict) else {}
        except FileNotFoundError:
            st = {}
        except (OSError, ValueError) as e:
            print(f"WARN model_swap: 알림 상태 못 읽음({e}) — 이번 알림은 묶지 않는다", file=sys.stderr)
            return True, ""
        e = st.get(key)
        last = e.get("last") if isinstance(e, dict) else None
        n = e.get("n") if isinstance(e, dict) else None
        last = last if type(last) is int else 0
        n = n if type(n) is int and n > 0 else 0
        inwin = bool(last) and self.now - last < NOTIFY_WIN
        if not sending:   # 못 보냈다(blocked·손상·dry-run·수신자 없음) — 시도만 세고 보낸 시각은 그대로
            st[key] = {"last": last, "n": n + 1 if inwin else 1}
            _ = self._notify_save(p, st)
            return False, ""
        if inwin:         # ★창 안 재정지 = 알림 0통★ — 시도 횟수만 오른다(사람 글·큐를 채우지 않는다)
            st[key] = {"last": last, "n": n + 1}
            if self._notify_save(p, st):
                return False, ""
            return True, ""   # 저장 실패 = 이 판정을 못 믿는다 → 묶지 않고 보낸다(WARN 문구와 동작 일치)
        tail = f" · 직전 10분 {n}회" if n >= 2 else ""
        self._pend = (p, st)   # ★저장은 send 뒤★ — 부르는 쪽이 send rc0 이면 notify_sent
        return True, tail

    def _notify_save(self, p: Path, st: dict[str, object]) -> bool:
        """묶기 상태 저장 — 실패 = WARN + False(저장된 묶기 판정이 없다 · 발신을 막지 않는다 · r912)."""
        try:
            write_atomic(p, st)
            return True
        except (OSError, TypeError, ValueError) as e:
            print(f"WARN model_swap: 알림 상태 저장 실패({e}) — 저장된 묶기 판정 없음(발신을 막지 않는다)", file=sys.stderr)
            return False

    def account(self, cands: list[tuple[str, Row, dict[str, object], Cut]], oks: list[tuple[int, str]]) -> bool:
        """r838 계정 한도 = 교대 0 · (가) api-outage 장애 중 ∧ 시작 뒤 정상 0 → 발신 0(알림 = ft_api_outage 1통) · (나) 최근 10분 역할 정지 ≥2 ∧ 첫 정지 뒤 정상 0 → 보류 장애당 1통."""
        after = lambda t0: any(t > t0 for t, _ in oks)  # noqa: E731
        if (since := self.outage_since()) and not after(since):
            return print(f"HOLD 계정 전체 한도 — api-outage 장애 중({hhmm(since)}~) · 교대 0 · 발신 0") or True
        raw, fresh = self.st.get("outage_open", 0), [c for _, _, _, c in cands if c.ts >= self.now - WINDOW]
        was = None if shut(raw) else self.read_key("outage_open", raw)  # r863 손상 = None · 보류는 이번 정지로만 판정 · 알림·덮어쓰기 0
        known = set(self.table) | {base_model(v) for v in self.table.values()}  # r838 r2 ③: (나) = 교대 표의 서로 다른 모델 2개 이상 정지 · 같은 모델 여럿 = 모델 하나 한도(r497)
        first = min((c.ts for c in fresh), default=0)
        hit = bool(was) or (len({c.model for c in fresh if c.model in known}) >= 2 and not after(first))  # 열린 키 = 닫힐 때까지 보류 · 닫기 = Swap.close_keys 하나(r3 ②)
        to, sent = cands[0][2].get("_hil_route") or cands[0][2].get("_master"), list(self.st.get("outage_notified") or [])  # pyright: ignore[reportCallIssue,reportArgumentType,reportUnknownArgumentType,reportUnknownVariableType]
        if hit and shut(raw) and first not in sent and isinstance(to, str) and not self.a.dry_run:
            self.send(to, f"[자동 교대 보류] 계정 전체 한도 — 정지 좌석 {len(cands)} · 교대 0 · 풀리면 ft_api_outage 재개")
            self.st["outage_open"], self.st["outage_notified"] = {"at": self.now, "seen": self.now}, [*sent, first][-20:]  # 키 값 {at, seen}(r4)
        return hit and (print(f"HOLD 계정 전체 한도 — 정지 좌석 {len(cands)} · {hhmm(was['at'] if was else first)}~ · 교대 0") or True)

    def outage_since(self) -> int:
        """api-outage 좌석표 상태 중 OUTAGE 의 가장 이른 시작 · 모양 어긋남 = raise(r838 r2 ④ · ERROR · 그 회차 교대 0 · fail-closed)."""
        since = []
        for f in sorted((self.ft / "state" / "api-outage").glob("seats*.json")):
            s = json.loads(f.read_text(encoding="utf-8"))
            if not isinstance(s, dict) or s.get("status") not in ("OK", "OUTAGE", "RECOVERED"):
                raise ValueError(f"api-outage 상태 모양 어긋남 {f.name}: status")
            if s["status"] == "OUTAGE" and not (type(s.get("since")) is int and s["since"] > 0):
                raise ValueError(f"api-outage 상태 모양 어긋남 {f.name}: OUTAGE 에 since 없음")
            since += [s["since"]] if s["status"] == "OUTAGE" else []
        return min(since, default=0)
