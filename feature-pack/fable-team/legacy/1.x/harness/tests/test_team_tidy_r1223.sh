#!/usr/bin/env bash
# test_team_tidy_r1223.sh — r1223: ft-team-tidy.sh(팀 하나 카드·좌석·사본 «전 → 정리 → 후» 표) + ft-scratch-repo.sh --prune-missing. 반례 R1~R9 + 변이 2.
# 전부 mktemp — 임시 저장소·가짜 tmux(PATH)·가짜 ft-index-move / ft-seat-close(호출 기록) · ft-scratch-repo 는 기록 뒤 실물. 실 좌석·실 STATE·자기 재호출 0.
# 돌리는 법: ulimit -u <지금+여유>; timeout 70 bash 이 파일
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
export FT_ALLOW_TRACKED_BIN=1
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR FT_FINISHED_MAIN FT_SCRATCH_OWNER FT_RES_ROOT FT_TIDY_CARD_FLOW
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="$HERE/../.."; BIN="$REPO/harness/bin"; KIT="$REPO/harness/kit/fable-team/bin"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'chmod -R u+rwx "$T" 2>/dev/null; rm -rf "$T"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
has() { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «$2» ← ${1:0:600}";; esac; }
hasnt() { case "$1" in *"$2"*) bad "$3 — 있으면 안 됨: «$2»";; *) ok "$3";; esac; }
for f in ft-team-tidy.sh ft-scratch-repo.sh; do
  bash -n "$BIN/$f" && ok "bash -n $f" || bad "bash -n $f"
  cmp -s "$BIN/$f" "$KIT/$f" && ok "키트 사본 cmp 0 $f" || bad "키트 사본 불일치 $f"
done
LINES="$(wc -l < "$BIN/ft-team-tidy.sh")"; [ "$LINES" -le 200 ] && ok "ft-team-tidy.sh ${LINES}줄 ≤ 200" || bad "ft-team-tidy.sh ${LINES}줄 > 200"

FAKE="$T/fake"; LOGD="$T/log"; mkdir -p "$FAKE" "$LOGD"
cat > "$FAKE/tmux" <<EOF
#!/bin/sh
case "\$1" in ls|list-sessions) cat "$T/sessions.txt";; *) exit 1;; esac
EOF
cat > "$FAKE/im.sh" <<EOF
#!/bin/bash
echo "\$*" >> "$LOGD/im.calls"
grep -q '^- 실사건:' "\$1" || { echo "REJECT 하네스 카드 실사건 증거 없음: \${1##*/}"; exit 1; }
mv "\$1" "\$(dirname "\$(dirname "\$1")")/완성/" && echo "MOVED \${1##*/} 완성"
EOF
cat > "$FAKE/sc.sh" <<EOF
#!/bin/bash
echo "\$*" >> "$LOGD/sc.calls"
python3 - "\$1" "\$5" <<'PY'
import json,sys
s,f=sys.argv[1:3]; d=json.load(open(f)); d[s]['role']='stop-ready'; d[s]['_closed']={'by':'t','at':'NEW','reason':'team-tidy'}
open(f,'w').write(json.dumps(d,ensure_ascii=False,indent=2)+'\n')
PY
echo "CLOSED-SESSION \$1 kill=ok reap left=0 rc=0"
EOF
cat > "$FAKE/sr.sh" <<EOF
#!/bin/bash
echo "\$* owner=\${FT_SCRATCH_OWNER-unset}" >> "$LOGD/sr.calls"
exec bash "$BIN/ft-scratch-repo.sh" "\$@"
EOF
printf '#!/bin/sh\necho "카드 숫자 확인 불가(주입)"; exit 3\n' > "$FAKE/cf-fail.sh"
chmod 755 "$FAKE"/*

mkfix() { # 새 픽스처: 저장소 R(카드·명부·장부) · 다른 저장소 O(두 번째 장부) · 사본 자리 SCR
  rm -rf "$T/w" "$LOGD"; mkdir -p "$T/w" "$LOGD"; R="$T/w/repo"; O="$T/w/other"; SCR="$T/w/scr"
  git init -q -b main "$R"; G() { git -C "$R" -c user.name=t -c user.email=t@t "$@"; }
  CD="$R/design/teams/tteam/indices"; mkdir -p "$CD"/{대기,진행,완성} "$R/.fable-team/state" "$O/.fable-team/state" "$SCR"
  echo x > "$R/f"; G add -A >/dev/null; G commit -q -m base; LANDED="$(G rev-parse HEAD)"; G branch keep-me
  printf '# w\n' > "$CD/대기/w1.md"; printf '# d\n' > "$CD/완성/d1.md"
  printf -- '- 착지: %s\n- 실사건: x\n- 판정: design/x/DA.md#§2\n' "$LANDED" > "$CD/진행/c-ok.md"
  printf -- '- 착지: %s\n- 판정: design/x/DA.md#§3\n' "$LANDED" > "$CD/진행/c-noev.md"
  printf -- '- 착지: %s\n' "$LANDED" > "$CD/진행/c-noda.md"
  printf -- '- 상태: 진행\n' > "$CD/진행/c-orph.md"; printf -- '- 상태: 진행\n' > "$CD/진행/c-live.md"
  python3 - "$R/.fable-team" <<'PY'
import json,sys
d=sys.argv[1]; w=lambda n,o: open(d+'/'+n,'w').write(json.dumps(o,ensure_ascii=False,indent=2)+'\n')
c={'by':'m','at':'OLD','reason':'r'}
w('seats-tteam.json',{'_master':'byz-tteam-master-claude#1','byz-tteam-master-claude#1':{'role':'master'},
  'byz-tteam-nano-a#0':{'role':'stop-ready','_closed_role':'nano','_closed':c},
  'byz-tteam-arch-claude#2':{'role':'stop-ready','_closed_role':'arch','_closed':c},
  'byz-tteam-arch-claude#1':{'role':'stop-ready','_replaced_by':'byz-tteam-arch-claude#2','_retired_role':'arch'},
  'byz-tteam-nano-old#0':{'role':'stop-ready','_closed_role':'nano','_closed':c}})
w('seats-tteam-extra.json',{'tteam-extra-nano-a#0':{'role':'stop-ready','_closed_role':'nano','_closed':c}})
PY
  mkdir -p "$SCR/repo-nodead" "$SCR/repo-live"; echo "gitdir: $O/.git/worktrees/live" > "$SCR/repo-live/.git"
  { printf '%s\tbyz-tteam-nano-old#0\t1\n' "$SCR/repo-gone1"; printf '%s\tbyz-tteam-arch-claude#1\t1\n' "$SCR/repo-gone2"
    printf '%s\tbyz-tteam-nano-old#0\t1\n' "$SCR/repo-nodead"; printf '%s\tbyz-tteam-master-claude#1\t1\n' "$SCR/repo-live"
    printf '%s\ttteam-extra-nano-a#0\t1\n' "$SCR/repo-xgone"; } > "$R/.fable-team/state/scratch-repos.tsv"
  cp "$R/.fable-team/state/scratch-repos.tsv" "$O/.fable-team/state/scratch-repos.tsv"
  printf '%s\n' byz-tteam-master-claude#1 byz-tteam-nano-a#0 byz-tteam-arch-claude#2 byz-tteam-nano-c-live#0 tteam-extra-nano-a#0 > "$T/sessions.txt"
}
tidy() { OUT="$(cd "$R" && env -u FT_SCRATCH_OWNER PATH="$FAKE:$PATH" FT_TIDY_INDEX_MOVE="$FAKE/im.sh" FT_TIDY_SEAT_CLOSE="$FAKE/sc.sh" FT_TIDY_SCRATCH="$FAKE/sr.sh" \
  FT_SCRATCH_DIR="$SCR" FT_BG_FINITE_LEDGER="$T/bg.tsv" ${CFX:+FT_TIDY_CARD_FLOW=$CFX} bash "${TOOL:-$BIN/ft-team-tidy.sh}" --team tteam --root "$R" "$@" 2>&1)"; RC=$?; }
calls() { cat "$LOGD/$1.calls" 2>/dev/null; }
ncalls() { calls "$1" | awk 'END{print NR}'; }
snap() { ( cd "$T/w" && find . -type f ! -path '*/.git/*' | LC_ALL=C sort | while IFS= read -r f; do cksum "$f"; done; git -C "$R" branch --list ); }
row() { printf '%s\n' "$OUT" | grep "^| $1 |"; }
same_before_after() { local r; r="$(row "$1")"; [ "$(echo "$r" | cut -d'|' -f3)" = "$(echo "$r" | cut -d'|' -f4)" ]; }

# R1 — 보기만: 쓰기·이동·kill 0 · 전 = 후 · 후보 목록만
mkfix; S0="$(snap)"; tidy
[ "$RC" = 0 ] && ok "R1 rc0" || bad "R1 rc=$RC ${OUT:0:400}"
[ "$(ncalls im)$(ncalls sc)$(ncalls sr)" = 000 ] && ok "R1 집행 도구 호출 0" || bad "R1 호출 있음 im=$(ncalls im) sc=$(ncalls sc) sr=$(ncalls sr)"
[ "$S0" = "$(snap)" ] && ok "R1 파일·가지 무변경" || bad "R1 파일 바뀜"
for a in 카드 좌석 사본; do same_before_after "$a" && ok "R1 $a 전 = 후" || bad "R1 $a 전≠후 «$(row "$a")»"; done
has "$OUT" "목록 사본 $SCR/repo-gone1 — 경로 없음(--prune-missing 후보)" "R1 사본 후보 목록"
has "$OUT" "목록 좌석 byz-tteam-nano-a#0 — 닫힘·은퇴 나노인데 세션 생존" "R1 좌석 후보 목록"
has "$OUT" "목록 카드 c-ok.md — 완성 이동 후보" "R1 카드 후보 목록"

# --apply 1회 → R2 R4 R5 R6 R7 R8
mkfix; cp "$R/.fable-team/seats-tteam.json" "$T/roster.before"; cp "$R/.fable-team/seats-tteam-extra.json" "$T/xroster.before"; B0="$(git -C "$R" branch --list)"; tidy --apply
[ "$RC" = 0 ] && ok "apply rc0" || bad "apply rc=$RC ${OUT:0:600}"
for L in "$R/.fable-team/state/scratch-repos.tsv" "$O/.fable-team/state/scratch-repos.tsv"; do   # R2 — 장부 둘 모두
  c="$(cat "$L")"
  hasnt "$c" "repo-gone1" "R2 ${L#$T/w/} 팀 경로 없음 줄 빠짐"; hasnt "$c" "repo-gone2" "R2 ${L#$T/w/} 옛 이름 주인 줄 빠짐"
  has "$c" "repo-xgone" "R2 ${L#$T/w/} 다른 팀 줄 남음"; has "$c" "repo-live" "R2 ${L#$T/w/} 현역 사본 줄 남음"; has "$c" "repo-nodead" "R2 ${L#$T/w/} 경로 있는 줄 남음"
done
[ -d "$SCR/repo-live" ] && [ -d "$SCR/repo-nodead" ] && ok "R2·R8 사본 디스크 그대로" || bad "R2 디스크 사본 사라짐"
has "$OUT" "집행 사본 $SCR/repo-gone1 rc=0" "R2 집행 줄"
has "$OUT" "목록 사본 $SCR/repo-nodead — 주인 byz-tteam-nano-old#0 세션 없음 — 다음 --sweep 대상" "R4 주인 없는 사본 = 목록 «다음 --sweep 대상»"
SRC_="$(calls sr)"; hasnt "$SRC_" "--sweep" "R4 --sweep 호출 0"; hasnt "$SRC_" "--done" "R4 --done 호출 0"
has "$SRC_" "--prune-missing --owners" "R4 --prune-missing 만 호출"; hasnt "$SRC_" "owner=byz" "R4 FT_SCRATCH_OWNER 대입 0"
[ "$(calls sc)" = "byz-tteam-nano-a#0 --reason team-tidy: 명부 닫힘인데 세션 생존 --seats $R/.fable-team/seats-tteam.json" ] && ok "R5 ft-seat-close 호출 1(닫힘 나노)" || bad "R5 호출 «$(calls sc)»"
has "$OUT" "목록 좌석 byz-tteam-arch-claude#2 — 닫힘 역할 좌석(arch)인데 세션 생존 — 목록만" "R5 역할 좌석 = 목록만"
[ "$(ncalls im)" = 2 ] && ok "R6 ft-index-move 호출 2" || bad "R6 호출 $(ncalls im) «$(calls im)»"
has "$(calls im)" "c-ok.md 완성 --da design/x/DA.md#§2 --landed $LANDED" "R6 --da --landed 인자"
has "$OUT" "거절 카드 c-noev.md rc=1 — REJECT 하네스 카드 실사건 증거 없음: c-noev.md" "R6 게이트 거절 원문 1줄"
has "$OUT" "목록 카드 c-noda.md — 착지됐는데 진행 · 판정문#§N 없음" "R6 판정문 없는 착지 카드 = 목록만"
has "$OUT" "목록 카드 c-orph.md — 좌석 0 진행" "R6 좌석 0 진행 카드 = 목록만"
hasnt "$OUT" "c-live.md" "R6 좌석 현역 카드 손대지 않음"
has "$(row 카드)" "진행 5 · 완성 1 | 대기 1 · 진행 4 · 완성 2 | 1 | 1 | 2 |" "R6 표 카드 전·후·집행·거절·목록"
has "$(row 사본)" "장부 4 · 경로 없음 2" "R2 표 사본 전"; has "$(row 사본)" "| 장부 2 · 경로 없음 0 · 주인 세션 없음 1 | 2 |" "R2 표 사본 후"
hasnt "$OUT$(calls im)$(calls sc)$(calls sr)" "tteam-extra" "R7 다른 팀(접두 겹침) 세기·집행 0"
cmp -s "$T/xroster.before" "$R/.fable-team/seats-tteam-extra.json" && ok "R7 다른 팀 명부 바이트 같음" || bad "R7 다른 팀 명부 바뀜"
python3 - "$T/roster.before" "$R/.fable-team/seats-tteam.json" <<'PY' && ok "R8 명부: 대상 나노 _closed·role 만 바뀜" || bad "R8 명부 다른 칸 바뀜"
import json,sys
a,b=(json.load(open(f)) for f in sys.argv[1:3]); t='byz-tteam-nano-a#0'
assert set(a)==set(b) and all(a[k]==b[k] for k in a if k!=t)
assert {k:v for k,v in a[t].items() if k not in ('_closed','role')}=={k:v for k,v in b[t].items() if k not in ('_closed','role')}
PY
[ "$B0" = "$(git -C "$R" branch --list)" ] && ok "R8 git 가지 목록 같음" || bad "R8 가지 바뀜"

# R3 — 장부 하나 못 읽음 → 지우기 0 · 판정 불가
mkfix; L2="$O/.fable-team/state/scratch-repos.tsv"; c1="$(cat "$R/.fable-team/state/scratch-repos.tsv")"; c2="$(cat "$L2")"; chmod 000 "$L2"; tidy --apply; chmod 644 "$L2"
[ "$RC" = 3 ] && ok "R3 rc3" || bad "R3 rc=$RC"
has "$OUT" "판정 불가 사본 — ft-scratch-repo --prune-missing rc=4 — 판정 불가 등록부 못 읽음 — 지우기 0" "R3 판정 불가 1줄"
[ "$c1" = "$(cat "$R/.fable-team/state/scratch-repos.tsv")" ] && [ "$c2" = "$(cat "$L2")" ] && ok "R3 장부 둘 다 지우기 0" || bad "R3 장부 바뀜"

# R9 — 영역 도구 1개 rc≠0 → 그 영역만 판정 불가 · 다른 두 영역 끝까지 · 전체 rc≠0
mkfix; CFX="$FAKE/cf-fail.sh" tidy --apply
[ "$RC" = 3 ] && ok "R9 rc3" || bad "R9 rc=$RC"
has "$OUT" "판정 불가 카드 — ft-card-flow rc=3 — 카드 숫자 확인 불가(주입)" "R9 카드 판정 불가 1줄"
[ "$(ncalls im)" = 0 ] && ok "R9 카드 이동 0" || bad "R9 카드 이동 $(ncalls im)"
[ "$(ncalls sc)" = 1 ] && [ "$(ncalls sr)" = 1 ] && ok "R9 좌석·사본 영역 끝까지" || bad "R9 sc=$(ncalls sc) sr=$(ncalls sr)"

# 변이 2 — 각각 FAIL 이어야 시험이 살아 있다(자기 파일 재호출 0 · 도구 사본만 바꾼다)
MB="$T/mbin"; cp -R "$BIN" "$MB"
sed 's/CROOT=""; APPLY=0/CROOT=""; APPLY=1/' "$BIN/ft-team-tidy.sh" > "$MB/ft-team-tidy.sh"
mkfix; TOOL="$MB/ft-team-tidy.sh" tidy
cmp -s "$BIN/ft-team-tidy.sh" "$MB/ft-team-tidy.sh" && bad "변이1 적용 안 됨" || { [ "$(ncalls im)$(ncalls sc)$(ncalls sr)" = 000 ] && bad "변이1(--apply 없이도 집행) 살아남음" || ok "변이1(--apply 없이도 집행) R1 이 FAIL 로 잡음"; }
sed "s/'seats-'+team+'.json'/'seats-'+team+'*.json'/" "$BIN/ft-team-tidy.sh" > "$MB/ft-team-tidy.sh"
mkfix; TOOL="$MB/ft-team-tidy.sh" tidy --apply
cmp -s "$BIN/ft-team-tidy.sh" "$MB/ft-team-tidy.sh" && bad "변이2 적용 안 됨" || { case "$OUT$(calls sc)$(calls sr)" in *tteam-extra*) ok "변이2(접두 검색) R7 이 FAIL 로 잡음";; *) bad "변이2(접두 검색) 살아남음";; esac; }

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILED $fail"
exit $fail
