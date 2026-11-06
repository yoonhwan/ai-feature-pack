#!/usr/bin/env bash
# ft-lead-eval.sh [--hours 24] [--json]   (r1436)
#   팀장 교체 판단용 «측정 표» — 각 master 좌석의 최근 도구 사용 성향으로 «실행형↔판단형» 을 가른다.
#   실행형(코드·스크립트·측정 위주) = codex 적합. 판단형(질문·결정·문서) = claude 유지.
#   지표 = 좌석 jsonl 의 tool_use 이름 분포 → Bash 비율 · AskUserQuestion 횟수 · 총 호출.
#   출력 = 표 + 추천(즉시/보류/비권장) + 전환 명령 안내(실행 0). 네트워크 0.
#   ★한계(초안)★ 좌석 귀속을 «워크트리» 로 잇는다 — 같은 워크트리를 쓰는 구·신 좌석(#242 와 #243 처럼)이
#     한 덩어리로 합쳐진다. 그래서 이 표는 «팀 성향 힌트» 이고 교체 결정의 단독 근거가 아니다.
#     정본 판단 = 역할 등급표(즉시: ops·feature·issues·harness / 조건부: knowledge·lecture·room·graphics·ccu / 보류: planner·cfo·v65·chatbot).
set -uo pipefail
HOURS=24; JSON=0
while [ $# -gt 0 ]; do case "$1" in --hours) HOURS="$2"; shift 2;; --json) JSON=1; shift;; *) shift;; esac; done
python3 - "$HOURS" "$JSON" "$HOME" "${FT_ROOT:-$PWD}" <<'PY'
import collections, datetime, glob, json, os, sys, time
hours, as_json, home, root = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
cut = time.time() - float(hours) * 3600
# 좌석 → jsonl: 명부의 worktree 경로를 claude 프로젝트 slug 로 바꿔 최신 파일을 쓴다(가장 확실).
def slug(path):
    return path.replace("/", "-").replace("_", "-")
masters = {}
for f in glob.glob(os.path.join(root, ".fable-team/seats*.json")):
    try: d = json.load(open(f))
    except Exception: continue
    team_best = {}
    for k, v in d.items():
        if k.startswith("_") or not isinstance(v, dict): continue
        if "-master-" not in k or v.get("_replaced_by"): continue
        import re as _re
        m = _re.search(r"#(\d+)$", k); n = int(m.group(1)) if m else -1
        team = k.split("-master-")[0]
        if team not in team_best or n > team_best[team][0]:
            team_best[team] = (n, k, v)
    for team, (n, k, v) in team_best.items():
        masters[k] = (v.get("agent"), v.get("model"), v.get("worktree") or "")
stats = collections.defaultdict(collections.Counter)
for seat, (agent, model, wt) in masters.items():
    wt = (wt or "").strip("/")
    if not wt:
        continue                                   # worktree 미상이면 남의 기록을 세지 않는다
    exact = os.path.join(home, ".claude/projects", slug(os.path.join(root, ".worktrees", wt)))
    cands = [c for c in glob.glob(os.path.join(exact, "*.jsonl")) if os.path.getmtime(c) >= cut]
    if not cands:
        cands = [c for c in glob.glob(os.path.join(home, ".claude/projects", "*--worktrees-" + slug(wt), "*.jsonl")) if os.path.getmtime(c) >= cut]
    for jf in cands:
        for line in open(jf, encoding="utf-8", errors="ignore"):
            if '"tool_use"' not in line: continue
            try: d2 = json.loads(line)
            except ValueError: continue
            for b in ((d2.get("message") or {}).get("content") or []):
                if isinstance(b, dict) and b.get("type") == "tool_use":
                    stats[seat][b.get("name")] += 1
rows = []
for seat, (agent, model, _wt) in masters.items():
    s = stats.get(seat, collections.Counter())
    total = sum(s.values())
    bash = s.get("Bash", 0)
    ask = s.get("AskUserQuestion", 0)
    ratio = (100.0 * bash / total) if total else 0.0
    if total < 5: verdict, why = "관측부족", "호출 %d건" % total
    elif ratio >= 70 and ask <= max(1, total * 0.05): verdict, why = "즉시", "Bash %.0f%% · 질문 %d" % (ratio, ask)
    elif ratio >= 50: verdict, why = "보류", "Bash %.0f%% · 질문 %d" % (ratio, ask)
    else: verdict, why = "비권장", "Bash %.0f%% · 질문 %d" % (ratio, ask)
    rows.append(dict(seat=seat, agent=agent, model=model, calls=total, bash=bash, ask=ask,
                     ratio=round(ratio, 1), verdict=verdict, why=why))
rows.sort(key=lambda r: (-r["ratio"], -r["calls"]))
if as_json == "1":
    print(json.dumps(rows, ensure_ascii=False, indent=1)); raise SystemExit
print("기준 = 최근 %s시간 tool_use 분포 · Bash 비율 ≥70%%+질문 5%%이하 = 즉시 · ≥50%% = 보류 · 그 외 = 비권장" % hours)
print("%-34s %-9s %6s %6s %6s %7s %-8s %s" % ("master 좌석", "model", "호출", "Bash", "질문", "Bash%", "판정", "근거"))
print("-" * 138)
for r in rows:
    print("%-34s %-9s %6d %6d %6d %6.0f%% %-8s %s" % (r["seat"][:34], (r["model"] or "-")[:9], r["calls"], r["bash"], r["ask"], r["ratio"], r["verdict"], r["why"]))
imm = [r["seat"] for r in rows if r["verdict"] == "즉시"]
print()
print("즉시 후보 %d명 → 전환 명령은 `ft-switch-plan.sh --to codex --teams %s`" % (len(imm), ",".join(x.split("-master-")[0].replace("byz-", "") for x in imm) or "-"))
print("판단: 즉시 후보만 codex, 나머지는 claude 유지. 전환·되돌림 모두 ft-successor-open 1회(증류).")
PY
