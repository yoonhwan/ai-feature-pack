#!/usr/bin/env python3
# pyright: basic
"""ft_desk_reply_wake.py — r1574: desk 승인 질문의 오빠 답글을 비모델(ft-stall-scan 120초 주기)이 찾아 desk 를 깨운다.
CLI: (인자 없음) 점검 · `--register <질문ts> <h번호> <sha40>` 등록(desk 가 Slack 질문 글을 올린 직후 · 끝 시각 = 등록 + 24h) · `--register-plan <계획> <h번호>` = 계획의 `approve-merge <sha40> … --oppa-slack <ts>` 1개에서 ts·sha 를 뽑아 같은 등록(r1587 · ft-hil 발급 자리)
점검 = 끝나지 않은 줄마다 ft_oppa_slack_check 1회(7초 · 재시도 1) → SLACK-OK 이면 seats-planner.json `_desk` 로 `[오빠 답글] h<N> ts=<답글> → 실행 차례` 1통.
끝 = h 실행 기록(<HIL_DIR>/h<N>.ran) 생성 또는 끝 시각 경과(경과는 `_master` 로 `[답글 없음 24시간]` 1통) · 같은 답글 ts = 1통 · 질문 ts 키는 한 줄(재등록 멱등).
r1591 · `--register-question <질문ts> <사유키>` = h·sha 칸이 없는 오빠 질문(설계 승인 등) 등록(kind=question · key 한 칸) → 점검은 `--reply-only` 로 보고 REPLY-SEEN 이면 `_master` 로 `[오빠 답글] <사유키> ts=<답글>` 1통(승인 판정 0).
r1776 · question 줄 조회 = `--reply-only <q> --stop-at <장부의 더 늦은 question ts> [--after <notified_ts>]` → 새 글마다 `[오빠 새 글] <키> ts=<글> → 원문 확인 · 답이면 --close <키>` 1통 · 줄은 notified(닫기 = --close) · notified 줄 끝 시각 = 조용히 timeout-notified.
r1764 · thread 줄(`--register-thread <스레드ts> <사유키>`)은 등록된 스레드에 오빠 «새 글» 이 올 때마다 `_desk` 1통 · 끝 시각 경과 = 조용히 닫힘 · `--close <질문ts|사유키> [--reason <낱말>]` = 열린 줄 수동 닫기 — 갈래 셋은 ft_desk_reply_thread.py 에 있다(이 파일은 부르기만).
장부 갱신 = 배타 잠금(<장부>.lock) 안에서 다시 읽고 합쳐 쓰기 · 조회는 <장부>.cursor 로 순환(열린 줄이 상한보다 많아도 모두 본다).
장부 = <루트>/.fable-team/state/desk-reply-wait.jsonl(open|notified|closed) · env: FT_ROOT · FT_NOW · FT_MBOX_SH · FT_SEATS_PLANNER · FT_SLACK_CHECK · HIL_DIR · FT_DESK_REPLY_LEDGER · FT_DESK_REPLY_MAX(4)
rc: 0 정상 · 1 발신·쓰기 실패 · 2 판정 불가(루트·장부·명부) · 3 등록 거절
"""
import fcntl
import io
import json
import os
import re
import subprocess
import sys
import time
from contextlib import redirect_stderr
from decimal import Decimal
from pathlib import Path
from types import SimpleNamespace

TS, SHA, HN = re.compile(r"[0-9]+\.[0-9]{6}$"), re.compile(r"[0-9a-f]{40}$"), re.compile(r"h[0-9]+$")
PLAN = re.compile(r"(?<![\w-])approve-merge\s+([0-9a-fA-F]{40})(?![0-9a-fA-F])[^\n]*?(?<![\w-])--oppa-slack[ =]+(?:(C[A-Z0-9]{8,12}):)?([0-9]+\.[0-9]{6})(?![\w.-])")  # r1587 · r1857 채널 칸 · ft_scope_plan_judge.OPPA 와 같은 꼴
TO, SEND_TO, MAX, DAY = 7, 25, 4, 86400  # 7초·재시도 1(하드 룰 12) · 발신 25초(로컬 하네스 상한) · 한 주기 4줄 · 24시간
KEY = re.compile(r"[a-z0-9][a-z0-9._-]{0,63}$")  # r1591 · 사유키 = 카드 slug 꼴


def bad(m: str) -> None:
    print("ft-desk-reply-wake 판정 불가 — " + m, file=sys.stderr)


def thread_mod():  # r1764 · thread 줄·--close 갈래 = 같은 폴더 새 파일(이 파일은 부르기만) · 없으면 None(부른 자리가 1줄로 드러낸다)
    sys.path[:0] = [str(Path(__file__).resolve().parent)]
    try:
        import ft_desk_reply_thread
    except ImportError:
        return None
    return ft_desk_reply_thread


def ns(base: Path, led: Path, seat: dict | None = None, check: str = "", maxn: int = MAX) -> SimpleNamespace:  # 새 파일에 넘기는 손잡이(잠금·장부·발신·명부)
    return SimpleNamespace(base=base, led=led, lock=lock, ledger=ledger, send=send, seat=seat or {}, check=check, maxn=maxn)


def lock(p: Path):  # 장부 배타 잠금 — 읽기→갱신 전체를 직렬화한다(등록과 점검이 겹쳐도 유실 0)
    f = p.parent / (p.name + ".lock")
    f.parent.mkdir(parents=True, exist_ok=True)
    fh = open(f, "a")
    fcntl.flock(fh, fcntl.LOCK_EX)
    return fh


def ledger(p: Path, rows: list | None = None) -> list | None:  # rows 없으면 읽기(못 읽으면 None) · 주면 원자적 쓰기
    try:
        if rows is None:
            return [json.loads(x) for x in p.read_text(encoding="utf-8").splitlines() if x.strip()] if p.exists() else []
        t = p.with_suffix(p.suffix + ".tmp")
        t.write_text("".join(json.dumps(r, ensure_ascii=False) + "\n" for r in rows), encoding="utf-8")
        os.replace(t, p)
        return rows
    except (OSError, json.JSONDecodeError):
        return None


def rowkey(r: dict) -> tuple[str, str]:  # r1764 보정 · 같은 q_ts 라도 kind 가 다르면 «다른 줄»(thread ↔ question 갱신 섬임 0)
    return (r.get("kind") or "h", r.get("q_ts"))


def commit(p: Path, up: dict) -> bool:  # 락 안에서 «다시 읽고» 바뀐 칸만 합쳐 쓴다(점검 중 들어온 등록 보존)
    try:
        fh = lock(p)
    except OSError:
        return False
    try:
        rows = ledger(p)
        if rows is None:
            return False
        for r in rows:
            u = up.get(rowkey(r)) or up.get(r.get("q_ts"))  # 앞 = r1764 갈래 열쇠((kind, ts)) · 뒤 = 옛 꼴(q_ts 만) — h 줄 호환
            if u:
                r.update(u)
        return bool(ledger(p, rows))
    finally:
        fh.close()


def cursor(p: Path, i: int | None = None) -> int:  # 다음에 볼 장부 줄번호(순환) — 못 읽으면 0(처음부터)
    f = p.parent / (p.name + ".cursor")
    try:
        if i is not None:
            f.write_text("%d\n" % i, encoding="utf-8")
            return i
        return int(f.read_text(encoding="utf-8").strip() or 0)
    except (OSError, ValueError):
        return 0


def send(base: Path, to: str, body: str) -> int:  # 0 = mbox 접수 · 25초 상한(로컬 하네스)
    sh = os.environ.get("FT_MBOX_SH") or str(base / ".fable-team/comm/mbox.sh")
    try:
        return subprocess.run(["bash", sh, "send", to, "ft-desk-reply-wake", body], capture_output=True, text=True, timeout=SEND_TO).returncode
    except (OSError, subprocess.SubprocessError):
        return 1


def judge(cmd: str, q: str, sha: str, argv: list | None = None) -> tuple[int, str]:  # 7초 · 재시도 1 · r1776 argv = question 줄 전용(h 줄은 [q, sha] 그대로)
    last = (1, "점검 도구 실행 실패")
    for _ in range(2):
        try:
            r = subprocess.run([sys.executable, cmd] + (argv or [q, sha]), capture_output=True, text=True, timeout=TO)
        except subprocess.SubprocessError:
            last = (124, "조회 %d초 초과" % TO)
            continue
        if r.returncode == 0:
            return 0, r.stdout
        last = (r.returncode, (r.stdout or r.stderr))
    return last


def register(led: Path, a: list, now: float, chan: str = "") -> int:  # ⓐ 등록 · 같은 질문 ts = 멱등 · 다른 값 = 거절(조용한 중복 0)
    h = a[1] if len(a) > 1 and HN.match(a[1]) else ("h" + a[1] if len(a) > 1 and a[1].isdigit() else "")
    row = {"q_ts": a[0] if a else "", "h": h, "sha": a[2].lower() if len(a) > 2 else "", "at": int(now), "deadline": int(now + DAY), "state": "open", **({"channel": chan} if chan else {})}  # r1857 · 채널 칸 없는 옛 줄 = byz-desk
    if len(a) != 3 or not TS.match(row["q_ts"]) or not h or not SHA.match(row["sha"]):
        print("감시 등록 실패 — 사용: --register <질문ts(1794295513.494289)> <h번호> <sha40>", file=sys.stderr)
        return 3
    try:
        fh = lock(led)
    except OSError as e:
        print("감시 등록 실패 — 장부 잠금 실패(%s): %s" % (e.__class__.__name__, led), file=sys.stderr)
        return 3
    try:
        rows = ledger(led)
        if rows is None:
            print("감시 등록 실패 — 장부를 못 읽음: %s" % led, file=sys.stderr)
            return 3
        same = next((r for r in rows if r.get("q_ts") == row["q_ts"] and r.get("kind") != "thread"), None)  # r1764 보정 · thread 줄은 다른 갈래(같은 ts 라도 충돌 아님)
        if same is not None:
            if same.get("h") == h and same.get("sha") == row["sha"]:
                print("등록 %s q_ts=%s 끝=%s (이미 등록 — 중복 0)" % (h, row["q_ts"], same.get("deadline")))
                return 0
            print("감시 등록 실패 — 같은 질문 ts 가 다른 값으로 이미 등록됨(%s · sha %s)" % (same.get("h"), same.get("sha")), file=sys.stderr)
            return 3
        if not ledger(led, rows + [row]):
            print("감시 등록 실패 — 장부 쓰기 실패: %s" % led, file=sys.stderr)
            return 3
    finally:
        fh.close()
    print("등록 %s q_ts=%s 끝=%d" % (h, row["q_ts"], row["deadline"]))
    return 0


def register_question(led: Path, a: list, now: float) -> int:  # r1591 · h·sha 칸이 없는 오빠 질문(설계 승인 등) — key 한 칸 · 승인 실행 기록(h 실행) 닫힘 없음
    row = {"q_ts": a[0] if a else "", "kind": "question", "key": a[1] if len(a) > 1 else "", "at": int(now), "deadline": int(now + DAY), "state": "open"}
    if len(a) != 2 or not TS.match(row["q_ts"]) or not KEY.match(row["key"]):
        print("감시 등록 실패 — 사용: --register-question <질문ts(1794295513.494289)> <사유키(r1590)>", file=sys.stderr)
        return 3
    try:
        with lock(led):
            rows = ledger(led)
            old = next((r for r in rows or [] if r.get("q_ts") == row["q_ts"] and r.get("kind") != "thread"), None)  # r1764 보정 · thread 줄은 다른 갈래
            if rows is None or (old and old.get("key") != row["key"]) or (old is None and not ledger(led, rows + [row])):
                print("감시 등록 실패 — 장부를 못 읽음·못 씀 또는 같은 질문 ts 가 다른 사유키로 이미 등록됨: %s" % led, file=sys.stderr)
                return 3
            print("등록 %s q_ts=%s 끝=%s%s" % (row["key"], row["q_ts"], (old or row).get("deadline"), " (이미 등록 — 중복 0)" if old else ""))
            return 0
    except OSError as e:
        print("감시 등록 실패 — 장부 처리 실패(%s): %s" % (type(e).__name__, led), file=sys.stderr)
        return 3


def register_plan(led: Path, a: list, now: float) -> int:  # r1587: 계획의 `approve-merge <sha40> … --oppa-slack <ts>` 1개 → ts·sha 로 기존 register · 0개 = 대상 아님(조용히 rc0) · 2개 이상 = 판정 불가 1줄
    try:
        hits = PLAN.findall(Path(a[0]).read_text(encoding="utf-8", errors="replace")) if len(a) == 2 else []
    except OSError as e:
        print("감시 등록 판정 불가 — 계획을 못 읽음(%s): %s" % (type(e).__name__, a[0]), file=sys.stderr)
        return 3
    if len(hits) != 1:
        if not hits:
            return 0
        print("감시 등록 판정 불가 — approve-merge --oppa-slack 줄이 %d개: %s" % (len(hits), a[0]), file=sys.stderr)
        return 3
    with redirect_stderr(err := io.StringIO()):  # 실패는 «감시 등록 실패 <ts>» 1줄로 모아 드러낸다(조용한 실패 0)
        rc = register(led, [hits[0][2], a[1], hits[0][0].lower()], now, hits[0][1])
    if rc:
        why = (err.getvalue().strip().splitlines() or ["알 수 없음"])[-1].replace("감시 등록 실패 — ", "")
        print("감시 등록 실패 %s — %s" % (hits[0][2], why), file=sys.stderr)
    return rc


def scan(base: Path, led: Path, now: float) -> int:
    rows = ledger(led)
    if rows is None:
        bad("장부를 못 읽음(JSON 아님·권한): %s" % led)
        return 2
    try:
        raw = json.loads(Path(os.environ.get("FT_SEATS_PLANNER") or base / ".fable-team/seats-planner.json").read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        bad("명부를 못 읽음(seats-planner.json)")
        return 2
    seat = {k: v for k, v in raw.items() if isinstance(v, str)} if isinstance(raw, dict) else {}
    check = os.environ.get("FT_SLACK_CHECK") or str(Path(__file__).resolve().parent / "ft_oppa_slack_check.py")
    hil, maxn = Path(os.environ.get("HIL_DIR") or "/tmp"), int(os.environ.get("FT_DESK_REPLY_MAX") or MAX)
    up: dict[str, dict] = {}  # q_ts → 바꿀 칸
    shut = nbad = sent = 0
    cands: list[int] = []
    for i, row in enumerate(rows):
        qn, h, q = row.get("kind") == "question", row.get("h") or row.get("key"), row.get("q_ts")  # r1591 · 질문 줄은 h 대신 key
        if row.get("state") == "closed":
            continue
        if row.get("kind") == "thread":  # r1764 · thread 줄은 아래 scan_threads 가 본다(만료 = 조용히)
            continue
        if not isinstance(h, str) or not isinstance(q, str):
            bad("장부 줄 꼴 아님: %s" % json.dumps(row, ensure_ascii=False)[:120])
            nbad += 1
            continue
        if not qn and (hil / (h + ".ran")).exists():  # ⓒ h 실행 기록 = 그 줄 닫힘(질문 줄은 h 실행 기록이 없다)
            up[rowkey(row)] = {"state": "closed", "closed": "executed"}
            shut += 1
            continue
        if now >= float(row.get("deadline") or 0):  # ⓒ 24시간 경과 = 닫고 planner master 1통
            if qn and row.get("state") == "notified":  # r1776 A4ⓑ · 새 글 알림이 간 질문 줄 = 조용히 닫힘(24h 오알림 0)
                up[rowkey(row)] = {"state": "closed", "closed": "timeout-notified"}
                shut += 1
                continue
            if not seat.get("_master") or send(base, seat["_master"], "[답글 없음 24시간] %s ts=%s → 장부 줄 닫힘" % (h, q)):
                bad("쪽지 발신 실패·수신자 없음 — %s 줄은 열린 채로 둔다" % h)
                nbad += 1
                continue
            up[rowkey(row)] = {"state": "closed", "closed": "timeout"}
            shut += 1
            continue
        cands.append(i)
    cur = cursor(led) % len(rows) if rows else 0
    picked = ([i for i in cands if i >= cur] + [i for i in cands if i < cur])[:maxn]  # R2 조회 순환
    for i in picked:
        row, h, q = rows[i], rows[i].get("h") or rows[i].get("key"), rows[i]["q_ts"]  # r1591 · 질문 줄은 h 대신 key · sha 칸 없음 = 답글 확인 모드
        qn = row.get("kind") == "question"  # r1591 · 오빠 질문(설계 승인 등) = 답글이 왔다는 알림만 · 승인 판정 0 · 받는이 planner master
        tgt = seat.get("_master") if qn else (seat["_desk"] if "_desk" in seat else None)
        if not tgt:  # ⓓ 현역 좌석 없음 = 알림 기록 0 · 다음 주기 재시도
            bad("%s 없음 — %s 알림 0(다음 주기 재시도)" % ("_master" if qn else "_desk", h))
            nbad += 1
            continue
        later = sorted({r["q_ts"] for r in rows if r.get("kind") == "question" and TS.match(str(r.get("q_ts"))) and TS.match(q) and Decimal(r["q_ts"]) > Decimal(q)}, key=Decimal) if qn else []  # r1776 A2 · state 무관
        args = (["--reply-only", q] + (["--stop-at", ",".join(later)] if later else []) + (["--after", row["notified_ts"]] if row.get("notified_ts") else [])) if qn else None
        rc, out = judge(check, row["channel"] + ":" + q if row.get("channel") else q, row.get("sha") or "", args)  # r1857
        if rc == 3:  # r1591 · 질문 줄의 답글 아직 없음 = 정상 열린 줄(판정 불가 아님)
            continue
        m = re.search(r"reply=([0-9]+\.[0-9]+)$", out.strip().splitlines()[-1]) if rc == 0 and out.strip() else None
        if not m:  # ⓓ 조회 실패·토큰 없음 = «판정 불가» 1줄 · 알림 완료 기록 0
            bad("%s %s" % (h, (out.strip().splitlines() or ["SLACK-OK 줄 없음"])[-1][:160]))
            nbad += 1
            continue
        if row.get("notified_ts") == m.group(1):  # ⓑ 중복 억제 키 = 질문 ts·답글 ts(다른 답글 ts 면 1통 더)
            continue
        if send(base, tgt, "[오빠 새 글] %s ts=%s → 원문 확인 · 답이면 --close %s" % (h, m.group(1), h) if qn else "[오빠 답글] %s ts=%s → 실행 차례" % (h, m.group(1))):  # r1776 A3
            bad("쪽지 발신 실패 — %s 알림 0(다음 주기 재시도)" % h)
            nbad += 1
            continue
        up[rowkey(row)] = {"notified_ts": m.group(1), "notified_at": int(now), "state": "notified"}  # r1776 · 질문 줄도 알림만 · 닫기 = --close 또는 끝 시각(timeout-notified)
        sent += 1
    tm = thread_mod()  # r1764 · 스레드 새 글·조용한 만료
    if tm is None:
        bad("ft_desk_reply_thread.py 를 못 읽음 — thread 줄 알림 0(설치 확인)")
        nbad += 1
    else:
        tup, tsent, tshut, tnbad = tm.scan_threads(ns(base, led, seat, check, maxn), rows, now)
        up |= tup
        sent, shut, nbad = sent + tsent, shut + tshut, nbad + tnbad
    if picked:
        cursor(led, (picked[-1] + 1) % len(rows))
    if up and not commit(led, up):
        bad("장부 쓰기 실패 — 다음 주기에 같은 답글이 1통 더 갈 수 있다")
        return 1
    print("desk-reply-wake 열린=%d 알림=%d 닫힘=%d 판정불가=%d" % (len(cands), sent, shut, nbad))
    return 1 if nbad else 0


def main(argv: list) -> int:
    base = Path(os.environ["FT_ROOT"]) if os.environ.get("FT_ROOT") else Path.cwd()
    if not (base / ".fable-team").is_dir():
        bad("루트를 못 풂(FT_ROOT 없음 · cwd 에 .fable-team/ 없음)")
        return 2
    led = Path(os.environ.get("FT_DESK_REPLY_LEDGER") or base / ".fable-team/state/desk-reply-wait.jsonl")
    now = float(os.environ.get("FT_NOW") or time.time())
    if argv[1:2] == ["--register-plan"]:
        return register_plan(led, argv[2:], now)
    if argv[1:2] == ["--register-question"]:
        return register_question(led, argv[2:], now)
    if argv[1:2] in (["--register-thread"], ["--close"]):  # r1764
        tm = thread_mod()
        if tm is None:
            bad("ft_desk_reply_thread.py 를 못 읽음 — 설치 확인")
            return 2
        return tm.register_thread(ns(base, led), argv[2:], now) if argv[1:2] == ["--register-thread"] else tm.close(ns(base, led), argv[2:], now)
    return register(led, argv[2:], now) if argv[1:2] == ["--register"] else scan(base, led, now)


if __name__ == "__main__":
    sys.exit(main(sys.argv))
