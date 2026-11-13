"""ft 2.0 keeper 판정 닫기 목록 (r1865 · keeper_close.close 가 부른다) — `<runtime>/keeper-verdict-close.tsv`
줄 = work<TAB>attempt<TAB>판정 <N><TAB><좌석> #<seq> (사람·master 가 씀 · 읽기만) · 꼴만으로 kill 0 — 읽기 전용 정본 2개 대조:
ⓐ planner md 원장 행(ledger) ⓑ 우편 로그 행(mailbox) · 없음·불일치·못 읽음 = HELD(같은 사유 1회)."""
import hashlib, json, os, re  # noqa: E401

LIST, GIT_S, MD_GLOB = "keeper-verdict-close.tsv", 25, "design/teams/planner/VERDICTS-planner-*.md"
VERDICT, APPROVE, ROLE = re.compile(r"판정 ([0-9]+)"), re.compile(r"(\S+) #([0-9]+)"), re.compile(r"byz-[a-z0-9]+-(master|desk)-")
MD_ROW, VOID = re.compile(r"^(?:- \*\*(\d+)\*\*|\|\s*(\d+)\s*\|)"), re.compile(r"[\s\[(*~]*(무효|철회)")   # ft_directive_watch 와 같은 꼴


def near(edge, word, text):
    return re.search(r"(?<!%s)%s(?!%s)" % (edge, re.escape(word), edge), text) is not None


def line(runtime, work, attempt):
    """(work, attempt) 줄 → [판정, 승인] · 목록에 없음 = None · 못 읽음·꼴 틀림·중복 = 판정 불가 문자열(sha 포함)."""
    try:
        with open(os.path.join(runtime, LIST), "rb") as fh:
            raw = fh.read()
        rows = [x.split("\t") for x in raw.decode("utf-8").splitlines() if x.strip() and not x.startswith("#")]
    except FileNotFoundError:
        return None
    except (OSError, UnicodeError) as exc:
        return "판정 불가 · 판정 목록 못 읽음 %s" % type(exc).__name__
    sha, keys = hashlib.sha256(raw).hexdigest()[:12], [tuple(r[:2]) for r in rows]
    if any(len(r) != 4 for r in rows) or len(set(keys)) != len(keys):
        return "판정 불가 · 판정 목록 꼴 틀림·중복 sha %s" % sha
    cells = next((r for r in rows if tuple(r[:2]) == (work, attempt)), None)
    if cells and not (VERDICT.fullmatch(cells[2]) and APPROVE.fullmatch(cells[3])):
        return "판정 불가 · 판정 목록 %s@%s 꼴 틀림 sha %s" % (work, attempt, sha)
    return cells and cells[2:]


def ledger(k, n, holder, seq):
    """ⓐ 빈 문자열 = 맞음 · 그 밖 = 사유. 표 없음·planner·* 행 없음 = `.` origin/main."""
    try:
        with open(os.path.join(k.root, ".fable-team", "state", "directive-roots.tsv"), encoding="utf-8") as fh:
            table = [x.rstrip("\n").split("\t") for x in fh if not x.startswith("#") and len(x.split("\t")) >= 4]
    except (OSError, UnicodeError) as exc:
        table = [] if isinstance(exc, FileNotFoundError) else None
    if table is None:
        return "원장 못 읽음 · directive-roots"
    r = next((x for x in table if x[0] == "planner"), None) or next((x for x in table if x[0] == "*"), ["*", ".", "origin/main"])
    rc, out, err = k.call(["git", "-C", os.path.join(k.root, r[1]), "grep", "-I", "-E", "-e", r"^- \*\*%s\*\*" % n,
                           "-e", r"^\|[[:space:]]*%s[[:space:]]*\|" % n, r[2], "--", MD_GLOB], GIT_S)
    if rc not in (0, 1):
        return "원장 못 읽음 · git grep rc %s %s" % (rc, err[:80])
    hits = {}
    for path, _, body in (x[len(r[2]) + 1:].partition(":") for x in out.splitlines()):
        row, num = MD_ROW.match(body), re.search(r"planner-(\d+)-", path)
        if row and num and (row.group(1) or row.group(2)) == n:
            rest = body[row.end():]   # R1 — md_row 같이: 글머리 = 나머지 · table = 시각 column 떼고 내용만
            hits.setdefault(int(num.group(1)), []).append(rest.strip() if row.group(1) else "|".join(rest.split("|")[1:]).strip(" |"))
    rows = hits[max(hits)] if hits else []
    if len(rows) != 1:
        return "판정 %s 원장 행 %d개" % (n, len(rows))
    body = rows[0]
    if not near(r"[\w#-]", holder, body):
        return "판정 %s 행에 %s 없음" % (n, holder)
    for bad, why in ((VOID.match(body), "무효·철회"), (not near("[0-9]", "#" + seq, body), "행에 #%s 없음" % seq)):
        if bad:
            return "판정 %s %s" % (n, why)
    return ""


def mailbox(k, seq, seat, work):
    """ⓑ 빈 문자열 = 맞음 · 그 밖 = 사유(없음·회전·깨짐 포함)."""
    try:
        with open(os.path.join(k.root, ".fable-team", "comm", "mailbox.log.jsonl"), encoding="utf-8") as fh:
            found = [rec for rec in (json.loads(x) for x in fh if seq in x) if isinstance(rec, dict) and str(rec.get("seq")) == seq]
    except (OSError, ValueError) as exc:
        return "우편 로그 못 읽음 %s" % type(exc).__name__
    rec = found[0] if len(found) == 1 else {}
    for bad, why in ((len(found) != 1, "로그 행 %d개" % len(found)), (rec.get("from") != seat, "from %s ≠ %s" % (rec.get("from"), seat)),
                     (not ROLE.match(seat), "역할 master·desk 아님"), (not near("[A-Za-z0-9_-]", work, str(rec.get("body") or "")), "본문에 %s 없음" % work)):
        if bad:
            return "승인 #%s %s" % (seq, why)
    return ""


def approved(k, n, holder, seat, seq, work):
    why = ledger(k, n, holder, seq)
    if why:
        return why
    return mailbox(k, seq, seat, work)


def gate(k, runtime, team, work, attempt, holder):
    """None = 목록 밖(지금 그대로) · False = HELD 남김(같은 사유 1회 · kill 0) · 문자열 = 승인 맞음(CLOSED-VERDICT 꼬리)."""
    cells = line(runtime, work, attempt)
    if not cells:
        return None
    if isinstance(cells, str):
        why, text = cells, "%s %s %s" % (work, holder, cells)
    else:
        n, (seat, seq) = cells[0][3:], APPROVE.fullmatch(cells[1]).groups()
        why = approved(k, n, holder, seat, seq, work)
        if not why:
            return "판정 %s %s" % (n, cells[1])
        text = "%s 승인 대조 %s · kill 0" % (work, why)
    key = "verdict|%s|%s@%s" % (team, work, attempt)
    if k.state["held"].get(key) != why:   # 같은 사유는 1회만 · 사유가 바뀌면 다시 1줄
        k.state["held"][key] = why
        k.log("HELD", team, text)
    return False
