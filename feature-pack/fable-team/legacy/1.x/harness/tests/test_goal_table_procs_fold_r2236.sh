#!/usr/bin/env bash
# test_goal_table_procs_fold_r2236.sh — 표준절차 골 블록(procs)이 예산 1600B 를 넘으면 블록을 통째로 버렸다 → 줄임 단계 ①~⑥(r2236).
#   ① 오늘 원장 꼴(골 파일 15 = 행 · 담당 없음 6 · 정지 8 · 담당 긴 새 골 1) → rc0 · ③ 단계 · ≤1600B · «정지 골 8» · «진행표 행 없음 6» · WARN 6
#   ② 행 없고 «담당:» 줄 있는 골 = 묶음 밖 제 줄   ③ 행 있고 담당 «—» 인 골 = ①~⑤ 모든 단계에서 제 줄
#   ④ ① + 행 없는 4 + 정지 아닌 긴 골 3 → ④ 단계 · «진행표 행 없음 10» · WARN 10
#   ⑤ 이름 긴 정지 골 20 + 정지 아닌 골 5 → ⑥ 접기 · 정지 줄 먼저 · «… 외 K골(정지 M)» · «정지 골 20» = ⚠ 줄 + M · 접음 WARN 1
#   ⑥ 완료 + 실재 sha10 행 3 + 예산 넉넉 → 기준판과 바이트 같음   ⑦ 골 0 · 원장 못 읽음 rc1 · teams 기준판과 바이트 같음
# R2236_TOOL = 대조할 판(기준판 Red · 변이) · 픽스처 = mktemp 임시 git 리포 · 실 리포·실 원장·외부 호출 0 · sleep 0.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
TOOL="${R2236_TOOL:-$HERE/../bin/ft_goal_table.py}"
PFX="$(cd -- "$HERE/.." && pwd -P)"; ROOT="$(git -C "$HERE" rev-parse --show-toplevel)"; PFX="${PFX#"$ROOT"/}"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0; ok() { echo "PASS $1"; }; bad() { echo "FAIL $1"; fail=$((fail+1)); }
cp -R "$HERE/../bin" "$T/basebin"; git -C "$ROOT" show "origin/main:$PFX/bin/ft_goal_table.py" > "$T/basebin/ft_goal_table.py"
F=design/teams/planner
cat > "$T/gen.py" <<'PY'
import json, os, subprocess, sys
repo, spec = sys.argv[1], json.loads(sys.argv[2])
F = "design/teams/planner"; os.makedirs(f"{repo}/{F}", exist_ok=True); os.makedirs(f"{repo}/design", exist_ok=True)
def git(*a, date=None):
    env = dict(os.environ, **({"GIT_AUTHOR_DATE": date, "GIT_COMMITTER_DATE": date} if date else {}))
    return subprocess.run(["git", "-C", repo, *a], check=True, capture_output=True, text=True, env=env).stdout
git("init", "-q", "-b", "main")
open(f"{repo}/design/TEAMS.md", "w").write(f"| 팀 | 폴더 | 오케 | 상태 |\n|---|---|---|---|\n| planner | `{F}/` | x | 현역 |\n")
for g in spec:
    own = f"\n담당: {g['line_owner']}\n" if g.get("line_owner") else ""
    open(f"{repo}/{F}/{g['file']}", "w").write(f"# 골 — {g['name']}\n{own}\n## 골\n문장\n")
def ledger(kinds, sha=""):
    rows = [f"| {g['name']} | {g['file']} | {g.get('owner', '')} | {g['stage'].replace('SHA', sha)} | 다음 |" for g in spec if g["kind"] in kinds]
    open(f"{repo}/{F}/PLAN-oppa-ledger.md", "w").write("# 원장\n\n## 팀별 완성 진행\n\n| 팀 | 끝선 N/M | 마지막 착지 | 지금 하는 것 |\n|---|---|---|---|\n| planner | 3/5 | a1b2 | 골 표 |\n\n"
        "## 표준절차 골 진행표\n\n| 골 | 골 파일 | 담당 | 지금 단계 | 다음 |\n|---|---|---|---|---|\n" + "".join(r + "\n" for r in rows))
def commit(msg, date):
    git("add", "-A"); git("-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "--allow-empty", "-m", msg, date=date)
ledger({"stale"}); commit("old", "2026-10-20T12:00:00")
sha = git("rev-parse", "HEAD")[:10]
ledger({"stale", "fresh", "done"}, sha); commit("new", "2026-11-18T10:00:00")
git("update-ref", "refs/remotes/origin/main", "HEAD")
PY
mk() { rm -rf "$T/r"; python3 "$T/gen.py" "$T/r" "$(python3 -c "$1")"; }  # <스펙 JSON 을 찍는 python>
run() { env -u FT_GOAL_A6_MD -u FT_GOAL_A6_LEDGER -u FT_LEDGER_PATH -u FT_GOAL_PROC_STALE_H -u FT_ROOT FT_NOW="2026-11-18 12:00" \
  FT_GOAL_REPO="$T/r" FT_LEDGER_REPO="$T/r" FT_TEAMS_REF=origin/main python3 "${2:-$TOOL}" "${1:-procs}" 2>"$T/err"; }
step() {  # 블록 → 줄임 단계 1~6(접기 줄 · 완성 수만 · 단계 칸 폭 · 묶음 수만 으로 판독)
  python3 -c '
import sys, re
t = sys.stdin.read().splitlines()
if any(l.startswith("… 외 ") for l in t): print(6); sys.exit()
if any(re.fullmatch(r"완성 \d+", l) for l in t): print(5); sys.exit()
w = max((len(l.split(" · ")[-1].split(" ⚠")[0]) - 1 for l in t if l.startswith("- ") and "…" in l), default=0)
if w == 12: print(4); sys.exit()
if any(re.fullmatch(r"진행표 행 없음 \d+", l) for l in t): print(3); sys.exit()
print(2 if w == 24 else 1)'
}
B() { printf '%s' "$1" | wc -c | tr -d ' '; }
has() { printf '%s\n' "$1" | grep -qxF -- "$2"; }
cnt() { printf '%s\n' "$1" | grep -c -- "$2"; }
LONG='② 제안서를 쓰는 중이며 사전 판정 회신을 기다린 뒤에 나노 발주로 넘어가는 단계'
# 스펙 조각(python): P = 행·담당 없음 · S = 정지 · N = 담당 긴 새 골(행 · 담당 칸 빈 = «—» · 정지 아님)
SPEC1="L='$LONG'
P=[dict(file=f'GOAL-a-plan{i}-20261021.md',name=f'계획 문서 묶음 ALIGN 완료 계획 {i}',kind='norow',stage='') for i in range(6)]
S=[dict(file=f'GOAL-b-stale{i}-20261021.md',name=f'정지 골 운영 정리 {i}',kind='stale',owner='planner · byz-harness-arch-pi',stage=L) for i in range(8)]
N=[dict(file='GOAL-c-harness-20261117.md',name='하네스팀 골',kind='fresh',owner='',stage=L,line_owner='')]"
# ── ① 오늘 원장 꼴
mk "$SPEC1
import json; print(json.dumps(P+S+N))"
OUT="$(run)"; RC=$?
[ "$RC" = 0 ] && [ -n "$OUT" ] && [ "$(B "$OUT")" -le 1600 ] && [ "$(step <<<"$OUT")" = 3 ] && ok "①1 rc0 · ③ 단계(24자 + 묶음 수만) · $(B "$OUT")B ≤ 1600B" || bad "①1 rc=$RC $(B "$OUT")B step=$(step <<<"$OUT") :: $OUT"
[ "$(cnt "$OUT" '^- 하네스팀 골 · — · ')" = 1 ] && [ "$(cnt "$OUT" '⚠')" = 8 ] && has "$OUT" "정지 골 8" && has "$OUT" "진행표 행 없음 6" \
  && ok "①2 새 골 줄 1 · ⚠ 줄 8 · «정지 골 8» · «진행표 행 없음 6»" || bad "①2 :: $OUT"
[ "$(grep -c 'WARN 표준절차 골 진행표 행 없음: ' "$T/err")" = 6 ] && ! grep -q '예산 초과' "$T/err" && ok "①3 stderr WARN 6줄(파일마다) · 예산 WARN 0" || bad "①3 :: $(cat "$T/err")"
OUT1="$OUT"
# ── ② 행 없고 «담당:» 줄 있는 골 = 묶음 밖 제 줄
mk "$SPEC1
P[0]['line_owner']='팀X'
import json; print(json.dumps(P[:2]+N))"
OUT="$(run)"
has "$OUT" "- 계획 문서 묶음 ALIGN 완료 계획 0 · 팀X · 진행표 행 없음" && has "$OUT" "진행표 행 없음 1: 계획 문서 묶음 ALIGN 완료 계획 1" && ok "② «담당:» 줄 있는 행 없는 골 = 제 줄 · 담당 없는 것만 묶음" || bad "② :: $OUT"
# ── ④ ① + 행 없는 4 + 정지 아닌 긴 골 3 → ④ 단계
mk "$SPEC1
P+=[dict(file=f'GOAL-a-plan{i}-20261021.md',name=f'계획 문서 묶음 ALIGN 완료 계획 {i}',kind='norow',stage='') for i in range(6,10)]
X=[dict(file=f'GOAL-d-live{i}-20261117.md',name=f'살아 있는 긴 골 이름 하네스 운영 {i}',kind='fresh',owner='byz-harness-master-pi',stage=L) for i in range(3)]
import json; print(json.dumps(P+S+N+X))"
OUT="$(run)"; OUT4="$OUT"
[ "$(step <<<"$OUT")" = 4 ] && [ "$(B "$OUT")" -le 1600 ] && has "$OUT" "진행표 행 없음 10" && [ "$(grep -c 'WARN 표준절차 골 진행표 행 없음: ' "$T/err")" = 10 ] \
  && ok "④ ④ 단계(12자) · «진행표 행 없음 10» · WARN 10줄 · $(B "$OUT")B" || bad "④ step=$(step <<<"$OUT") $(B "$OUT")B :: $OUT / $(cat "$T/err")"
# ── ⑤ 이름 긴 정지 골 20 + 정지 아닌 골 5(파일 이름 순 맨 아래) → ⑥ 접기
mk "S=[dict(file=f'GOAL-b-stale{i:02d}-20261021.md',name=f'아주 긴 이름의 정지 골 하네스 운영 정리 번호 {i}',kind='stale',owner='planner',stage='② 진행') for i in range(20)]
A=[dict(file=f'GOAL-z-live{i}-20261117.md',name=f'살아 있는 골 {i}',kind='fresh',owner='harness',stage='① 등록') for i in range(5)]
import json; print(json.dumps(S+A))"
OUT="$(run)"; RC=$?
FOLD="$(printf '%s\n' "$OUT" | grep '^… 외 ' || true)"; K="$(sed -E 's/^… 외 ([0-9]+)골.*/\1/' <<<"$FOLD")"; M="$(sed -E 's/.*\(정지 ([0-9]+)\)$/\1/' <<<"$FOLD")"
[ "$RC" = 0 ] && [ -n "$OUT" ] && [ "$(B "$OUT")" -le 1600 ] && [ -n "$FOLD" ] && ok "⑤1 ⑥ 접기 · $(B "$OUT")B ≤ 1600B · «${FOLD}»" || bad "⑤1 rc=$RC $(B "$OUT")B :: $OUT"
[ "$(cnt "$OUT" '^- 살아 있는 골 ')" = 5 ] && ok "⑤2 정지 줄 먼저 접힘 · 살아 있는 5줄 남음" || bad "⑤2 :: $OUT"
[ -n "$M" ] && has "$OUT" "정지 골 20" && [ "$(( $(cnt "$OUT" '⚠') + M ))" = 20 ] && ok "⑤3 «정지 골 20» = ⚠ 줄 $(cnt "$OUT" '⚠') + 접힌 정지 $M" || bad "⑤3 M=$M :: $OUT"
[ "$(grep -c "예산 초과 .* — ${K:-x}줄 접음" "$T/err")" = 1 ] && ok "⑤4 접음 WARN 1줄" || bad "⑤4 :: $(cat "$T/err")"
# ── ③ 행 있고 담당 «—» 인 정지 아닌 골 = ①~⑤ 모든 단계에서 제 줄(단계별 픽스처)
STEPS=""
for v in "1:N" "2:N+[dict(file=f'GOAL-e-{i}-20261117.md',name=f'살아 있는 골 이름 {i}',kind='fresh',owner='planner',stage=L) for i in range(12)]" \
         "5:N+[dict(file=f'GOAL-f-{i}-20261117.md',name='완'*300+str(i),kind='done',owner='planner',stage='완료 SHA') for i in range(3)]"; do
  mk "$SPEC1
import json; print(json.dumps($(cut -d: -f2- <<<"$v")))"
  O="$(run)"; s="$(step <<<"$O")"; [ "$s" = "${v%%:*}" ] && [ "$(cnt "$O" '^- 하네스팀 골 · — · ')" = 1 ] && STEPS="$STEPS $s" || bad "③ 단계 ${v%%:*} → $s :: $O"
done
for O in "$OUT1" "$OUT4"; do [ "$(cnt "$O" '^- 하네스팀 골 · — · ')" = 1 ] && STEPS="$STEPS $(step <<<"$O")"; done
[ "$STEPS" = " 1 2 5 3 4" ] && ok "③ 담당 «—» 행 있는 골 = 단계 1·2·3·4·5 모두 제 줄" || bad "③ 단계 =$STEPS"
# ── ⑥ 완료 + 실재 sha10 행 3 + 예산 넉넉 → 기준판과 바이트 같음
mk "import json; print(json.dumps([dict(file=f'GOAL-f-{i}-20261117.md',name=f'끝난 골 {i}',kind='done',owner='p',stage='완료 SHA') for i in range(3)]+[dict(file='GOAL-g-20261117.md',name='진행 골',kind='fresh',owner='p',stage='① 등록')]))"
OUT="$(run)"; BASEOUT="$(run procs "$T/basebin/ft_goal_table.py")"
has "$OUT" "완성 3: 끝난 골 0, 끝난 골 1, 끝난 골 2" && [ "$OUT" = "$BASEOUT" ] && ok "⑥ «완성 3: 이름들» 그대로 · 기준판과 바이트 같음" || bad "⑥ :: $OUT // $BASEOUT"
# ── ⑦ 골 0 · 원장 못 읽음 · teams 기준판과 바이트 같음
mk "import json; print(json.dumps([]))"
OUT="$(run)"; [ "$(printf '%s\n' "$OUT" | sed -n 2p)" = "표준절차 골 0" ] && [ "$OUT" = "$(run procs "$T/basebin/ft_goal_table.py")" ] && ok "⑦1 골 0 = «표준절차 골 0» · 기준판과 같음" || bad "⑦1 :: $OUT"
RC="$(env -u FT_ROOT FT_GOAL_REPO="$T/r" FT_LEDGER_REPO="$T/r" FT_TEAMS_REF=origin/main FT_GOAL_A6_LEDGER="gitref:origin/main:$F/NOPE.md" python3 "$TOOL" procs >/dev/null 2>"$T/err"; echo $?)"
[ "$RC" = 1 ] && grep -q 'ERROR 표준절차 골 원장 못 읽음' "$T/err" && ok "⑦2 원장 못 읽음 = ERROR rc1" || bad "⑦2 rc=$RC :: $(cat "$T/err")"
mk "$SPEC1
import json; print(json.dumps(P+S+N))"
OUT="$(run teams)"; [ -n "$OUT" ] && [ "$OUT" = "$(run teams "$T/basebin/ft_goal_table.py")" ] && ok "⑦3 teams 기준판과 바이트 같음" || bad "⑦3 :: $OUT"
[ "$fail" = 0 ] && { echo "ALL PASS"; exit 0; }
echo "FAIL $fail"; exit 1
