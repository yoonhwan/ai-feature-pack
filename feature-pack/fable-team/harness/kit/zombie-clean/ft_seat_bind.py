#!/usr/bin/env python3
"""ft_seat_bind.py <좌석> [--expect <재개 기록.json>] — 좌석 pane 의 claude 프로세스 소유 결속 판정기 하나 (R364 · 판정 1344 H2).

결속 = 후보(pane pid 자신 ∪ 직계 자식) 중 세션 파일(~/.claude/sessions/<pid>.json)이 있는 «정확히 1개» 의
  ①파일 pid == 후보 pid ②소유: 파일 `tmux` 칸(<세션>:@window.%pane) == 지금 tmux 의 그 좌석 pane 전부 · 칸 «부재» 만 name==좌석 후퇴(legacy-name)
  ③프로세스 실재 ∧ 실행 주체 claude ∧ 시작시각(ps lstart) ≤ 파일 mtime(pid 재사용 차단). 이름·mtime 추측으로 하나 고르기 0.
출력 = JSON 1줄 {rc,reason,pid,uuid,cwd,jsonl,name,name_source,binding} · rc 0 결속 · 1 NORECORD(사유) · 2 조회 불가.
--expect 는 기록의 binding 이 «지금도» 같은 pane·pid·lstart 인지만 본다(닫기 직전 재비교 · 세션 파일은 다시 읽지 않음).
외부 조회(tmux·pgrep·ps)는 전부 timeout 7초 — 넘으면 rc 2.
"""
import json
import os
import re
import subprocess
import sys
import time

TIMEOUT_S = 7


def sh(*a):
    """(rc, stdout) · 시간 초과·실행 불가 = None."""
    try:
        r = subprocess.run(a, capture_output=True, text=True, timeout=TIMEOUT_S, env={**os.environ, "LC_ALL": "C"})
        return r.returncode, r.stdout
    except (OSError, subprocess.SubprocessError):
        return None


def load(path):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return None


def res(rc, reason="", **kw):
    return dict(rc=rc, reason=reason, **kw)


def pane_of(seat):
    """(pane_pid, 'session:@win.%pane') | res(실패)."""
    r = sh("tmux", "display", "-p", "-t", "=" + seat + ":", "#{pane_pid}\t#{session_name}:#{window_id}.#{pane_id}")
    if r is None:
        return res(2, "tmux 조회 불가(시간 초과)")
    parts = r[1].strip().split("\t")
    if r[0] != 0 or not parts[0]:
        return res(1, "tmux 세션 없음")
    if len(parts) < 2 or not parts[1]:
        return res(2, "pane 식별 조회 불가")
    return parts[0], parts[1]


def candidates(pane_pid):
    """pgrep rc 3분기 — 0 목록 · 1 정상 무일치(자식 없음) · 그 밖/숫자 아닌 토큰 = 조회 오류(rc 2 · 후보 부재로 바꾸지 않는다)."""
    if not pane_pid.isdigit():
        return res(2, "pane pid 형식 오류")
    k = sh("pgrep", "-P", pane_pid)
    if k is None:
        return res(2, "pgrep 조회 불가(시간 초과)")
    toks = k[1].split()
    if k[0] not in (0, 1) or (k[0] == 1 and toks) or not all(t.isdigit() for t in toks):
        return res(2, f"pgrep 조회 오류(rc={k[0]})")
    return list(dict.fromkeys([pane_pid] + toks))


def proc_of(pid, engine="claude"):
    """(lstart, '') | res(실패) — 실재 ∧ 실행 주체 engine. ps 두 조회 중 하나라도 rc≠0 이면 부분 출력이 있어도 조회 오류(rc 2)."""
    ls, cm = sh("ps", "-o", "lstart=", "-p", pid), sh("ps", "-o", "comm=", "-p", pid)
    if ls is None or cm is None:
        return res(2, "ps 조회 불가(시간 초과)")
    if ls[0] != 0 or cm[0] != 0:
        return res(2, f"ps 조회 오류(lstart rc={ls[0]} · comm rc={cm[0]})")
    lstart, comm = ls[1].strip(), cm[1].strip()
    if not lstart or not comm:
        return res(1, "프로세스 없음")
    if os.path.basename(comm) != engine:
        return res(1, f"실행 주체 {engine} 아님")
    return lstart, ""


def bind_codex(pane_pid, ident, home):
    """R400 codex 좌석: pane 자손(깊이 ≤4 · npm→node→codex) 중 실행 주체 codex 가 연 ~/.codex/sessions/**/rollout-*.jsonl «정확히 1개» ∧ 첫 줄 session_meta id == 파일명 끝 ∧ 시작시각 ≤ mtime · codex 프로세스 없음 = None."""
    level, pairs, found = [pane_pid], [], False
    for _ in range(4):
        nxt = []
        for p in level:
            if isinstance(c := candidates(p), dict): return c
            nxt += c[1:]
        for d in (level := list(dict.fromkeys(nxt))):
            lf = sh("lsof", "-Fn", "-p", d) if (cm := sh("ps", "-o", "comm=", "-p", d)) and os.path.basename(cm[1].strip()) == "codex" else ()
            if cm is None or lf is None: return res(2, "ps·lsof 조회 불가(시간 초과)")
            found |= bool(lf); pairs += [(d, ln[1:]) for ln in (lf[1].splitlines() if lf else []) if ln.startswith(f"n{home}/.codex/sessions/") and re.search(r"/rollout-[^/]*\.jsonl$", ln)]
    if not found or len(pairs) != 1: return res(1, f"codex rollout {len(pairs)}개") if found else None
    (pid, path), pr = pairs[0], proc_of(pairs[0][0], "codex")
    if isinstance(pr, dict): return pr
    try: m = json.loads(open(path, encoding="utf-8").readline())
    except (OSError, ValueError): m = None
    p = m.get("payload") if isinstance(m, dict) and m.get("type") == "session_meta" else None
    uuid, cwd = (p.get("id") or "", p.get("cwd") or "") if isinstance(p, dict) else ("", "")
    if not (uuid and cwd and path.endswith(f"-{uuid}.jsonl")): return res(1, "rollout id·cwd 없음")
    if (started := lstart_epoch(pr[0])) is None or started > os.path.getmtime(path) + 1: return res(1, "시간 모순: 프로세스 시작시각 > rollout mtime")
    sess, win, pane = re.fullmatch(r"(.+):(@\d+)\.(%\d+)", ident).groups()
    return res(0, "", pid=int(pid), uuid=uuid, cwd=cwd, jsonl=path, name=None, name_source=None, engine="codex", binding=dict(session=sess, window=win, pane=pane, pid=int(pid), lstart=pr[0], source="codex-open-fd"))


def lstart_epoch(lstart):
    try:
        return time.mktime(time.strptime(lstart, "%a %b %d %H:%M:%S %Y"))
    except ValueError:
        return None


def owner_source(s, seat, ident):
    """(source | res(NORECORD)) — tmux 칸이 있으면 칸 전부 == 이 pane · 칸 부재만 name 후퇴."""
    if "tmux" not in s:
        return "legacy-name" if s.get("name") == seat else res(1, "소유 불일치: tmux 칸 없음 · name≠좌석")
    col = s.get("tmux")
    if not (isinstance(col, str) and re.fullmatch(r"(.+):(@\d+)\.(%\d+)", col)):
        return res(1, "tmux 칸 형식 깨짐")
    return "tmux-col" if col == ident else res(1, "소유 불일치: tmux 칸 ≠ 이 pane")


def bind(seat):
    home = os.path.expanduser("~")
    p = pane_of(seat)
    if isinstance(p, dict):
        return p
    pane_pid, ident = p
    cands = candidates(pane_pid)
    if isinstance(cands, dict):
        return cands
    files = [c for c in cands if os.path.isfile(f"{home}/.claude/sessions/{c}.json")]
    if not files and (cx := bind_codex(pane_pid, ident, home)) is not None: return cx   # claude 세션 파일 0개 → codex 좌석인가(R400)
    if len(files) != 1:
        return res(1, f"세션 파일 {len(files)}개")
    pid = files[0]
    sf = f"{home}/.claude/sessions/{pid}.json"
    s = load(sf)
    if not isinstance(s, dict):
        return res(1, "세션 파일 읽기 실패")
    if str(s.get("pid")) != pid:
        return res(1, "소유 불일치: 파일 pid ≠ 후보 pid")
    src = owner_source(s, seat, ident)
    if isinstance(src, dict):
        return src
    pr = proc_of(pid)
    if isinstance(pr, dict):
        return pr
    started = lstart_epoch(pr[0])
    if started is None or started > os.path.getmtime(sf) + 1:
        return res(1, "시간 모순: 프로세스 시작시각 > 세션 파일 mtime")
    uuid, cwd = s.get("sessionId") or "", s.get("cwd") or ""
    jsonl = f"{home}/.claude/projects/{re.sub('[^A-Za-z0-9]', '-', cwd)}/{uuid}.jsonl"
    if not (uuid and cwd and os.path.isfile(jsonl)):
        return res(1, "uuid·cwd·jsonl 없음")
    sess, rest = ident.split(":", 1)
    win, pane = rest.split(".", 1)
    return res(0, "", pid=int(pid), uuid=uuid, cwd=cwd, jsonl=jsonl, name=s.get("name"), name_source=s.get("nameSource"),
               binding=dict(session=sess, window=win, pane=pane, pid=int(pid), lstart=pr[0], source=src))


def expect(seat, rec_path):
    rec = load(rec_path)
    b = rec.get("binding") if isinstance(rec, dict) else None
    keys = ("session", "window", "pane", "pid", "lstart")
    if not (isinstance(b, dict) and all(b.get(k) not in (None, "") for k in keys)):
        return res(1, "기록에 binding 없음")
    p = pane_of(seat)
    if isinstance(p, dict):
        return p
    pane_pid, ident = p
    if ident != f"{b['session']}:{b['window']}.{b['pane']}":
        return res(1, "pane 불일치")
    cands = candidates(pane_pid)
    if isinstance(cands, dict):
        return cands
    if str(b["pid"]) not in cands:
        return res(1, "pid 불일치")
    pr = proc_of(str(b["pid"]))
    if isinstance(pr, dict):
        return pr
    return res(0) if pr[0] == b["lstart"] else res(1, "시작시각 불일치(pid 재사용)")


def main(argv):
    if len(argv) == 1 and not argv[0].startswith("-"):
        r = bind(argv[0])
    elif len(argv) == 3 and argv[1] == "--expect":
        r = expect(argv[0], argv[2])
    else:
        print("usage: ft_seat_bind.py <좌석> [--expect <재개 기록.json>]", file=sys.stderr)
        return 2
    print(json.dumps(r, ensure_ascii=False))
    return r["rc"]


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
