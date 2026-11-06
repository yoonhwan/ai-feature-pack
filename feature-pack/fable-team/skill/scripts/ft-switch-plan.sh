#!/usr/bin/env bash
# ft-switch-plan.sh [--to codex|claude] [--teams a,b] [--json]   (r1434)
#   «선택 전환» 준비 도구 — 자동 폴백이 아니라 사람/데스크가 빠르게 고르도록 «명령을 미리 만들어 준다».
#   전환기 = 이미 있는 ft-successor-open(승계·증류). 이 도구는 실행하지 않는다(출력만).
#   출력 = 팀장 표(현재 모델·계정 여유) + 좌석별 전환 명령 1줄 + 체크 3개 + 되돌림 1줄.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
TO=""; TEAMS=""; JSON=0
while [ $# -gt 0 ]; do case "$1" in
  --to) TO="$2"; shift 2;; --teams) TEAMS="$2"; shift 2;; --json) JSON=1; shift;; -*) shift;; *) shift;; esac; done
python3 - "$HERE" "$TO" "$TEAMS" "$JSON" "${FT_ROOT:-$PWD}" <<'PY'
import glob, json, os, re, sys, subprocess
here, to, teams, as_json, root = sys.argv[1:6]
MODEL = {"codex": ("codex", "gpt-6.1-sol"), "claude": ("claude", "claude-opus-5-5")}
rows = []
for f in sorted(glob.glob(os.path.join(root, ".fable-team", "seats*.json"))):
    try: d = json.load(open(f))
    except Exception: continue
    for k, v in d.items():
        if k.startswith("_") or not isinstance(v, dict): continue
        if "-master-" not in k: continue
        if v.get("_replaced_by"): continue          # 은퇴 좌석 제외
        n = re.search(r"#(\d+)$", k)
        rows.append(dict(seat=k, num=int(n.group(1)) if n else -1, agent=v.get("agent") or "claude",
                         model=v.get("model") or "-", org=(v.get("_tree") or "")[:0]))
# 계정 여유
avail = {}
try:
    out = subprocess.run(["bash", os.path.join(here, "ft-acct-quota.sh"), "--json"], capture_output=True, text=True, timeout=40).stdout
    for r in json.loads(out):
        p = r.get("provider"); avail.setdefault(p, {"ok": 0, "total": 0})
        avail[p]["total"] += 1
        if not r.get("disabled") and (r.get("u5") is None or r["u5"] < 100) and (r.get("w") is None or r["w"] < 100):
            avail[p]["ok"] += 1
except Exception:
    avail = {}
if teams:
    want = [t.strip() for t in teams.split(",") if t.strip()]
    rows = [r for r in rows if any(w in r["seat"] for w in want)]
if to not in MODEL: to = ""
pk = lambda p: "%s 가용 %d/%d" % (p, avail.get(p, {}).get("ok", 0), avail.get(p, {}).get("total", 0))
if as_json == "1":
    print(json.dumps(dict(to=to, accounts=avail, seats=rows), ensure_ascii=False, indent=1)); raise SystemExit
print("계정 여유 = claude %s · codex %s" % (pk("claude"), pk("codex")))
print("%-34s %-24s %-6s %s" % ("팀장 좌석", "현재 모델", "#", "전환 명령"))
print("-" * 132)
for r in sorted(rows, key=lambda x: x["seat"]):
    if not to:
        print("%-34s %-24s %-6d %s" % (r["seat"], r["model"], r["num"], "( --to codex|claude 로 명령 생성 )")); continue
    ag, md = MODEL[to]
    if (ag == "codex" and r["agent"] == "codex") or (ag == "claude" and r["agent"] == "claude"):
        print("%-34s %-24s %-6d 이미 %s" % (r["seat"], r["model"], r["num"], ag)); continue
    tok = "sol" if ag == "codex" else "claude"
    base = re.sub(r"-(claude|sol)-master-.*$", "", r["seat"])
    role = re.search(r"-master-", r["seat"])
    newname = re.sub(r"-(claude|sol)(?=#[0-9]+$)", "-" + tok, re.sub(r"#[0-9]+$", "#%d" % (r["num"] + 1), r["seat"]))
    wt = ".worktrees/" + (r["seat"].split("-master-")[0].replace("byz-", "") + "-lead")
    body = ".fable-team/state/successor-body-%s.md" % newname.split("#")[0]
    print("%-34s %-24s %-6d bash .fable-team/bin/ft-successor-open.sh '%s' %s --name '%s' --agent %s --model %s --effort high --body-file %s"
          % (r["seat"], r["model"], r["num"], r["seat"], wt, newname, ag, md, body))
print()
print("체크 3개 = ① %s 가용 ≥1 ② 워크트리 clean ③ 인계서 본문 존재(--body-file)" % (to or "대상엔진"))
print("되돌림 = 같은 명령에서 --agent/--model 을 반대 엔진으로, 이름은 -claude#N+1 / -sol#N+1")
print("주의 = codex 좌석은 -c model_auto_compact_token_limit=300000 을 실행 인자에 넣어 300k 압축을 강제한다")
PY
