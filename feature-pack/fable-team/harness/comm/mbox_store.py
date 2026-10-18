# mbox.py 의 우편함 저장 계층(seq·레거시·본문·잠금) · CANON·_ROOT·_SEQCTR·SEQ_FLOOR 는 mbox.py 가 import 뒤 묶는다 · 200줄 규칙 분리.
from mbox_conf import *
CANON = _ROOT = _SEQCTR = SEQ_FLOOR = None   # mbox.py 가 묶는다


def _next_seq(rows):
    """★high-water mark 를 한 칸 올려 돌려준다★ — 호출자가 이미 mailbox.lock 을 쥐고 있다.

    ★새 잠금을 걸지 않는다★: flock 은 블로킹이라 물고 죽은 프로세스가 send 를 멈춘다.
    같은 잠금 안에서 하므로 원자성은 기존 잠금이 준다(동시 24건 중복 0 실측).

    ★`rows` 의 max 도 함께 본다★ — 카운터를 모르는 «구버전 사본» 이 같은 우편함에
    큰 번호를 남겼을 때 그것을 «덮어쓰지» 않기 위해서다. 사본 3종이 같은 CANON 을 계산한다.

    ★단 이것이 공존을 안전하게 만들지는 «않는다»★ — 실측(2026-09-03)이 내 첫 가정을
    반박했다: 구/신 사본을 번갈아 16건 보내니 중복 3종이 났고 ★전부 «구버전» 이 발급★
    한 번호였다(신버전끼리는 0). 구버전은 이 카운터를 안 읽고 파일 max 를 보므로,
    recv 가 그 행을 지우면 여전히 낮은 번호로 되돌아간다.
    ⇒ ★배포는 «사본 전부를 동시에» 갈아야 한다★. 하나라도 남으면 오염이 계속된다.
    """
    try:
        with open(_SEQCTR, encoding="utf-8") as f:
            hwm = int(f.read().strip())
    except FileNotFoundError:
        hwm = SEQ_FLOOR
    except (ValueError, OSError) as e:
        # ★삼키지 않는다★ — 여기서 파일 max 로 폴백하면 «고치려던 그 병» 으로 되돌아간다.
        raise RuntimeError("mbox seq counter unreadable: %s (%s)" % (_SEQCTR, e))
    seq = max(hwm, max((r.get("seq", 0) for r in rows), default=0)) + 1
    # ★원자적 교체★ — 쓰다 죽어도 반쪽 숫자가 남지 않는다(반쪽은 위 ValueError 로 간다).
    tmp = _SEQCTR + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        f.write(str(seq))
    os.replace(tmp, _SEQCTR)
    return seq



def _legacy_dirs():
    """레거시 우편함 — ★기본은 «없음»★ (2026-09-14 · 하네스 업그레이드 §4-1 · 오빠 결정 Q2).

    ★왜 union 을 걷었나 (실측 2026-09-14)★
      · 워크트리 `.fable-team` 이 루트로 가는 «심링크»인 곳(v65-input-admission·proof-store)이
        glob 에 잡혀 ★같은 inode 를 3번 읽었다★ — 좌석마다 recv 가 같은 메시지를 `(legacy)`
        꼬리로 세 번 찍었고(#13038·#13041·#13046), 모든 좌석의 recv 컨텍스트가 3배였다.
      · 남은 레거시 파일은 c-level(1행, 09-09)·v6-realtime-live 워크트리(77행, 전부 08-24 이전,
        수신 좌석 26종 «전부 사망»)·나머지 0행 — 살아 있는 좌석 앞으로 온 행은 0 이었다.
      · 트랙이 다른 우편함(c-level·loom)이 v65 좌석 recv 에 섞일 이유도 없다.
    ★되돌리는 문은 남긴다★ — `FT_MBOX_LEGACY=1` 이면 예전 union(중복은 realpath 로 제거)을 돈다.
      옛 파일에 뭔가 남았다고 의심될 때 «한 번» 켜서 보고 끄는 용도다. 기본값으로 켜 두지 않는다.
    """
    if not _ROOT or os.environ.get("FT_MBOX_LEGACY") != "1":
        return []
    out, seen, wt = [], {os.path.realpath(CANON)}, os.path.join(_ROOT, ".worktrees")
    if os.path.isdir(wt):
        for depth in (1, 2, 3):
            pat = os.path.join(wt, *(["*"] * depth), ".fable-team", "comm")
            for d in sorted(glob.glob(pat)):
                rp = os.path.realpath(d)
                # ★realpath 로 가른다★ — abspath 는 심링크를 못 본다. 같은 파일을 두 번 읽지 않는다.
                if os.path.isdir(d) and rp not in seen:
                    seen.add(rp)
                    out.append(d)
    return out


def _mbox(d): return os.path.join(d, "mailbox.jsonl")


def _bodies_dir(d): return os.path.join(d, "bodies")


def _stash_body(d, seq, body):
    """★전문을 «큐에 넣기 전»에 우편함 안에 박는다★ (2026-09-05).

    ★/tmp 를 쓰지 않는다★ — `/tmp/mbox` 는 relay 스냅샷 자리라 섞이면 둘 다 못 믿게 되고,
    /tmp 는 재부팅에 비워진다. 여기(우편함 디렉터리)는 gitignore 아래이고 ★우편함과 수명이
    같다★ — 행이 살아 있는 한 전문도 살아 있다.

    ★실패하면 None 을 돌려준다★ — 그러면 recv 가 «자르지 않는다»(_clip 참조).
    되찾을 수 없는 절단은 받는 쪽에서의 유실이고, 그건 이 개정이 없애려던 병 그 자체다.
    """
    try:
        bd = _bodies_dir(d)
        os.makedirs(bd, exist_ok=True)
        p = os.path.join(bd, "%d.txt" % seq)
        with open(p, "w", encoding="utf-8") as f:
            f.write(body)
        return p
    except OSError:
        return None


def _clip(r):
    """★수신측 절단★ (2026-09-05) — MAX_BODY 를 넘으면 잘라 주고 전문 경로를 붙인다.

    ★RECV_LIMIT(표시 «건수» 5)과 다른 축이다★ — 저건 «몇 건을 보여줄까», 이건 «한 건을
    얼마나 보여줄까». 둘을 섞으면 «5건 넘게 왔는데 안 보인다»와 «본문이 잘렸다»가
    같은 증상으로 보인다.

    ★전문을 «되찾을 수 있을 때만» 자른다★ — body_full 이 없거나(구버전이 큐잉한 행)
    파일이 사라졌으면 통째로 출력한다.
    """
    body = r.get("body", "")
    if len(body) <= MAX_BODY:
        return body, None
    full = r.get("body_full")
    if not full or not os.path.exists(full):
        return body, None
    return body[:MAX_BODY], "전문: %s (%d자)" % (full, len(body))


def _prune_bodies(d):
    """★TTL 지난 전문 파일을 지운다★ (2026-09-06) — 보존 BODIES_TTL_DAYS 일.

    ★«소비 여부»가 아니라 «시간»으로 자른다★ — 근거는 BODIES_TTL_DAYS 주석.

    설계 제약 셋 — 전부 «청소가 통신을 해치지 않게» 하려는 것이다:
      ①★send 를 막지 않는다★ — 전체를 삼킨다(except Exception: pass).
        청소 실패는 통신 실패보다 훨씬 가볍다. 여기서 예외가 새면 그 send 가 죽는다.
      ②★1시간에 한 번만 돈다★ — `<d>/.bodies-pruned` 스탬프 mtime 으로 억제.
        안 그러면 매 send 가 bodies 전체를 listdir 해 파일 수에 비례해 느려진다.
        ★스탬프를 «청소 전»에 찍는다★ — 중간에 죽어도 다음 send 가 곧바로 재시도해
        같은 비용을 다시 물지 않는다.
      ③★잠금 «밖»에서 부른다★ — _locked 안에서 listdir 하면 잠금 보유 시간이 파일
        수에 비례해 늘고, 그동안 다른 좌석의 send 가 통째로 막힌다.
    """
    try:
        bd = _bodies_dir(d)
        if not os.path.isdir(bd):
            return
        now = time.time()
        stamp = os.path.join(d, ".bodies-pruned")
        try:
            if now - os.path.getmtime(stamp) < BODIES_PRUNE_EVERY:
                return
        except OSError:
            pass  # 스탬프 없음/못 읽음 = 아직 안 돌았다 → 이번에 돈다.
        with open(stamp, "w", encoding="utf-8") as f:
            f.write(str(int(now)))
        cutoff = now - BODIES_TTL_DAYS * 86400
        for name in os.listdir(bd):
            if not name.endswith(".txt"):
                continue
            p = os.path.join(bd, name)
            try:
                if os.path.getmtime(p) < cutoff:
                    os.remove(p)
            except OSError:
                pass   # 한 건이 안 지워져도 나머지는 계속 지운다.
    except Exception:
        pass


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

