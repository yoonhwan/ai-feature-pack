#!/usr/bin/env python3
"""ft_card_map_lint.py <card.md> [more…] — 카드 «## 계약↔시험 대응표» 검사 (r984 · 오빠 결정 D4).
왜: 반례 집합을 고정해도 계약끼리 모순이면 DA 가 그 틈을 찬다 — r963 r4 는 계약 ②«표식 0» 과 시험 ⓙ«표식 그대로» 가 어긋났고, r899 r3 은 설계 순서와 구현 순서가 달랐다.
카드에 «계약 → 입력 → 기대 → 시험» 표를 두고 구현 착수 전(lint·spawn 게이트)에 검사한다.
검사 3: ⓐ 계약 행마다 시험 ≥ 1 · ⓑ 같은 입력에 다른 기대 0(입력·기대 열이 둘 다 있을 때) · ⓒ 시험 번호 순서 = 계약 순서.
표 분할 = 셀 안 `\\|` 보존(이스케이프된 `|` 는 열 경계가 아니다) — 머리·구분선·본문 행이 같은 함수를 쓴다.
출력 = «STATUS<TAB>카드경로<TAB>사유» · STATUS ∈ OK·INFO·WARN·BAD · 경로가 빈 줄 = 실행 전체 사유(이력 조회 판정 불가).
첫 추가일은 배치 1회로 본다 — lint 가 사전(FT_CARD_ADDED_MAP)을 주면 git 호출 0, 단독 실행이면 git log 1번(--diff-filter=A · --since=스위치 · 7초 상한 · 넘으면 rc3 «판정 불가» · WARN 으로 숨기기 0).
날짜 스위치 1곳 = FT_CARD_GATE_STRICT_FROM(기본 2026-10-30 · 20장 뒤 · r986 이 같은 값을 재사용) — 그 날 이후 추가 카드만 REJECT, 그 전·이력 없는 카드는 WARN 만.
읽는 범위는 스위치 «뒤» 커밋뿐이다(r1062) — 이 날짜의 쓰임은 «스위치 뒤 추가인가» 한 비교뿐이라 판정은 그대로고, 카드 폴더 이력이 길어도 7초를 넘지 않는다.
창 밖으로 밀린 카드는 두 가지 표식으로 적는다 — ① 제안서 문턱(PROPOSAL_FROM 2026-10-11) 스냅숏에 이미 있던 카드 = BEFORE(그 전 추가) ② 스냅숏에 없고 지금 추적되는 카드 = PROPOSAL_FROM(10-11 뒤·창 이전 추가). 사전 날짜를 보는 둘째 문턱(ft-index-lint.sh ⑨ 제안서 줄)도 날짜를 잃지 않는다. 사전에 «아예 없는» 카드 = 이력 없음(미커밋) 이다.
rc 0 = BAD 0 · 1 = BAD 있음 · 2 = usage · 3 = 스위치·이력 꼴 오류(통과 0).
"""
import os
import re
import subprocess
import sys
from datetime import date, datetime

HEAD = "## 계약↔시험 대응표"
SWITCH_ENV = "FT_CARD_GATE_STRICT_FROM"
STRICT_DEFAULT = "2026-10-30"
CIRCLED = "①②③④⑤⑥⑦⑧⑨⑩⑪⑫⑬⑭⑮⑯⑰⑱⑲⑳"
LOWERED = "ⓐⓑⓒⓓⓔⓕⓖⓗⓘⓙⓚⓛⓜⓝⓞⓟⓠⓡⓢⓣⓤⓥⓦⓧⓨⓩ"
ORD = {**{c: i + 1 for i, c in enumerate(CIRCLED)}, **{c: i + 1 for i, c in enumerate(LOWERED)}}
SEP_CELL = re.compile(r"^:?-{3,}:?$")
DATE_LINE = re.compile(r"^\d{4}-\d{2}-\d{2}$")
MAPFILE_ENV = "FT_CARD_ADDED_MAP_FILE"
PROPOSAL_FROM = "2026-10-11"   # 사전 날짜를 쓰는 둘째 문턱(ft-index-lint.sh ⑨ 제안서 줄 · r984) — 창 밖 카드가 «그 뒤» 인지 가르는 데 쓴다
BEFORE = "0000-00-00"          # PROPOSAL_FROM 스냅숏에 이미 있던 카드 = 그 전 추가 · 두 문턱 다 «옛 카드» 로 본다
EMPTY_MARK = "!EMPTY"
TIMEOUT_MARK = "!TIMEOUT"
TIMEOUT_WHY = "이력 조회 판정 불가 — git log 7초 상한 초과(통과 0 · WARN 으로 숨기지 않는다)"


def section_body(text):
    """«## 계약↔시험 대응표» 절 본문 줄 목록 — 절이 없으면 None."""
    lines = text.splitlines()
    for i, line in enumerate(lines):
        if not line.startswith(HEAD):
            continue
        body = []
        for nxt in lines[i + 1:]:
            if nxt.startswith("## "):
                break
            body.append(nxt)
        return body
    return None


def cells(line):
    """행 → 셀 목록. 이스케이프된 `\\|` 는 열 경계가 아니다(셀 안에서 `|` 로 되돌린다)."""
    body = line.strip()
    body = body[1:] if body.startswith("|") else body
    body = body[:-1] if body.endswith("|") else body
    return [c.strip().replace("\\|", "|") for c in re.split(r"(?<!\\)\|", body)]


def is_sep(line):
    cs = cells(line)
    return len(cs) >= 2 and all(SEP_CELL.match(c) for c in cs)


def parse_table(body):
    """(머리 열, 행들, 표 밖 글 줄 수) — 표가 없으면 (None, [], 표 밖 글 줄 수)."""
    tbl = [ln for ln in body if ln.startswith("|")]
    free = sum(1 for ln in body if ln.strip() and not ln.startswith("|"))
    if not tbl:
        return None, [], free
    return cells(tbl[0]), [cells(ln) for ln in tbl[1:] if not is_sep(ln)], free


def norm(s):
    return re.sub(r"\s+", " ", s.replace("**", "").replace("`", "").strip())


def label(con, n):
    m = re.match(r"\s*(C[0-9]+)", con or "")
    return m.group(1) if m else f"{n}행"


def ordinals(cell):
    """시험 칸의 «번호 목록» 만 — «①·③» 은 [1, 3]. 산문 속 번호(변이 설명·시험 이름)는 세지 않는다."""
    out = []
    for seg in re.split(r"[·,、/]", cell or ""):
        seg = seg.strip()
        if seg.startswith("시험"):
            seg = seg[2:].strip()
        if seg and all(ch in ORD or ch in "·,、" for ch in seg):
            out += [ORD[ch] for ch in seg if ch in ORD]
    return out


def pick(row, i):
    return row[i] if i is not None and i < len(row) else ""


def clash(rows, ci, ii, ei):
    """ⓑ 같은 입력 다른 기대."""
    if ii is None or ei is None:
        return []
    seen, out = {}, []
    for n, row in enumerate(rows, 1):
        key, want = norm(pick(row, ii)), norm(pick(row, ei))
        if not key or not want:
            continue
        lab = label(pick(row, ci), n)
        if key in seen and seen[key][1] != want:
            out.append(f"대응표: 같은 입력 다른 결과 — «{key}» → «{seen[key][1]}»({seen[key][0]}) ↔ «{want}»({lab})")
        elif key not in seen:
            seen[key] = (lab, want)
    return out


def order(rows, ci, ti):
    """ⓒ 시험 번호 순서 = 계약 순서."""
    out, prev = [], None
    for n, row in enumerate(rows, 1):
        lab = label(pick(row, ci), n)
        for o in ordinals(pick(row, ti)):
            if prev is not None and o < prev[0]:
                out.append(f"대응표: 시험 순서 ≠ 계약 순서 — «{prev[1]}» 시험 {prev[0]} 뒤 «{lab}» 시험 {o}")
            else:
                prev = (o, lab)
    return out


def infos(rows, ti, free):
    out = []
    if free:
        out.append(f"대응표 절에 표 밖 글 {free}줄 (표만 둔다)")
    plain = sum(1 for r in rows if pick(r, ti).strip() and not ordinals(pick(r, ti)))
    if plain:
        out.append(f"시험 칸 번호 없음 {plain}행 (①~⑳·ⓐ~ⓩ 만 순서 검사 대상)")
    nums = [o for r in rows for o in ordinals(pick(r, ti))]
    dup = sorted({n for n in nums if n is not None and nums.count(n) > 1})
    if dup:
        out.append(f"시험 번호 중복 {len(dup)}개 (한 시험이 계약 여럿을 덮음 — 허용)")
    return out


def findings(path):
    """(위반 목록, INFO 목록)."""
    body = section_body(open(path, encoding="utf-8").read())
    if body is None:
        return [f"절 없음: {HEAD} — 계약마다 시험 ≥ 1 (r984)"], []
    head, rows, free = parse_table(body)
    if head is None:
        return ["대응표: 표 없음 — «| 계약 | 입력 | 기대 | 시험 |» 머리 2줄 + 계약 행 1+ (r984)"], []
    if "계약" not in head or "시험" not in head:
        return [f"대응표: 머리에 «계약»·«시험» 열 없음 — 지금: {' | '.join(head)[:80]}"], []
    ci, ti = head.index("계약"), head.index("시험")
    if not rows:
        return ["대응표: 표 머리만 있고 계약 행 0 — 계약 행을 적는다"], []
    out = []
    for n, row in enumerate(rows, 1):
        if not pick(row, ci).strip():
            out.append(f"대응표: 표 {n}행 계약 칸 빔")
        if not pick(row, ti).strip():
            out.append(f"대응표: 계약 «{label(pick(row, ci), n)}» 시험 없음 — 계약마다 시험 ≥ 1")
    out += clash(rows, ci, head.index("입력") if "입력" in head else None, head.index("기대") if "기대" in head else None)
    out += order(rows, ci, ti)
    return out, infos(rows, ti, free)


def git_names(base, args, timeout=7):
    """git 출력의 이름 줄 → basename 집합(빈 줄·실패는 빈 집합) — 이력 diff 0(트리·색인만 읽는다)."""
    r = subprocess.run(["git", "-C", base] + args, capture_output=True, text=True, timeout=timeout)
    return {os.path.basename(ln.strip()) for ln in r.stdout.splitlines() if ln.strip()}


def old_names(base, spec):
    """PROPOSAL_FROM 직전 커밋 트리에 있던 카드들 — 창 밖 카드를 «그 전» 과 «그 뒤» 로 가른다."""
    r = subprocess.run(["git", "-C", base, "rev-list", "-1", f"--before={PROPOSAL_FROM} 00:00:00", "HEAD"],
                       capture_output=True, text=True, timeout=7)
    rev = r.stdout.split()
    return git_names(base, ["ls-tree", "-r", "--name-only", rev[0], "--"] + spec) if rev else set()


def build_map(paths, sw):
    """경로 basename → «이름\t날짜» 텍스트. git 호출 1회(7초 상한) — 넘치면 subprocess.TimeoutExpired.

    --since=<스위치> 1개로 그 «뒤» 커밋만 읽는다(r1062) — 판정은 report 의 같은 비교 하나뿐이라 그대로다.
    창 밖 카드는 실제 날짜 대신 표식(BEFORE · PROPOSAL_FROM)을 쓴다 — 두 문턱의 판정은 같고, 읽는 이력이 짧다.
    """
    base = os.path.dirname(os.path.abspath(paths[0]))
    dirs = sorted({os.path.dirname(os.path.abspath(p)) for p in paths})
    spec = ["."] if dirs == [base] else dirs
    r = subprocess.run(["git", "-C", base, "log", "--diff-filter=A", f"--since={sw} 00:00:00", "--format=%ad", "--date=short", "--name-only", "--"] + spec,
                       capture_output=True, text=True, timeout=7)
    out, cur = {}, None
    for line in r.stdout.splitlines():
        line = line.strip()
        if DATE_LINE.match(line):
            cur = line
        elif line and cur:
            out.setdefault(os.path.basename(line), cur)   # 사전 키 = basename(카드 이름) — 같은 이름 2장은 같은 날로 본다
    for name in old_names(base, spec):
        out.setdefault(name, BEFORE)
    for name in git_names(base, ["ls-files", "--"] + spec):
        out.setdefault(name, PROPOSAL_FROM)   # 창 밖인데 10-11 스냅숏에 없음 = 10-11 뒤·창 이전 추가
    return "".join(f"{k}\t{v}\n" for k, v in out.items()) or EMPTY_MARK + "\n"


def load_map(paths, sw):
    """(사전, 판정 불가 사유). 사전 파일이 있으면 재조회 0 — 빈 사전도 «제공됨» 으로 읽는다."""
    f = os.environ.get(MAPFILE_ENV, "")
    text = ""
    if f:
        text = open(f, encoding="utf-8").read()
        if TIMEOUT_MARK in text:
            return {}, TIMEOUT_WHY
    if not text.strip():
        try:
            text = build_map(paths, sw)
        except (subprocess.TimeoutExpired, OSError):
            if f:
                open(f, "w", encoding="utf-8").write(TIMEOUT_MARK + "\n")
            return {}, TIMEOUT_WHY
        if f:
            open(f, "w", encoding="utf-8").write(text)
    out = {}
    for line in text.splitlines():
        name, _, day = line.partition("\t")
        if name and day and not name.startswith("!"):
            out.setdefault(name.strip(), day.strip())
    return out, ""


def strict_from():
    sw = os.environ.get(SWITCH_ENV, STRICT_DEFAULT)
    if not re.match(r"^\d{4}-\d{2}-\d{2}$", sw):
        return None
    try:
        datetime.strptime(sw, "%Y-%m-%d")
    except ValueError:
        return None
    return sw


def shown(added):
    """added= 칸의 사람용 표기 — 표식·빈 값도 읽을 수 있게."""
    if added == BEFORE:
        return f"{PROPOSAL_FROM} 이전"
    if added == PROPOSAL_FROM:
        return f"{PROPOSAL_FROM} 이후·창 이전"
    return added or "이력 없음"


def report(path, added, sw):
    """카드 1장 출력 — BAD 수를 돌려준다."""
    strict = added >= sw
    bad, info = findings(path)
    for line in info:
        print(f"INFO\t{path}\t{line}")
    if not bad:
        print(f"OK\t{path}\tadded={shown(added)} · 스위치 {sw} · strict={int(strict)}")
        return 0
    for line in bad:
        tail = "" if strict else f" (스위치 전 WARN · {sw} 이후 추가 카드부터 REJECT)"
        print(f"{'BAD' if strict else 'WARN'}\t{path}\t{line}{tail}")
    return len(bad) if strict else 0


def main(argv):
    flags = [a for a in argv[1:] if a.startswith("--")]
    args = [a for a in argv[1:] if not a.startswith("--")]
    if not args:
        print(f"usage: {argv[0]} <card.md> [more…] [--map-only]", file=sys.stderr)
        return 2
    sw = strict_from()
    if sw is None and "--map-only" not in flags:
        print(f"BAD\t*\t날짜 스위치 꼴 오류 — {SWITCH_ENV}={os.environ.get(SWITCH_ENV, STRICT_DEFAULT)} (YYYY-MM-DD)")
        print(f"ERROR {SWITCH_ENV} 꼴 오류 rc3", file=sys.stderr)
        return 3
    dates, why = load_map([p for p in args if os.path.isfile(p)] or args, sw or STRICT_DEFAULT)
    if why:
        print(f"BAD\t*\t{why}")
        print("ERROR 이력 조회 판정 불가 rc3", file=sys.stderr)
        return 3
    if "--map-only" in flags:
        return 0
    nb = 0
    for path in args:
        if not os.path.isfile(path):
            print(f"BAD\t{path}\t파일 없음")
            nb += 1
            continue
        nb += report(path, dates.get(os.path.basename(os.path.abspath(path)), date.today().isoformat()), sw)   # 사전에 없음 = 이력 없음(미커밋) → 지금처럼 오늘 날짜
    return 1 if nb else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
