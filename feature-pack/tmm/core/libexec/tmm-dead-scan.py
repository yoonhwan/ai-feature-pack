#!/usr/bin/env python3
"""tmm-dead-scan — «종료된 에이전트 세션» 발견·대화 꼬리 렌더 (읽기 전용, 표준 라이브러리만).

  scan  --since H [--all-gen] [--snapshot PATH] [--live NAME ...]
        → 탭 구분 한 줄/세션:
          src agent name cwd sid model last_msg_ts last_alive_ts base gen resume_cmd
          (src: SNAP=tmuxc 스냅샷에 있어 argv 완제품 / CC=claude jsonl / CDX=codex / CMD=Command Code / OC=opencode)
  tail  --sid SID [--n 40]
        → 마지막 user/assistant 메시지 N줄을 Claude TUI 비슷한 모양으로 (SGR 색 포함)

규칙 출처: tmuxc-restore-scan.py(infer_role_name/is_noise/safe_name/dedupe/tail_lines) — assistant 파서는 여기서 신설.
시각: 레코드 timestamp 는 UTC. «마지막 생존»은 파일 mtime(로컬), «마지막 대화»는 max(timestamp).
라이브 제외 3중: ps argv 의 session uuid · --live 로 넘어온 tmux 세션명 · 최근 TMM_LIVE_GRACE(90s) 안에 쓰인 파일(argv 에
uuid 가 없는 신규 세션 — claude 는 트랜스크립트를 append 로 열어 lsof 에도 안 잡힌다).
"""
import argparse
import glob
import json
import os
import re
import sqlite3
import subprocess
import sys
import time
from datetime import datetime

HOME = os.path.expanduser("~")
CLAUDE_GLOB = os.environ.get("TMM_CLAUDE_GLOB", os.path.join(HOME, ".claude/projects/*/*.jsonl"))
CODEX_GLOB = os.environ.get("TMM_CODEX_GLOB", os.path.join(HOME, ".codex/sessions/*/*/*/rollout-*.jsonl"))
CMD_GLOB = os.environ.get("TMM_CMD_GLOB", os.path.join(HOME, ".commandcode/projects/*/*.jsonl"))
OPENCODE_DB = os.environ.get("TMM_OPENCODE_DB", os.path.join(HOME, ".local/share/opencode/opencode.db"))
SNAPSHOT = os.environ.get("TMM_SNAPSHOT", os.path.join(HOME, ".tmuxc/snapshots/latest.json"))

NAME_RE_ME = re.compile(r"세션명\(me\)=([^\s.,]+)")
NAME_RE_COMM = re.compile(r"\[[^\]]+?(?:->|→)([A-Za-z0-9_#\-]+)\]")
NAME_RE_MBOX = re.compile(r"mbox\.sh recv ['\"]?([A-Za-z0-9_#\-]+)")
NAME_COUNTER_RE = re.compile(r"^(.*?#\d+)")
CHAIN_RE = re.compile(r"^(.*)#(\d+)$")
MODEL_RE = re.compile(r'"model"\s*:\s*"(claude-[^"\[]+)')
TS_RE = re.compile(r'"timestamp"\s*:\s*"([^"]+)"')
HEADLESS_PREFIXES = ("Review the current working tree", "Respond with PONG", "Re-review")

SEP = "\t"


# ---------- 공통 ----------
def tail_bytes(path, block):
    try:
        with open(path, "rb") as f:
            f.seek(0, 2)
            size = f.tell()
            f.seek(max(0, size - block))
            return f.read().decode("utf-8", "ignore")
    except OSError:
        return ""


def head_lines(path, n):
    out = []
    try:
        with open(path, "r", encoding="utf-8", errors="ignore") as f:
            for i, line in enumerate(f):
                if i >= n:
                    break
                out.append(line)
    except OSError:
        pass
    return out


def jl(line):
    try:
        return json.loads(line)
    except Exception:
        return None


def parse_ts(s):
    if not s:
        return 0
    try:
        return int(datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp())
    except Exception:
        return 0


def safe_name(s):
    return re.sub(r"[^A-Za-z0-9_#\-]", "-", s or "")


def clip_role_name(name):
    m = NAME_COUNTER_RE.match(name or "")
    return m.group(1) if m else (name or "")


def text_of(content, allow=("text", "input_text", "output_text")):
    if isinstance(content, str):
        return content.strip()
    if isinstance(content, list):
        return "".join(p.get("text", "") for p in content if isinstance(p, dict) and p.get("type") in allow).strip()
    return ""


def is_noise_user(t):
    if not t or t.startswith("<") or t.startswith("#"):
        return True
    if any(t.startswith(p) for p in HEADLESS_PREFIXES):
        return True
    return False


def infer_name(users):
    for rx in (NAME_RE_ME, NAME_RE_COMM, NAME_RE_MBOX):
        for u in users:
            m = rx.search(u)
            if m:
                return clip_role_name(m.group(1))
    return ""


UUID_RE = re.compile(r"\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b")


def live_sids():
    """지금 살아있는 에이전트의 session id 집합 — ps argv 의 uuid(--resume/-r/--session-id) + lsof 가 잡은 jsonl.
    claude 는 트랜스크립트를 append 로만 열어 lsof 에 안 잡히므로(실측 0건) argv 가 주 소스다.
    실패 시 빈 집합 — 그러면 --live(tmux 세션명) 제외만 남는다."""
    out = set()
    try:
        ps = subprocess.run(["ps", "-eo", "args"], capture_output=True, text=True, timeout=5).stdout
        for line in ps.splitlines():
            if re.search(r"\b(claude|codex|cmd|opencode)\b", line):
                out.update(UUID_RE.findall(line))
    except Exception:
        pass
    try:
        lo = subprocess.run(["lsof", "-Fn"], capture_output=True, text=True, timeout=8).stdout
        for l in lo.splitlines():
            if l.startswith("n") and l.endswith(".jsonl"):
                out.update(UUID_RE.findall(l))
    except Exception:
        pass
    return out


def load_snapshot(path):
    """session_id → (name, resume_cmd, model, effort). 없으면 빈 dict."""
    try:
        with open(path, "r", encoding="utf-8") as f:
            doc = json.load(f)
    except Exception:
        return {}
    out = {}
    for s in doc.get("sessions", []):
        sid = s.get("session_id") or ""
        if sid and s.get("resume_cmd"):
            out[sid] = (s.get("name") or "", s["resume_cmd"], s.get("model") or "", s.get("effort") or "")
    return out


# ---------- claude ----------
def scan_claude(since_epoch, live_names, opened):
    rows = []
    for path in glob.glob(CLAUDE_GLOB):
        if "/subagents/" in path:
            continue
        try:
            mtime = os.path.getmtime(path)
        except OSError:
            continue
        if mtime < since_epoch or time.time() - mtime < LIVE_GRACE:
            continue   # 창 밖이거나, 지금 쓰이고 있는(라이브) 파일
        sid = os.path.basename(path)[:-6]
        if sid in opened:
            continue
        name = cwd = branch = ""
        users = []
        for line in head_lines(path, 120):
            o = jl(line)
            if not o:
                continue
            if not name and o.get("agentName"):
                name = o["agentName"]
            if not cwd and o.get("cwd"):
                cwd = o["cwd"]
            if not branch and o.get("gitBranch"):
                branch = o["gitBranch"]
            if o.get("type") == "user" and not o.get("isMeta") and not o.get("isSidechain"):
                t = text_of((o.get("message") or {}).get("content"))
                if not is_noise_user(t):
                    users.append(t)
            if o.get("isSidechain"):
                users = []
                break
        if not cwd:
            continue
        tail = tail_bytes(path, 400 * 1024)
        last_ts = 0
        for m in TS_RE.finditer(tail):
            last_ts = max(last_ts, parse_ts(m.group(1)))
        models = {}
        for m in MODEL_RE.finditer(tail):
            models[m.group(1)] = models.get(m.group(1), 0) + 1
        model = max(models.items(), key=lambda kv: kv[1])[0] if models else ""
        if not name:
            name = infer_name(users) or (os.path.basename(cwd) + "#0")
        if name in live_names:
            continue
        rows.append(dict(src="CC", agent="claude", name=safe_name(name), cwd=cwd, sid=sid, model=model,
                         last_msg=last_ts, last_alive=int(mtime), resume=""))
    return rows


def tail_claude(path, n):
    msgs = []
    for line in tail_bytes(path, 600 * 1024).splitlines():
        o = jl(line)
        if not o or o.get("isSidechain"):
            continue
        t = o.get("type")
        if t == "user" and not o.get("isMeta"):
            txt = text_of((o.get("message") or {}).get("content"))
            if txt and not txt.startswith("<"):
                msgs.append(("user", o.get("timestamp", ""), txt))
        elif t == "assistant":
            txt = text_of((o.get("message") or {}).get("content"))
            if txt:
                msgs.append(("assistant", o.get("timestamp", ""), txt))
    return msgs[-n:]


# ---------- codex ----------
def scan_codex(since_epoch, live_names, opened):
    rows = []
    for path in glob.glob(CODEX_GLOB):
        try:
            mtime = os.path.getmtime(path)
        except OSError:
            continue
        if mtime < since_epoch or time.time() - mtime < LIVE_GRACE:
            continue
        head = head_lines(path, 40)
        meta = None
        for line in head:
            o = jl(line)
            if o and o.get("type") == "session_meta":
                meta = o.get("payload") or {}
                break
        if not meta:
            continue
        src = meta.get("source")
        if src == "exec" or isinstance(src, dict):
            continue
        sid = meta.get("session_id") or meta.get("id") or os.path.basename(path)
        if sid in opened:
            continue
        cwd = meta.get("cwd") or ""
        users = []
        for line in head:
            o = jl(line)
            if not o:
                continue
            p = o.get("payload") or {}
            if o.get("type") == "response_item" and p.get("type") == "message" and p.get("role") == "user":
                t = text_of(p.get("content"))
                if not is_noise_user(t):
                    users.append(t)
        name = infer_name(users) or ("codex-" + sid[:8])
        if name in live_names:
            continue
        last_ts = 0
        for m in TS_RE.finditer(tail_bytes(path, 64 * 1024)):
            last_ts = max(last_ts, parse_ts(m.group(1)))
        rows.append(dict(src="CDX", agent="codex", name=safe_name(name), cwd=cwd, sid=sid, model="",
                         last_msg=last_ts, last_alive=int(mtime), resume=""))
    return rows


def tail_codex(path, n):
    msgs = []
    for line in tail_bytes(path, 600 * 1024).splitlines():
        o = jl(line)
        if not o or o.get("type") != "response_item":
            continue
        p = o.get("payload") or {}
        if p.get("type") != "message":
            continue
        txt = text_of(p.get("content"))
        if not txt or (p.get("role") == "user" and txt.startswith("<")):
            continue
        msgs.append((p.get("role"), o.get("timestamp", ""), txt))
    return msgs[-n:]


# ---------- Command Code ----------
def scan_cmd(since_epoch, live_names, opened):
    rows = []
    for path in glob.glob(CMD_GLOB):
        if ".checkpoints." in path:
            continue
        try:
            mtime = os.path.getmtime(path)
        except OSError:
            continue
        if mtime < since_epoch or time.time() - mtime < LIVE_GRACE:
            continue
        o = jl((head_lines(path, 1) or [""])[0])
        if not o or o.get("type") != "session":
            continue
        sid = o.get("id") or ""
        if sid in opened:
            continue
        cwd = o.get("cwd") or ""
        name = ""
        try:
            with open(path[:-6] + ".meta.json", "r", encoding="utf-8") as f:
                name = (json.load(f).get("title") or "")
        except Exception:
            pass
        name = name or ("cmd-" + sid[:8])
        if name in live_names:
            continue
        last_ts = 0
        for m in TS_RE.finditer(tail_bytes(path, 64 * 1024)):
            last_ts = max(last_ts, parse_ts(m.group(1)))
        rows.append(dict(src="CMD", agent="cmd", name=safe_name(name), cwd=cwd, sid=sid, model="",
                         last_msg=last_ts, last_alive=int(mtime), resume=""))
    return rows


def tail_cmd(path, n):
    msgs = []
    for line in tail_bytes(path, 600 * 1024).splitlines():
        o = jl(line)
        if not o or o.get("type") != "message":
            continue
        m = o.get("message") or {}
        txt = text_of(m.get("content"))
        if txt:
            msgs.append((m.get("role"), o.get("timestamp", ""), txt))
    return msgs[-n:]


# ---------- opencode ----------
def scan_opencode(since_epoch, live_names):
    if not os.path.isfile(OPENCODE_DB):
        return []
    try:
        con = sqlite3.connect("file:" + OPENCODE_DB + "?mode=ro&immutable=1", uri=True, timeout=3)
        rows_db = con.execute(
            "select id, directory, title, time_updated from session where time_updated >= ? order by time_updated desc",
            (int(since_epoch) * 1000,)).fetchall()
        con.close()
    except Exception:
        return []
    out = []
    for sid, cwd, title, upd in rows_db:
        name = "oc-" + sid[-8:]
        if name in live_names:
            continue
        ts = int(upd // 1000)
        out.append(dict(src="OC", agent="opencode", name=name, cwd=cwd or "", sid=sid, model="",
                        last_msg=ts, last_alive=ts, resume="", title=title or ""))
    return out


# ---------- 계보 ----------
def gen_filter(rows, all_gen):
    latest = {}
    for r in rows:
        m = CHAIN_RE.match(r["name"])
        r["base"], r["gen"] = (m.group(1), int(m.group(2))) if m else (r["name"], -1)
        if m:
            k = (r["agent"], r["base"])
            latest[k] = max(latest.get(k, -1), r["gen"])
    out = {}
    for r in rows:
        if not all_gen and r["gen"] >= 0 and r["gen"] < latest.get((r["agent"], r["base"]), -1):
            continue
        k = (r["agent"], r["name"])
        if k not in out or r["last_alive"] > out[k]["last_alive"]:
            out[k] = r
    return sorted(out.values(), key=lambda r: r["last_alive"], reverse=True)


# ---------- 파일 찾기 (tail 용) ----------
def find_transcript(sid):
    for pat in (CLAUDE_GLOB, CODEX_GLOB, CMD_GLOB):
        for p in glob.glob(pat):
            if "/subagents/" in p:
                continue
            if sid in os.path.basename(p):
                if "/.claude/" in p:
                    return "claude", p
                if "/.codex/" in p:
                    return "codex", p
                return "cmd", p
    return None, None


# ---------- 렌더 ----------
def render(msgs, width):
    """Claude TUI 흉내: user=회색 `❯`, assistant=굵게 `⏺`, 끝에 완료 마커. render_pane 이 그대로 먹는다."""
    out = []
    last_ts = ""
    for role, ts, txt in msgs:
        last_ts = ts or last_ts
        body = txt.replace("\r", "")
        if role == "user":
            out.append("\033[2m❯ " + body.splitlines()[0][:width] + "\033[0m")
            for l in body.splitlines()[1:6]:
                out.append("\033[2m  " + l[:width] + "\033[0m")
        else:
            lines = body.splitlines() or [""]
            out.append("\033[1m⏺ " + lines[0] + "\033[0m")
            out.extend("  " + l for l in lines[1:])
        out.append("")
    if last_ts:
        t = parse_ts(last_ts)
        hm = time.strftime("%H:%M", time.localtime(t)) if t else "--:--"
        out.append("\033[32m✻ done " + hm + "\033[0m")
    return "\n".join(out)


# ---------- main ----------
LIVE_GRACE = int(os.environ.get("TMM_LIVE_GRACE", "90"))


def cmd_scan(a):
    since_epoch = time.time() - a.since * 3600
    live = set(a.live or [])
    opened = live_sids()
    snap = load_snapshot(a.snapshot)
    rows = scan_claude(since_epoch, live, opened) + scan_codex(since_epoch, live, opened) \
        + scan_cmd(since_epoch, live, opened) + scan_opencode(since_epoch, live)
    for r in rows:
        s = snap.get(r["sid"])
        if s:
            r["src"] = "SNAP"
            r["resume"] = s[1]
            if s[0]:
                r["name"] = safe_name(s[0])
            if s[2]:
                r["model"] = s[2]
    rows = gen_filter(rows, a.all_gen)
    for r in rows:
        print(SEP.join(str(x) for x in (
            r["src"], r["agent"], r["name"], r["cwd"], r["sid"], r["model"],
            r["last_msg"], r["last_alive"], r["base"], r["gen"], r["resume"].replace("\t", " "))))


def cmd_tail(a):
    agent, path = find_transcript(a.sid)
    if not path or not agent:
        print("(트랜스크립트 없음: %s)" % a.sid)
        return 1
    tailers = {"claude": tail_claude, "codex": tail_codex, "cmd": tail_cmd}
    msgs = tailers[agent](path, a.n)
    if not msgs:
        print("(대화 없음)")
        return 0
    print(render(msgs, a.width))
    return 0


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("scan")
    s.add_argument("--since", type=float, default=12.0, help="시간 (기본 12)")
    s.add_argument("--all-gen", action="store_true")
    s.add_argument("--snapshot", default=SNAPSHOT)
    s.add_argument("--live", nargs="*", help="살아있는 tmux 세션명 (제외)")
    t = sub.add_parser("tail")
    t.add_argument("--sid", required=True)
    t.add_argument("--n", type=int, default=40)
    t.add_argument("--width", type=int, default=200)
    a = ap.parse_args()
    return cmd_scan(a) if a.cmd == "scan" else cmd_tail(a)


if __name__ == "__main__":
    sys.exit(main() or 0)
