#!/usr/bin/env python3
"""파일 기반 세션 메시지 큐 (fable-team). LIFO·per-to ring·fcntl.flock·consume-on-read·to==me grep.
v6-realtime-live mbox.py 계승 + 팩 추가분: FT_MBOX_DIR 경로 주입·세션명 allowlist·READ 출력·from 필터.

★2026-08-25 — 우편함이 «셋으로 갈라져» 메시지가 유실되던 것을 고친다★
이전: 데이터 경로가 «cwd 기준»이라, 같은 스크립트를 불러도 부른 사람의 cwd 에 따라 다른
우편함을 썼다 — 보낸 쪽과 받는 쪽이 서로 다른 파일을 보는 사고가 실제로 났다.
지금: ★send 는 «정본» 하나에만 쓰고, recv/peek 는 «정본+레거시»를 전부 읽는다(union)★.
union 을 두는 이유 — 경로를 «순간에» 바꾸면 바꾸기 직전 큐잉된 메시지가 옛 파일에 남아
★아무도 안 읽는다★. 레거시가 전부 0행이 되면 그때 걷어낸다(그 판단은 별도).
"""
import sys, os, re, json, time, fcntl, hashlib, shutil, glob

MAX_PER_TO = int(os.environ.get("FT_MBOX_RING") or 10)
# 세션명 allowlist — 세션명이 doorbell 명령 문자열에 삽입되므로 하드 거부(명령 삽입 원천 차단).
NAME_RE = re.compile(r'^[A-Za-z0-9._#-]+$')

# ── 발신 규율 물리 가드 (COMM-GUIDE §1.5) ──────────────────────────────
# 홍수는 사용자 입력을 막고, ring(MAX_PER_TO) 상한을 넘긴 메시지를 조용히 유실시킨다.
MAX_BODY = int(os.environ.get("FT_MBOX_MAX_BODY") or 700)        # 본문 문자 상한(3~5줄)
FANOUT_WIN = int(os.environ.get("FT_MBOX_FANOUT_WINDOW") or 600)  # 동일 본문 다중 좌석 판정 창(초)
RATE_N = int(os.environ.get("FT_MBOX_RATE_N") or 5)               # from당 발신 건수
RATE_WIN = int(os.environ.get("FT_MBOX_RATE_WINDOW") or 60)       # 그 창(초)
# ★2026-09-02 재발신 쿨다운★ — 큐잉은 «가져가기» 방식이므로 pending 동안 재발신 금지.
# N초 경과 후 1회 허용(재발신이 기록을 갱신하므로 자연히 «1회씩»). 그 전엔 pane 캡처로 확인.
RESEND_COOL = int(os.environ.get("FT_MBOX_RESEND_COOLDOWN") or 300)
RECV_LIMIT = int(os.environ.get("FT_MBOX_RECV_LIMIT") or 5)       # recv 기본 표시 건수
RELAY_DIR = os.environ.get("FT_MBOX_RELAY_DIR") or "/tmp/mbox"    # 긴 본문의 정본 자리


def _repo_root(start):
    """★정본 자리를 «유도»한다 — 하드코딩 금지★.

    이 파일 위쪽의 `.fable-team` 을 찾고, 그 부모가 `.worktrees/<x>` 면 리포 루트는 두 단계
    위다. ★워크트리 «안»이 아니라 «밖»을 정본으로 잡는 이유★: 워크트리는 정리되면 사라지고,
    그날 그 안의 우편함을 쓰던 세션이 전부 끊긴다.
    """
    d = os.path.abspath(start)
    while d != os.path.dirname(d):
        if os.path.basename(d) == ".fable-team":
            parent = os.path.dirname(d)
            # ★워크트리 이름이 «한 단계»라는 보장이 없다★ (2026-09-03 실측)
            #   브랜치명에 슬래시가 있으면 `.worktrees/feat/loom-pack-layer` 처럼 두 단계가
            #   된다(BYZ 에 실존). 조부모만 보고 판정하면 그 경우 `.worktrees` 를 못 만나
            #   ★자기 워크트리 «안»을 정본으로 잡아 조용히 별도 우편함을 판다★ — 에러가
            #   안 나고 send/recv 는 성공하므로, 그 좌석만 아무에게도 안 닿는다.
            #   그래서 깊이를 가정하지 않고 «`.worktrees` 조상을 만날 때까지» 올라간다.
            a = parent
            while a != os.path.dirname(a):
                if os.path.basename(a) == ".worktrees":
                    return os.path.dirname(a)
                a = os.path.dirname(a)
            return parent
        d = os.path.dirname(d)
    return None  # ★F4: .fable-team 조상이 없으면 정본을 «유도할 수 없다» — 조용히 만들지 않는다.


_ROOT = _repo_root(os.path.dirname(os.path.abspath(__file__)))
# ★명시가 추론을 이긴다★ — env 로 준 FT_MBOX_DIR 은 그대로 존중한다(이전엔 래퍼가 덮어썼다).
# ★F4: env 도 조상도 없으면 fail-loud — 스크립트 디렉토리 «안»에 우편함을 만들지 않는다.
CANON = os.environ.get("FT_MBOX_DIR") or (os.path.join(_ROOT, ".fable-team", "comm") if _ROOT else None)
if not CANON:
    sys.stderr.write("NO_MAILBOX_ROOT: .fable-team 조상 없음 — FT_MBOX_DIR 를 지정하라\n")
    sys.exit(2)
os.makedirs(CANON, exist_ok=True)


def _legacy_dirs():
    """레거시 우편함 — ★손으로 나열하지 않고 워크트리 목록에서 «유도»한다★.

    손으로 쓴 목록은 다음에 생기는 워크트리를 못 잡는다.
    """
    if not _ROOT:  # ★F4: 루트를 못 유도했으면(env 만으로 동작) 레거시도 없다.
        return []
    out, wt = [], os.path.join(_ROOT, ".worktrees")
    if os.path.isdir(wt):
        # ★깊이를 «1» 로 가정하지 않는다★ — _repo_root 와 같은 함정이 여기에도 있었다.
        #   브랜치명에 슬래시가 있으면 워크트리는 `.worktrees/feat/loom-pack-layer` 처럼
        #   두 단계다(BYZ 실존). 한 단계만 훑으면 그 안에 큐잉된 메시지를 union 이 못 봐
        #   ★아무도 안 읽는다★ — recv 는 정상 종료하므로 유실이 무증상으로 남는다.
        for depth in (1, 2, 3):
            pat = os.path.join(wt, *(["*"] * depth), ".fable-team", "comm")
            for d in sorted(glob.glob(pat)):
                if os.path.isdir(d) and os.path.abspath(d) != os.path.abspath(CANON):
                    out.append(d)
    return out


def _mbox(d): return os.path.join(d, "mailbox.jsonl")


# ★seq 는 «파일에 남은 행» 이 아니라 «카운터» 에서 받는다★ (2026-09-03)
#   recv 가 읽은 행을 파일에서 지우므로, max(rows)+1 은 큰 번호가 소비되면 «되감긴다».
#   되감긴 번호는 에러 없이 다른 메시지를 가리켜 조용히 틀린다(격리 실측 30건 중 7건 중복).
_SEQCTR = os.path.join(CANON, ".mbox-seq")
# 부트스트랩 하한. 전수 실측(2026-09-03) 우편함·아카이브 6곳의 max 가 1556 이었다.
# ★1601★ — v6 계보와 번호 공간을 어긋나게 두지 않으려는 하한(첫 seq=1602).
SEQ_FLOOR = int(os.environ.get("FT_MBOX_SEQ_FLOOR") or 1601)


def _next_seq(rows):
    """★high-water mark 를 한 칸 올려 돌려준다★ — 호출자가 이미 mailbox.lock 을 쥐고 있다.

    ★새 잠금을 걸지 않는다★: flock 은 블로킹이라 물고 죽은 프로세스가 send 를 멈춘다.
    같은 잠금 안에서 하므로 원자성은 기존 잠금이 준다.

    ★`rows` 의 max 도 함께 본다★ — 카운터를 모르는 «구버전 사본» 이 같은 우편함에
    큰 번호를 남겼을 때 그것을 덮어쓰지 않기 위해서다. 단 이것이 공존을 안전하게
    만들지는 «않는다» — 구버전은 이 카운터를 안 읽으므로 여전히 되감는다.
    ⇒ ★사본 전부를 동시에 갈아야 한다★. 하나라도 남으면 오염이 계속된다.
    """
    try:
        with open(_SEQCTR, encoding="utf-8") as f:
            hwm = int(f.read().strip())
    except FileNotFoundError:
        hwm = SEQ_FLOOR
    except (ValueError, OSError) as e:
        # ★삼키지 않는다★ — 여기서 파일 max 로 폴백하면 고치려던 그 병으로 되돌아간다.
        raise RuntimeError("mbox seq counter unreadable: %s (%s)" % (_SEQCTR, e))
    seq = max(hwm, max((r.get("seq", 0) for r in rows), default=0)) + 1
    # ★원자적 교체★ — 쓰다 죽어도 반쪽 숫자가 남지 않는다(반쪽은 위 ValueError 로 간다).
    tmp = _SEQCTR + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        f.write(str(seq))
    os.replace(tmp, _SEQCTR)
    return seq


def _check_name(n):
    if not n or not NAME_RE.match(n):
        sys.stderr.write("BAD_SESSION_NAME %s\n" % n)
        sys.exit(1)


def _load(d):
    rows, p = [], _mbox(d)
    if os.path.exists(p):
        for ln in open(p, encoding="utf-8"):
            ln = ln.strip()
            if ln:
                try: rows.append(json.loads(ln))
                except Exception: pass
    return rows


def _save(d, rows):
    rows.sort(key=lambda r: r["seq"])
    with open(_mbox(d), "w", encoding="utf-8") as f:
        for r in rows:
            f.write(json.dumps(r, ensure_ascii=False) + "\n")


def _locked(d, fn):
    lf = open(os.path.join(d, "mailbox.lock"), "w")
    fcntl.flock(lf, fcntl.LOCK_EX)
    try:
        return fn()
    finally:
        fcntl.flock(lf, fcntl.LOCK_UN); lf.close()


_GUARD = os.path.join(CANON, ".mbox-guard.json")


def _guard_log():
    try:
        with open(_GUARD, encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return []


def _body_hash(body):
    # ★F2: 전문 해시 — 앞 200자만 보면 같은 템플릿 헤더로 시작하는 다른 보고가 오탐된다.
    return hashlib.md5(body.encode("utf-8")).hexdigest()


def _guard_record(to, frm, body):
    now = time.time()
    log = [r for r in _guard_log() if now - r.get("t", 0) < max(FANOUT_WIN, RATE_WIN)]
    log.append({"t": now, "f": frm, "to": to, "h": _body_hash(body)})
    with open(_GUARD, "w", encoding="utf-8") as f:
        json.dump(log[-200:], f)


def _guard_verdict(to, frm, body, dispatch=False):
    """통과면 None, 아니면 (reason, hint). 판정만 하고 기록은 _guard_record 가 한다."""
    n = len(body)
    if not body.strip():
        return ("EMPTY_BODY", "빈 메시지는 받는 쪽을 깨우기만 하고 아무것도 전하지 않는다.")
    # ★F5: 발주(--dispatch)는 EMPTY_BODY만 판정 — 길이·RESEND·FANOUT·RATE 면제(좌석마다 동일 본문 연속 주입).
    if dispatch:
        return None
    if n > MAX_BODY:
        return ("BODY_TOO_LONG len=%d max=%d" % (n, MAX_BODY),
                "본문은 3~5줄. 원문은 파일에 쓰고 «경로»만 보낸다 — 정본 절차:\n"
                "  ft-mbox.sh relay %s %s <원문파일> \"요약 3~5줄\"\n"
                "  (원문을 %s 로 «복사»하고 요약+경로만 큐잉한다)\n"
                "진행보고는 mbox 가 아니라 파일에." % (to, frm, RELAY_DIR))
    now = time.time()
    log = _guard_log()
    h = _body_hash(body)
    # ★F1: 발신 기록 시각이 아니라 «실제 큐»에 같은 본문이 pending 인지로 판정 — 소비됐으면 통과.
    dup = next((r for r in _load(CANON) if r.get("from") == frm
                and r.get("to") == to and _body_hash(r.get("body", "")) == h), None)
    last = max((r.get("t", 0) for r in log
                if r.get("f") == frm and r.get("to") == to and r.get("h") == h), default=0)
    if dup and last and now - last < RESEND_COOL:
        return ("RESEND_COOLDOWN from=%s to=%s seq=%s %ds<%ds"
                % (frm, to, dup.get("seq"), int(now - last), RESEND_COOL),
                "같은 본문이 큐에 pending(seq=%s) — 받는 쪽이 «가져갈» 때까지 기다린다. "
                "pending 동안 재발신 금지. 수신 여부가 궁금하면 pane 캡처로 확인하고, "
                "%ds 경과 후 1회만 재발신한다(소비되거나 시간이 지나면 자동 통과)."
                % (dup.get("seq"), RESEND_COOL))
    others = sorted({r["to"] for r in log
                     if r.get("f") == frm and r.get("h") == h and r.get("to") != to
                     and now - r.get("t", 0) < FANOUT_WIN})
    if others:
        return ("FANOUT from=%s already_sent_to=%s" % (frm, ",".join(others)),
                "같은 본문을 여러 좌석에 뿌리지 않는다 — 필요한 한 좌석만. "
                "공지가 필요하면 파일에 쓰고 경로만 알린다.")
    recent = sum(1 for r in log if r.get("f") == frm and now - r.get("t", 0) < RATE_WIN)
    if recent >= RATE_N:
        return ("RATE_LIMIT from=%s %d sends/%ds" % (frm, recent, RATE_WIN),
                "연속 발신 상한. 받는 쪽이 읽고 답할 시간을 준다.")
    return None


def send(to, frm, body, force=False, dispatch=False):
    _check_name(to); _check_name(frm)
    def op():
        rows = _load(CANON)
        # ★F6: 가드 판정을 잠금 «안»에서(load 직후) — 밖이면 동시 send 가 서로의 큐를 못 봐 둘 다 통과.
        # ★게이트가 고장나면 통과시킨다(fail-open)★ — 가드 버그로 통신이 끊기는 쪽이 더 크다.
        try:
            verdict = None if force else _guard_verdict(to, frm, body, dispatch)
        except Exception:
            verdict = None
        if verdict:
            return ("__BLOCKED__", verdict)   # 잠금 안에서 exit 금지 — 해제 후 처리.
        seq = _next_seq(rows)
        rows.append({"seq": seq, "ts": time.strftime("%Y-%m-%dT%H:%M:%S"),
                     "to": to, "from": frm, "body": body})
        byto = {}
        for r in rows: byto.setdefault(r["to"], []).append(r)
        keep, dropped = [], 0
        for t, rs in byto.items():
            rs.sort(key=lambda r: r["seq"])
            # ★밀려난 건수를 «센다»★ — ring 은 조용히 가장 오래된 것을 버린다. 안 세면
            # «보낸 사람은 QUEUED 를 봤는데 받는 사람은 영영 못 보는» 유실이 무증상으로 쌓인다.
            # 포화는 대개 «받는 쪽이 안 읽고 있다» 는 신호라, 이 줄이 그 사실을 처음 알린다.
            if t == to and len(rs) > MAX_PER_TO:
                dropped = len(rs) - MAX_PER_TO
            keep.extend(rs[-MAX_PER_TO:])
        _save(CANON, keep)
        # ★가드 기록을 «이미 잡고 있는» 우편함 잠금 안에서 한다★ — 밖에서 하면 동시 send 가
        # 읽고-고쳐-쓰기로 겹쳐 기록이 유실되고(실측 20건 중 일부), 가드가 «덜 잡는» 쪽으로 샌다.
        # 잠금을 새로 «거는» 것은 오히려 나쁘다 — flock 은 블로킹이라 물고 죽은 프로세스가
        # send 를 멈춘다. 기록 몇 건 잃는 것보다 큰 실패다. 여기는 획득이 늘지 않는다.
        try:
            _guard_record(to, frm, body)
        except Exception:
            pass
        return seq, sum(1 for r in keep if r["to"] == to), dropped
    res = _locked(CANON, op)
    if res[0] == "__BLOCKED__":
        reason, hint = res[1]
        sys.stderr.write("BLOCKED %s\n%s\n정말 필요하면 --force 를 붙인다.\n" % (reason, hint))
        sys.exit(3)
    seq, pend, dropped = res
    # ★«어느 파일에 몇 바이트» 를 찍는다★ — QUEUED 를 «도착»으로도 «온전»으로도 읽지 않게.
    print(f"QUEUED seq={seq} to={to} pending={pend} "
          f"file={_mbox(CANON)} bytes={len(body.encode('utf-8'))}")
    if dropped:
        sys.stderr.write(
            "DROPPED %d oldest to=%s (ring=%d 포화) — 이 좌석이 %d건을 안 읽고 쌓아뒀다.\n"
            "가장 오래된 %d건은 «영구 유실»이다. 좌석 상태를 보고, 급하면 pane 으로 직접 보낸다.\n"
            % (dropped, to, MAX_PER_TO, pend, dropped))


def relay(to, frm, path, summary, force=False):
    """긴 본문의 «정본 절차» — 원문은 파일, 큐엔 사람이 쓴 요약 + 경로만.

    ★원본을 «가리키지» 않고 «복사»한다★ — 보낸 뒤 원본이 바뀌거나 지워지면
    받는 쪽이 읽는 글이 보낸 글과 달라진다. 스냅샷이라야 인용이 성립한다.
    ★요약은 자동 생성하지 않는다★ — 무엇이 중요한지는 보내는 사람만 안다.
    자동 요약을 끼우면 받는 쪽은 결국 원문 전체를 열게 되고, 아낀 게 없어진다.
    """
    _check_name(to); _check_name(frm)
    if not os.path.isfile(path):
        sys.stderr.write("NO_SUCH_FILE %s\n" % path); sys.exit(1)
    if not summary.strip():
        sys.stderr.write("EMPTY_SUMMARY 요약 3~5줄은 보내는 사람이 쓴다.\n"); sys.exit(1)
    os.makedirs(RELAY_DIR, exist_ok=True)
    safe = re.sub(r'[^A-Za-z0-9._#-]', '_', os.path.basename(path))
    base = os.path.join(RELAY_DIR, "%s-%s-to-%s-" % (time.strftime("%Y%m%dT%H%M%S"), frm, to))
    # ★같은 이름이면 «덮어쓰지 않고» 새 자리를 만든다★ — 초 단위 타임스탬프라 같은 초에 같은
    # from→to 로 같은 파일명을 보내면 앞 스냅샷이 파괴돼, 먼저 보낸 포인터가 «나중 내용»을
    # 가리킨다. 스냅샷이 안 남으면 relay 는 경로만 보내는 것과 다를 게 없다.
    dest, n = base + safe, 1
    while os.path.exists(dest):
        n += 1
        dest = "%s%d-%s" % (base, n, safe)
    shutil.copyfile(path, dest)
    # ★F3: relay 도 재발신 탈출구를 send 로 전달 — 힌트대로 --force 를 붙이면 실제로 풀리게.
    send(to, frm, "%s\n상세(전문): %s (%d B)"
         % (summary.strip(), dest, os.path.getsize(dest)), force=force)


def _rows_for(d, me, frm):
    return [r for r in _load(d)
            if r.get("to") == me and (frm is None or r.get("from") == frm)]


def _consume(d, seqs):
    def op():
        rows = _load(d)
        keep = [r for r in rows if r.get("seq") not in seqs]
        if len(keep) != len(rows):
            _save(d, keep)
    _locked(d, op)


def recv(me, frm=None, limit=None):
    _check_name(me)
    if frm is not None: _check_name(frm)
    dirs = [CANON] + _legacy_dirs()
    got = []
    for d in dirs:
        got.extend((d, r) for r in _locked(d, lambda d=d: _rows_for(d, me, frm)))
    got.sort(key=lambda x: x[1]["seq"], reverse=True)  # LIFO
    # ★표시한 것만 소비한다★ — 표시 상한을 두면서 전량 소비하면 나머지가 조용히 사라진다.
    held = []
    if limit is not None and len(got) > limit:
        got, held = got[:limit], got[limit:]
    # ★어느 파일들을 봤는지 찍는다★ — 안 찍으면 union 이 실제로 도는지 아무도 모른다.
    print(f"SCANNED {len(dirs)} mailbox(es): " + " ".join(_mbox(d) for d in dirs))
    if not got:
        print("READ none"); return
    byd = {}
    for d, r in got:
        byd.setdefault(os.path.abspath(d), (d, set()))[1].add(r["seq"])
    for d, seqs in byd.values():
        _consume(d, seqs)
    for d, r in got:
        tag = "" if os.path.abspath(d) == os.path.abspath(CANON) else " (legacy)"
        print(f"READ [{r['from']}->{me}] #{r['seq']}{tag} — {r['body']}")
    if held:
        print(f"HELD {len(held)} more — 큐에 남겨둠. 전체는 `recv {me} --all`")
        for _, r in held:
            print(f"  · #{r['seq']} [{r['from']}] {r['body'][:70].replace(chr(10), ' ')}…")


def peek(me):
    _check_name(me)
    dirs = [CANON] + _legacy_dirs()
    mine = []
    for d in dirs:
        mine.extend(r for r in _locked(d, lambda d=d: _load(d)) if r.get("to") == me)
    mine.sort(key=lambda r: r["seq"], reverse=True)
    head = f"pending={len(mine)}"
    if mine:
        head += f" latest_seq={mine[0]['seq']} from={mine[0]['from']}"
    print(f"{head} scanned={len(dirs)}")


if __name__ == "__main__":
    a = sys.argv[1:]
    force = "--force" in a
    dispatch = "--dispatch" in a
    show_all = "--all" in a
    a = [x for x in a if x not in ("--force", "--all", "--dispatch")]
    if not a: sys.exit("usage: mbox {send <to> <from> <body> [--force]"
                       "|relay <to> <from> <file> <summary>"
                       "|recv <me> [<from>] [--all]|peek <me>}")
    c = a[0]
    if c == "send": send(a[1], a[2], " ".join(a[3:]), force, dispatch)
    elif c == "relay": relay(a[1], a[2], a[3], " ".join(a[4:]), force)
    elif c == "recv": recv(a[1], a[2] if len(a) > 2 else None, None if show_all else RECV_LIMIT)
    elif c == "peek": peek(a[1])
    else: sys.exit("unknown cmd")
