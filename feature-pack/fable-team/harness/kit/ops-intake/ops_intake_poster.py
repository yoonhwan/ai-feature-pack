#!/usr/bin/env python3
"""ops_intake_poster — mini 게시기. mini 쪽지함의 [OPS-REPLY] 1통 → 슬랙 같은 스레드 답글 1건 → 쪽지 삭제(ack).

계약(기획 §3 ⑨ · §4 · §6):
  · `thread_ts` 가 없으면 게시 0 (최상위 글 금지) — rc2
  · 게시 «전» 문장 검사: 비밀 + 내부어(경로·좌석 이름·sha·판정 번호) → 걸리면 게시 0 — rc4
  · 같은 쪽지(seq+ts)는 두 번 게시하지 않는다 — state/posted.json 장부
  · 봇 토큰은 mini `~/.hermes/.env` 에서 «읽기만» 한다(새 비밀 0)
  · 슬랙 호출은 하네스 정본 `mirror_lib.post` 재사용 — 7초 상한 + 재시도 1 이 그 안에 있다

사용: python3 ops_intake_poster.py            1회 처리(launchd 60초)  rc 0 정상 · 2 형식 · 4 게시 거부 · 5 쪽지 실패
env: OPS_INTAKE_ROOT · OPS_MBOX_SH/OPS_MBOX_PY · OPS_SLACK_LIB(정본 slack-mirror 폴더) · OPS_HERMES_ENV · OPS_SLACK_BASE · OPS_INTAKE_CHANNEL · OPS_TOOL_SEAT · FT_NOW
"""
from __future__ import annotations

import fcntl
import hashlib
import json
import re
import socket
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

import ops_intake_common as c

HEADS = "[OPS-REPLY]"
TS_RX = re.compile(r"^\s*thread_ts:\s*(\S+)\s*$", re.M)
CHAN_RX = re.compile(r"^\s*channel:\s*(\S+)\s*$", re.M)
OPS_RX = re.compile(r"\[OPS-REPLY\]\s*(OPS-\d{8}-\d{3})")
SHA_RX = re.compile(r"(?<![0-9A-Za-z])[0-9a-f]{7,40}(?![0-9A-Za-z])")  # 커밋 sha 꼴 — 사람 글에 나갈 이유가 없다
# DA⑥ r1 반례: «/etc/service/config.yaml» 같은 시스템 절대경로와 «토큰 ***» 같은 «비밀 종류 + 가림 표시» 는
# 사용자 글에 나갈 이유가 없다(내부 구조 노출 · 우리가 무엇을 가렸는지 알려 주는 것).
PATH_RX = re.compile(r"(?<![\w.~/-])(?:~|/[\w.@-]+)/(?:[\w.@-]+/)*[\w.@-]*")  # /a/b 이상 · ~/a
SECRET_WORD_RX = re.compile(r"(?i)(토큰|비밀번호|비번|키|dsn|token|secret|password|api[ _-]?key)")
MASK_MARK_RX = re.compile(r"\*\*\*|마스킹")
MAX_LINES = 3
WALL_LIMIT = 7.0  # ★호출 «전체» 벽시계★ — 소켓 timeout 은 1바이트씩 흘리면 매번 되살아난다(DA r3 반례 4)


def slack_lib():
    """정본 post_guard 규칙표 + mirror_lib.post — 복제 0."""
    here = Path(__file__).resolve().parent
    d = Path(c.env_path("OPS_SLACK_LIB", str(here.parent / "slack-mirror")))
    if not (d / "post_guard.py").is_file() or not (d / "mirror_lib.py").is_file():
        raise c.IntakeError(f"슬랙 정본 모듈 없음: {d} · 게시 0", 2)
    if str(d) not in sys.path:
        sys.path.insert(0, str(d))
    import mirror_lib
    import post_guard
    return mirror_lib, post_guard


def secrets(text: str) -> None:
    """★비밀 검출기는 하나★ — 가림 자리는 common 한 곳(`c.post_kinds`)뿐이다. 검출 1건 이상이면 게시 0.
    두 쪽 판정이 갈리면 그 차이가 곧 구멍이다(DA⑥ r2 반례 1 · r6 «개별 호출 0»)."""
    kinds = c.post_kinds(text)
    if kinds:
        raise c.IntakeError(f"게시 거부 — 비밀 꼴 검출({c.kind_summary(kinds)}) · 카드 검출기와 같은 판정 · 게시 0", 4)


def guard(text: str) -> None:
    """게시 전 문장 검사 — ① 비밀 = 카드와 같은 검출기 ② 내부어 = 정본 규칙표(post_guard) + 이 폴더 3규칙."""
    secrets(text)
    _ml, pg = slack_lib()
    hits = [f"묶음2:{n}" for n, p in pg.INTERNAL.items() if re.search(p, text)]
    if SHA_RX.search(text):
        hits.append("묶음2:sha")
    if PATH_RX.search(text):
        hits.append("묶음2:abs-path")
    if MASK_MARK_RX.search(text) and SECRET_WORD_RX.search(text):
        hits.append("묶음2:secret-with-mask-mark")
    if hits:
        raise c.IntakeError(f"게시 거부(post_guard) — {', '.join(hits)} · 게시 0", 4)


def token(path: Path) -> str:
    """`SLACK_BOT_TOKEN=값` — 값은 어디에도 출력하지 않는다."""
    try:
        for ln in path.read_text(encoding="utf-8").splitlines():
            if ln.startswith("SLACK_BOT_TOKEN=") and ln.split("=", 1)[1].strip():
                return ln.split("=", 1)[1].strip().strip("'\"")
    except OSError as e:
        raise c.IntakeError(f"토큰 파일 읽기 실패: {path} ({type(e).__name__}) · 게시 0", 2) from e
    raise c.IntakeError(f"토큰 파일에 SLACK_BOT_TOKEN 없음: {path} · 게시 0", 2)


def channel_of(body: str, ops_id: str) -> str:
    m = CHAN_RX.search(body) or re.search(r"채널\s+(C[A-Z0-9]{6,})", body)
    if m:
        return m.group(1)
    if c.env_path("OPS_INTAKE_CHANNEL", ""):
        return c.env_path("OPS_INTAKE_CHANNEL", "")
    st = c.read_json(c.sub("status") / f"{ops_id}.json", {})
    if isinstance(st, dict) and st.get("slack_channel"):
        return str(st["slack_channel"])
    raise c.IntakeError("채널 판정 불가 — channel 줄·OPS_INTAKE_CHANNEL·상태 파일 모두 없음 · 게시 0", 2)


def parse(body: str) -> tuple[str, str, str]:
    """(ops_id, thread_ts, 게시 문장). 첫 줄 머리는 문장에서 뺀다."""
    m_o, m_t = OPS_RX.search(body), TS_RX.search(body)
    if not m_o:
        raise c.IntakeError("형식 위반: [OPS-REPLY] ops_id 없음 · 게시 0", 2)
    if not m_t:
        raise c.IntakeError(f"형식 위반: thread_ts 없음({m_o.group(1)}) · 최상위 글 금지 · 게시 0", 2)
    lines = [ln for ln in body.splitlines() if ln.strip() and not TS_RX.match(ln) and not CHAN_RX.match(ln) and not ln.startswith(HEADS)]
    lines = [ln for ln in lines if not ln.strip().startswith("상태 파일")]
    if not lines:
        raise c.IntakeError("형식 위반: 게시 문장 없음 · 게시 0", 2)
    return m_o.group(1), m_t.group(1), "\n".join(lines[:MAX_LINES])


def ledger_key(ops_id: str, ts: str, text: str) -> str:
    """같은 쪽지를 두 번 보내도(new seq) 한 번만 게시 — 본문 지문으로 센다."""
    return hashlib.sha1(f"{ops_id}|{ts}|{text}".encode()).hexdigest()[:16]


def marker(key: str) -> str:
    """본문 끝 표식 — 자기 검사(SHA_RX·PATH_RX·NAMED)에 안 걸리는 꼴: base36 5자(hex 7자 미만) · 콜론·슬래시 0."""
    n = int(key, 16)
    digits, out = "0123456789abcdefghijklmnopqrstuvwxyz", ""
    while n:
        n, r = divmod(n, 36)
        out = digits[r] + out
    return "ops-" + (out or "0").rjust(5, "0")[-5:]


def final_text(text: str, tag: str) -> str:
    return f"{text}\n· {tag}"


def _call(base: str, tok: str, method: str, params: dict, *, get: bool = False, limit: float = WALL_LIMIT) -> dict:
    """슬랙 1회 호출 — ★벽시계 7초 하나, 시작 = `urlopen()` «호출 전»★(카드 r6 · DA⑥ r4 반례 3).
    연결·상태줄·헤더·본문·종료가 전부 그 안에 들어간다. 마감에 소켓을 닫아 막힌 recv 를 끊고,
    결과를 기다리는 쪽도 `wait(남은 시간)` 으로 같은 마감을 지킨다 — 넘으면 TimeoutError(sent 0 · 원장 failed)."""
    end = time.monotonic() + limit  # ★타이머 시작 자리 하나 — urlopen 보다 먼저★

    def left() -> float:
        return end - time.monotonic()

    headers = {"Authorization": f"Bearer {tok}"}
    if get:
        req = urllib.request.Request(f"{base}/{method}?{urllib.parse.urlencode(params)}", headers=headers)
    else:
        headers["Content-Type"] = "application/json; charset=utf-8"
        req = urllib.request.Request(f"{base}/{method}", data=json.dumps(params).encode("utf-8"), headers=headers)
    box: dict = {}
    done = threading.Event()

    def _shutdown() -> None:  # 마감 — 소켓을 닫아 상태줄·헤더·본문 어느 구간에서 막혀도 끊는다
        sock = box.get("sock")
        try:
            if sock is not None:
                sock.shutdown(socket.SHUT_RDWR)
        except Exception:
            pass

        def _close() -> None:  # 응답 닫기는 «다른 스레드» 에서 — 막힌 read 를 쥔 채로 마감을 늦추면 안 된다
            try:
                resp = box.get("resp")
                if resp is not None:
                    resp.close()
            except Exception:
                pass

        threading.Thread(target=_close, daemon=True).start()

    def work() -> None:
        try:
            resp = urllib.request.urlopen(req, timeout=max(0.1, left()))
            box["resp"] = resp
            box["sock"] = getattr(getattr(getattr(resp, "fp", None), "raw", None), "_sock", None)
            chunks: list[bytes] = []
            try:
                while True:
                    if left() <= 0:
                        raise TimeoutError(f"{method} 벽시계 {limit:.0f}초 초과")
                    chunk = resp.read1(4096)
                    if not chunk:
                        break
                    chunks.append(chunk)
            finally:
                resp.close()
            box["raw"] = b"".join(chunks)
        except BaseException as e:  # 소켓 닫힘·깨진 응답 — 호출한 쪽이 마감과 함께 판단한다
            box["err"] = e
        finally:
            done.set()

    threading.Thread(target=work, daemon=True).start()
    if not done.wait(max(0.0, left())):  # 마감까지 결과가 없으면 실패
        _shutdown()
        raise TimeoutError(f"{method} 벽시계 {limit:.0f}초 초과")
    if left() <= 0:  # 결과가 마감을 넘겨 도착한 경우(4초 청크 + 8초 종료)
        raise TimeoutError(f"{method} 벽시계 {limit:.0f}초 초과")
    if "err" in box:
        raise box["err"]
    body = json.loads(box["raw"].decode("utf-8"))
    if not body.get("ok"):
        raise RuntimeError(f"{method} ok=false")
    return body


def post_bounded(base: str, tok: str, channel: str, text: str, ts: str) -> str:
    body = _call(base, tok, "chat.postMessage", {"channel": channel, "text": text, "thread_ts": ts})
    return str(body.get("ts"))


def thread_has(ml, base: str, tok: str, entry: dict) -> bool | None:
    """이 스레드에 표식이 이미 있나 — True 있음 · False 없음 · None 확인 불가(조회 실패).
    조회가 실패하면 «없다» 로 단정하지 않는다(그 단정이 재게시를 만든다)."""
    try:
        body = _call(base, tok, "conversations.replies", {"channel": entry["channel"], "ts": entry["ts"], "limit": 100}, get=True)
    except Exception:
        return None
    tag = marker(entry.get("key") or "")
    return any(tag in str(m.get("text", "")) for m in body.get("messages") or [])


def lock_ledger():
    """원장 단일 실행 잠금 — 두 프로세스가 같이 돌면 둘 다 «보내는 중 없음» 을 보고 둘 다 보낸다.
    잠금 파일을 열어 LOCK_EX 로 잡고, 그 핸들을 돌려준다(닫으면 풀린다)."""
    path = c.sub("state") / "posted.lock"
    fh = open(path, "w")
    fcntl.flock(fh, fcntl.LOCK_EX)
    return fh


def main() -> int:
    seat = c.env_path("OPS_TOOL_SEAT", "byz-opsintake-tool-cmd#0")
    ledger_path = c.sub("state") / "posted.json"
    rows = [r for r in c.mbox_rows(seat) if str(r.get("body", "")).startswith(HEADS)]
    if not rows:
        print("POST idle n=0")
        return 0
    ml, _pg = slack_lib()
    tok = token(Path(c.env_path("OPS_HERMES_ENV", str(c.home() / ".hermes/.env"))))
    base = c.env_path("OPS_SLACK_BASE", "https://slack.com/api/")
    lock = lock_ledger()  # ★여기서부터 원장은 한 프로세스만 본다★
    ledger: dict = c.read_json(ledger_path, {})
    if not isinstance(ledger, dict):
        ledger = {}
    ok, acked, stuck, sent = 0, [], 0, 0
    try:
        for row in rows:
            ops_id, ts, text = parse(str(row.get("body", "")))
            key = ledger_key(ops_id, ts, text)
            entry = ledger.get(key) or {}
            if entry.get("state") == "sent":
                acked.append(row.get("seq"))
                continue
            ch = channel_of(str(row.get("body", "")), ops_id) if not entry else entry.get("channel", "")
            tag = marker(key)
            body_text = final_text(text, tag)
            guard(body_text)  # ★표식 붙인 최종 본문★ 에 검사를 건다(자기 표식에 자기가 안 걸리는지도 여기서 증명된다)
            if entry.get("state") in ("sending", "failed"):  # 보내는 중·실패 = 재게시 금지 · 스레드 표식으로만 확인
                found = thread_has(ml, base, tok, dict(entry, key=key))
                if found is True:
                    ledger[key] = dict(entry, state="sent")
                    c.write_json(ledger_path, ledger)
                    acked.append(row.get("seq"))
                    ok += 1
                    print(f"POST recovered {ops_id} ts={ts} — 이미 나간 글을 표식으로 확인하고 원장을 맞췄다")
                    continue
                stuck += 1
                why = "스레드 조회 실패" if found is None else "스레드에 그 표식 없음"
                print(f"ERROR 확인 불가 {ops_id} key={key} · {why} · 재게시 0 · 이 쪽지는 건너뛰고 다음 쪽지로 간다 · "
                      f"사람이 풀려면 {ledger_path} 에서 키 {key} 항목을 지우고 그 쪽지를 다시 보내세요", file=sys.stderr)
                continue
            ledger[key] = {"state": "sending", "channel": ch, "ts": ts, "ops_id": ops_id, "key": key}  # 본문은 원장에 남기지 않는다
            c.write_json(ledger_path, ledger)  # ★기록 먼저★ — 보내는 중에 죽어도 «모르는 게시» 가 안 생긴다
            try:
                post_bounded(base, tok, ch, body_text, ts)
            except BaseException:  # 전체 벽시계 초과·깨진 응답 = sent 0 · 원장 failed(카드 r5)
                ledger[key] = dict(ledger[key], state="failed")
                c.write_json(ledger_path, ledger)
                raise
            ledger[key] = dict(ledger[key], state="sent")
            c.write_json(ledger_path, ledger)
            acked.append(row.get("seq"))
            ok += 1
            sent += 1
            print(f"POST ok {ops_id} ts={ts} tag={tag}")
    except c.IntakeError as e:
        if acked:
            c.mbox_ack(acked)
        print(f"STOP {e}", file=sys.stderr)
        return e.rc
    except Exception as e:  # 슬랙 응답 깨짐·벽시계 초과 — 원장은 «실패» 로 남는다(다음 실행이 스레드 표식으로 확인한다)
        if acked:
            c.mbox_ack(acked)
        print(f"ERROR 게시 응답 불확실({type(e).__name__}) · 원장=failed · 다음 실행이 스레드 표식으로 확인한다", file=sys.stderr)
        return 5
    finally:
        try:
            lock.close()  # 닫으면 flock 해제
        except OSError:
            pass
    if acked:
        c.mbox_ack(acked)
    print(f"POST done n={ok} sent={sent} stuck={stuck}")
    return 5 if stuck else 0


if __name__ == "__main__":
    sys.exit(main())
