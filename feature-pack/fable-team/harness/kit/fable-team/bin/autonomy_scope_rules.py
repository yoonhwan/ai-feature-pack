"""autonomy_scope_rules.py — 범위 승인 분류기의 «경로 분류표 · 종류 키 · DDL 적용 기록» (r466 · autonomy_scope_classify.py 가 부른다).

분류표 = 위에서부터 첫 일치 (종류, 종류 키, 정규식) — 종류 ∈ forbid·docs·code. 기본 내장 = BYZ(옛 PATH_RULES·DOC_RE 그대로).
팩 표 = 키트 templates/scope-classes-pack.tsv(`--table <파일>`) · 줄 꼴 `종류<TAB>키<TAB>정규식` · `#` 주석.
종류 키 = FORBID 사유의 «종류»(학습 단위 · r466 5b) — 소문자·숫자·하이픈만. secret 은 학습 불가(오빠 승인으로도 종류 저장 0)."""
import os
import re

KIND_RE = re.compile(r"^[a-z][a-z0-9-]*$")
NEVER_LEARN = {"secret"}
LABEL = {"ddl": "DDL", "deploy": "배포·인프라", "key": "키", "billing": "과금", "deps": "의존", "global-rule": "전역 규칙"}
BYZ_TABLE = [(c, k, re.compile(rx, re.I)) for c, k, rx in [
    ("forbid", "ddl", r"(^|/)migrations/|\.sql$|^alembic/"),
    ("forbid", "deploy", r"^\.github/workflows/|^infra/|^terraform/|cloudbuild|(^|/)Dockerfile|^deploy/|^scripts/deploy"),
    ("forbid", "key", r"^secrets/|(^|/)[^/]*\.env[^/]*$|\.cred$"),
    ("forbid", "billing", r"^docs/architect/COST_BASE_TABLE\.md$"),
    ("forbid", "deps", r"(^|/)(package\.json|pyproject\.toml|requirements[^/]*\.txt)$|(^|/)[^/]*[-.]lock[^/]*$"),
    ("forbid", "global-rule", r"(^|/)CLAUDE\.md$|(^|/)\.claude/|COMM-GUIDE|(^|/)harness/kit/|(^|/)scripts/harness-install/"),
    ("docs", "docs", r"^(design|docs)/.*\.md$"),   # 확장자만으로 문서 판정 0 — design/ 아래 .py·.sh 는 code, 루트 .md 는 docs 아님
    # 낱말 금지는 문서 줄 아래 — 경로로 지정한 문서 금지만 문서 줄 위(r514)
    ("forbid", "billing", r"billing|credit|payment|pricing|toss|subscription"),
    ("forbid", "key", r"credential"),
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


STATUS_KIND = {"D": "delete", "C": "copy", "T": "type"}


def judge_row(table, row, ddl_ok):   # (옛 모드, 새 모드, 상태, [경로…]) → (종류, 키, 사유|None) · ddl_ok(경로) = 적용 기록 있는 새 sql
    om, nm, st, paths = row
    classes = [path_class(table, p) for p in paths]
    bad = next(((k, p) for (c, k), p in zip(classes, paths) if c == "forbid"), None)
    if st[0] == "R":   # 카드 상태 폴더 이동 = 내용 동일(R100) ∧ 모드 같음 ∧ 파일 이름 같음 ∧ 양쪽 docs
        if st == "R100" and om == nm and os.path.basename(paths[0]) == os.path.basename(paths[1]) and all(c == "docs" for c, _ in classes):
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
