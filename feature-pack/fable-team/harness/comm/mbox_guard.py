# mbox.py 의 발신 가드(fan-out·속도·재발주·회신 면제)와 발신 사본 로그 · CANON·_GUARD 는 mbox.py 가 묶는다 · 200줄 규칙 분리.
from mbox_conf import *
from mbox_store import _load
CANON = _GUARD = None   # mbox.py 가 묶는다(_GUARD = CANON/.mbox-guard.json)




def _guard_log():
    try:
        with open(_GUARD, encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return []


def _body_hash(body):
    # ★F2: 전문 해시★ — 앞 200자만 보면 같은 템플릿 헤더로 시작하는 «다른» 보고가
    #   RESEND·FANOUT 으로 오탐되어 막혔다. 또 계보마다 해시 방식이 갈리면 같은
    #   .mbox-guard.json 을 공유하면서도 서로의 기록을 못 읽어 가드가 반쪽만 작동한다.
    #   ★라이브 실측(2026-09-06)★ 같은 본문 206자(앞 200자 동일)로
    #     ① BYZ send → QUEUED  ② 곧바로 pack 으로 같은 본문 → ★QUEUED(안 막힘)★
    #     ③ BYZ 로 또 → BLOCKED RESEND_COOLDOWN / 가드 로그는 기록 2건에 고유 해시 2종.
    #   ★부작용★ 기존 .mbox-guard.json 의 200자 해시 기록은 전부 무효화된다
    #   ⇒ 억제가 1회 리셋된다(이전에 막히던 재발신이 한 번 통과). 홍수가 아니고,
    #   두 계보의 해시를 통일하는 것 자체가 정상화다.
    return hashlib.md5(body.encode("utf-8")).hexdigest()


_HEAD_PREFIX = re.compile(r"^\s*\[[^\]]*->[^\]]*\]\s*")  # 본문 머리 `[from->to]`
_REPLY_REF = re.compile(r"쪽지 ?#(\d{4,})((?:[·,] ?#\d{4,})*)")  # 회신 인용 = `쪽지 #<seq>`(+ `·#<seq>`) 꼴만 — `PR #N`·맨 `#N` 은 회신 아님


def _reply_seqs(body):
    out = []
    for m in _REPLY_REF.finditer(_HEAD_PREFIX.sub("", body, 1)[:80]):
        out += [int(m.group(1))] + [int(x) for x in re.findall(r"#(\d+)", m.group(2))]
    return list(dict.fromkeys(out))


def _received_seqs(frm):
    """frm 이 받은 쪽지 seq — 큐(아직 안 읽은 것) + 보낸 행 사본(읽혀 큐에서 빠진 것)."""
    got = {r.get("seq") for r in _load(CANON) if role_key(r.get("to")) == role_key(frm)}   # 역할 키(r1116) — 앞 판이 받은 쪽지 회신도 면제
    for p in (os.path.join(CANON, SENT_LOG) + ".1", os.path.join(CANON, SENT_LOG)):
        try:
            with open(p, encoding="utf-8") as f:
                got |= {r.get("seq") for r in map(_json_or_empty, f) if role_key(r.get("to")) == role_key(frm)}
        except OSError:
            pass
    return got


def _json_or_empty(ln):
    try:
        return json.loads(ln)
    except ValueError:
        return {}


def _is_exempt_row(r):
    return isinstance(r.get("r"), list) and bool(r["r"])  # 옛 기록 `r: 1`(int) 은 면제 행으로 보지 않는다(호환)


def _reply_exempt(frm, body, log):
    """이번 발신이 발신 상한(RATE)에서 면제받는 seq 목록(판정 423 ④) — send() 가 잠금 안에서 «한 번» 계산해 verdict·record 에 넘긴다.
    면제 = 본문 앞 80자의 `쪽지 #<seq>` 중 frm 이 받은 seq 이고 같은 frm 의 가드 기록(log)에서 아직 면제에 안 쓴 것 — 받은 seq 1개당 1회."""
    seqs = _reply_seqs(body)
    if not seqs:
        return []
    if sum(1 for r in log if _is_exempt_row(r)) >= EXEMPT_CAP:  # 이력이 잘렸을 수 있는 상태 — 새 면제를 내주지 않는다(RATE 셈에 들어감)
        sys.stderr.write("WARN EXEMPT_CAP reached (%d) — 이번 발신은 회신 면제 없음(RATE 셈 포함)\n" % EXEMPT_CAP)
        return []
    used = {x for r in log if r.get("f") == frm and isinstance(r.get("r"), list) for x in r["r"]}
    cand = [x for x in seqs if x not in used]
    return [x for x in cand if x in _received_seqs(frm)] if cand else []


def _guard_record(to, frm, body, exempt=()):
    now = time.time()
    log = [r for r in _guard_log() if now - r.get("t", 0) < max(FANOUT_WIN, RATE_WIN)]
    log.append({"t": now, "f": frm, "to": to, "h": _body_hash(body), "r": list(exempt)})
    # 면제 사용 이력은 200행 절단과 분리해 보존 — 절단으로 같은 seq 가 재면제되던 경로(DA r2 Q1) 차단
    ex = [r for r in log if _is_exempt_row(r)]
    log = sorted([r for r in log if not _is_exempt_row(r)][-200:] + ex[-EXEMPT_CAP:], key=lambda r: r.get("t", 0))
    with open(_GUARD, "w", encoding="utf-8") as f:
        json.dump(log, f)


def _is_tool_sender(frm):
    """도구 발신자 = `ft-` 접두 + `#N` 없음(예 `ft-head-lag`). 좌석 이름은 늘 `#N` 을 달므로(`ft-v65-arch-fable#40` 포함) 구분된다.
    도구는 팀당 1통 fan-out 이 일이라 FANOUT·RATE 면제(R380) — EMPTY_BODY·RESEND_COOLDOWN 은 그대로, 좌석 규율(COMM-GUIDE 4)은 불변."""
    return frm.startswith("ft-") and "#" not in frm


def _guard_verdict(to, frm, body, exempt=()):
    """통과면 None, 아니면 (reason, hint). 판정만 하고 기록은 _guard_record 가 한다."""
    if not body.strip():
        return ("EMPTY_BODY", "빈 메시지는 받는 쪽을 깨우기만 하고 아무것도 전하지 않는다.")
    # ★길이로 막지 않는다★ (2026-09-05, BODY_TOO_LONG 제거) — 근거는 MAX_BODY 주석.
    #   긴 본문은 send 가 전문을 파일에 박고 recv 가 잘라 읽는다. 상한이 가르친 것은
    #   relay 가 아니라 --force 였고, 우회를 가르치는 가드는 규율이 아니라 소음이다.
    now = time.time()
    log = _guard_log()
    h = _body_hash(body)
    # ★F1: 발신 기록 시각이 아니라 «실제 큐» 에 같은 본문이 pending 인지로 판정★
    #   — 소비됐으면 통과한다. 기존은 가드 로그의 last 시각만 봐서, 받는 쪽이
    #   이미 recv 로 가져간 뒤에도 RESEND_COOL 동안 보고를 막았다.
    #   ★F6 이후 이 _load(CANON) 은 더티 리드가 아니다★ — send() 가 우편함 잠금을 쥔 채
    #   불러주므로, 동시에 들어온 다른 send 가 이미 큐에 넣은 행을 «본다». 그전에는
    #   판정이 잠금 밖이라 두 send 가 서로의 큐를 못 보고 ★둘 다 통과★ 했다(실측 5회 중 4회).
    dup = next((r for r in _load(CANON) if r.get("from") == frm
                and role_key(r.get("to")) == role_key(to) and _body_hash(r.get("body", "")) == h), None)
    last = max((r.get("t", 0) for r in log
                if r.get("f") == frm and role_key(r.get("to")) == role_key(to) and r.get("h") == h), default=0)
    if dup and last and now - last < RESEND_COOL:
        return ("RESEND_COOLDOWN from=%s to=%s seq=%s %ds<%ds"
                % (frm, to, dup.get("seq"), int(now - last), RESEND_COOL),
                "같은 본문이 큐에 pending(seq=%s) — 받는 쪽이 «가져갈» 때까지 기다린다. "
                "pending 동안 재발신 금지. 수신 여부가 궁금하면 pane 캡처로 확인하고, "
                "%ds 경과 후 1회만 재발신한다(소비되거나 시간이 지나면 자동 통과)."
                % (dup.get("seq"), RESEND_COOL))
    tool, skipped = _is_tool_sender(frm), []
    others = sorted({role_key(r["to"]) for r in log   # 같은 역할 옛·새 번호 = 한 좌석(r1116)
                     if r.get("f") == frm and r.get("h") == h and role_key(r.get("to")) != role_key(to)
                     and now - r.get("t", 0) < FANOUT_WIN})
    if others and tool:
        others, skipped = [], skipped + ["fanout"]
    if others:
        return ("FANOUT from=%s already_sent_to=%s" % (frm, ",".join(others)),
                "같은 본문을 여러 좌석에 뿌리지 않는다 — 필요한 한 좌석만. "
                "공지가 필요하면 파일에 쓰고 경로만 알린다.")
    # 면제(exempt = 받은 쪽지 `쪽지 #seq` 회신)는 상한을 세지도 걸리지도 않는다 — 다른 가드(fan-out·재발송 쿨다운)는 그대로. 옛 기록 `r: 1`(int)도 «면제였음».
    recent = sum(1 for r in log if r.get("f") == frm and not r.get("r") and now - r.get("t", 0) < RATE_WIN)
    if recent >= RATE_N and tool:
        skipped.append("rate")
    elif recent >= RATE_N and not exempt:
        return ("RATE_LIMIT from=%s %d sends/%ds" % (frm, recent, RATE_WIN),
                "연속 발신 상한. 받는 쪽이 읽고 답할 시간을 준다.")
    if skipped:
        sys.stderr.write("TOOL_SENDER from=%s exempt=%s\n" % (frm, ",".join(skipped)))
    return None


def _rotate_sent_log(p):
    """`.<KEEP-1>`→`.<KEEP>` … `.1`→`.2` 로 «밀어» 보관하고 빈 `.1` 자리를 만든다(있는 것만).

    r553 — 한 벌(`.1`)만 남기면 바쁜 날 보관이 약 10시간이라 매거진 24시간 창을 못 덮는다.
    가장 오래된 벌(`.<KEEP>`)은 `os.replace` 로 덮여 사라진다 — 그 밖으로 밀린 것만 잃는다.
    """
    for n in range(SENT_LOG_KEEP - 1, 0, -1):
        src = "%s.%d" % (p, n)
        if os.path.exists(src):
            os.replace(src, "%s.%d" % (p, n + 1))


def _log_sent(d, row):
    """보낸 행을 추가 전용 사본에 1줄 쓴다. 실패해도 send 는 산다 — 단 «조용히» 삼키지 않는다.

    통신이 사본 때문에 끊기는 쪽이 더 크므로 raise 하지 않고, 대신 stderr WARN 으로 드러낸다
    (미러는 이 사본이 비면 보고를 못 올리므로 «보이는 실패» 여야 한다). 우편함 잠금 안에서 부른다.
    한도 초과 시 `.1`~`.<SENT_LOG_KEEP>` 로 밀어 보관한다 — 회전본은 1개가 아니다.
    """
    p = os.path.join(d, SENT_LOG)
    try:
        if os.path.exists(p) and os.path.getsize(p) > SENT_LOG_MAX_BYTES:
            _rotate_sent_log(p)
            os.replace(p, p + ".1")
        with open(p, "a", encoding="utf-8") as f:
            f.write(json.dumps(row, ensure_ascii=False) + "\n")
    except OSError as e:
        sys.stderr.write("WARN %s 사본 기록 실패(%s) — 이 행은 Slack 미러에 안 올라간다. 큐에는 정상 적재됨.\n"
                         % (SENT_LOG, type(e).__name__))

