# 버린 쪽지의 «유실 표시» — mbox_ops.recv 가 SCANNED 줄 다음에 1줄 · 200줄 규칙 분리(r1651).
"""★ring 포화로 버린 seq 를 «받는 좌석» 에 보인다★ (r1651)

r912/r630 은 버린 «건수» 만 남겼다(dropped=3 oldest_seq=…). 받는 쪽은 무엇이 사라졌는지,
그것이 실보고였는지 영영 몰랐다 — 실측 2026-11-11: h8178·h8172 완료 보고 2통이 그렇게 사라졌다.
⇒ 원장 줄에 버린 seq «전부» 를 적고, 그 좌석의 다음 recv 가 `DROPPED-SEEN n #a,#b` 1줄로 보여준다.
   전문은 mailbox.log.jsonl 에 그대로 있으니 잃은 것은 «알림» 뿐, 되찾는 길은 이 줄이 처음 연다.
   같은 seq 를 두 번 보이지 않는다 — 표식 = mailbox.drops.seen.json 1파일(계보 키 → 마지막 줄 번호).
★DA R2(2026-11-11)★ 표식 읽기·갱신은 «우편함 잠금 안» — 밖에서 읽고-고치면 동시 report 가 서로의 키를
   덮어써 이미 보여준 seq 가 다시 나온다(once 계약 위반). 잠금 재설계 0, claim 의 잠금을 그대로 쓴다.
★DA R1(2026-11-11)★ 은퇴한 옛 좌석은 표시를 «소비하지 않는다» — 소유권은 recv 의 계보 규칙을 그대로 따른다
   (mbox_ops.recv 가 현역일 때만 report 를 부른다).
★r1663★ 표식이 «없을 때» 의 시작점(최근 24시간 창)과 한 줄 길이(최근 10개)에 상한을 둔다 — 설치 직후·
   계보 개명 직후 첫 recv 가 seq 1,893개(수천 자)를 한 줄에 찍던 실사건(planner master #283454)의 보정.
   개명 계보는 recv 가 넘긴 계보 이름(`_replaced_by` 사슬)의 마지막 줄 번호만 «이어받아» 창을 다시 훑지 않는다
   — 같은 줄기의 «동시 현역» 두 좌석은 서로 표식을 잇지 않는다(DA B · #284125).
"""
import json
import os
import sys
import time

from mbox_conf import role_key
from mbox_store import _locked   # ★잠금을 «새로» 만들지 않는다 — claim 이 쓰는 그 우편함 잠금(r1651 DA R2)

DROP_SEEN = "mailbox.drops.seen.json"
SEEN_WINDOW = 24 * 3600   # ★표식이 없을 때★ 보일 원장 줄의 시각 창(초) — r1663
SEEN_MAX = 10             # 한 줄에 싣는 seq 개수 상한 — 나머지는 «앞 N개 생략» — r1663
LINE_MAX = 200            # 그 한 줄 길이 상한(자) — r1663


def report(canon, me, names):
    """★유실 표시 (r1651)★ — 내 계보 앞으로 버려진 seq 를 «다음 recv» 에 1줄. 같은 seq 는 두 번 안 보인다.
    표식 = mailbox.drops.seen.json 한 파일(계보 키 → 마지막으로 본 원장 «줄 번호»).
    ★원장을 «읽기만» 한다★ — 버린 행은 mailbox.log.jsonl 에 남아 있으니 전문은 거기서 되찾는다.
    """
    try:
        with open(os.path.join(canon, "mailbox.drops.log"), encoding="utf-8") as f:
            lines = f.read().splitlines()
    except OSError:
        return ""
    return _locked(canon, lambda: _mark(canon, me, names, lines))


def _num(v):
    try:
        return int(v or 0)
    except (TypeError, ValueError):
        return 0


def _start(seen, key, names):
    """시작 줄 번호 — 내 키 → (없으면) recv 가 넘긴 «계보 이름»(`_replaced_by` 사슬)의 표식. 0 = 표식 없음(창 모드).
    ★줄기(stem) 추론 0★ — 동시 현역 `…-da-astra#0` 와 `…-da-codex#10` 는 서로 표식을 잇지 않는다(DA B · r1663).
    옛 이름의 값을 이어받으면 창을 다시 훑지 않는다 — 이미 소비한 seq 를 다시 보이지 않기 위해서다(r1663 ⓒ)."""
    last = _num(seen.get(key))
    if last:
        return last
    olds = [_num(seen.get(role_key(n))) for n in names if role_key(n) != key]
    return max(olds) if olds else 0


def _now():
    """현재 시각 — 시험 고정용 env FT_MBOX_NOW(epoch 초 또는 ISO) — r1663."""
    raw = os.environ.get("FT_MBOX_NOW")
    if raw:
        try:
            return float(raw)
        except ValueError:
            try:
                return time.mktime(time.strptime(raw, "%Y-%m-%dT%H:%M:%S"))
            except ValueError:
                pass
    return time.time()


def _recent(ln, cut):
    """원장 줄 머리 시각이 창 안인가 — 시각을 못 읽는 줄은 «숨기지 않는다»(근거를 조용히 지우지 않는다)."""
    try:
        return time.mktime(time.strptime(ln.split()[0], "%Y-%m-%dT%H:%M:%S")) >= cut
    except (IndexError, ValueError):
        return True


def _line(seqs):
    """한 줄 꼴 — 최근 SEEN_MAX 개 + 길이 LINE_MAX 자 상한(r1663 ⓑ)."""
    show, omitted = seqs[-SEEN_MAX:], max(0, len(seqs) - SEEN_MAX)
    def fmt():
        if not omitted:
            return "DROPPED-SEEN %d %s — 전문 = mailbox.log.jsonl" % (len(seqs), "#" + ",#".join(show))
        return "DROPPED-SEEN %d 최근 %s (앞 %d개 생략) — 전문 = mailbox.log.jsonl" % (
            len(seqs), "#" + ",#".join(show), omitted)
    while show and len(fmt()) > LINE_MAX:
        show, omitted = show[1:], omitted + 1
    return fmt()


def _mark(canon, me, names, lines):
    """표식 읽기·갱신 — ★반드시 우편함 잠금 안에서 부른다★(r1651 DA R2). 보여줄 seq 가 없으면 파일을 안 건드린다."""
    state = os.path.join(canon, DROP_SEEN)
    try:
        with open(state, encoding="utf-8") as f:
            seen = json.load(f)
        seen = seen if isinstance(seen, dict) else {}
    except (OSError, ValueError):
        seen = {}
    key = role_key(me)
    mine, last = {role_key(n) for n in names}, _start(seen, key, names)
    cut = None if last else _now() - SEEN_WINDOW   # ★표식이 없을 때만★ 시각 창 — r1663 ⓐ
    seqs, upto = [], last
    for i, ln in enumerate(lines, 1):
        if i <= last:
            continue
        kv = dict(p.split("=", 1) for p in ln.split() if "=" in p)
        if role_key(kv.get("to", "")) not in mine:
            continue
        if cut is not None and not _recent(ln, cut):
            continue
        upto = i
        seqs.extend(s for s in (kv.get("seqs") or kv.get("oldest_seq") or "").split(",") if s)
    if not seqs:
        return ""
    try:
        seen[key] = len(lines) if cut is not None else upto   # 창 모드 = 원장 «끝» 줄 번호(r1663 ⓐ)
        tmp = "%s.%d.tmp" % (state, os.getpid())   # 고정 .tmp 이름 = 동시 갱신이 서로의 파일을 덮는다
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(seen, f)
        os.replace(tmp, state)
    except OSError:
        pass
    return _line(seqs)


def log_drop(canon, to, dropped, oldest, seqs=()):
    """★버림 원장 (r630 · seq 전부 r1651)★ — stderr DROPPED 는 보낸 쪽 화면에만 남았다. 본문 0 · 1줄.
    r1651: 버린 seq 를 «전부» 적는다(`seqs=a,b`) — 받는 좌석의 다음 recv 가 DROPPED-SEEN 1줄로 보여준다.
    기록 실패로 send 를 실패시키지 않는다(이미 큐에 들어갔다) — 대신 stderr ERROR 1줄."""
    try:
        with open(os.path.join(canon, "mailbox.drops.log"), "a", encoding="utf-8") as f:
            f.write("%s to=%s dropped=%d oldest_seq=%s seqs=%s\n" % (
                time.strftime("%Y-%m-%dT%H:%M:%S"), to, dropped, oldest, ",".join(str(s) for s in seqs)))
    except OSError as e:
        sys.stderr.write("ERROR mailbox.drops.log 기록 실패: %s\n" % e)
