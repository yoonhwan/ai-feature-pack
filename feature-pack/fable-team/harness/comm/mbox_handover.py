# mbox.py 의 승계 마무리(r1116 ②③④ · 오빠 «구세션과 신세션이 통신해 레디되고 메세지 유실없고 구세션 마지막 작업을 정상 이관»).
#   ③ recv 가 가져간 쪽지마다 영수 1줄(receipts/<세션>.jsonl) · seq 마다 «처리함|인계» 표시 · 미표시 1개라도 있으면 retire·닫기 거절(close-check)
#   ④ handover = 남은 쪽지 끝까지 recv + 미표시 쪽지·실행 중 h·백그라운드 명령을 기계가 [인계] 에 붙인다 · ready = 항목마다 «<id> 받음»
#   ② 후계가 있는 옛 세션 닫기 = 마지막 [인계] 뒤 후계 [레디] 가 항목 전부 «받음» 일 때만. CANON 은 mbox.py 가 묶는다 · 200줄 규칙 분리.
from mbox_conf import *
import subprocess
import mbox_lineage
CANON = None   # mbox.py 가 묶는다
ITEM = re.compile(r"^- (#\d+|h\d+|bg:[\w.-]+) ", re.M)   # [인계] 항목 줄 = «- <id> …» · [레디] 는 «<id> 받음»
HEAD_N = re.compile(r"^\[인계\] \S+ -> \S+ · 항목 (\d+) ")   # handover 가 쓰는 머리 — 항목 수가 «- <id>» 줄 수와 같아야 기계 [인계]
ASK_HEADS = ("[HIL]", "[결정]", "[질문]", "[긴급]")
IGNORE_BG = re.compile(r"(^|/)(claude|codex|node|pi|opencode|caffeinate|tmux|login|-?zsh|-?bash)( |$)|lsp|language-server|mcp|serena|pyright")


def _rfile(me):
    return os.path.join(CANON, "receipts", me + ".jsonl")


def _rows(me):
    try:
        with open(_rfile(me), encoding="utf-8") as f:
            return [json.loads(l) for l in f if l.strip()]
    except FileNotFoundError:
        return []


def _append(me, rows):   # 영수·표시는 추가 전용 — 못 쓰면 raise(recv 는 잠금 안에서 불러 큐를 안 지운다 · 조용한 유실 0)
    os.makedirs(os.path.dirname(_rfile(me)), exist_ok=True)
    with open(_rfile(me), "a", encoding="utf-8") as f:
        for r in rows:
            f.write(json.dumps(r, ensure_ascii=False) + "\n")


def record(me, rows):   # [레디] 는 받는 순간 «처리함»(r1116b ③ — 핸드셰이크 회신 자체가 구세션 미표시로 잡혀 close-check 가 막던 자리)
    now = time.strftime("%Y-%m-%dT%H:%M:%S")
    out = []
    for r in rows:
        out.append({"seq": r["seq"], "from": r.get("from", ""), "ts": now, "body": r.get("body", "")[:300], "body_full": r.get("body_full", "")})
        if _head(r.get("body")) == "[레디]":
            out.append({"seq": r["seq"], "mark": "처리함", "ts": now, "auto": "[레디]"})
    _append(me, out)


def mark(me, seqs, kind):
    if kind not in ("처리함", "인계"):
        sys.exit("usage: mark <me> <seq,…> 처리함|인계")
    got = {r["seq"] for r in _rows(me) if "mark" not in r}
    want = [int(x) for x in re.findall(r"\d+", seqs)]
    miss = [s for s in want if s not in got]
    if miss:
        sys.stderr.write("REJECT 영수 없는 seq %s — 내가 recv 한 쪽지만 표시한다\n" % ",".join(map(str, miss))); sys.exit(3)
    _append(me, [{"seq": s, "mark": kind, "ts": time.strftime("%Y-%m-%dT%H:%M:%S")} for s in want])
    print("MARKED %s %s %s" % (me, kind, ",".join(map(str, want)) or "0"))


def unmarked(me):   # 받았는데 «처리함|인계» 표시가 없는 영수 행
    rows = _rows(me)
    done = {r["seq"] for r in rows if "mark" in r}
    return [r for r in rows if "mark" not in r and r["seq"] not in done]


def _sent():   # 보낸 행 사본(회전본 .1 포함 · 오래된 것 먼저)
    out = []
    for p in (os.path.join(CANON, SENT_LOG) + ".1", os.path.join(CANON, SENT_LOG)):
        try:
            with open(p, encoding="utf-8") as f:
                for l in f:
                    try: out.append(json.loads(l))
                    except ValueError: pass
        except FileNotFoundError:
            pass
    return sorted(out, key=lambda r: r.get("seq", 0))


def _head(body):
    m = re.match(r"\s*(\[[^\]]*\])", body or ""); return m.group(1) if m else ""


def _h_items():   # 실행 중·미실행 h — ft-hil.sh --pending --each(«h<N> <분>») · 도구 없음 = 칸 생략 · 실패 = 판정 불가(raise)
    hil = os.environ.get("FT_HIL_BIN") or os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "bin", "ft-hil.sh")
    if not os.path.isfile(hil):
        return [], "h 목록 확인 불가(ft-hil.sh 없음 %s)" % hil
    r = subprocess.run(["bash", hil, "--pending", "--each"], capture_output=True, text=True, timeout=7)   # 옵션 꼴(r1116b · 하위 명령 꼴 = usage rc 2)
    if r.returncode not in (0, 1):
        raise RuntimeError("ft-hil.sh pending rc=%d %s" % (r.returncode, r.stderr.strip()[:80]))
    return ["- %s 실행 전·실행 중 %s분" % tuple((ln.split() + ["?"])[:2]) for ln in r.stdout.splitlines() if re.match(r"h\d+ ", ln)], ""


def _bg_items(old):   # 옛 세션 pane 아래 백그라운드 명령(에이전트·LSP·MCP 제외) · tmux 세션 없음 = 0 · ps 실패 = 판정 불가(raise)
    t = subprocess.run(["tmux", "list-panes", "-t", "=" + old, "-F", "#{pane_pid}"], capture_output=True, text=True, timeout=7)
    roots = [p for p in t.stdout.split() if p.isdigit()] if t.returncode == 0 else []
    if not roots:
        return []
    ps = subprocess.run(["ps", "-A", "-o", "pid=,ppid=,args="], capture_output=True, text=True, timeout=7)
    if ps.returncode != 0:
        raise RuntimeError("ps rc=%d" % ps.returncode)
    kids, args = {}, {}
    for ln in ps.stdout.splitlines():
        a = ln.split(None, 2)
        if len(a) >= 2 and a[0].isdigit():
            kids.setdefault(a[1], []).append(a[0]); args[a[0]] = a[2] if len(a) > 2 else ""
    out, todo = [], list(roots)
    while todo:
        p = todo.pop(0)
        for c in kids.get(p, []):
            todo.append(c)
            if not IGNORE_BG.search(args[c].split(" ")[0]) and not IGNORE_BG.search(args[c][:80]):
                out.append("- bg:%s %s" % (c, args[c][:80]))
    return out


def handover_body(old, new, extra=()):
    """[인계] 본문 — 남은 쪽지 끝까지 recv(현역일 때) → 미표시 영수 전부 · h · bg · 손 항목(--bg «설명»). 표시(인계)는 send 성공 뒤 mbox.sh 가 한다."""
    if not mbox_lineage.retired_to(old):
        names, _ = mbox_lineage.eligible(old)
        mbox_lineage.claim([CANON], names, None, None, me=old, on_take=lambda rows: record(old, rows))
    asks, rest = [], []
    for r in unmarked(old):
        ln = "- #%s [%s] %s (전문: %s)" % (r["seq"], r["from"], re.sub(r"\s+", " ", r["body"])[:100],
                                         r.get("body_full") or "mailbox.log.jsonl seq %s" % r["seq"])
        (asks if r["from"] == "slack-oppa" or _head(r["body"]) in ASK_HEADS else rest).append(ln)
    hs, note = _h_items()
    bg = _bg_items(old) + ["- bg:x%d %s" % (i + 1, e) for i, e in enumerate(extra)]
    n = len(asks) + len(rest) + len(hs) + len(bg)
    parts = ["[인계] %s -> %s · 항목 %d · [레디] 는 항목마다 «<id> 받음»(bash mbox.sh ready %s %s)" % (old, new, n, new, old)]
    for title, xs in (("답 안 한 오빠 질문", asks), ("남은 회신·쪽지", rest), ("실행 중 h", hs), ("백그라운드 명령", bg)):
        parts.append("%s: %s" % (title, len(xs) or "0")); parts += xs
    if note: parts.append(note)
    return "\n".join(parts)


def last_handover(old):
    hs = [r for r in _sent() if r.get("from") == old and _head(r.get("body")) == "[인계]"]
    return hs[-1] if hs else None


def items(h):
    """[인계] 항목 id 목록 · 형식 불명이면 None(r1116b ④) — 손으로 문장처럼 쓴 [인계] 는 «- #N» 줄이 없어 항목 0 으로 «전부 받음» 이 되던 자리.
    문장 속 «#숫자» 를 항목으로 세지 않는다: PR·Issue 번호와 구분이 안 돼 거짓 항목이 생긴다 → 머리 «항목 N» 과 줄 수가 다르면 거절이 더 단순하다."""
    body = h.get("body", "")
    m, ids = HEAD_N.match(body), ITEM.findall(body)
    return ids if m and int(m.group(1)) == len(ids) else None


def ready_body(new, old):
    h = last_handover(old)
    if not h:
        sys.stderr.write("REJECT %s 의 [인계] 없음 — 구세션이 bash mbox.sh handover %s %s 먼저\n" % (old, old, new)); sys.exit(3)
    if h["seq"] not in {r["seq"] for r in _rows(new)}:
        sys.stderr.write("REJECT [인계] #%s 를 %s 가 아직 recv 안 함 — recv 먼저\n" % (h["seq"], new)); sys.exit(3)
    ids = items(h)
    if ids is None:
        sys.stderr.write("REJECT [인계] #%s 형식 불명(기계 머리 «항목 N» 과 «- <id>» 줄 수 불일치) — 구세션이 bash mbox.sh handover %s %s 로 다시\n" % (h["seq"], old, new)); sys.exit(3)
    return "\n".join(["[레디] %s <- %s · [인계] #%s 받음 · 항목 %d" % (new, old, h["seq"], len(ids))] + ["%s 받음" % i for i in ids])


def close_check(seat, need_ready=True):
    """rc 0 = 닫아도 됨 · 3 = 거절(사유 줄) — ③ 미표시 영수 · ② 후계가 있으면 [인계] 뒤 후계 [레디] 가 항목 전부 «받음».
    need_ready=False(retire 관문) = ③ 만 · True(닫기 관문) = 후계 있는 옛 세션만 ③+② — 후계 없는 닫기(나노·판정 닫기)는 승계 검사 대상 아님."""
    succ = mbox_lineage.retired_to(seat)
    if need_ready and not succ:
        print("CLOSE-OK %s 후계 없음(승계 검사 대상 아님)" % seat); return 0
    bad = unmarked(seat)
    if bad:
        print("REJECT %s 미표시 쪽지 %d (#%s) — bash mbox.sh mark %s <seq> 처리함|인계 또는 handover" % (
            seat, len(bad), ",#".join(str(r["seq"]) for r in bad[:10]), seat)); return 3
    if not need_ready:
        print("CLOSE-OK %s 미표시 0" % seat); return 0
    h = last_handover(seat)
    if not h:
        print("REJECT %s [인계] 없음 — bash mbox.sh handover %s %s" % (seat, seat, succ)); return 3
    ids = items(h)
    if ids is None:
        print("REJECT %s [인계] #%s 형식 불명(손으로 쓴 [인계]) — bash mbox.sh handover %s %s 로 다시" % (seat, h["seq"], seat, succ)); return 3
    for r in reversed(_sent()):
        if r.get("seq", 0) > h["seq"] and _head(r.get("body")) == "[레디]" and r.get("from") != seat \
                and role_key(r.get("from")) == role_key(seat) and "#%s 받음" % h["seq"] in r.get("body", ""):
            miss = [i for i in ids if "%s 받음" % i not in r["body"]]
            if miss:
                print("REJECT %s [레디] #%s 에 «받음» 없는 항목 %s" % (seat, r["seq"], ",".join(miss))); return 3
            print("CLOSE-OK %s [인계] #%s → [레디] #%s 항목 %d 전부 받음" % (seat, h["seq"], r["seq"], len(ids))); return 0
    print("REJECT %s [인계] #%s 뒤 후계 [레디] 없음(회신 0 = 안 닫음)" % (seat, h["seq"])); return 3
