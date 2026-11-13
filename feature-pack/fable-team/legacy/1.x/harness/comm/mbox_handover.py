# mbox.py 의 승계 마무리(r1116 ②③④ · 오빠 «구세션과 신세션이 통신해 레디되고 메세지 유실없고 구세션 마지막 작업을 정상 이관»).
#   ③ recv 가 가져간 쪽지마다 영수 1줄(receipts/<세션>.jsonl) · seq 마다 «처리함|인계» 표시 · 미표시 1개라도 있으면 retire·닫기 거절(close-check)
#   ④ handover = 남은 쪽지 끝까지 recv + 미표시 쪽지·실행 중 h·백그라운드 명령을 기계가 [인계] 에 붙인다 · ready = 항목마다 «<id> 받음»
#   ② 후계가 있는 옛 세션 닫기 = 마지막 [인계] 뒤 후계 [레디] 가 항목 전부 «받음» 일 때만. CANON 은 mbox.py 가 묶는다 · 200줄 규칙 분리.
from mbox_conf import *
import subprocess
import mbox_lineage
import mbox_retire_check   # r1319 승계 retire 관문(C0~C2·C7) — 이 파일 182줄·200줄 규칙, 검사 함수는 그 모듈에
CANON = None   # mbox.py 가 묶는다
ITEM = re.compile(r"^- (#\d+|h\d+|bg:[\w.-]+) (\[억제 doorbell\] 미전달분 )?", re.M)   # 옛 꼴·손 항목 줄 = «- <id> …» · [레디] 는 «<id> 받음»
IDS = re.compile(r"^항목:(.*)$", re.M)   # r1863 새 꼴 = «항목: #a #b! h1 bg:9»(«!» = 억제 doorbell · mark 제외)
ID = re.compile(r"#\d+!?|h\d+|bg:[\w.-]+")
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


def _successor_open_seq(old):
    """r1692 — 옛 좌석의 «후계 개설 쪽지» seq(도달 파일 <state>/successor/<옛>.json · state = FT_MBOX_STATE_DIR › CANON/../state).
    그 쪽지는 머리가 [인계] 라 묶음에 세어지지만 항목 머리가 없어 ready·close 가 «형식 불명» 으로 영구 막힌다(#285416·#285446) · 없음·깨짐 = None(뺄 것 0)."""
    if not old or "/" in old or old in (".", ".."):
        return None
    sd = os.environ.get("FT_MBOX_STATE_DIR") or os.path.join(CANON, "..", "state")
    try:
        with open(os.path.join(sd, "successor", old + ".json"), encoding="utf-8") as f:
            seq = json.load(f).get("seq")
    except (OSError, ValueError, AttributeError):
        return None
    return seq if isinstance(seq, int) else None


def _handovers(old, new):   # 옛→후계 기계 [인계] 전부(보낸 순) — r1692: 개설 쪽지(도달 파일이 가리키는 seq) 1통은 묶음 밖
    skip = _successor_open_seq(old)
    return [r for r in _sent() if r.get("from") == old and r.get("to") == new
            and _head(r.get("body")) == "[인계]" and r.get("seq") != skip]


def _readies(new, old, after=0):   # 후계→옛 [레디] 중 seq > after(보낸 순)
    return [r for r in _sent() if r.get("seq", 0) > after and r.get("from") == new
            and r.get("to") == old and _head(r.get("body")) == "[레디]"]


def handover_group(old, new):
    """r1653 — [인계] 묶음 = 아직 «받음» 이 없는 통들(항목 단위 완료 확인) · 다 받았으면 마지막 1통(다시 ready 해도 항목 0 이 아니다).
    마지막 1통만 보면 앞 통 항목이 확인 없이 통과하고(#282965 104 항목 · #283071), seq 로 자르면 옛 꼴 [레디] 뒤 새 [레디] 가 앞 통을 덮어
    미받음이 누락된다(DA R1-a). 한 통이라도 항목이 남아 있으면 합집합에 남긴다 — 이미 받은 항목을 두 번 받으라 하지 않는다(DA R1-b)."""
    hs = _handovers(old, new)
    if not hs:
        return []
    pend = []
    for h in hs:
        got = "\n".join(r.get("body", "") for r in _readies(new, old, h.get("seq", 0)))
        ids = items(h)
        if ids is None or any(("%s 받음" % i) not in got for i in ids):
            pend.append(h)
    return pend or hs[-1:]


def group_items(gs):   # 묶음 항목 id 합집합(처음 나온 순서 · 중복 1번) · 형식 불명 1통이라도 있으면 None
    return None if any(items(h) is None for h in gs) else list(dict.fromkeys(i for h in gs for i in items(h)))


def _raw_ids(h):   # r1863 — 항목 id 원형(억제 «!» 보존) · 새 꼴 «항목:» 줄 + 옛 꼴·손 항목 «- <id>» 줄(옛 억제 줄 = #N!)
    b = h.get("body", "")
    return [t for ln in IDS.findall(b) for t in ln.split()] + [m.group(1) + ("!" if m.group(2) else "") for m in ITEM.finditer(b)]


def _resent(old, new):   # r1653 ⓒ·r1863 — 앞 [인계] 로 넘겼지만 뒤 [레디] 에 «받음» 이 아직 없는 쪽지 id(id 로 재구성 · «!» 유지)
    out = []
    for h in _handovers(old, new):
        got = "\n".join(r.get("body", "") for r in _readies(new, old, h.get("seq", 0)))
        out += [i for i in (_raw_ids(h) if items(h) is not None else []) if i[0] == "#" and "%s 받음" % i.rstrip("!") not in got and i not in out]
    return out


def handover_body(old, new, extra=()):
    """[인계] 본문 — 남은 쪽지 끝까지 recv(현역일 때) → 미표시 영수 전부 · h · bg · 손 항목(--bg «설명»). 표시(인계)는 send 성공 뒤 mbox.sh 가 한다."""
    if not mbox_lineage.retired_to(old):
        names, _ = mbox_lineage.eligible(old)
        mbox_lineage.claim([CANON], names, None, None, me=old, on_take=lambda rows: record(old, rows))
    asks, ids = [], []   # r1863 — 항목마다 100자 요약 줄 대신 id 묶음 1줄(전문 = mailbox.log.jsonl seq)
    for r in unmarked(old):
        (asks if r["from"] == "slack-oppa" or _head(r["body"]) in ASK_HEADS else ids).append("#%s" % r["seq"])
    # ★r1665 ⓐ — 억제 doorbell 은 항목으로 넘겨 후계 [레디] 가 닫게 한다 · «#N!» 꼴은 mbox.sh handover 갈래의 mark 제외 sed 와 한 쌍★
    for i in _resent(old, new) + ["#%s!" % s for s in _held_seqs(old) if re.fullmatch(r"\d+", s)]:
        ids += [] if i.rstrip("!") in {x.rstrip("!") for x in asks + ids} else [i]   # r1653 ⓒ 미받음 재적재 · 같은 seq 1번
    hs, note = _h_items()
    hs, bg, hand = [x.split()[1] for x in hs], [x.split()[1] for x in _bg_items(old)], ["- bg:x%d %s" % (i + 1, e) for i, e in enumerate(extra)]
    held = sum(i.endswith("!") for i in ids)
    parts = ["[인계] %s -> %s · 항목 %d · [레디] 는 항목마다 «<id> 받음»(bash mbox.sh ready %s %s)" % (old, new, len(asks + ids + hs + bg + hand), new, old),
             "수: 답 안 한 오빠 질문 %d · 남은 회신·쪽지 %d · 억제 doorbell %d · 실행 중 h %d · 백그라운드 %d" % (len(asks), len(ids) - held, held, len(hs), len(bg + hand)),
             "전문: mailbox.log.jsonl seq 로 · 오빠 질문 먼저 = %s" % (" ".join(asks) or "0"), "항목:" + "".join(" " + i for i in asks + ids + hs + bg)]
    return "\n".join(parts + hand + ([note] if note else []))


def last_handover(old, new):
    hs = [r for r in _sent() if r.get("from") == old and r.get("to") == new and _head(r.get("body")) == "[인계]"]
    return hs[-1] if hs else None


def items(h):
    """[인계] 항목 id 목록 · 형식 불명이면 None(r1116b ④) — 손으로 문장처럼 쓴 [인계] 는 «- #N» 줄이 없어 항목 0 으로 «전부 받음» 이 되던 자리.
    문장 속 «#숫자» 를 항목으로 세지 않는다: PR·Issue 번호와 구분이 안 돼 거짓 항목이 생긴다 → 머리 «항목 N» 과 줄 수가 다르면 거절이 더 단순하다."""
    m, ids = HEAD_N.match(h.get("body", "")), _raw_ids(h)   # r1863 — 새 꼴 «항목:» 줄 + 옛 꼴 «- <id>» 줄 · 안내 줄 id 는 안 센다 · «!» 는 #seq 로
    return [i.rstrip("!") for i in ids] if m and int(m.group(1)) == len(ids) and all(ID.fullmatch(i) for i in ids) else None


def _gate(g, out=sys.stderr):   # r1319 — (rc, 문구) 관문 결과를 그대로 내고 끝낸다(0 통과)
    if g:
        out.write(g[1] + "\n"); sys.exit(g[0])


def ready_body(new, old):
    gs = handover_group(old, new)
    if not gs:
        sys.stderr.write("REJECT %s 의 [인계] 없음 — 구세션이 bash mbox.sh handover %s %s 먼저\n" % (old, old, new)); sys.exit(3)
    miss = [h["seq"] for h in gs if h["seq"] not in {r["seq"] for r in _rows(new)}]
    if miss:
        sys.stderr.write("REJECT [인계] #%s 를 %s 가 아직 recv 안 함 — recv 먼저\n" % (miss[0], new)); sys.exit(3)
    _gate(mbox_retire_check.ready_gate(new, old, mbox_retire_check.handover_target(gs[-1])), sys.stderr)   # C1 retire 먼저 · C2 남은 `_*` 칸
    ids = group_items(gs)   # r1653 ⓐ — 묶음 항목 합집합(머리 = #a,#b)
    if ids is None:
        sys.stderr.write("REJECT [인계] #%s 형식 불명(기계 머리 «항목 N» 과 «- <id>» 줄 수 불일치) — 구세션이 bash mbox.sh handover %s %s 로 다시\n" % (next(h["seq"] for h in gs if items(h) is None), old, new)); sys.exit(3)
    return "\n".join(["[레디] %s <- %s · [인계] #%s 받음 · 항목 %d" % (new, old, ",".join(str(h["seq"]) for h in gs), len(ids))] + ["%s 받음" % i for i in ids])


def _held_file(seat):
    """r1476 — 억제된 doorbell 기록 자리(state/doorbell-held/<좌석>). state 는 우편함 옆(FT_MBOX_STATE_DIR 이 이긴다 · 시험 격리)."""
    sd = os.environ.get("FT_MBOX_STATE_DIR") or os.path.join(CANON, "..", "state")
    return os.path.join(sd, "doorbell-held", re.sub(r"[^A-Za-z0-9._#-]", "_", seat))


def _held_seqs(seat):
    """r1665 — 억제된 doorbell 의 seq 목록(첫 줄 `held …` 그 뒤 `seq=<N>` · mbox_wakegate.sh 와 같은 꼴) · 파일 없음 = []"""
    try:
        with open(_held_file(seat), encoding="utf-8") as f:
            return [l.strip()[4:] for l in f if l.startswith("seq=")]
    except OSError:
        return []


def _open_work(seat):   # r1539 — 받을 일 0 이면 False · 있으면 True · 판정 불가 = None(지금처럼 [인계] 요구)
    tool = os.environ.get("FT_SEAT_OPEN_WORK") or os.path.join(
        os.path.dirname(os.path.abspath(__file__)), "..", "bin", "ft-seat-open-work.py")
    root = os.path.dirname(os.path.dirname(os.path.abspath(CANON))) if CANON else ""
    if not root or not os.path.isfile(tool):
        return None   # 도구·루트 없음 = 설치 환경 문제 — 지금처럼 [인계] 요구(닫기 계약에 새 출력 0)
    try:
        p = subprocess.run([sys.executable, tool, seat, "--root", root],
                           capture_output=True, text=True, timeout=20)
    except (OSError, subprocess.SubprocessError) as e:
        sys.stderr.write("받을 일 판정 불가 도구 실행 실패 %s — 지금처럼 [인계] 요구\n" % type(e).__name__); return None
    if p.returncode == 0: return False
    if p.returncode == 1: return True
    sys.stderr.write((p.stderr.strip().splitlines() or ["받을 일 판정 불가 — 지금처럼 [인계] 요구"])[0] + "\n"); return None


def close_check(seat, need_ready=True, verdict=False):
    """rc 0 = 닫아도 됨 · 3 = 거절(사유 줄) — ③ 미표시 영수 · ② 후계가 있으면 [인계] 뒤 후계 [레디] 가 항목 전부 «받음».
    need_ready=False(retire 관문) = ③ 만 · True(닫기 관문) = 후계 있는 옛 세션만 ③+② — 후계 없는 닫기(나노·판정 닫기)는 승계 검사 대상 아님.
    verdict=True(--verdict · 사람 판정 1건) = 후계가 있으면 ②③ 면제 — 판정 번호의 원장 실재는 ft-seat-close.sh 가 본다(r1481)."""
    # ★r1476 — 억제된 doorbell 이 남은 채 닫으면 그 쪽지는 영영 안 깨운다★ (닫는 사건 = 후속 doorbell 뒤 파일 삭제).
    hs = _held_seqs(seat)
    if hs or os.path.exists(_held_file(seat)):
        nxt = (mbox_lineage.chain(seat) or [mbox_lineage.retired_to(seat) or "<후계>"])[0]   # r1665 ⓓ — 막았으면 후계가 칠 명령을 다음 줄에 준다
        print("REJECT %s 억제된 doorbell %d건 미전달(seq %s) — recv 먼저" % (
            seat, len(hs), ",#".join(hs[:10]) or "?"))
        print("다음(후계 pane): bash mbox.sh recv '%s' → bash mbox.sh handover '%s' '%s' → bash ft-seat-retire.sh '%s' '%s'" % (nxt, seat, nxt, seat, nxt))
        return 3
    chain = mbox_lineage.chain(seat)   # r1600 — 직계 후계부터 사슬 끝까지(여러 번 승계된 좌석)
    succ = chain[-1] if chain else mbox_lineage.retired_to(seat)
    if succ and verdict:   # r1481 — R400 사람 판정 1건이면 승계 검사(②③)를 건너뛴다(은퇴 뒤 ready REJECT 로 닫을 길이 0 이던 자리)
        print("CLOSE-OK %s 판정 닫기(②③ 면제 · 사람 판정 1건)" % seat); return 0
    if need_ready and not succ:
        g = None if verdict else mbox_retire_check.close_gate(seat)   # C7 [인계] 는 보냈는데 retire 0 — 면제 = --verdict(사람 판정)
        if g:
            print(g[1]); return g[0]
        print("CLOSE-OK %s 후계 없음(승계 검사 대상 아님)" % seat); return 0
    bad = unmarked(seat)
    if bad:
        print("REJECT %s 미표시 쪽지 %d (#%s) — bash mbox.sh mark %s <seq> 처리함|인계 또는 handover" % (
            seat, len(bad), ",#".join(str(r["seq"]) for r in bad[:10]), seat)); return 3
    if not need_ready:
        print("CLOSE-OK %s 미표시 0" % seat); return 0
    if _open_work(seat) is False:   # r1539 — 받을 일 0 이면 [인계] 요구 면제(승계 0 = 인계할 것이 없다) · 있음·판정 불가 = 지금처럼 REJECT
        print("CLOSE-OK %s 받을 일 0 · [인계] 면제" % seat); return 0
    near, succ = chain or [succ], (chain or [succ])[0]   # 안내 줄·[레디] 대상 = «직계» 후계(r1600 ⓑ)
    gs = []
    for n in near:   # 직계부터 기계 [인계] 를 가진 후계를 고른다(사슬 끝만 보면 다 마친 좌석이 막힌다)
        gs = handover_group(seat, n)
        if gs: succ = n; break
    if not gs:
        print("REJECT %s [인계] 없음 — bash mbox.sh handover %s %s" % (seat, seat, succ)); return 3
    seqs, after = ",".join(str(h["seq"]) for h in gs), min(h.get("seq", 0) for h in gs)
    ids = group_items(gs)   # r1653 ⓑ — 묶음 합집합 항목이 묶음 뒤 [레디] 들의 «받음» 합집합에 전부 있어야
    if ids is None:
        print("REJECT %s [인계] #%s 형식 불명(손으로 쓴 [인계]) — bash mbox.sh handover %s %s 로 다시" % (seat, seqs, seat, succ)); return 3
    hit = [r for r in _sent() if r.get("seq", 0) > after and _head(r.get("body")) == "[레디]" and r.get("from") != seat
           and r.get("from") == succ and r.get("to") == seat]   # r1493 후계 = 명부 사슬 끝 «정확 일치»(개명 승계도 닫힌다 · 같은 역할 키 비후계 [레디] 는 안 센다)
    if not hit:
        print("REJECT %s [인계] #%s 뒤 후계 [레디] 없음(회신 0 = 안 닫음) — 후계가 bash mbox.sh ready %s %s (pane 입력은 세지 않음)" % (seat, seqs, succ, seat)); return 3
    got = "\n".join(r.get("body", "") for r in hit)
    miss = [i for i in ids if "%s 받음" % i not in got]
    if miss:
        print("REJECT %s [레디] #%s 에 «받음» 없는 항목 %s" % (seat, hit[-1]["seq"], ",".join(miss))); return 3
    print("CLOSE-OK %s [인계] #%s → [레디] #%s 항목 %d 전부 받음" % (seat, seqs, hit[-1]["seq"], len(ids))); return 0
