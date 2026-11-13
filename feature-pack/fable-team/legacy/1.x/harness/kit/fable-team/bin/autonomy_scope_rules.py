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
    # 잠금 파일 이름만(r1211): «-lock»·«.lock» 뒤에 붙는 것은 b·file·.json·.yaml·.yml·.toml·.hcl 만 — «-locked.png» 같은 보통 파일은 deps 아님
    ("forbid", "deps", r"(^|/)(package\.json|pyproject\.toml|requirements[^/]*\.txt)$|(^|/)([^/]*[-.]lock(b|file|\.(json|ya?ml|toml|hcl))?|npm-shrinkwrap\.json)$"),
    ("forbid", "global-rule", r"(^|/)CLAUDE\.md$|(^|/)\.claude/|COMM-GUIDE|(^|/)harness/kit/|(^|/)scripts/harness-install/"),
    ("docs", "docs", r"^(design|docs)/.*\.md$"),   # 확장자만으로 문서 판정 0 — design/ 아래 .py·.sh 는 code, 루트 .md 는 docs 아님
    # 낱말 금지는 문서 줄 아래 — 경로로 지정한 문서 금지만 문서 줄 위(r514)
    # 팀 폴더의 «그림·PDF 증거» 는 과금 낱말 줄 «위»(r1248 · 판정 2997) — credential 낱말·실행 확장자 중간 이름 없음 · 모드는 judge_row 가 100644 로 닫는다
    ("docs", "team-billing-doc", r"^design/teams/[^/]+/(?!.*credential)(?=.*(?:billing|credit|payment|pricing|toss|subscription))(?!(?:.*/)?[^/]*\.(?:sh|py|bash|zsh|command|js|ts)\.[^/]*$).*\.(?:png|jpe?g|gif|webp|pdf)$"),
    ("forbid", "billing", r"billing|credit|payment|pricing|toss|subscription"),
    # 시험 파일 경로는 «credential» 낱말 금지 밖(r909 칸 2 · room 3395 · DA⑥ 반례 2 로 좁힘): 파일 이름이 *.test.*·*_test.*·test_*.* 인
    # 코드 파일(.py .ts .tsx .js .sh)만 — 경로 어디든 .json·.pem·.key·.env·secrets/ 가 있으면 예외 0(실값 파일은 그대로 막는다)
    ("code", "test-file", r"(?i)^(?!.*(?:\.json|\.pem|\.key|\.env|(?:^|/)secrets/))(?:.*/)?(?:[^/]*\.(?:test|spec)|[^/]*_test|test_[^/]*)\.(?:py|ts|tsx|js|sh)$"),
    ("forbid", "key", r"credential"),
    # 하네스 research·inventory «원자료»(r1521): 데이터 확장자·SHA256SUMS 는 docs · .py .sh .js .ts 와 실행 확장자 중간 이름(x.py.txt)은 code(import 부작용 H3) · 모드는 judge_row 가 100644 로 닫는다 · .md 는 위 :21 docs 줄 그대로(이 줄 확장자에 .md 없음)
    ("docs", "research-data", r"^design/harness/(?:research|inventory)/(?!(?:.*/)?[^/]*\.(?:py|sh|js|ts)\.[^/]*$)(?:.*/)?(?:SHA256SUMS|[^/]*\.(?:json|jsonl|txt|tsv|html|log))$"),
    # 팀 폴더 첫 문서 착지(r559) — 낱말 금지 «아래»(팀 폴더 결제 낱말: 그림·PDF 증거(100644)만 판정 2997 로 문서 · .json 등 데이터 파일은 실행기 입력일 수 있어 금지 유지 · DA②)
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


# r1778 카드 범위 — 카드 «- 대상:» 줄과 «## 구현 범위» 절의 backtick 경로만 목록으로 읽는다(제외 줄·그 밖 산문 무시 · 닫힌 쪽)
CARD_SPEC = re.compile(r"^[ \t]*[-*][ \t]*대상[ \t]*[:：(]")            # «- 대상:» · «- 대상(…)» 만 — «- 대상 밖:» 은 목록 아님(DA HOLD 292120)
CARD_EXCLUDE = re.compile(r"^[ \t]*[-*][ \t]*(?:안[ \t]*하는[ \t]*것|제외|대상[ \t]*밖)")   # 구현 범위 절 안의 제외 줄도 목록 아님
CARD_SCOPE_HEAD = re.compile(r"^##[ \t]*구현[ \t]*범위")
CARD_HEAD = re.compile(r"^##[ \t]")
CARD_TICK = re.compile(r"`([^`\n]+)`")
CARD_PATH = re.compile(r"^(?:\./)?[^\s`:*?<>|\"'«»→·]+(?:/[^\s`:*?<>|\"'«»→·]+)*/?$")   # 경로 꼴만(예시 `a/**`·`sym:12`·`x → y` 는 목록 아님)


def card_scope_paths(text, root=None):   # 카드 본문 → 경로 집합(리포 기준 상대 · 폴더는 끝 «/») · 못 읽음 = 빈 집합(닫힌 쪽)
    out, inside = set(), False
    for line in (text or "").splitlines():
        if CARD_EXCLUDE.match(line):
            continue
        if CARD_SCOPE_HEAD.match(line):
            inside = True
            continue
        if inside and CARD_HEAD.match(line):
            inside = False
        if not (inside or CARD_SPEC.match(line)):
            continue
        for tok in CARD_TICK.findall(line):
            if "/" not in tok or not CARD_PATH.match(tok):
                continue
            tok = tok[2:] if tok.startswith("./") else tok
            if tok.startswith("/"):   # 절대 경로 = 이 리포 안일 때만(밖이면 목록 아님) · 실경로로 풀어 비교(/var → /private/var 같은 심링크)
                pre = os.path.realpath(root or "").rstrip("/") + "/"
                tok = os.path.realpath(tok)
                if not root or not tok.startswith(pre):
                    continue
                tok = tok[len(pre):]
            out.add(tok)
    return out


def card_scope_file(path, root=None):   # 카드 파일 → 집합 · 파일 없음·읽기 실패 = 빈 집합(닫힌 쪽 · 판정은 행마다 불러도 1회 읽기)
    if not path:
        return set()
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            return card_scope_paths(f.read(), root)
    except OSError:
        return set()


def in_card_scope(scope, path):   # 목록 안 = 같은 경로 ∨ «끝 /» 로 명시된 폴더 아래 · 폴더를 안 적었으면 그 하위 파일은 밖(⑤)
    return bool(scope) and (path in scope or any(p.endswith("/") and path.startswith(p) for p in scope))


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


def judge_row(table, row, ddl_ok, env_ok=lambda p: False, card_scope=None):   # (옛 모드, 새 모드, 상태, [경로…]) → (종류, 키, 사유|None) · ddl_ok(경로) = 적용 기록 있는 새 sql · env_ok(경로) = .env.example 류에 «이름만» 추가 · card_scope = 카드 «대상» 경로 집합(D 판정용 · 없으면 지금과 같다)
    om, nm, st, paths = row
    classes = [kind_of(table, p, env_ok) for p in paths]
    bad = next(((k, p) for (c, k), p in zip(classes, paths) if c == "forbid"), None)
    wrong_mode = next((p for (c, k), p in zip(classes, paths) if k in ("team-billing-doc", "research-data") and st[0] in "AMR" and (nm != "100644" or (st[0] != "A" and om != "100644"))), None)
    if wrong_mode:   # 과금 낱말 그림·PDF(r1248)와 하네스 research·inventory 원자료(r1521)는 일반 파일(100644)일 때만 문서 — 심링크·실행 비트·같은 100755 수정 M = mode(학습 불가)
        return "forbid", "mode", "모드 %s→%s: %s" % (om, nm, wrong_mode)
    if st[0] == "R":   # 카드 상태 폴더 이동 = 같은 팀 카드 폴더 사이 같은 이름/모드/양쪽 docs(유사도 무관) 또는 내용 동일(R100)
        same = os.path.basename(paths[0]) == os.path.basename(paths[1])
        if om == nm and all(c == "docs" for c, _ in classes) and (same_card(table, om, nm, paths[0], paths[1]) or (st == "R100" and same)):
            return "docs", "move", None
        return "forbid", "rename" if st == "R100" else "move-changed", "상태 %s: %s" % (st, " → ".join(paths))
    if st[0] == "D" and card_scope and all(in_card_scope(card_scope, p) for p in paths):   # r1778 §3 — 카드가 지목한 파일 삭제는 경로 분류로(경계 종류는 그대로 ④)
        bad = next(((k, p) for (c, k), p in zip(classes, paths) if c == "forbid"), None)
        return ("forbid", bad[0], forbid_text(bad[0], bad[1])) if bad else (classes[-1][0], classes[-1][1], None)
    if st[0] not in "AM":
        return "forbid", STATUS_KIND.get(st[0], "status"), "상태 %s: %s" % (st, " → ".join(paths))   # 삭제·복사·타입 변경
    new_test_sh = st == "A" and om == "000000" and nm == "100755" and re.search(r"(^|/)tests/test_[^/]*\.sh$", paths[0]) and classes[0][0] == "code"   # r1866: 새 시험 sh 실행 비트만 통과(M·심링크·helper = mode)
    if not new_test_sh and ((st[0] == "M" and om != nm) or (st[0] == "A" and nm != "100644")):
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


# ── r1577 상시 승인 D2 «크리티컬 종류» (카드 r1577-approval-split-critical-slack-only · DA R3) ──
#   되돌릴 수 있는 병합은 팀 master 가 결정한다. 되돌릴 수 «없는» 일만 오빠 Slack 답글로 남긴다.
#   ★scope·D1 의 FORBID 표와 «분리»된 함수다(표에 합치면 scope 승인이 같이 닫힌다 — 변이 M9)★
#   판정 대상 = merge-base..head 의 «추가된 줄·추가된 파일» · 글자 규칙이라 모든 언어 해석 0
CRIT_LAUNCHD = re.compile(r"(^|/)(LaunchAgents|LaunchDaemons)/[^/]*\.plist$", re.I)
CRIT_CONFIG = re.compile(r"(^|/)(\.codex/)?config\.toml$|(^|/)(cliproxy|headroom)[^/]*\.(json|ya?ml|toml|conf|ini)$|"
                         r"(^|/)\.env(\.[^/]*)?$", re.I)   # R1: 외부 설정은 «새 파일» 만이 아니라 «있던 파일의 값 변경» 도 크리티컬
CRIT_APIKEY_PATH = re.compile(r"(^|/)models\.json$", re.I)   # models.json = apiKey 칸만(카드 ⓒ② 문구 그대로 — 범위 임의 확장 0)
CRIT_APIKEY = re.compile(r"apiKey", re.I)
CRIT_DESTROY = re.compile(
    r"\b(?:kill|pkill|killall)\b|"
    r"\blaunchctl\s+(?:bootout|unload|remove)\b|"
    r"\brm\s+-[A-Za-z]*[rR][A-Za-z]*[fF]\b|\brm\s+-[A-Za-z]*[fF][A-Za-z]*[rR]\b|"
    r"\btmux\s+kill-(?:server|session)\b|"
    r"\bgit\s+push\b[^\n]*?(?:--force(?:-with-lease)?|\s-[A-Za-z]*f[A-Za-z]*\b|--delete\b|\s-d\b|\s\+[^\s]+|\s:)\S*|"
    r"\bgit\s+branch\b[^\n]*?(?:\s-D\b|\s--delete\b)|"
    r"\bDROP\s+(?:TABLE|DATABASE)\b|\bFLUSH(?:ALL|DB)\b", re.I)


# ── r1597 «시험이 자기가 만든 임시 폴더를 끝에 지우는 줄» 예외 (카드 r1597 · 오빠 Slack 승인 ts=1794320041.110549) ──
#   destroy 판정은 줄 글자만 본다 — 그래서 시험의 `T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT` 도 destroy 가 된다(r1593 ⓔ 실측).
#   세 조건이 «모두» 참인 그 줄만 뺀다: ① 경로가 tests/ ② 줄이 `trap '<rm -rf "$V">' EXIT` 꼴이고 trap 안 명령이 그 rm -rf 하나뿐
#   ③ 같은 파일(바뀐 뒤 전문 · show)에서 V 대입이 정확히 1번이고 그 값이 `$(mktemp -d …)`. 하나라도 거짓이면 지금처럼 destroy(닫힌 쪽).
#   ★NG1(r1597 arch 인수)★ 줄 «전체» 가 trap 하나일 때만 — 앞에 다른 명령(`rm -rf / ;` · `kill -9 1 &&` · `psql … DROP TABLE ;`)이 붙으면 예외 0.
#     예외인 앞머리는 «같은 변수의 mktemp -d 대입» 하나뿐(r1592 실사건이 한 줄 꼴이라 필요 — 변수까지 같아야 한다).
#   ★NG2(r1597 arch 재인수)★ 앞머리 값은 «닫힌 꼴» 만: V="$(mktemp -d)" · V=$(mktemp -d) · 템플릿 인자 1개(글자 [\w./-] 만).
#     `$(mktemp -d && rm -rf /)` · `$(mktemp -d | xargs rm -rf)` · `$(mktemp -d) && kill …` · `$(mktemp -d) $(…)` = destroy.
MKTEMP_VALUE = r"\"?\$\(\s*mktemp\s+-d(?:\s+[\w./-]+)?\s*\)\"?"
TRAP_LINE = re.compile(r"^\s*(?:(?P<pre>[A-Za-z_][A-Za-z0-9_]*)=\s*" + MKTEMP_VALUE + r"\s*;\s*)?"
                       r"trap\s+(?P<q>['\"])(?P<body>.+?)(?P=q)\s+EXIT\s*;?\s*$")
TRAP_RM_RF_BODY = re.compile(r'^rm -rf "\$\{?([A-Za-z_][A-Za-z0-9_]*)\}?"$')
# DA② R1: 대입은 «줄 머리» 에서 «값 전체» 가 mktemp -d 여야 한다 — re.search 로 본문 어딘가의 접두만 보면 주석 줄·`$(mktemp -d)/../..` 가 통과한다
# NG3: 재대입을 «줄 머리» 로만 세면 `true; T=/` · `local T=/` · `T+=/../..` · `read -r T` · `for T in /` 가 새어나간다 — 맨 이름 출현으로 센다
MKTEMP_LINE = r"(?m)^[ \t]*(?:export[ \t]+)?%s[ \t]*=[ \t]*"   # 줄 머리 대입만(주석·문자열 속 대입은 안 센다)
MKTEMP_NAME = r"(?<![$\w{])%s(?![A-Za-z0-9_])"                # «쓰는 자리»($T·${T})가 아닌 맨 이름 — 대입·재대입·read·for 를 전부 센다
MKTEMP_CASSIGN = r"\$\{%s:?="                                    # ${T:=…}·${T=…} 조건부 대입 = 읽기가 아니라 «추가 대입»(DA② R2)
MKTEMP_TAIL = r"[ \t]*(?:;[ \t]*trap\s+.*)?$"                  # 값 뒤 = 줄 끝 또는 «; trap …» 하나


def mktemp_trap_exempt(path, txt, show=None):   # → True = «그 시험이 방금 만든 임시 폴더를 지우는» 줄
    if not path or not (path.startswith("tests/") or "/tests/" in path):
        return False
    m = TRAP_LINE.match(txt or "")   # 줄 전체가 trap 하나(+ 같은 변수의 mktemp 대입 하나) — r1597 NG1
    var = TRAP_RM_RF_BODY.match(m.group("body")) if m else None
    if not var or (m.group("pre") and m.group("pre") != var.group(1)):   # 앞 대입 변수 ≠ trap 변수 = 그 임시 폴더가 아니다
        return False
    body = (show(path) if show else "") or ""   # trap 꼴인 줄만 파일을 읽는다(git 호출 아끼기)
    if not body:
        return False
    v = re.escape(var.group(1))
    uses = re.findall(MKTEMP_NAME % v, body) + re.findall(MKTEMP_CASSIGN % v, body)
    if len(uses) != 1:   # 맨 이름 + 조건부 대입이 «정확히 1번»(재대입·read·for·${T:=…} = 대상이 그 임시 폴더가 아니다 · NG3·R2)
        return False
    return bool(re.search(MKTEMP_LINE % v + MKTEMP_VALUE + MKTEMP_TAIL, body))   # 값 «전체» 가 mktemp -d (DA② R1-a: 뒤에 붙은 /../.. = destroy)


def critical_kinds(blocks, secret=None, show=None):   # → (종류, 사유) | None · blocks = autonomy_scope_secret.parse_added 결과
    for path, _items, is_new in blocks:   # ① 새 LaunchAgents/LaunchDaemons plist
        if is_new and CRIT_LAUNCHD.search(path or ""):
            return "launchd", "새 launchd plist: %s" % path
    for path, items, is_new in blocks:   # ② 외부 설정(cliproxy·headroom · codex config.toml · .env) — 새 파일이든 값 변경이든
        if CRIT_CONFIG.search(path or ""):
            return "config", "%s · %s" % (path, "새 설정 파일" if is_new else "기존 설정 값 변경")
    for path, items, _is_new in blocks:   # ② models.json = apiKey 칸(R1: 여기만 좁게 — 다른 일반 값 변경은 크리티컬 아님)
        if CRIT_APIKEY_PATH.search(path or "") and any(CRIT_APIKEY.search(t) for _n, t in items):
            return "config", "%s · apiKey 칸" % path
    why = secret() if secret else ""   # ③ 비밀 줄(autonomy_scope_secret.reason 재사용)
    if why:
        return "secret", why
    for path, items, _is_new in blocks:   # ④ 파괴 명령 새 줄 — r1597 tests/ 임시 폴더 trap 줄만 예외
        for no, txt in items:
            if CRIT_DESTROY.search(txt) and not mktemp_trap_exempt(path, txt, show):
                return "destroy", "%s:%d %s" % (path or "?", no, txt.strip()[:80])
    return None


def ddl_recorded(records, sql_path, added, show):   # added = PR 추가 줄 · show(경로) = sha 트리의 그 파일 본문(없으면 "")
    name = re.escape(os.path.basename(sql_path))
    for where, rx in records:
        pat = re.compile(rx.replace("{sql}", name))
        text = added if where == "-" else show(where)
        if any(pat.search(ln) for ln in text.split("\n")):
            return True
    return False
