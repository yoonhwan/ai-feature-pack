# mbox.py 의 명령(send·relay·recv·peek) · CANON 은 mbox.py 가 묶는다 · 200줄 규칙 분리.
from mbox_conf import *
from mbox_store import _check_name, _clip, _legacy_dirs, _load, _locked, _mbox, _next_seq, _prune_bodies, _save, _stash_body
from mbox_guard import _guard_log, _guard_record, _guard_verdict, _log_sent, _reply_exempt
CANON = None   # mbox.py 가 묶는다


def send(to, frm, body, force=False):
    _check_name(to); _check_name(frm)
    def op():
        rows = _load(CANON)
        # ★F6: 가드 판정을 잠금 «안»에서(load 직후) — 밖이면 동시 send 가 서로의 큐를 못 봐 둘 다 통과.
        # ★게이트가 고장나면 통과시킨다(fail-open)★ — 가드 버그로 통신이 끊기는 쪽이 더 크다.
        try:
            window = max(FANOUT_WIN, RATE_WIN)
            exempt = _reply_exempt(frm, body, [r for r in _guard_log() if time.time() - r.get("t", 0) < window])
            verdict = None if force else _guard_verdict(to, frm, body, exempt)
        except Exception:
            exempt, verdict = [], None
        if verdict:
            return ("__BLOCKED__", verdict)   # 잠금 안에서 exit 금지 — 락 파일을 쥔 채 죽는다.
        seq = _next_seq(rows)
        row = {"seq": seq, "ts": time.strftime("%Y-%m-%dT%H:%M:%S"),
               "to": to, "from": frm, "body": body}
        # ★전문 보관은 «큐에 넣기 전»★ — 행은 큐에 있는데 전문은 없는 순간을 만들지 않는다.
        #   그 순간이 있으면 그 사이에 도착한 recv 가 «되찾을 수 없는 절단»을 하게 된다.
        if len(body) > MAX_BODY:
            full = _stash_body(CANON, seq, body)
            if full:
                row["body_full"] = full
        rows.append(row)
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
        _log_sent(CANON, row)
        # ★가드 기록을 «이미 잡고 있는» 우편함 잠금 안에서 한다★ — 밖에서 하면 동시 send 가
        # 읽고-고쳐-쓰기로 겹쳐 기록이 유실되고(실측 20건 중 일부), 가드가 «덜 잡는» 쪽으로 샌다.
        # 잠금을 새로 «거는» 것은 오히려 나쁘다 — flock 은 블로킹이라 물고 죽은 프로세스가
        # send 를 멈춘다. 기록 몇 건 잃는 것보다 큰 실패다. 여기는 획득이 늘지 않는다.
        try:
            _guard_record(to, frm, body, exempt)
        except Exception:
            pass
        return seq, sum(1 for r in keep if r["to"] == to), dropped
    res = _locked(CANON, op)
    if res[0] == "__BLOCKED__":
        reason, hint = res[1]
        # ★마지막 줄에 이유를 «다시» 싣는다★ (2026-09-04 실측)
        #   사람은 stderr 를 tail 로 받는다. 이유가 첫 줄에만 있으면 `tail -1` 은
        #   "--force 를 붙인다" 만 보여주고, RESEND_COOLDOWN 처럼 hint 가 여러 줄인 가드는
        #   ★`tail -3` 으로도 이유가 밀려나 안 잡힌다★. 그러면 받는 사람은 «왜 막혔는지
        #   모른 채» 본문만 줄여 재발송한다 — 실제로 그 일이 났고 당사자는 어느
        #   가드였는지 사후에도 확정하지 못했다. 잘리는 쪽을 정할 수 없으니 양 끝에 둔다.
        sys.stderr.write("BLOCKED %s\n%s\n→ BLOCKED %s · 정말 필요하면 --force\n"
                         % (reason, hint, reason))
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
    # ★청소는 «QUEUED 를 찍은 뒤», «잠금 밖»에서★ — 이 호출이 실패하거나 느려도
    #   메시지는 이미 큐에 들어갔고 발신자는 이미 결과를 받았다. relay 는 send 를
    #   타므로 여기 한 곳이면 두 경로가 모두 덮인다.
    _prune_bodies(CANON)


def relay(to, frm, path, summary):
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
    send(to, frm, "%s\n상세(전문): %s (%d B)"
         % (summary.strip(), dest, os.path.getsize(dest)))


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
        shown, note = _clip(r)
        print(f"READ [{r['from']}->{me}] #{r['seq']}{tag} — {shown}")
        if note:
            print(note)
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

