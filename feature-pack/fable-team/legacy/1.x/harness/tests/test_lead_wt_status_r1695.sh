#!/usr/bin/env bash
# test_lead_wt_status_r1695.sh — r1695 ft-lead-wt-status.sh(팀장 워크트리·가지 현황 집계 · 읽기 전용)
#   ⓐ worktree 목록 = porcelain «모든» 항목(시험이 따로 셈) · 경로 중복 0 · 공유 worktree 1개 + 좌석 2(master·arch) → 1행 · 팀장 · 좌석들 2
#   ⓑ 결속 목록 = 명부 _master·_arch 좌석 수(시험이 따로 셈) · 좌석 중복 0 · 공유 = 같은 경로 2행 · 불일치 0(공유 쪽) · 결속 경로 집합 = 팀장 행 경로 집합
#   ⓒ 착지 대상 = BASE 두 sha 중 하나(main) · behind 3(알려진 커밋 수) · upstream = BASE 밖 ref 이름(정보만 · 계산 0) · 첫 줄 BASE = origin/main·ops sha
#   변이(사본): M1 입력 worktree 1개 뺌 → ⓐ FAIL · M4 결속을 worktree 단위로 접음 → ⓑ FAIL · M5 behind 기준 = upstream → ⓒ FAIL
# 임시 bare 원격 · 실 리포·실 명부 0 · sleep 0
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; BIN="$HERE/../bin"
. "$HERE/_merge_fixture.sh"
fail=0
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1"; fail=$((fail+1)); fi; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkrepo "$T"
echo .worktrees/ >> "$W/.git/info/exclude"
git -C "$W" checkout -q -b ops/main-base "$M0"; echo o1 > "$W/o1.txt"; cm "$W" o1; echo o2 > "$W/o2.txt"; cm "$W" o2; echo o3 > "$W/o3.txt"; cm "$W" o3; echo o4 > "$W/o4.txt"; cm "$W" o4
git -C "$W" push -q origin ops/main-base; git -C "$W" checkout -q main
L="$W/.worktrees/lead"; git -C "$W" worktree add -q -b lead/r77-x "$L" main; echo lead > "$L/lead.txt"; cm "$L" "lead r77 work"
git -C "$L" push -q -u origin lead/r77-x:side 2>/dev/null   # upstream = origin/side (BASE 밖 ref)
for i in 1 2 3; do echo "m$i" > "$W/m$i.txt"; cm "$W" "main $i"; done; git -C "$W" push -q origin main
git -C "$W" worktree add -q -b nano/r9-n "$W/.worktrees/nano-r9" main
git -C "$W" worktree add -q --detach "$W/.worktrees/det" main
L2="$W/.worktrees/lead2"; git -C "$W" worktree add -q -b planner/r77-y "$L2" main; echo other > "$L2/lead.txt"; cm "$L2" "planner same file"
git -C "$W" fetch -q origin
SD="$T/seats"; mkdir -p "$SD"
printf '{"_master":"byz-feature-master-pi#1","_arch":"byz-feature-arch-pi#1","byz-feature-master-pi#1":{"worktree":"lead"},"byz-feature-arch-pi#1":{"worktree":"lead"}}\n' > "$SD/seats-feature.json"
printf '{"_master":"byz-planner-master-pi#3","byz-planner-master-pi#3":{"worktree":"lead2"}}\n' > "$SD/seats-planner.json"
printf '{"_master":"byz-ops-master-pi#2","_arch":"","byz-ops-master-pi#2":{"worktree":"nope"}}\n' > "$SD/seats-ops.json"
run() { bash "$1" --json --repo "$W" --seats-dir "$SD" --no-fetch 2>/dev/null; }

case_a() {  # $1=도구 → rc
  local out n; out="$(run "$1")" || return 1; n="$(git -C "$W" worktree list --porcelain | grep -c '^worktree ')"
  sed -n 2p <<<"$out" | python3 -c '
import json,os,sys
d=json.load(sys.stdin); n=int(sys.argv[1]); L=os.path.realpath(sys.argv[2]); w=d["worktrees"]
paths=[os.path.realpath(r["path"]) for r in w]
lead=[r for r in w if r["kind"]=="팀장"]
ok = len(w)==n and len(set(paths))==len(paths) and all(r["kind"] in ("팀장","나노","그밖") for r in w) \
  and len(lead)==2 and [len(r["seats"]) for r in lead if os.path.realpath(r["path"])==L]==[2] \
  and sum(r["kind"]=="나노" for r in w)==1 and any(r["kind"]=="그밖" and r["reason"]=="detached" for r in w)
sys.exit(0 if ok else 1)' "$n" "$L"
}
case_b() {
  local out m; out="$(run "$1")" || return 1
  m="$(python3 -c 'import glob,json,sys;print(sum(1 for f in glob.glob(sys.argv[1]+"/seats-*.json") for k in ("_master","_arch") if json.load(open(f)).get(k)))' "$SD")"
  sed -n 2p <<<"$out" | python3 -c '
import json,sys
d=json.load(sys.stdin); m=int(sys.argv[1]); s=d["seats"]
names=[x["seat"] for x in s]; feat=[x for x in s if x["team"]=="feature"]
bound={x["path"] for x in s if x["path"]}; leads={r["path"] for r in d["worktrees"] if r["kind"]=="팀장"}
ok = len(s)==m and len(set(names))==len(names) and len(feat)==2 and feat[0]["path"]==feat[1]["path"]!=None \
  and all(x["mismatch"] is None for x in feat) and bound==leads \
  and [x["mismatch"] for x in s if x["team"]=="ops"]==["좌석 칸 불일치 nope"]
sys.exit(0 if ok else 1)' "$m"
}
case_c() {
  local out; out="$(run "$1")" || return 1
  [ "$(sed -n 1p <<<"$out")" = "BASE main=$(sha "$W" origin/main) ops=$(sha "$W" origin/ops/main-base)" ] || return 1
  sed -n 2p <<<"$out" | python3 -c '
import json,sys
d=json.load(sys.stdin); r=[r for r in d["worktrees"] if r["kind"]=="팀장" and r["branch"]=="lead/r77-x"][0]
ok = r["target"]=="main" and d["base"]["main"]==sys.argv[1] and r["behind"]==3 and r["ahead"]==1 \
  and r["basis"]=={"main":3,"ops/main-base":4} and r["upstream"]=="origin/side" and r["cards"]==["77"]
sys.exit(0 if ok else 1)' "$(sha "$W" origin/main)"
}
S0=$SECONDS
before="$(git -C "$W" status --porcelain; git -C "$W" worktree list --porcelain)"
case_a "$BIN/ft-lead-wt-status.sh"; ck "ⓐ worktree 목록 = porcelain 전부 · 중복 0 · 공유 worktree 1행·좌석 2" $?
case_b "$BIN/ft-lead-wt-status.sh"; ck "ⓑ 결속 목록 = 명부 좌석 수 · 공유 = 같은 경로 2행 · 결속 경로 = 팀장 행" $?
case_c "$BIN/ft-lead-wt-status.sh"; ck "ⓒ 착지 대상 main · behind 3 · upstream 정보 칸(origin/side) · BASE 줄" $?
[ "$before" = "$(git -C "$W" status --porcelain; git -C "$W" worktree list --porcelain)" ]; ck "읽기 전용 — 실행 전후 status·worktree 목록 같음" $?
bash "$BIN/ft-lead-wt-status.sh" --repo "$W" --seats-dir "$SD" --no-fetch | grep -q '^SUM worktrees=5 팀장=2 나노=1 그밖=2 seats=4 결속=3 불일치=1$'; ck "텍스트 SUM 줄" $?
bash "$BIN/ft-lead-wt-status.sh" --repo "$W" --seats-dir "$SD" --no-fetch >"$T/o"; grep -q '^OVERLAP-FILE .*/lead .*/lead2 n=1 lead.txt$' "$T/o" && grep -q '^OVERLAP-CARD .*/lead .*/lead2 r77$' "$T/o"; ck "겹침 칸: 팀장 가지끼리 같은 파일·같은 카드 번호" $?
git -C "$W" update-ref -d refs/remotes/origin/main; bash "$BIN/ft-lead-wt-status.sh" --repo "$W" --seats-dir "$SD" --no-fetch >"$T/o" 2>&1; r=$?
git -C "$W" fetch -q origin; [ "$r" = 3 ] && grep -q '^판정 불가 BASE' "$T/o"; ck "BASE 없음 = rc3 판정 불가 1줄" $?

mut() {  # mut <이름> <옛 문자열> <새 문자열> <case> — 사본만 고친다 · 변이가 case 를 깨야 PASS
  local c="$T/mut-$1.sh"
  python3 - "$BIN/ft-lead-wt-status.sh" "$c" "$2" "$3" <<'PY' || { echo "FAIL $1 변이 적용 실패(원문 없음)"; fail=$((fail+1)); return; }
import sys
s=open(sys.argv[1],encoding='utf-8').read(); assert s.count(sys.argv[3])==1
open(sys.argv[2],'w',encoding='utf-8').write(s.replace(sys.argv[3],sys.argv[4]))
PY
  "$4" "$c"; [ $? != 0 ]; ck "$1 변이 → $4 FAIL(잡힘)" $?
}
mut M1 "    return items" "    return items[1:]" case_a
mut M4 "bind(root, srows, wt_real)" "bind(root, srows, wt_real); srows = list({(s_['path'] or s_['seat']): s_ for s_ in srows}.values())" case_b
mut M5 "b, why = count(root, '%s..%s' % (tip, sha))" "b, why = count(root, '%s..%s' % (tip, (git(w['path'], 'rev-parse', '@{u}')[0] or sha).strip()))" case_c
echo "secs=$((SECONDS-S0)) fail=$fail"
[ "$fail" = 0 ]
