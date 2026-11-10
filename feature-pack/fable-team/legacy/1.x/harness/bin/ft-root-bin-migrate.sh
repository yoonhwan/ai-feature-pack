#!/bin/bash
# ft-root-bin-migrate.sh — 라이브 plist·팀 env 의 «v6 워크트리 시작 경로» 를 공용 루트로 옮긴다 (r962 r4 · REWORK-r962-r4 고침 2)
#   기본 = dry-run(표만 · 쓰기 0) · --apply 일 때만 쓴다 · ★launchctl 은 부르지 않는다★(바뀐 라벨 목록만 출력 → master 가 kickstart)
#   대상 = ① 하네스 관리 라벨 plist ② 팀 env(<공용 루트>/.fable-team/bin-*/*-env.sh)
#          ★r5: 관리 라벨 정본 = plist «내부 Label»★(파일명 아님 — 리서치 §2-3 · launchd 적재 단위도 Label)
#            내부 Label 이 관리 패턴 밖 = REPORT(파일명·Label 병기) 쓰기 0 · 없음/비문자열 = ERROR rc≠0 · 파일명≠Label(둘 다 관리) = 이전 + REPORT 병기
#          그 밖 라벨·값은 «보고만»(REPORT 줄) — 파일을 건드리지 않는다.
#   값 판정은 plistlib 로 읽은 «값» 단위다. 정확히 아래 두 꼴일 때만 옮긴다(부분 일치·사람 글 0):
#     <v6 워크트리>                        → <공용 루트>
#     <v6 워크트리>/.fable-team/bin/<파일> → <공용 루트>/.fable-team/bin/<파일>   (그 밖 하위 경로 = 보고만)
#   새 값이 실재하지 않으면 그 파일 전체를 건드리지 않고 ERROR(rc≠0) — 다른 파일은 계속 진행한다.
#   env 파일은 «정확히 같은 줄» `export FT_BIN=<v6 bin>` 하나만 바꾼다(다른 줄 0 · 주석 줄의 v6 글자 그대로).
#   ★r5 쓰기 = «바꿈值 固有 구간만»★ plist = 대상 key 의 <string>…</string> 내부 텍스트만(주석·들여쓰기·나머지 bytes 불변 · 리서치 §3-1)
#     env = bytes(rb/wb) + split(b"\n") — 조각 끝 \r 보존(CRLF 원본 유지 · text mode 의 universal-newline 번역 0 · 리서치 §3-2)
#   쓰기 전 <파일>.bak-r962 → tmp → fsync → os.replace · plist 는 재해석 dict 를 «바꼈 key 만 다르다» 로 비교 + plutil -lint → 실패면 .bak 로 되돌리고 rc≠0.
#   다시 돌리면 바꿀 것 0(멱등).
#   공용 루트 = --root 또는 기존 함수 ft_repo_root(<이 폴더>) · v6 경로 = --from-wt(기본 <공용 루트>/.worktrees/v6-realtime-live) · 새 해석기 0
#   출력(탭 구분): MIGRATE <파일> <키> <옛값> <새값> / REPORT <파일> <키> <값> / ERROR <파일> <키> <사유> / BAK <파일> <백업> / SUM <칸=값…>
set -uo pipefail
PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"; export PATH
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
APPLY=0; ROOT=""; FROMWT=""; LA="$HOME/Library/LaunchAgents"; TEAMS=""
while [ $# -gt 0 ]; do case "$1" in
  --apply) APPLY=1; shift;; --dry-run) APPLY=0; shift;;
  --root) ROOT="$2"; shift 2;; --from-wt) FROMWT="$2"; shift 2;;
  --launchagents) LA="$2"; shift 2;; --teams-dir) TEAMS="$2"; shift 2;;
  -h|--help) sed -n '2,20p' "$0"; exit 0;;
  *) echo "usage: $0 [--dry-run|--apply] [--root DIR] [--from-wt DIR] [--launchagents DIR] [--teams-dir DIR]" >&2; exit 2;; esac; done

if [ -z "$ROOT" ]; then
  # 기존 함수만 쓴다(새 해석기 0) — 실전: 이 도구 = <공용 루트>/.fable-team/bin 이라 git 공용 루트가 곧 공용 루트
  [ -f "$HERE/ft-harness-root.sh" ] && . "$HERE/ft-harness-root.sh"
  ROOT="$(type -t ft_repo_root >/dev/null 2>&1 && ft_repo_root "$HERE")" || { echo "REJECT 공용 루트를 못 풂 — --root 로 준다($HERE)" >&2; exit 2; }
fi
[ -n "$ROOT" ] || { echo "REJECT 공용 루트가 비었다 — --root 로 준다" >&2; exit 2; }
ROOT="$(cd -- "$ROOT" 2>/dev/null && pwd -P)" || { echo "REJECT 공용 루트 폴더를 못 연다: $ROOT" >&2; exit 2; }
[ -n "$FROMWT" ] || FROMWT="$ROOT/.worktrees/v6-realtime-live"
[ -n "$TEAMS" ] || TEAMS="$ROOT/.fable-team"

FT_M_ROOT="$ROOT" FT_M_FROMWT="$FROMWT" FT_M_LA="$LA" FT_M_TEAMS="$TEAMS" FT_M_APPLY="$APPLY" python3 - <<'PY'
import copy, glob, os, plistlib, re, shutil, subprocess, sys
from xml.sax.saxutils import escape as xml_escape

R = os.environ["FT_M_ROOT"]; V = os.environ["FT_M_FROMWT"].rstrip("/")
LA = os.environ["FT_M_LA"]; TEAMS = os.environ["FT_M_TEAMS"]; APPLY = os.environ["FT_M_APPLY"] == "1"
BIN = os.path.join(R, ".fable-team", "bin"); V6BIN = os.path.join(V, ".fable-team", "bin")
LABEL_RE = re.compile(r"^(com\.byz\.ft-.*|com\.hermes\.byz-slack-.*-inbound)$")
C = dict.fromkeys(("plist_migrate", "plist_report", "plist_error",
                   "env_migrate", "env_report", "env_error"), 0)
errors = 0; labels = []

def emit(*cols): print("\t".join(str(c) for c in cols))
def show(p): return "/".join(str(x) for x in p)

def walk(node, path=()):
    if isinstance(node, dict):
        for k, v in node.items(): yield from walk(v, path + (k,))
    elif isinstance(node, list):
        for i, v in enumerate(node): yield from walk(v, path + (i,))
    elif isinstance(node, str):
        yield path, node

def judge(v):
    """값 단위 판정 — 정확히 두 꼴만 이전. 나머지는 보고만/무시."""
    if v == V: return "migrate", R
    if v == V6BIN: return "migrate", BIN
    if v.startswith(V6BIN + "/"):
        f = v[len(V6BIN) + 1:]
        if f and "/" not in f: return "migrate", os.path.join(BIN, f)
    if V in v: return "report", v
    return None, None

def plutil_lint(path):
    if not shutil.which("plutil"): return None
    return subprocess.run(["plutil", "-lint", path], capture_output=True, text=True).returncode

#   ★r988 r1 (DA⑥ 수용 3)★ — ② 주석 속 <string> 태그는 «값» 이 아니다(주석 구간 건너뛰기 · 주석 바이트 보존)
#     ⑤ 백업 = 임시 이름에 쓰고 «바이트 대조» 뒤 mv · 기존 백업이 원본과 다르면 «쓰기 0»(불완전 백업 재사용 0)
#     ⑤ 원본 보존 = 임시 파일 → 재해석·plutil 검사 → os.replace 만 · 검사 실패면 임시 삭제뿐(원본을 열지 않는다)
def backup(path):
    """r1(DA⑤): 임시 이름에 쓰고 «바이트 대조» 뒤 mv — 불완전 백업이 남아도 재사용하지 않는다."""
    bak = path + ".bak-r962"
    try: src = open(path, "rb").read()
    except OSError: return None
    if os.path.exists(bak):
        try: same = open(bak, "rb").read() == src
        except OSError: same = False
        return bak if same else None          # 기존 백업이 원본과 바이트 다르다 = 보고만 아님, 쓰기 0
    tmp = "%s.tmp.%d" % (bak, os.getpid())
    try:
        with open(tmp, "wb") as fh:
            fh.write(src); fh.flush(); os.fsync(fh.fileno())
        if open(tmp, "rb").read() != src: raise OSError("백업 대조 불일치")
        os.replace(tmp, bak)
    except OSError:
        try: os.remove(tmp)
        except OSError: pass
        return None
    return bak

# ── r5: plist 안의 <string> 구간 색인 (값 위치만 바꾸기 위한 위치 기반 — 전역 replace 0 · 리서치 §3-1)
TAG = re.compile(rb"<(/?)([A-Za-z]+)(\s*/>|>)")
OTHER = ("integer", "real", "true", "false", "date", "data")

def comment_spans(b):
    """r1(DA②): XML 주석 구간 — 주석 속 <string> 태그를 «값» 으로 세지 않는다."""
    out = []; i = 0
    while True:
        s = b.find(b"<!--", i)
        if s < 0: break
        e = b.find(b"-->", s + 4)
        if e < 0: out.append((s, len(b))); break
        out.append((s, e + 3)); i = e + 3
    return out

def index_strings(b):
    """(path, inner_start, inner_end) 목록 — path 예: ('WorkingDirectory',) · ('ProgramArguments', 1) · ('EnvironmentVariables','K')"""
    out = []; stack = []; cur_key = None; i = 0; cm = comment_spans(b); ci = 0
    def take():
        if not stack:
            return ()          # 루트 컨테이너(<plist> 아래 첫 dict) — 경로는 빈 튜플
        top = stack[-1]
        if top[0] == "array":
            p = top[1] + (top[2][0],); top[2][0] += 1; return p
        return top[1] + (cur_key,)
    while True:
        m = TAG.search(b, i)
        if not m: break
        while ci < len(cm) and cm[ci][1] <= m.start(): ci += 1
        if ci < len(cm) and cm[ci][0] <= m.start() < cm[ci][1]:
            i = cm[ci][1]; continue          # 주석 안 태그 = 값 아님(주석 바이트는 그대로 둔다)
        closing = m.group(1) == b"/"; name = m.group(2).decode(); tail = m.group(3)
        if not closing and name == "key":
            e = b.find(b"</key>", m.end())
            if e < 0: break
            cur_key = xml_unescape(b[m.end():e].decode("utf-8")); i = e + 6; continue
        if closing and name in ("dict", "array"):
            if stack: stack.pop()
            i = m.end(); continue
        if not closing and name == "dict":
            stack.append(("dict", take())); i = m.end(); continue
        if not closing and name == "array":
            stack.append(("array", take(), [0])); i = m.end(); continue
        if not closing and name == "string" and tail == b">":
            p = take()
            e = b.find(b"</string>", m.end())
            if e < 0: break
            out.append((p, m.end(), e)); i = e + 9; continue
        if not closing and name in OTHER:
            take()
            if tail != b"/>":
                e = b.find(b"</" + name.encode() + b">", m.end())
                i = (e + len(name) + 3) if e >= 0 else m.end()
            else:
                i = m.end()
            continue
        i = m.end()
    return out

xml_unescape = lambda s: (s.replace("&lt;", "<").replace("&gt;", ">").replace("&quot;", '"')
                          .replace("&apos;", "'").replace("&amp;", "&"))

def set_path(node, p, v):
    for k in p[:-1]: node = node[k]
    node[p[-1]] = v

def atomic_write(path, data):
    tmp = path + ".r962tmp"
    with open(tmp, "wb") as f:
        f.write(data); f.flush(); os.fsync(f.fileno())
    return tmp

def apply_plist(path, d, rows):
    """r5: 바꿈 값의 <string> 내부 텍스트만 치환 → 재해석 dict 부분 비교 + lint → 원자 쓰기"""
    try: raw = open(path, "rb").read()
    except OSError as e: return "읽기 실패(%s)" % type(e).__name__
    spans = {}
    for p, s, e in index_strings(raw):
        spans.setdefault(p, []).append((s, e))
    edits = []
    for p, old, new in rows:
        sp = spans.get(tuple(p))
        if not sp or len(sp) != 1:
            return "값 구간을 못 찾음(%s · %d곳) → 쓰기 0" % (show(p), len(sp or []))
        edits.append((sp[0][0], sp[0][1], xml_escape(new).encode("utf-8")))
    out = raw
    for s, e, nb in sorted(edits, reverse=True):
        out = out[:s] + nb + out[e:]
    expect = copy.deepcopy(d)
    for p, old, new in rows: set_path(expect, p, new)
    try: back = plistlib.loads(out)
    except Exception as e: return "재해석 실패(%s) → 쓰기 0" % type(e).__name__
    if back != expect: return "재해석 dict 가 «바꼈 key 만 다르다» 가 아니다 → 쓰기 0"
    bak = backup(path)
    if not bak: return "백업 불일치 또는 백업 쓰기 실패 → 쓰기 0(원본 그대로)"
    try: tmp = atomic_write(path, out)
    except OSError as e: return "임시 쓰기 실패(%s) → 쓰기 0(원본 그대로)" % type(e).__name__
    r = plutil_lint(tmp)
    if r not in (None, 0):
        try: os.remove(tmp)
        except OSError: pass
        return "plutil -lint rc=%s → 쓰기 0(원본 그대로)" % r      # r1(DA⑤): 복원 쓰기 0 — 원본을 열지 않는다
    os.replace(tmp, path)
    emit("BAK", path, bak)
    return None

# ── ① plist ──────────────────────────────────────────────────────────────────────
if not os.path.isdir(os.path.join(R, ".fable-team")):
    emit("ERROR", R, "root", "공용 루트에 .fable-team 이 없다 — --root 확인"); print("SUM mode=%s error=1" % ("apply" if APPLY else "dry-run")); sys.exit(2)
for path in sorted(glob.glob(os.path.join(LA, "*.plist"))):
    fname = os.path.basename(path)[:-6]
    rawb = b""
    try:
        rawb = open(path, "rb").read()
        d = plistlib.loads(rawb)
        if not isinstance(d, dict): raise ValueError("dict 아님")
    except Exception as e:
        # r5: plistlib 이 못 읽는 옛 꼴(DOCTYPE)이 있다 — Label 만은 텍스트에서 읽는다(선례 ft_live_install_check.py:163)
        m = re.search(rb"<key>\s*Label\s*</key>\s*<string>([^<]*)</string>", rawb)
        if not m:
            emit("ERROR", path, "load", "plist 를 못 읽고 Label 도 없다(%s) — fail-closed" % type(e).__name__); C["plist_error"] += 1; errors += 1
            continue
        emit("REPORT", path, "Label", "plistlib 로 못 읽음(%s) · Label=%s — 쓰기 0" % (type(e).__name__, m.group(1).decode("utf-8", "replace"))); C["plist_report"] += 1
        continue
    label = d.get("Label")   # r5: 관리 라벨 정본 = 내부 Label (파일명 0 — 리서치 §2-3)
    if not isinstance(label, str):
        emit("ERROR", path, "Label", "내부 Label 이 없거나 문자열이 아니다(파일명=%s) — fail-closed" % fname); C["plist_error"] += 1; errors += 1
        continue
    rows, miss, rep = [], [], []
    managed = bool(LABEL_RE.match(label))   # 하네스 관리 라벨만 «이전» — 그 밖 라벨은 보고만(계약 ③)
    if not managed:
        # r5: 비관리 라벨 = 파일당 REPORT 1줄(파일명·내부 Label 병기) · 쓰기 0
        emit("REPORT", path, "Label", "비관리 Label(파일명=%s · Label=%s) — 이전 대상 아님" % (fname, label)); C["plist_report"] += 1
        continue
    if fname != label:
        emit("REPORT", path, "Label", "파일명≠내부 Label(파일명=%s · Label=%s) — 이전은 Label 기준" % (fname, label)); C["plist_report"] += 1
    for p, v in walk(d):
        kind, new = judge(v)
        if kind == "migrate":
            (rows if os.path.exists(new) else miss).append((p, v, new))
        elif kind == "report":
            rep.append((p, v))
    for p, v, new in rows:
        emit("MIGRATE", path, show(p), v, new); C["plist_migrate"] += 1
    for p, v in rep:
        emit("REPORT", path, show(p), v); C["plist_report"] += 1
    for p, v, new in miss:
        emit("ERROR", path, show(p), "새 값이 실재하지 않는다: %s" % new); C["plist_error"] += 1; errors += 1
    if APPLY and rows and not miss:
        why = apply_plist(path, d, rows)
        if why:
            emit("ERROR", path, "-", why); C["plist_error"] += 1; errors += 1
        else:
            labels.append(label)
    elif rows and miss and APPLY:
        emit("ERROR", path, "-", "새 값 없는 칸이 있어 이 파일은 손대지 않는다"); C["plist_error"] += 1; errors += 1

# ── ② 팀 env ────────────────────────────────────────────────────────────────────
OLD = "export FT_BIN=%s" % V6BIN; NEW = "export FT_BIN=%s" % BIN
OLD_B = OLD.encode(); NEW_B = NEW.encode(); V_B = V.encode()   # r5: bytes 비교 · CRLF 보존(리서치 §3-2)
for d in sorted(glob.glob(os.path.join(TEAMS, "bin-*"))):
    for f in sorted(glob.glob(os.path.join(d, "*-env.sh"))):
        try: data = open(f, "rb").read()
        except OSError as e:
            emit("ERROR", f, "FT_BIN", "읽기 실패(%s)" % type(e).__name__); C["env_error"] += 1; errors += 1; continue
        parts = data.split(b"\n")
        hits = [i for i, s in enumerate(parts) if s.rstrip(b"\r") == OLD_B]
        if not hits:
            if any(b"FT_BIN=" in s and V_B in s for s in parts):
                emit("REPORT", f, "FT_BIN", "정확히 같은 줄이 아니다 — 보고만"); C["env_report"] += 1
            continue
        if not os.path.isdir(BIN):
            emit("ERROR", f, "FT_BIN", "새 값(공용 bin 폴더)이 없다: %s" % BIN); C["env_error"] += 1; errors += 1; continue
        for i in hits:
            emit("MIGRATE", f, "FT_BIN", OLD, NEW); C["env_migrate"] += 1
        if not APPLY: continue
        want = list(parts)
        for i in hits: want[i] = NEW_B + (b"\r" if parts[i].endswith(b"\r") else b"")
        bak = backup(f)
        if not bak:
            emit("ERROR", f, "FT_BIN", "백업 불일치 또는 백업 쓰기 실패 → 쓰기 0"); C["env_error"] += 1; errors += 1; continue
        try:
            tmp = atomic_write(f, b"\n".join(want))
        except OSError as e:
            emit("ERROR", f, "FT_BIN", "쓰기 실패(%s) → 원본 그대로" % type(e).__name__); C["env_error"] += 1; errors += 1; continue
        got = open(tmp, "rb").read().split(b"\n")
        if len(got) != len(parts) or any(got[j] != parts[j] for j in range(len(parts)) if j not in hits):
            os.remove(tmp)
            emit("ERROR", f, "FT_BIN", "바꿈 줄 밖이 바뀌었다 → 쓰기 0 · 원본 그대로"); C["env_error"] += 1; errors += 1
        else:
            os.replace(tmp, f)
            emit("BAK", f, bak); labels.append(os.path.basename(f))

mode = "apply" if APPLY else "dry-run"
emit("SUM", "mode=%s" % mode, " ".join("%s=%d" % kv for kv in C.items()))
if APPLY and labels: print("RELOAD_NEEDED\t" + " ".join(sorted(set(labels))))
sys.exit(1 if errors else 0)
PY
