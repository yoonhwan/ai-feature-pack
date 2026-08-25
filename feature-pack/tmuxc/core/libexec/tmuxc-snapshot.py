#!/usr/bin/env python3
"""tmuxc save 보조 엔진 (UC13) — session_id 해석 + 스냅샷 JSON 직렬화.

두 서브커맨드로 나뉜다. 사이에 bash 가 복구 커맨드를 합성한다 —
합성기를 bash 한 곳에만 두어 open 경로와 방식이 갈라지지 않게 한다.

  resolve : stdin TSV(8필드) → stdout TSV(9필드, sid/sid_source 채움)
  emit    : stdin TSV(10필드) → JSON 파일 또는 stdout

구분자는 0x1f(unit separator). 탭은 bash IFS whitespace라 빈 중간 필드가
collapse 되어 필드가 밀린다 — restore-scan.py 와 동일한 이유·동일한 선택.

sid 해석이 필요한 이유: argv 에 sid 가 있는 것은 이미 --resume 으로 뜬 세션뿐이고,
처음 열린 세션은 argv 에 sid 가 없다. 반대로 [1m]/effort 는 argv 에만 있다
(트랜스크립트 미기록 — 2026-08-25 실측). 두 소스를 합쳐야 완전한 복구 정보가 된다.
"""
import argparse
import glob
import json
import os
import re
import socket
import sqlite3
import sys
from datetime import datetime, timezone

SEP = "\x1f"
SCHEMA = 1

# 글롭은 env 로 오버라이드 가능 — verify.sh fixture 테스트용 (restore-scan.py 관례 동일)
CLAUDE_PROJECTS = os.environ.get("TMUXC_CLAUDE_PROJECTS", "~/.claude/projects")
CODEX_GLOB = os.environ.get("TMUXC_CODEX_GLOB", "~/.codex/sessions/*/*/*/rollout-*.jsonl")
CMD_PROJECTS = os.environ.get("TMUXC_CMD_PROJECTS", "~/.commandcode/projects")
OPENCODE_SESSIONS = os.environ.get(
    "TMUXC_OPENCODE_SESSIONS", "~/.local/share/opencode/storage/session"
)
OPENCODE_DB = os.environ.get("TMUXC_OPENCODE_DB", "~/.local/share/opencode/opencode.db")

RESOLVE_FIELDS = ["name", "cwd", "attached", "pane_command", "agent", "model", "effort", "sid"]
# resolve 가 덧붙이는 2필드. title 은 복구 표에서 "이 세션이 뭘 하던 세션인가"를
# 보여준다 — 사용자가 스냅샷 «내용»으로 고르게 하는 축.
RESOLVED_FIELDS = RESOLVE_FIELDS + ["sid_source", "title"]
EMIT_FIELDS = RESOLVED_FIELDS + ["resume_cmd"]

TITLE_LIMIT = 72


def cwd_slug(cwd):
    """claude/commandcode 공통 프로젝트 디렉터리 규칙 — '/' 와 '.' 를 '-' 로."""
    return cwd.replace("/", "-").replace(".", "-")


def newest(paths, key=os.path.getmtime):
    best, best_k = "", None
    for p in paths:
        try:
            k = key(p)
        except OSError:
            continue
        if best_k is None or k > best_k:
            best, best_k = p, k
    return best


def head_bytes(path, n=4096):
    try:
        with open(path, "rb") as f:
            return f.read(n).decode("utf-8", "ignore")
    except OSError:
        return ""


def tail_bytes(path, n=65536):
    try:
        with open(path, "rb") as f:
            f.seek(0, 2)
            f.seek(max(0, f.tell() - n))
            return f.read().decode("utf-8", "ignore")
    except OSError:
        return ""


MBOX_RE = re.compile(r"mbox\.sh recv ['\"]?([A-Za-z0-9_#\-]+)")


def clip(s, limit=TITLE_LIMIT):
    s = " ".join((s or "").split())
    s = s.replace(SEP, " ")
    # mbox 폴링은 절대경로가 길어 표를 다 잡아먹는다 — 역할만 남긴다
    # (restore-scan.py short_work_hint 과 같은 정규화).
    m = MBOX_RE.search(s)
    if m and "mbox.sh recv" in s:
        s = "mbox recv " + m.group(1)
    if len(s) > limit:
        s = s[: limit - 1] + "…"
    return s


def text_of(content):
    """claude/codex/cmd 공통 — content 가 str 이거나 [{"type":"text","text":...}] 리스트."""
    if isinstance(content, str):
        return content.strip()
    out = []
    if isinstance(content, list):
        for part in content:
            if isinstance(part, dict) and part.get("type") in ("text", "input_text"):
                out.append(part.get("text", ""))
    return "".join(out).strip()


def last_user_text(path, extract, n=1 << 20):
    """파일 끝에서 마지막 «유의미» user 메시지. head 와 상보적이다 — 짧은 세션은
    head 에, 장수명 세션은 도입부가 시스템 주입뿐이라 tail 에만 내용이 있다."""
    best = ""
    for line in tail_bytes(path, n).splitlines():
        line = line.strip()
        if not line.startswith("{"):
            continue
        try:
            o = json.loads(line)
        except (json.JSONDecodeError, ValueError):
            continue
        txt = extract(o)
        if is_meaningful(txt):
            best = txt
    return clip(best)


def title_for(path, extract):
    """head 우선, 없으면 tail. 둘 다 비면 빈 문자열.
    선택된 파일 «하나»에만 부르므로 1MB 디코드 비용이 세션 수에 곱해지지 않는다."""
    return first_user_text(path, extract) or last_user_text(path, extract)


def recent_first(paths, cap=12):
    """mtime 내림차순 상위 cap 개만 본다 — 라이브 세션의 트랜스크립트는 반드시
    최근 수정본 안에 있다. 프로젝트 디렉터리에 수백 개가 쌓인 경우 1MB×N 읽기가
    스냅샷 전체를 느리게 만든다(실측 49세션 31초 → cap 적용 필요)."""
    def mt(p):
        try:
            return os.path.getmtime(p)
        except OSError:
            return 0.0
    return sorted(paths, key=mt, reverse=True)[:cap]


def _claude_user(o):
    if o.get("type") != "user" or o.get("isMeta") or o.get("isSidechain"):
        return ""
    return text_of((o.get("message") or {}).get("content"))


def _cmd_user(o):
    if o.get("type") != "message":
        return ""
    m = o.get("message") or {}
    if m.get("role") != "user":
        return ""
    return text_of(m.get("content"))


def _codex_user(o):
    pay = o.get("payload") or {}
    if pay.get("type") != "message" or pay.get("role") != "user":
        return ""
    return text_of(pay.get("content"))


def first_user_text(path, extract, limit=1 << 20):
    """앞 1MB 에서 첫 «유의미» user 메시지 — 복구 표의 작업 힌트.
    첫 메시지를 쓰는 이유: 도입부의 역할 부여 메시지가 «이게 무슨 세션인가»를
    가장 잘 말해준다. 없으면 호출부가 tail 로 넘어간다."""
    try:
        with open(path, "rb") as f:
            blob = f.read(limit)
    except OSError:
        return ""
    for line in blob.decode("utf-8", "ignore").splitlines():
        line = line.strip()
        if not line.startswith("{"):
            continue
        try:
            o = json.loads(line)
        except (json.JSONDecodeError, ValueError):
            continue  # 1MB 경계에서 잘린 마지막 라인 포함
        txt = extract(o)
        if is_meaningful(txt):
            return clip(txt)
    return ""


def is_meaningful(txt):
    """시스템 주입·tmuxc 통신 가이드는 «작업 내용»이 아니다."""
    if not txt:
        return False
    if txt.startswith("<") or txt.startswith("#"):
        return False
    if txt.startswith("[") and ("→" in txt[:80] or "->" in txt[:80]):
        return False
    return True


# tmuxc 가 기동 직후 COMM-GUIDE 로 주입하는 정본 마커. 이것이 붙어 있는 트랜스크립트가
# 그 세션의 것이다. 반면 «세션명 문자열»만 보면 세션간 메시지(mbox/[A→B])에 남의 이름이
# 실려 있어 오매칭한다 — 실측: CFO_OPSALERT#0 과 CFO_SSOT#0 이 같은 sid 로 붙었다.
ME_MARKER = "세션명(me)="

# 어느 패스에서 sid 가 정해졌는지 — 복구 표에서 신뢰도를 사람이 보게 한다.
MODE_SRC = {"strict": "transcript", "loose": "name-match", "latest": "cwd-latest"}


def _transcript_files(root_env, cwd, drop_checkpoints=False):
    d = os.path.join(os.path.expanduser(root_env), cwd_slug(cwd))
    files = glob.glob(os.path.join(d, "*.jsonl"))
    if drop_checkpoints:
        files = [p for p in files if ".checkpoints." not in p]
    return recent_first(files, cap=DIR_INDEX_CAP)


# ---------- 디렉터리 인덱스 (cwd 당 1회) ----------
# 세션마다 후보 파일을 다시 훑으면 O(세션수 × 파일수) 가 된다 — 한 워크트리에 세션이
# 27개면 그만큼 배로 읽는다. 그래서 cap 을 12로 눌러야 했고, 그 결과 mtime 14위였던
# 세션이 후보에서 잘려 sid 를 못 얻었다(2026-08-25 실측).
# cwd 당 한 번만 스캔해 «마커 → 파일» 지도를 만들면 O(파일수)로 떨어지므로
# cap 을 크게 올리면서 오히려 빨라진다.
DIR_INDEX_CAP = int(os.environ.get("TMUXC_DIR_INDEX_CAP", "80"))

# 바이트 레벨로 찾는다 — 1MB × N 을 유니코드로 디코드하는 비용을 피한다.
ME_MARKER_RE_B = re.compile(re.escape(ME_MARKER.encode()) + rb"([A-Za-z0-9_#\-]+)")
MENTION_RE_B = re.compile(rb"([A-Za-z0-9_\-]+#\d+)")

_dir_cache = {}


def dir_index(root_env, cwd, drop_checkpoints=False):
    """[(path, markers:set, mentions:set)] — mtime 내림차순. title 은 지연 계산."""
    key = (root_env, os.path.realpath(cwd))
    hit = _dir_cache.get(key)
    if hit is not None:
        return hit
    out = []
    for p in _transcript_files(root_env, cwd, drop_checkpoints):
        try:
            with open(p, "rb") as f:
                blob = f.read(1 << 20)
        except OSError:
            continue
        out.append((
            p,
            {m.decode("utf-8", "ignore") for m in ME_MARKER_RE_B.findall(blob)},
            {m.decode("utf-8", "ignore") for m in MENTION_RE_B.findall(blob)},
        ))
    _dir_cache[key] = out
    return out


def pick_from_index(entries, name, mode, claimed):
    """mode 별 후보 선택. claimed 에 든 sid 는 어떤 mode 에서도 재사용하지 않는다."""
    for path, markers, mentions in entries:   # 이미 mtime 내림차순
        if _sid_of(path) in claimed:
            continue
        if mode == "strict" and name not in markers:
            continue
        if mode == "loose" and name not in mentions:
            continue
        return path
    return None


def _sid_of(path):
    return os.path.basename(path)[: -len(".jsonl")]


def resolve_claude(name, cwd, mode, claimed):
    pick = pick_from_index(dir_index(CLAUDE_PROJECTS, cwd), name, mode, claimed)
    if not pick:
        return "", "none", ""
    return _sid_of(pick), MODE_SRC[mode], title_for(pick, _claude_user)


def resolve_cmd(name, cwd, mode, claimed):
    entries = dir_index(CMD_PROJECTS, cwd, drop_checkpoints=True)
    pick = pick_from_index(entries, name, mode, claimed)
    if not pick:
        return "", "none", ""
    title = title_for(pick, _cmd_user)
    # 헤더 {"type":"session","id":...,"cwd":...} 로 cwd 를 교차검증
    for line in head_bytes(pick).splitlines():
        try:
            o = json.loads(line)
        except (json.JSONDecodeError, ValueError):
            continue
        if o.get("type") == "session" and o.get("id"):
            if o.get("cwd") and os.path.realpath(o["cwd"]) != os.path.realpath(cwd):
                return "", "none", ""
            return o["id"], MODE_SRC[mode], title
    return _sid_of(pick), MODE_SRC[mode], title


_codex_cache = None


def codex_index():
    """realpath(cwd) → (sid, path) 를 «한 번만» 만든다. 세션마다 전체 rollout 을
    다시 훑으면 codex 세션 수만큼 배로 느려진다(실측 병목).
    session_index.jsonl 의 thread_name 은 쓰지 않는다 — 2026-08-25 실측에서
    마지막 항목이 2026-07-06 이라 stale. session_meta.payload.cwd 로만 매칭한다."""
    global _codex_cache
    if _codex_cache is not None:
        return _codex_cache
    idx = {}
    for path in glob.glob(os.path.expanduser(CODEX_GLOB)):
        meta_cwd, sid = "", ""
        for line in head_bytes(path, 8192).splitlines():
            try:
                o = json.loads(line)
            except (json.JSONDecodeError, ValueError):
                continue
            if o.get("type") == "session_meta":
                pay = o.get("payload") or {}
                meta_cwd = pay.get("cwd", "")
                sid = pay.get("session_id") or pay.get("id") or ""
                break
        if not sid or not meta_cwd:
            continue
        try:
            key = os.path.realpath(meta_cwd)
            ts = os.path.getmtime(path)
        except OSError:
            continue
        idx.setdefault(key, []).append((sid, path, ts))
    # 같은 cwd 에 여러 codex 세션이 뜬다 — 최신순 리스트로 둬야 선점된 sid 를 건너뛰고
    # 다음 후보로 넘어갈 수 있다(단일 best 만 두면 두 세션이 같은 sid 를 문다).
    for k in idx:
        idx[k].sort(key=lambda r: r[2], reverse=True)
    _codex_cache = idx
    return idx


def resolve_codex(name, cwd, mode, claimed):
    # codex 는 세션명 마커가 트랜스크립트에 없다 — cwd 매칭만 가능하다.
    # 따라서 strict/loose 패스에서는 아무것도 내지 않고 latest 패스에서만 답한다.
    if mode != "latest":
        return "", "none", ""
    hits = codex_index().get(os.path.realpath(cwd)) or []
    for sid, path, _ts in hits:
        if sid in claimed:
            continue
        return sid, "cwd-latest", title_for(path, _codex_user)
    return "", "none", ""


def resolve_opencode_db(cwd, claimed):
    """opencode >= 1.0.220 은 세션을 sqlite(opencode.db)에 둔다 — storage/session/*.json
    은 레거시다(2026-08-25 실측: 라이브 세션이 json 에 전혀 안 남고 db 에만 있음).
    반드시 mode=ro 로 연다 — 25GB 라이브 DB 를 쓰기 모드로 잡으면 안 된다.
    title 컬럼이 있어 작업 힌트를 공짜로 얻는다."""
    db = os.path.expanduser(OPENCODE_DB)
    if not os.path.exists(db):
        return "", ""
    try:
        con = sqlite3.connect("file:" + db + "?mode=ro", uri=True, timeout=5)
    except sqlite3.Error:
        return "", ""
    try:
        rows = con.execute(
            "select id, title from session where directory=? order by time_updated desc limit 20",
            (cwd,),
        ).fetchall()
        for sid, title in rows:
            if sid not in claimed:
                return sid, clip(title)
        return "", ""
    except sqlite3.Error:
        return "", ""
    finally:
        con.close()


def resolve_opencode(name, cwd, mode, claimed):
    # opencode 도 세션명 마커가 없다 — cwd 매칭만 가능하므로 latest 패스 전용.
    if mode != "latest":
        return "", "none", ""
    sid, title = resolve_opencode_db(cwd, claimed)
    if sid:
        return sid, "cwd-latest", title
    # 레거시 JSON 스토어 폴백 (구버전 opencode)
    cands = []
    root = os.path.expanduser(OPENCODE_SESSIONS)
    for path in glob.glob(os.path.join(root, "*", "ses_*.json")):
        try:
            with open(path, encoding="utf-8", errors="ignore") as f:
                o = json.load(f)
        except (OSError, json.JSONDecodeError, ValueError):
            continue
        d = o.get("directory") or ""
        if not d or os.path.realpath(d) != os.path.realpath(cwd):
            continue
        sid = o.get("id", "")
        if not sid or sid in claimed:
            continue
        cands.append(((o.get("time") or {}).get("updated") or 0, sid, clip(o.get("title", ""))))
    if not cands:
        return "", "none", ""
    cands.sort(reverse=True)
    return cands[0][1], "cwd-latest", cands[0][2]


RESOLVERS = {
    "claude": resolve_claude,
    "codex": resolve_codex,
    "cmd": resolve_cmd,
    "opencode": resolve_opencode,
}


# ---------- sid 를 이미 아는 행의 title (argv 경로) ----------
# 이름 매칭을 다시 돌리지 않고 «그 sid 의 파일»에서 바로 읽는다 — 남의 세션 제목이
# 붙는 사고를 구조적으로 막는다.

def title_by_sid(agent, sid, cwd):
    if not sid:
        return ""
    try:
        if agent == "claude":
            p = os.path.join(os.path.expanduser(CLAUDE_PROJECTS), cwd_slug(cwd), sid + ".jsonl")
            return title_for(p, _claude_user) if os.path.exists(p) else ""
        if agent == "cmd":
            p = os.path.join(os.path.expanduser(CMD_PROJECTS), cwd_slug(cwd), sid + ".jsonl")
            return title_for(p, _cmd_user) if os.path.exists(p) else ""
        if agent == "codex":
            for s, path, _ts in codex_index().get(os.path.realpath(cwd), []):
                if s == sid:
                    return title_for(path, _codex_user)
            return ""
        if agent == "opencode":
            db = os.path.expanduser(OPENCODE_DB)
            if not os.path.exists(db):
                return ""
            con = sqlite3.connect("file:" + db + "?mode=ro", uri=True, timeout=5)
            try:
                row = con.execute("select title from session where id=?", (sid,)).fetchone()
                return clip(row[0]) if row else ""
            finally:
                con.close()
    except (OSError, sqlite3.Error):
        return ""
    return ""


def read_rows(fields):
    rows = []
    for line in sys.stdin.read().splitlines():
        if not line.strip():
            continue
        parts = line.split(SEP)
        # 뒤쪽 선택 필드가 잘려 오면 빈 값으로 채운다(합성 실패 행도 보존)
        parts += [""] * (len(fields) - len(parts))
        rows.append(dict(zip(fields, parts[: len(fields)])))
    return rows


def cmd_resolve():
    """3패스 해석 + sid 선점.

    argv(정본) → strict(세션명 마커) → loose(이름 등장) → latest(cwd 최신) 순으로
    확신도가 높은 패스부터 sid 를 «선점»한다. 한 sid 가 두 세션에 붙으면 복원이
    같은 대화를 두 번 되살린다 — 실측으로 잡힌 결함이라 선점이 필수다.
    """
    rows = read_rows(RESOLVE_FIELDS)
    claimed = set()
    src = {}
    title = {}

    def resolvable(r):
        return RESOLVERS.get(r["agent"]) and r["cwd"] and os.path.isdir(r["cwd"])

    # 패스 0: argv 의 sid 는 무조건 정본. title 도 «그 sid 의 파일»에서 바로 읽는다.
    for i, r in enumerate(rows):
        if not r["sid"]:
            continue
        src[i] = "argv"
        claimed.add(r["sid"])
        if resolvable(r):
            title[i] = title_by_sid(r["agent"], r["sid"], r["cwd"])

    # 패스 1~3: sid 미상 행만. title 은 «sid 를 준 그 트랜스크립트»에서만 온다 —
    # 확정 후 다음 패스가 title 을 덧칠하면 남의 세션 제목이 붙는다(실측 사고).
    for mode in ("strict", "loose", "latest"):
        for i, r in enumerate(rows):
            if r["sid"] or not resolvable(r):
                continue
            try:
                sid, s, t = RESOLVERS[r["agent"]](r["name"], r["cwd"], mode, claimed)
            except (OSError, sqlite3.Error):
                continue
            if not sid:
                continue
            r["sid"] = sid
            src[i] = s
            claimed.add(sid)
            title[i] = t

    for i, r in enumerate(rows):
        sys.stdout.write(
            SEP.join([r[f] for f in RESOLVE_FIELDS] + [src.get(i, "none"), title.get(i, "")]) + "\n"
        )


def cmd_emit(out_path, to_stdout):
    sessions = []
    for r in read_rows(EMIT_FIELDS):
        sessions.append({
            "name": r["name"],
            "cwd": r["cwd"],
            "agent": r["agent"],
            "model": r["model"] or None,
            "effort": r["effort"] or None,
            "session_id": r["sid"] or None,
            "sid_source": r["sid_source"] or "none",
            "title": r["title"] or None,
            "attached": r["attached"] == "1",
            "pane_command": r["pane_command"],
            "resume_cmd": r["resume_cmd"] or None,
        })
    doc = {
        "schema": SCHEMA,
        "created_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "host": socket.gethostname(),
        "session_count": len(sessions),
        "sessions": sessions,
    }
    text = json.dumps(doc, ensure_ascii=False, indent=2) + "\n"
    if to_stdout or not out_path:
        sys.stdout.write(text)
        return
    # 원자적 쓰기 — 종료 직전에 부분 기록된 스냅샷을 남기지 않는다
    tmp = out_path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        f.write(text)
    os.replace(tmp, out_path)


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("resolve")
    e = sub.add_parser("emit")
    e.add_argument("--out", default="")
    e.add_argument("--stdout", action="store_true")
    args = ap.parse_args()
    if args.cmd == "resolve":
        cmd_resolve()
    else:
        cmd_emit(args.out, args.stdout)


if __name__ == "__main__":
    main()
