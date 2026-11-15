# r1661 단계 1 — 받는 이 검사(ⓐ)·큐 정리 = 보관 이동(ⓑ)·중복 접기(ⓒ) · mbox_ops.send 가 부른다 · 200줄 규칙 분리.
#   ring 상한·버리는 순서(r1651 mbox_keep·mbox_drops)는 손 0 — 이 파일은 «안 읽힐 행» 과 «겹친 행» 만 다룬다.
from mbox_conf import *
import subprocess
from mbox_store import _load, _locked, _save
from mbox_keep import HUMAN_SENDERS
import mbox_lineage

GOAL_BLOCK = re.compile(r"^★골 표 A6 \(.*?^★/골 표★[ \t]*$\n?", re.M | re.S)   # mbox_guard_goal.sh _goal_trim 과 같은 마커
KEEP_HEADS = ("HIL", "긴급", "오빠", "인계", "레디")   # 머리 [..] 안에 있으면 안 접는다 — 사람 일·승계 핸드셰이크
SWEEP_STAMP = ".queue-swept"
ARCHIVE_DAYS = BODIES_TTL_DAYS   # «14일 recv 없음» = 행이 14일 넘게 안 읽힘(consume-on-read 라 읽히면 큐에 없다)


def check_to(to):
    """ⓐ 받는 이 검사 — 옵션 낱말(`-` 시작)은 늘 거절 · #N 없는 이름은 «좌석 행이 있는 명부가 있는데 어느 좌석으로도 안 풀릴 때만» 거절.

    ★#N 없는 역할 이름 자체는 막지 않는다★ — r1116 역할 우편함(번호 없는 역할 이름 = 한 우편함)이 정상 길이다
    (2026-11-14 라이브 로그 실측: 나노 → `byz-harness-master-pi` 15건). 팀 접두(byz-|ft-<팀>-) 없는 #N 없는 받는 이는
    로그 4벌에서 0건(큐에만 `dispatch`·`x`·`master39` 같은 줏은 이름) → 명부가 있으면 거절. 좌석 행 없는 명부 = 판정 재료 없음 = 지금 동작."""
    why = ""
    if to.startswith("-"):
        why = "옵션 낱말이 받는 이 자리에 있음(인자 순서 확인)"
    elif not re.search(r"#\d+$", to):
        docs = mbox_lineage._load_docs(os.path.dirname(mbox_lineage._seats_json()) or ".")[0]
        rows = mbox_lineage._team_rows(to)[0]
        if not any(isinstance(v, dict) for doc in docs.values() for v in doc.values()):
            pass
        elif not re.match(r"^(?:byz|ft)-[a-z0-9]+-", to):
            why = "#N 없음 · 팀 접두 없음(좌석 이름 아님)"
        elif rows and to not in rows and mbox_lineage._resolve(rows, to) == to:
            why = "#N 없음 · 명부의 어느 좌석으로도 안 풀림"
    if why:
        sys.stderr.write("REJECT 받는 이 %s — %s · 큐 쓰기 0\n" % (to, why))
        sys.exit(2)


def fingerprint(body):   # 골 표 블록을 뺀 본문 지문 — 같은 쪽지에 골 표 판본만 다른 경우도 같은 본문으로 본다
    return hashlib.sha256(GOAL_BLOCK.sub("", body or "").strip().encode("utf-8")).hexdigest()


def _keep(frm, body):
    m = re.match(r"\s*\[([^\]]*)\]", body or "")
    return frm in HUMAN_SENDERS or bool(m and any(k in m.group(1) for k in KEEP_HEADS))


def fold(d, rows, to, frm, body):
    """ⓒ 중복 접기 — 같은 받는 이(이름 그대로)·같은 보낸 이·같은 본문 지문이 «아직 안 읽힌 채» 큐에 있으면 새 행 대신 그 행 dup+1.

    호출자가 mailbox.lock 을 쥐고 있다(send op 안 · 가드 판정 뒤). 접으면 큐를 저장하고 출력 1줄을 돌려준다 · 아니면 None.
    ★보낸 이도 같아야 접는다★ — 다른 좌석이 같은 글을 보냈다는 사실은 버리지 않는다.
    ★역할 키로 접지 않는다★(DA#10 HOLD R1) — 같은 역할 현역 둘(arch#1·#2)은 r1225 로 따로 받는다. 다른 이름 행에 접으면 둘째가 못 받는다."""
    if _keep(frm, body):
        return None
    fp = fingerprint(body)
    for r in rows:
        if r.get("to") == to and r.get("from") == frm and fingerprint(r.get("body")) == fp:
            r["dup"] = int(r.get("dup") or 0) + 1
            _save(d, rows)
            return "QUEUED-DUP seq=%d dup=%d to=%s" % (r["seq"], r["dup"], to)
    return None


def _sessions():   # tmux 세션 이름 집합 · 못 읽음 = None(판정 불가 — 하드 룰 20 · 이동 0)
    try:
        p = subprocess.run(["tmux", "list-sessions", "-F", "#{session_name}"], capture_output=True, text=True, timeout=7)
    except (OSError, subprocess.SubprocessError):
        return None
    return set(p.stdout.split("\n")) - {""} if p.returncode == 0 else None


def _age_ok(r, cut):   # 행 ts 가 cut 보다 옛날이면 True · ts 못 읽음 = False(남긴다)
    try:
        return time.mktime(time.strptime(r.get("ts", ""), "%Y-%m-%dT%H:%M:%S")) < cut
    except (TypeError, ValueError, OverflowError):
        return False


def dead_rows(rows, live, cut):
    """ⓑ 읽을 사람이 없는 행 — 받는 이 세션 없음 ∧ 계보 끝(_replaced_by 사슬 · 역할 현역)도 세션 없음
    ∧ 같은 역할 키의 세션도 없음 ∧ 14일 넘게 안 읽힘. 하나라도 아니면 남긴다."""
    live_keys, memo, out = {role_key(s) for s in live}, {}, []
    for r in rows:
        to = r.get("to") or ""
        if to in live or role_key(to) in live_keys or not _age_ok(r, cut):
            continue
        if to not in memo:
            memo[to] = mbox_lineage.holder(to)
        if memo[to] in live:
            continue
        out.append(r)
    return out


def _archive(d, out):   # 보관 = 이동(하드 룰 2 · 삭제 0) · 날짜 파일에 덧붙임 · 일반 파일(하드 룰 19)
    p = os.path.join(d, "mailbox.archive-%s.jsonl" % time.strftime("%Y-%m-%d"))
    with open(p, "a", encoding="utf-8") as f:
        for r in out:
            f.write(json.dumps(r, ensure_ascii=False) + "\n")
        f.flush(); os.fsync(f.fileno())
    return p


def sweep(d):
    """ⓑ 큐 정리 — send 의 1시간 청소 자리(_prune_bodies 와 같은 억제 · 잠금 밖에서 부름 · send 를 막지 않음).

    스탬프를 «판정 전»에 찍는다(_prune_bodies 와 같은 이유 + 판정 불가 줄이 send 마다 나지 않게).
    tmux 목록은 잠금 «밖»에서 읽고, 큐 읽기·보관 쓰기·큐 저장만 잠금 안에서 한다. 보관 쓰기 실패 = 큐 손 0."""
    try:
        now, stamp = time.time(), os.path.join(d, SWEEP_STAMP)
        try:
            if now - os.path.getmtime(stamp) < BODIES_PRUNE_EVERY:
                return
        except OSError:
            pass
        with open(stamp, "w", encoding="utf-8") as f:
            f.write(str(int(now)))
        live = _sessions()
        if live is None:
            sys.stderr.write("NOTE 큐 정리 판정 불가 — tmux 세션 목록 못 읽음 · 이동 0\n")
            return
        cut = now - ARCHIVE_DAYS * 86400

        def op():
            rows = _load(d)
            out = dead_rows(rows, live, cut)
            if not out:
                return 0, ""
            p = _archive(d, out)
            gone = {r["seq"] for r in out}
            _save(d, [r for r in rows if r["seq"] not in gone])
            return len(out), p
        n, p = _locked(d, op)
        if n:
            sys.stderr.write("ARCHIVED %d rows → %s\n" % (n, p))
    except Exception:
        pass
