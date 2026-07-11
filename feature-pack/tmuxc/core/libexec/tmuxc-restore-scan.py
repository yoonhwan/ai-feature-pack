#!/usr/bin/env python3
"""tmuxc restore 판별 엔진 (UC11) — claude + codex 세션 로그에서 복구 대상을 식별한다.

출력: 0x1f(unit separator) 구분 행 (agent, name, cwd, model, route, sid, ts, status, summary)
  - 탭 대신 0x1f인 이유: 탭은 bash IFS whitespace라 빈 중간 필드(cwd="" 등)가 collapse되어
    필드가 밀린다. 0x1f는 non-whitespace라 빈 필드가 보존된다 (DA 2026-07-08 ⑩).
  - route: claude=역할 alias(ccf/ccs/ccd), codex=effort 힌트(high)
  - status: ok | no-cwd | no-alias
정렬 키는 파일 mtime이 아니라 jsonl 내부 마지막 유효 라인의 timestamp (재부팅 시 mtime이 뭉개짐).
"""
import argparse
import glob
import json
import os
import re
import subprocess
import sys
from datetime import datetime, timedelta, timezone

SEP = "\x1f"
# 글롭은 env로 오버라이드 가능 — verify.sh fixture 테스트용
CLAUDE_GLOB = os.environ.get("TMUXC_CLAUDE_GLOB", "~/.claude/projects/*/*.jsonl")
CODEX_GLOB = os.environ.get("TMUXC_CODEX_GLOB", "~/.codex/sessions/*/*/*/rollout-*.jsonl")
CODEX_INDEX = os.environ.get("TMUXC_CODEX_INDEX", "~/.codex/session_index.jsonl")

# 헤드리스/자동/DA 세션 판별 프롬프트 (첫 user 메시지 prefix)
HEADLESS_PREFIXES = (
    "너는 baton 핸드오프 정리 헤드리스 에이전트다",
    "Review the current working tree",
    "Respond with PONG",
    "Re-review",
)

NAME_RE_ME = re.compile(r"세션명\(me\)=([^\s.,]+)")
NAME_RE_COMM = re.compile(r"\[[^\]]+?(?:->|→)([A-Za-z0-9_#\-]+)\]")  # ASCII '->' + legacy '→' 둘 다 수용
NAME_COUNTER_RE = re.compile(r"^(.*?#\d+)")
MODEL_RE = re.compile(r'"model"\s*:\s*"(claude-[^"]+)"')
TS_RE = re.compile(r'"timestamp"\s*:\s*"([^"]+)"')

# 모델 → 기동 alias (prefix 매칭 — [1m] suffix 포함 대응)
MODEL_ALIAS = (
    ("claude-fable-5", "ccf"),
    ("claude-sonnet-5", "ccs"),
    ("claude-opus-4-8", "ccd"),
)


def tail_lines(path, n=12, block=65536):
    try:
        with open(path, "rb") as f:
            f.seek(0, 2)
            size = f.tell()
            f.seek(max(0, size - block))
            return f.read().decode("utf-8", "ignore").splitlines()[-n:]
    except OSError:
        return []


def head_line(path):
    try:
        with open(path, encoding="utf-8", errors="ignore") as f:
            return f.readline()
    except OSError:
        return ""


def parse_ts(s):
    if not s:
        return None
    try:
        return datetime.fromisoformat(s.replace("Z", "+00:00"))
    except ValueError:
        return None


def field(s, limit=0):
    s = " ".join((s or "").split())
    if limit and len(s) > limit:
        s = s[: limit - 1] + "…"
    return s.replace("\t", " ").replace(SEP, " ")


def safe_name(s):
    """tmux 세션 타깃으로 안전한 이름 (sanitize_name과 동일 문자셋).
    ':' '.' 등은 tmux target 구문과 충돌해 restore를 중단시킨다 (DA ⑪)."""
    return re.sub(r"[^A-Za-z0-9_#-]", "-", s or "")


def extract_text(content):
    if isinstance(content, str):
        return content.strip()
    out = []
    if isinstance(content, list):
        for part in content:
            if isinstance(part, dict) and part.get("type") in ("text", "input_text"):
                out.append(part.get("text", ""))
    return "".join(out).strip()


# ---------- claude ----------

def claude_tail_probe(path):
    """끝 64KB만 읽어 (last_ts, sidechain, cwd) 회수 — 전량 파싱 전 저비용 필터."""
    ts, side, cwd = None, False, ""
    for line in reversed(tail_lines(path)):
        line = line.strip()
        if not line:
            continue
        if '"isSidechain":true' in line or '"isSidechain": true' in line:
            side = True
        if ts is None:
            m = TS_RE.search(line)
            if m:
                ts = parse_ts(m.group(1))
        if not cwd:
            m = re.search(r'"cwd"\s*:\s*"([^"]+)"', line)
            if m:
                cwd = m.group(1)
        if ts and cwd:
            break
    return ts, side, cwd


def claude_full_parse(path):
    """후보 확정 파일만 전량 스캔: user 텍스트 메시지·모델 최빈값·세션명."""
    users = []
    models = {}
    try:
        fh = open(path, encoding="utf-8", errors="ignore")
    except OSError:
        return users, models, ""
    with fh:
        for line in fh:
            if '"model"' in line:
                for m in MODEL_RE.findall(line):
                    models[m] = models.get(m, 0) + 1
            if '"type":"user"' not in line and '"type": "user"' not in line:
                continue
            try:
                o = json.loads(line)
            except (json.JSONDecodeError, ValueError):
                continue
            if o.get("type") != "user" or o.get("isMeta") or o.get("isSidechain"):
                continue
            txt = extract_text((o.get("message") or {}).get("content"))
            if not txt or txt.startswith("<"):
                continue
            if "Another Claude session sent" in txt:
                continue
            users.append(txt)
    name = ""
    for u in users:
        m = NAME_RE_ME.search(u)
        if m:
            name = m.group(1)
            break
        m = NAME_RE_COMM.search(u)
        if m:
            name = m.group(1)
            break
    # 'FB_Master#30(메인...' 처럼 부연이 붙으면 #숫자까지만
    m = NAME_COUNTER_RE.match(name)
    if m:
        name = m.group(1)
    return users, models, name


def model_to_alias(models):
    if not models:
        return "", ""
    top = max(models, key=models.get)
    for prefix, alias in MODEL_ALIAS:
        if top.startswith(prefix):
            return top, alias
    return top, ""


AGENT_PROC_RE = re.compile(r"(?:^|/)(claude|codex)(?:\s|$)")


def is_agent_command(cmd):
    """command 라인이 claude/codex 에이전트인지 판정.
    bare node는 무관 reader일 수 있어(DA 2차 ①) 그 자체로는 인정하지 않고,
    node의 *스크립트 경로*(첫 인자)가 claude/codex일 때만 인정.
    전체 args를 검사하면 파일 인자 경로에 'claude'가 들어가는 순간 오탐한다."""
    if AGENT_PROC_RE.search(cmd):
        return True
    m = re.match(r"\S*node\s+(\S+)", cmd)
    if m:
        return bool(re.search(r"(?:^|/)(claude|codex)(?:[./-]|$)",
                              os.path.basename(m.group(1)) if "/" not in m.group(1)
                              else m.group(1)))
    return False


def file_in_use(path):
    """세션 로그를 라이브 *에이전트*(claude/codex)가 물고 있으면 True — 복구 불필요.
    open FD 존재만 보면 무관한 reader(cat/python open 등)에도 후보가 사라지므로(DA ⑫)
    PID의 command를 확인해 에이전트 프로세스만 인정한다."""
    try:
        r = subprocess.run(
            ["lsof", "-t", "--", path],
            capture_output=True, text=True, timeout=10,
        )
        pids = [p for p in r.stdout.split() if p.isdigit()]
        if not pids:
            return False
        ps = subprocess.run(
            ["ps", "-o", "command=", "-p", ",".join(pids)],
            capture_output=True, text=True, timeout=10,
        )
        return any(is_agent_command(line) for line in ps.stdout.splitlines())
    except (OSError, subprocess.TimeoutExpired):
        return False  # lsof/ps 불가 환경 — 필터 생략 (과탐 쪽이 안전)


def scan_claude(since, loose=False):
    rows = []
    for path in glob.glob(os.path.expanduser(CLAUDE_GLOB)):
        ts, side, cwd = claude_tail_probe(path)
        if not ts or ts < since or side:
            continue
        first = head_line(path)
        if '"isSidechain":true' in first or '"isSidechain": true' in first:
            continue
        users, models, name = claude_full_parse(path)
        if not users:
            continue  # tool-only/빈 세션
        if users[0].startswith(HEADLESS_PREFIXES):
            continue  # 헤드리스 자동/DA 세션
        if not loose:
            # UC1 규약: tmuxc 세션은 세션명(me)= 주입 + #N 카운터 상시 부여.
            # 이름 미추출/카운터 없음 = tmuxc 오케스트레이션 세션 아님 (ad-hoc/종료 워커)
            if not name or "#" not in name:
                continue
        if file_in_use(path):
            continue  # 라이브 프로세스가 물고 있음 — 죽은 세션 아님
        model, alias = model_to_alias(models)
        sid = os.path.basename(path)[: -len(".jsonl")]
        summary = f"{field(users[0], 56)} ⇢ {field(users[-1], 56)}"
        if not name:
            name = os.path.basename(cwd or "unknown") + "#0"
        status = "ok"
        if not cwd or not os.path.isdir(cwd):
            status = "no-cwd"
        elif not alias:
            status = "no-alias"
        rows.append({
            "agent": "claude", "name": name, "cwd": cwd, "model": model or "?",
            "route": alias or "?", "sid": sid, "ts": ts, "status": status,
            "summary": summary,
        })
    return rows


# ---------- codex ----------

def load_codex_index():
    index = {}
    path = os.path.expanduser(CODEX_INDEX)
    if not os.path.exists(path):
        return index
    with open(path, encoding="utf-8", errors="ignore") as fh:
        for line in fh:
            try:
                o = json.loads(line)
            except (json.JSONDecodeError, ValueError):
                continue
            if o.get("id"):
                index[o["id"]] = o  # 뒤 라인이 최신 — 덮어쓰기
    return index


def codex_user_msgs(path):
    users = []
    try:
        fh = open(path, encoding="utf-8", errors="ignore")
    except OSError:
        return users
    with fh:
        for line in fh:
            if '"role":"user"' not in line and '"role": "user"' not in line:
                continue
            try:
                o = json.loads(line)
            except (json.JSONDecodeError, ValueError):
                continue
            pay = o.get("payload") or {}
            if pay.get("type") != "message" or pay.get("role") != "user":
                continue
            txt = extract_text(pay.get("content"))
            if not txt or txt.startswith("<"):
                continue
            users.append(txt)
    return users


def codex_session_meta(path, probe_lines=20):
    """첫 유효 session_meta를 전방 탐색. 첫 줄만 믿으면 손상 시 무증상 누락 (DA ①/⑤)."""
    try:
        fh = open(path, encoding="utf-8", errors="ignore")
    except OSError:
        return None
    with fh:
        for _, line in zip(range(probe_lines), fh):
            try:
                o = json.loads(line)
            except (json.JSONDecodeError, ValueError):
                continue
            if o.get("type") == "session_meta":
                return o
    return None


def scan_codex(since):
    index = load_codex_index()
    rows = []
    for path in glob.glob(os.path.expanduser(CODEX_GLOB)):
        meta = codex_session_meta(path)
        if meta is None:
            print(f"tmuxc-restore-scan: corrupt-meta (session_meta 미발견, 스킵): {path}",
                  file=sys.stderr)
            continue
        pay = meta.get("payload") or {}
        sid = pay.get("session_id") or pay.get("id") or ""
        cwd = pay.get("cwd", "")
        # 헤드리스 판별은 thread_name 유무가 아니라 session_meta.source가 정본:
        # exec=codex exec 헤드리스(DA 등), dict=subagent 스폰 — 복구 대상 아님.
        # cli=대화형(익명 가능), source 부재=구버전 → 후보 유지.
        src = pay.get("source")
        if src == "exec" or isinstance(src, dict):
            continue
        last = None
        for line in reversed(tail_lines(path, 20)):
            m = TS_RE.search(line)
            if m:
                last = parse_ts(m.group(1))
                if last:
                    break
        entry = index.get(sid, {})
        upd = parse_ts(entry.get("updated_at", ""))
        candidates = [t for t in (last, upd) if t]
        if not candidates:
            continue
        ts = max(candidates)
        if ts < since:
            continue
        name = (entry.get("thread_name") or "").strip()
        if not name:
            # 익명 대화형 세션 — 재부팅 직전 쓰던 세션일 수 있어 제외하면 안 됨.
            # dedupe()가 (agent, name)으로 키를 잡으므로 앞 8자만 쓰면 prefix가
            # 같은 다른 세션이 충돌해 소실된다(DA 5차 실증: 익명 세션 99개 중 충돌 2쌍).
            # sid 전체를 이름에 넣어 충돌 자체를 없앤다.
            name = f"codex-{sid}" if sid else ""
        if not name:
            continue  # sid조차 없는 손상 메타
        users = codex_user_msgs(path)
        if not users:
            continue
        if file_in_use(path):
            continue  # 라이브 codex가 물고 있음
        summary = f"{field(users[0], 56)} ⇢ {field(users[-1], 56)}"
        status = "ok" if cwd and os.path.isdir(cwd) else "no-cwd"
        rows.append({
            "agent": "codex", "name": name, "cwd": cwd, "model": "gpt-5.5",
            "route": "high", "sid": sid, "ts": ts, "status": status,
            "summary": summary,
        })
    return rows


# ---------- 공통: 증류 체인 / 중복 정리 ----------

def dedupe(rows):
    """같은 (agent, base)의 #N 여러 개면 최대 N만. 같은 이름 중복이면 최신 ts만."""
    latest_counter = {}
    chain_re = re.compile(r"^(.*)#(\d+)$")
    for r in rows:
        m = chain_re.match(r["name"])
        if m:
            key = (r["agent"], m.group(1))
            n = int(m.group(2))
            if key not in latest_counter or n > latest_counter[key]:
                latest_counter[key] = n
    out = {}
    for r in rows:
        m = chain_re.match(r["name"])
        if m:
            key = (r["agent"], m.group(1))
            if int(m.group(2)) < latest_counter.get(key, 0):
                continue  # 구증류본 — 이미 인계됨
        k = (r["agent"], r["name"])
        if k not in out or r["ts"] > out[k]["ts"]:
            out[k] = r
    return sorted(out.values(), key=lambda r: r["ts"], reverse=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--since", type=float, default=24.0, help="시간창(시간 단위, 기본 24)")
    ap.add_argument("--agent", choices=["claude", "codex", "all"], default="all")
    ap.add_argument("--loose", action="store_true",
                    help="tmuxc 세션명 규약(#N) 필터 해제 — ad-hoc claude 세션까지 나열")
    args = ap.parse_args()

    since = datetime.now(timezone.utc) - timedelta(hours=args.since)
    rows = []
    if args.agent in ("claude", "all"):
        rows += scan_claude(since, loose=args.loose)
    if args.agent in ("codex", "all"):
        rows += scan_codex(since)
    # tmux 세션명 확정: sanitize + 동명 충돌 시 유일해질 때까지 결정적 suffix (DA ⑧⑪)
    seen_names = set()
    for r in dedupe(rows):
        tmux_name = safe_name(r["name"]) or f"restored-{r['sid'][:8]}"
        if tmux_name in seen_names:
            tmux_name = f"{tmux_name}-{r['agent'][:3]}"
        n = 2
        base = tmux_name
        while tmux_name in seen_names:  # 3개 이상 collapse 대비 (DA 2차 ②)
            tmux_name = f"{base}-{n}"
            n += 1
        seen_names.add(tmux_name)
        print(SEP.join([
            r["agent"], field(tmux_name), r["cwd"], field(r["model"]),
            r["route"], r["sid"], r["ts"].strftime("%Y-%m-%dT%H:%M:%SZ"),
            r["status"], r["summary"],
        ]))


if __name__ == "__main__":
    main()
