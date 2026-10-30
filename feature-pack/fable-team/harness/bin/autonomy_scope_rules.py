"""autonomy_scope_rules.py — 범위 승인 분류기의 «경로 분류표 · 종류 키 · DDL 적용 기록» (r466 · autonomy_scope_classify.py 가 부른다).

분류표 = 위에서부터 첫 일치 (종류, 종류 키, 정규식) — 종류 ∈ forbid·docs·code. 기본 내장 = BYZ(옛 PATH_RULES·DOC_RE 그대로).
팩 표 = 키트 templates/scope-classes-pack.tsv(`--table <파일>`) · 줄 꼴 `종류<TAB>키<TAB>정규식` · `#` 주석.
종류 키 = FORBID 사유의 «종류»(학습 단위 · r466 5b) — 소문자·숫자·하이픈만. secret 은 학습 불가(오빠 승인으로도 종류 저장 0)."""
import os
import re

KIND_RE = re.compile(r"^[a-z][a-z0-9-]*$")
NEVER_LEARN = {"secret"}
NEVER_LEARN = NEVER_LEARN | {"repo-outside", "scope-table", "mode"}   # 경계 종류 = 한 번 학습되면 범위 전체가 열린다(r1208 · h569)
LABEL = {"ddl": "DDL", "deploy": "배포·인프라", "key": "키", "billing": "과금", "deps": "의존", "global-rule": "전역 규칙"}
BYZ_TABLE = [(c, k, re.compile(rx, re.I)) for c, k, rx in [
    ("forbid", "ddl", r"(^|/)migrations/|\.sql$|^alembic/"),
    ("forbid", "deploy", r"^\.github/workflows/|^infra/|^terraform/|cloudbuild|(^|/)Dockerfile|^deploy/|^scripts/deploy"),
    ("forbid", "key", r"(^|/)secrets/|(^|/)[^/]*\.env[^/]*$|\.cred$"),
    ("forbid", "billing", r"^docs/architect/COST_BASE_TABLE\.md$"),
    ("forbid", "deps", r"(^|/)(package\.json|pyproject\.toml|requirements[^/]*\.txt)$|(^|/)[^/]*[-.]lock[^/]*$"),
    ("forbid", "global-rule", r"(^|/)CLAUDE\.md$|(^|/)\.claude/|COMM-GUIDE|(^|/)harness/kit/|(^|/)scripts/harness-install/"),
    ("docs", "docs", r"^(design|docs)/.*\.md$"),   # 확장자만으로 문서 판정 0 — design/ 아래 .py·.sh 는 code, 루트 .md 는 docs 아님
    # 낱말 금지는 문서 줄 아래 — 경로로 지정한 문서 금지만 문서 줄 위(r514)
    ("forbid", "billing", r"billing|credit|payment|pricing|toss|subscription"),
    # 시험 파일 경로는 «credential» 낱말 금지 밖(r909 칸 2 · room 3395 · DA⑥ 반례 2 로 좁힘): 파일 이름이 *.test.*·*_test.*·test_*.* 인
    # 코드 파일(.py .ts .tsx .js .sh)만 — 경로 어디든 .json·.pem·.key·.env·secrets/ 가 있으면 예외 0(실값 파일은 그대로 막는다)
    ("code", "test-file", r"(?i)^(?!.*(?:\.json|\.pem|\.key|\.env|(?:^|/)secrets/))(?:.*/)?(?:[^/]*\.(?:test|spec)|[^/]*_test|test_[^/]*)\.(?:py|ts|tsx|js|sh)$"),
    ("forbid", "key", r"credential"),
    # 팀 폴더 첫 문서 착지(r559) — 낱말 금지 «아래»(팀 폴더 안이라도 결제 낱말 경로는 금지 유지 · ⓗ)
    ("code", "pytest", r"^design/teams/[^/]+/(.*/)?(test_[^/]*\.py|[^/]*_test\.py|conftest\.py)$"),   # 시험 도구가 모으는 파일 = 계속 코드
    ("docs", "team-file", r"^design/teams/[^/]+/(?!.*\.(py|sh)$).+$"),                             # 팀 폴더의 실행 안 되는 파일
    ("docs", "team-evidence", r"^design/teams/[^/]+/evidence[^/]*/.+\.sh$"),                        # 증거 폴더 .sh 만(pytest 가 안 모은다) — .py 는 code(import 부작용 · H3)
    ("code", "code", r"."),
]]


class TableErr(Exception):
    pass


def load_table(path):   # None = 기본 내장 BYZ · 파일 = 팩 표(틀린 줄 = 오류 · 닫힌 쪽)
    if not path:
        return BYZ_TABLE
    rows = []
    with open(path, encoding="utf-8") as f:
        for n, line in enumerate(f, 1):
            if not line.strip() or line.startswith("#"):
                continue
            cols = line.rstrip("\n").split("\t")
            if len(cols) != 3 or cols[0] not in ("forbid", "docs", "code") or not KIND_RE.match(cols[1]):
                raise TableErr("분류표 %s:%d 꼴 틀림" % (os.path.basename(path), n))
            rows.append((cols[0], cols[1], re.compile(cols[2])))
    if not rows:
        raise TableErr("분류표 빈 파일: %s" % path)
    return rows


def path_class(table, path):   # → (종류, 키) · 어떤 줄에도 안 맞으면 forbid repo-outside(조용한 통과 0)
    for cls, kind, rx in table:
        if rx.search(path):
            return cls, kind
    return "forbid", "repo-outside"


def forbid_text(kind, path):
    return "%s 경로: %s" % (LABEL.get(kind, kind), path)


ENV_TEMPLATE = re.compile(r"\.env\.(?:example|sample|template)$")   # 값 없는 견본 파일(r909 칸 3)
DOTENV_LINE = re.compile(r"^\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=(.*)$")
ENV_PLACEHOLDER = re.compile(r"^<[^>]*>$")


def dotenv_value(rest):   # 한 줄의 «값» 을 dotenv 규칙으로 — 따옴표·뒤 #주석 · 닫는 따옴표 없음 = None(파싱 실패)
    rest = rest.lstrip()
    q = rest[:1]
    if q in ("'", '"'):
        j = 1
        while j < len(rest):
            if rest[j] == "\\" and q == '"':
                j += 2
                continue
            if rest[j] == q:
                tail = rest[j + 1:].strip()
                return None if tail and not tail.startswith("#") else rest[1:j]
            j += 1
        return None   # 닫는 따옴표 없음(여러 줄 값 = 줄 단위 규칙 위반 · 닫힌 쪽)
    return re.split(r"\s+#", rest, 1)[0].strip()


def _closes(s, q, start=0):   # s[start:] 에 q 를 닫는 따옴표가 있나(큰따옴표는 \ 이스케이프)
    j = start
    while j < len(s):
        if s[j] == "\\" and q == '"':
            j += 2
            continue
        if s[j] == q:
            return True
        j += 1
    return False


def quoted_continuation_lines(full):   # 바뀐 뒤 전문에서 «여러 줄 따옴표 값의 둘째 줄 이후» 줄 번호 — 그 줄은 값의 일부다
    inside, q = set(), ""
    for n, ln in enumerate(full.split("\n"), 1):
        if q:
            inside.add(n)
            q = "" if _closes(ln, q) else q
            continue
        m = DOTENV_LINE.match(ln)
        rest = m.group(2).lstrip() if m else ""
        if rest[:1] in ("'", '"') and not _closes(rest, rest[0], 1):
            q = rest[0]
    return inside


def env_added_values_ok(full, items):   # .env.example 류: «추가된 대입 줄 각각» 의 값이 빈 값 또는 <…> 자리표시일 때만(r909 r3) · 전문 = 따옴표 값 «안» 줄 판별용(없으면 FORBID)
    if full is None:
        return False
    inside = quoted_continuation_lines(full)
    for lineno, text in items:
        if lineno in inside:
            return False   # 여러 줄 따옴표 값의 안쪽 줄 = 값의 일부(주석처럼 보여도 값)
        s = text.strip()
        if not s or s.startswith("#"):
            continue
        m = DOTENV_LINE.match(text)
        if not m:
            return False   # 대입 줄이 아닌 추가 줄 = 해석 실패(닫힌 쪽)
        v = dotenv_value(m.group(2))
        if v is None or (v and not ENV_PLACEHOLDER.match(v)):
            return False
    return True


STATUS_KIND = {"D": "delete", "C": "copy", "T": "type"}
TEAM_CARD = re.compile(r"^(design/teams/[^/]+)/indices/(?:대기|진행|완성|보류)/[^/]+$")   # 팀 카드 폴더 = 같은 팀의 네 상태 폴더(r559)


def same_card(table, om, nm, a, b):   # 같은 팀 카드 폴더 사이 같은 이름 이동 = 모드 같음 ∧ 파일 이름 같음 ∧ 양쪽 docs(내용 변화 무관 · r559)
    ma, mb = TEAM_CARD.match(a), TEAM_CARD.match(b)
    return bool(ma and mb and ma.group(1) == mb.group(1) and os.path.basename(a) == os.path.basename(b) and om == nm
                and all(path_class(table, p)[0] == "docs" for p in (a, b)))


def pair_card_moves(table, rows):   # D+A 로 잡힌 같은 카드 이동(유사도 낮음) → R100 한 행 · 짝 없는 D 는 그대로(ⓑ·ⓒ)
    added, used, out = {}, set(), []
    for r in rows:
        if r[2] == "A":
            added.setdefault((r[1], os.path.basename(r[3][0])), r)
    for r in rows:
        a = added.get((r[0], os.path.basename(r[3][0]))) if r[2] == "D" else None
        if a is not None and same_card(table, r[0], a[1], r[3][0], a[3][0]):
            out.append((r[0], a[1], "R100", [r[3][0], a[3][0]]))
            used.add(id(a))
            continue
        if id(r) not in used:
            out.append(r)
    return out


def kind_of(table, path, env_ok):   # 분류표 판정 + .env.example 류 «이름만» 예외(r909 칸 3) — 실값이 있으면 예외 없음(닫힌 쪽)
    cls, kind = path_class(table, path)
    return ("code", "code") if cls == "forbid" and kind == "key" and ENV_TEMPLATE.search(path) and env_ok(path) else (cls, kind)


def judge_row(table, row, ddl_ok, env_ok=lambda p: False):   # (옛 모드, 새 모드, 상태, [경로…]) → (종류, 키, 사유|None) · ddl_ok(경로) = 적용 기록 있는 새 sql · env_ok(경로) = .env.example 류에 «이름만» 추가
    om, nm, st, paths = row
    classes = [kind_of(table, p, env_ok) for p in paths]
    bad = next(((k, p) for (c, k), p in zip(classes, paths) if c == "forbid"), None)
    if st[0] == "R":   # 카드 상태 폴더 이동 = 같은 팀 카드 폴더 사이 같은 이름/모드/양쪽 docs(유사도 무관) 또는 내용 동일(R100)
        same = os.path.basename(paths[0]) == os.path.basename(paths[1])
        if om == nm and all(c == "docs" for c, _ in classes) and (same_card(table, om, nm, paths[0], paths[1]) or (st == "R100" and same)):
            return "docs", "move", None
        return "forbid", "rename" if st == "R100" else "move-changed", "상태 %s: %s" % (st, " → ".join(paths))
    if st[0] not in "AM":
        return "forbid", STATUS_KIND.get(st[0], "status"), "상태 %s: %s" % (st, " → ".join(paths))   # 삭제·복사·타입 변경
    if (st[0] == "M" and om != nm) or (st[0] == "A" and nm != "100644"):
        return "forbid", "mode", "모드 %s→%s: %s" % (om, nm, paths[0])
    new_sql = bool(bad) and bad[0] == "ddl" and st[0] == "A" and bad[1].endswith(".sql")
    if new_sql and ddl_ok(bad[1]):
        return "docs", "ddl-recorded", None
    if bad:
        return "forbid", "ddl-no-record" if new_sql else bad[0], forbid_text(bad[0], bad[1])
    return classes[-1][0], classes[-1][1], None


def apply_learned(judged, learned):   # 학습된 종류의 forbid 줄 → docs (secret 제외) · 쓰인 키 목록(순서 유지)
    used = []
    for i, (cls, kind, _) in enumerate(judged):
        if cls == "forbid" and kind in learned and kind not in NEVER_LEARN:
            judged[i] = ("docs", kind, None)
            if kind not in used:
                used.append(kind)
    return used


def load_ddl_records(path):   # 줄 꼴 `기록 파일(리포 기준 경로)<TAB>줄 정규식` — 정규식에 {sql} 이 있으면 그 sql 파일 이름으로 바꾼다
    if not path:
        return []
    out = []
    with open(path, encoding="utf-8") as f:
        for n, line in enumerate(f, 1):
            if not line.strip() or line.startswith("#"):
                continue
            cols = line.rstrip("\n").split("\t")
            if len(cols) != 2:
                raise TableErr("DDL 기록표 %s:%d 꼴 틀림" % (os.path.basename(path), n))
            out.append((cols[0], cols[1]))
    return out


def ddl_recorded(records, sql_path, added, show):   # added = PR 추가 줄 · show(경로) = sha 트리의 그 파일 본문(없으면 "")
    name = re.escape(os.path.basename(sql_path))
    for where, rx in records:
        pat = re.compile(rx.replace("{sql}", name))
        text = added if where == "-" else show(where)
        if any(pat.search(ln) for ln in text.split("\n")):
            return True
    return False
