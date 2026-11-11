#!/bin/bash
# fable-team ft-worker-guard — PreToolUse:Write|Edit|MultiEdit(+Bash 쓰기 대표 패턴) (§1-2 매트릭스 강제부, §1-5)
# FT_WORKER_ROLE 기준 역할별 allowlist 대조 → 위반 deny(exit 2). 전 역할 공통 deny에
# install.json·.fable-team/approvals/** 포함(§0-2 L1 — 승인 기록의 워커발 오염 차단).
# ★ FAIL-OPEN(AR-2 수용): 어떤 파싱 오류·환경 이상에서도 exit 0. FT_WORKER_ROLE 미주입 = 비대상 → 허용.
# ★ 완화 계층이지 '등가'가 아니다(§1-2 재정의) — 대표 경로 차단 + DA 게이트 이중 방어.
set +e
INPUT=$(cat 2>/dev/null)
[ -z "$INPUT" ] && exit 0
ROLE="${FT_WORKER_ROLE:-}"
[ -z "$ROLE" ] && exit 0   # 워커 아님(또는 env 미주입 — AR-2/AR-5 수용) → 허용

python3 - "$INPUT" "$ROLE" <<'PYEOF'
import json, sys, os, re, subprocess
from datetime import datetime, timezone
def allow(): sys.exit(0)
def deny(msg):
    sys.stderr.write("🚫 [ft-worker-guard] " + msg + "\n"); sys.exit(2)

try:
    data = json.loads(sys.argv[1]); role = sys.argv[2]
except Exception:
    allow()   # fail-open

tool = data.get("tool_name", "")
tin  = data.get("tool_input", {}) or {}
seat = os.environ.get("FT_SEAT_NAME") or os.environ.get("FT_SEAT") or role


# 경로에서 .fable-team/ 이후 상대부를 추출(절대/상대 무관). 없으면 원본 사용.
def relpart(p):
    if not isinstance(p, str) or not p:
        return ""
    p = p.strip().strip('"\'')
    m = re.search(r'\.fable-team/(.*)$', p)
    return m.group(1) if m else p

# ── 전 역할 공통 deny: install.json · approvals/** (§0-2 L1) ──
COMMON_DENY = re.compile(r'(^|/)install\.json$|(^|/)approvals(/|$)')
# ── r1672: 라이브 설치 자리(ⓑ) — 직접 쓰기 금지(설치 = master h). 라이브 «읽기»(cat·cmp·diff·ls)는 쓰기 패턴이 없어 통과 ──
PROTECT = re.compile(r'(^|[\s/])\.fable-team/bin(-[^/\s]*)?(/|\s|$)|(^|[\s/])\.pi/agent/extensions(/|\s|$)|(^|[\s/])fable-team/live(/|\s|$)|(^|[\s/])\.fable-team/comm/(mailbox[^/\s]*\.jsonl|bodies/|drops/)')
def live_hit(path, rel):   # 파일 경로 — 정적 칸 + rel(bin*/comm) 꼴 · 실경로(심링크·..) 판정은 pi 확장(ⓐ·ⓑ)이 맡는다
    return bool(PROTECT.search(str(path).replace(os.sep, "/")) or PROTECT.search(rel) or re.match(r'^bin(-[^/]*)?/', rel))
def live_cmd(cmd):   # Bash — «쓰기 동사의 대상» 만 본다(R3: 공백 없는 `>파일`·rsync·ln 포함 · `cp 라이브 /tmp` = 읽기는 통과)
    toks = re.findall(r'"[^"]*"|\'[^\']*\'|[^\s"\']+', cmd)
    for i, t in enumerate(toks):
        j = t.rfind(">")
        if j >= 0 and t[j + 1:] and not t[j + 1:].startswith("&") and PROTECT.search(t[j + 1:]):
            return t[j + 1:]   # `text>라이브` · `>라이브`
        if t in (">", ">>") and i + 1 < len(toks) and PROTECT.search(toks[i + 1]):
            return toks[i + 1]
        base = os.path.basename(t)
        if base not in ("cp", "mv", "install", "rsync", "tee", "ln", "dd"):
            continue
        args = []
        for a in toks[i + 1:]:
            if a in (";", "&&", "||", "|") or ">" in a: break
            if not a.startswith("-"): args.append(a)
        if not args: continue
        cand = args[-1:] + args[:1] if base == "mv" else (args if base in ("tee", "dd") else args[-1:])
        for a in cand:
            if PROTECT.search(a): return a
    return ""
def wx_log(tool, target):   # r1672 R4: worker 거절도 감지 1줄(같은 좌석·같은 대상 1회 · 일반 파일)
    try:
        root = os.environ.get("FT_LIVE_ROOT") or os.path.dirname(subprocess.check_output(
            ["git", "rev-parse", "--path-format=absolute", "--git-common-dir"], text=True, stderr=subprocess.DEVNULL, timeout=7).strip())
        f = os.path.join(root, ".fable-team", "state", "live-write-block.log")
        prev = open(f, encoding="utf-8").read().split("\n") if os.path.exists(f) else []
        if any((" %s " % seat) in l and l.endswith(" " + target) for l in prev): return
        os.makedirs(os.path.dirname(f), exist_ok=True)
        with open(f, "a", encoding="utf-8") as fh:
            fh.write("%s %s %s %s\n" % (datetime.now(timezone.utc).isoformat(timespec="seconds"), seat, tool, target))
    except Exception:
        sys.stderr.write("ERROR ft-worker-guard: 감지 로그 실패 %s\n" % target)

# 역할별 Write allowlist (rel 매치). 값이 None = 제한 없음(implementer/tester).
ALLOW = {
    "analyst":     r'(^|/)state/[^/]+/analysis[^/]*|(^|/)\.signals(/|$)',
    "checker":     r'(^|/)state/[^/]+/checker-[^/]*\.json$|(^|/)\.signals(/|$)',
    "da":          r'(^|/)state/[^/]+/da-[^/]*\.md$|(^|/)\.signals(/|$)',
    "da2":         r'(^|/)state/[^/]+/da-[^/]*\.md$|(^|/)\.signals(/|$)',
    "architect":   r'(^|/)designs(/|$)|(^|/)state(/|$)',
    "pm":          r'(^|/)pm(/|$)|(^|/)\.signals(/|$)',
}

# ── Write/Edit/MultiEdit: 파일 경로 판정 ──
if tool in ("Write", "Edit", "MultiEdit", "NotebookEdit"):
    path = tin.get("file_path") or tin.get("notebook_path") or ""
    rel = relpart(path)
    if COMMON_DENY.search(rel) or live_hit(path, rel):
        if live_hit(path, rel): wx_log(tool, str(path))   # R4: worker 거절도 감지 1줄
        deny("전 역할 공통 금지 대상입니다(install.json·approvals/**·라이브 자리 r1672): %s" % path)
    pat = ALLOW.get(role, None)
    if pat is None:
        allow()   # implementer/tester 등 — 코드 수정이 본업, deny 없음(공통 deny만 적용)
    if not re.search(pat, rel):
        deny("%s 역할 allowlist 위반 — 허용 경로: %s / 요청: %s" % (role, pat, path))
    allow()

# ── Bash: 쓰기 대표 패턴만 (install.json·approvals 오염 차단 + pm의 비-cairn/baton 쓰기) ──
if tool == "Bash":
    cmd = tin.get("command", "") or ""
    if not isinstance(cmd, str):
        allow()
    writes = re.compile(r'(>>?|\btee\b|\bsed\b[^|;]*-i|\bcp\b|\bmv\b|\bdd\b|\binstall\b|\brsync\b|\bln\b)')
    # 전 역할 공통: install.json·approvals/ 로의 쓰기 대표 패턴 · 라이브 자리(R3: rsync·ln·공백 없는 > 포함)
    lt = live_cmd(cmd)
    if (re.search(r'install\.json|\.fable-team/approvals/', cmd) or lt) and writes.search(cmd):
        if lt: wx_log(tool, lt)   # R4
        deny("전 역할 공통 금지(Bash 쓰기) — install.json·approvals·라이브 자리(r1672) 오염: %s" % cmd.strip()[:120])
    # pm 역할: cairn/baton CLI 외 Bash 쓰기 명령 대표 deny
    if role == "pm" and writes.search(cmd):
        first = (cmd.strip().split() or [""])[0]
        base = os.path.basename(first)
        if base not in ("cairn", "baton") and not re.search(r'(^|/)(cairn|baton)(\s|/|$)', cmd):
            deny("pm는 cairn/baton CLI 외 Bash 쓰기 금지(대표 패턴): %s" % cmd.strip()[:120])
    allow()

allow()
PYEOF
RC=$?
[ "$RC" = "2" ] && exit 2
exit 0
