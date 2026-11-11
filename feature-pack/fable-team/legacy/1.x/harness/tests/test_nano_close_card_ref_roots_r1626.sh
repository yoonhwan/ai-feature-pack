#!/usr/bin/env bash
# test_nano_close_card_ref_roots_r1626.sh — r1626: 카드 ref = 팀 카드 루트 표(state/directive-roots.tsv) · env 우선 · 표 없으면 origin/main
# 축 ⓐ 표 행(harness → origin/ops/main-base) → harness 나노 닫기가 그 ref 판을 읽는다(«INFO 카드 위치 ← origin/ops/main-base:…» · rc0)
#    ⓑ env FT_CARD_REF 가 표보다 앞선다(표=ops · env=main → origin/main 판) ⓒ 표 없음·팀 행·«*» 행 없음 → origin/main(지금 동작)
#    ⓓ 다른 팀(v65)은 «*» 행 ref ⓔ 표 행 ref 를 리포에서 못 읽음 → rc≠0 «판정 불가» 1줄 · origin/main 후퇴 0
#    ⓕ 단계 판정도 같은 ref(ft_card_stage_ref · 표=완성/ · env=진행/) ⓖ 변이 M1(표를 안 봄)·M2(env 를 표 뒤로) → ⓐ·ⓑ FAIL 검출 + bin==kit cmp0 + bash -n
# 임시 git 리포 + bare origin + 가짜 tmux 만 — 실 리포·실 좌석·실 mbox 0 · 고정 sleep 0 · 자기 재호출 0.
# 돌리기: ulimit -u <지금+여유>; timeout 70 bash harness/tests/test_nano_close_card_ref_roots_r1626.sh
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
SRC="$HERE/../../harness/kit/fable-team/bin"; RBIN="$HERE/../../harness/bin"
T0="$(mktemp -d)"; trap 'rm -rf "$T0"' EXIT; T="$(cd "$T0" && pwd -P)"
fail=0; S=$(date +%s); lap(){ echo "LAP $1=$(( $(date +%s) - S ))s"; S=$(date +%s); }
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
has()  { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «$2» ← ${1:0:500}";; esac; }
hasnt(){ case "$1" in *"$2"*) bad "$3 — 있으면 안 됨: «$2»";; *) ok "$3";; esac; }

echo "== ⓖ bin·kit 같은 바이트 + bash -n"
for f in ft-team-lib.sh ft-nano-close.sh ft-press-baseline-check.sh; do
  cmp -s "$RBIN/$f" "$SRC/$f" && ok "cmp $f (bin==kit)" || bad "cmp $f 다름"
  bash -n "$SRC/$f" && ok "bash -n $f" || bad "bash -n $f"
done
mkdir -p "$T/bin" "$T/fake" "$T/tmp" "$T/comm/bodies" "$T/sheet-root/.fable-team/state"
export FT_SHEET_ROOT="$T/sheet-root"
cp -R "$SRC/." "$T/bin/"   # 닫기 도구 전부(변이는 이 사본에서만)
printf '#!/bin/sh\necho "QUIESCED $1 stub left=0"\n' > "$T/bin/ft-seat-quiesce.sh"
printf '#!/bin/sh\necho "reap $1 stopped=0 left=0 rc=0"\n' > "$T/bin/ft-seat-reap.sh"
chmod +x "$T/bin/"*
cat > "$T/fake/tmux" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  list-panes) if [ -s "$FAKE_PANES" ]; then cat "$FAKE_PANES"; else echo "no server running on /tmp/fake"; exit 1; fi;;
  display-message) cat "$FAKE_CWD";;
  has-session) exit 1;;
  set-option|kill-session) echo "$*" >> "$FAKE_LOG";;
esac
EOF
chmod +x "$T/fake/tmux"; echo seq > "$T/comm/bodies/1.txt"; echo res > "$T/result.md"

ORIGIN="$T/origin.git"; git init -q --bare "$ORIGIN"
REPO="$T/repo"; mkdir -p "$REPO"; git -C "$REPO" init -q -b main; git -C "$REPO" remote add origin "$ORIGIN"
gitc() { git -C "$REPO" -c user.email=t@t -c user.name=t "$@"; }
mkdir -p "$REPO/design/harness/indices/진행" "$REPO/.fable-team/state"
printf '.fable-team/\n' > "$REPO/.gitignore"; printf '| 팀 | 폴더 |\n|---|---|\n| harness | design/harness/ |\n' > "$REPO/design/TEAMS.md"
for c in cs st; do printf '# 인덱스: %s\n## 상태\n- 진행\n' "$c" > "$REPO/design/harness/indices/진행/$c.md"; done
gitc add -A && gitc commit -q -m "A0: 기준"; SHA0="$(git -C "$REPO" rev-parse HEAD)"; gitc push -q origin main
NW="$REPO/.worktrees/v65-cs"; git -C "$REPO" worktree add -q "$NW" -b nano/cs; LW="$T/lw"; git -C "$REPO" worktree add -q --detach "$LW" "$SHA0"
gitc checkout -q -b opsbase
mkdir -p "$REPO/design/harness/indices/완성"; gitc mv "design/harness/indices/진행/st.md" "design/harness/indices/완성/st.md"
printf -- '- 세트: %s · 시험: bash t.sh (3 passed) rc=0 · 이슈: 0\n' "$SHA0" >> "$REPO/design/harness/indices/진행/cs.md"
gitc add design && gitc commit -q -m "B: ops 만 증거 줄 · st 는 완성/"; gitc push -q origin opsbase:ops/main-base; gitc checkout -q main; gitc fetch -q origin
SEAT='byz-harness-nano-cs#0'; PRG='design/harness/indices/진행/cs.md'; TAB="$REPO/.fable-team/state/directive-roots.tsv"
printf '{"%s":{"role":"nano","index":"%s"}}\n' "$SEAT" "$PRG" > "$REPO/.fable-team/seats-harness.json"
tab() { printf "$1" > "$TAB"; }
TAB_OPS='harness\t.\torigin/ops/main-base\tdesign/harness/indices\n'; TAB_STAR='*\t.\torigin/ops/main-base\tdesign/teams/*/indices\n'
run() { ( cd "$REPO" && env -i HOME="$HOME" TMPDIR="$T/tmp" FT_SHEET_ROOT="$FT_SHEET_ROOT" PATH="$T/fake:$PATH" FAKE_PANES="$T/panes" FAKE_CWD="$T/cwd" FAKE_LOG="$T/tlog" "$@" 2>&1 ); }
close() { : > "$T/panes"; printf '%s' "$NW" > "$T/cwd"; : > "$T/tlog"; : > "$T/ledger.md"
  git -C "$NW" reset -q --hard "$SHA0" 2>/dev/null; git -C "$REPO" reset -q --hard main 2>/dev/null
  printf '{"%s":{"role":"nano","index":"%s"}}\n' "$SEAT" "$PRG" > "$REPO/.fable-team/seats-harness.json"
  run FT_NANO_PREFIX=byz-harness-nano- FT_SEATS_JSON="$REPO/.fable-team/seats-harness.json" FT_NANO_LEDGER="$T/ledger.md" FT_NANO_LEDGER_WT="$LW" FT_NANO_FEAT=main \
    FT_CHERRY_OVERRIDE_LEDGER="$T/cherry.log" FT_INBOX_ROOT="$T/comm" FT_NANO_IDLE_MIN=0 FT_WT_CLEAN_DIR="$T/wtclean" FT_WT_AUTOCLEAN=0 ${CREF:+FT_CARD_REF="$CREF"} \
    bash "$T/bin/ft-nano-close.sh" "$SEAT" --result "$T/result.md" --recv 1; }
libr() { ( unset FT_CARD_REF; . "$RBIN/ft-team-lib.sh" && ft_card_ref "$REPO" "$1" ); }
libs() { ( unset FT_CARD_REF; . "$RBIN/ft-team-lib.sh" && ft_card_stage_ref "$REPO" "$1" ); }

echo "== ⓐ 표 행 harness → origin/ops/main-base → 닫기가 ops 판을 읽는다"
tab "$TAB_OPS"; out="$(close)"; rc=$?
has "$out" "INFO 카드 위치 ← origin/ops/main-base:$PRG" "ⓐ INFO 카드 위치 ← ops ref"
hasnt "$out" "INFO 카드 위치 ← origin/main" "  └ origin/main 판 안 읽음"
[ "$rc" -eq 0 ] && has "$out" "CLOSED" "  └ 닫기 rc0(ops 증거 줄)" || bad "ⓐ rc=$rc ← ${out:0:700}"; lap ⓐ
echo "== ⓑ env FT_CARD_REF 가 표보다 앞선다(표=ops · env=main)"
CREF=origin/main out="$(CREF=origin/main close)"; rc=$?
has "$out" "INFO 카드 위치 ← origin/main:$PRG" "ⓑ env ref 판"
hasnt "$out" "INFO 카드 위치 ← origin/ops/main-base" "  └ 표 ref 안 씀"
[ "$rc" -eq 1 ] && has "$out" "REJECT" "  └ main 판 증거 줄 없음 → REJECT" || bad "ⓑ rc=$rc ← ${out:0:700}"; lap ⓑ
echo "== ⓒ 표 없음 → origin/main(지금 동작) · 기본값 3꼴"
rm -f "$TAB"; [ "$(libr harness)" = origin/main ] && ok "ⓒ 표 없음 → origin/main" || bad "ⓒ 표 없음 결과 ≠ origin/main"
CREF= out="$(CREF= close)"; rc=$?
has "$out" "INFO 카드 위치 ← origin/main:$PRG" "  └ 닫기도 origin/main 판"
hasnt "$out" "origin/ops/main-base" "  └ ops ref 등장 0"
tab 'harness\t.\t\t design/harness/indices\n'; [ "$(libr harness)" = origin/main ] && ok "ⓒ ref 칸 빈 행 → origin/main" || bad "ⓒ 빈 ref 칸"
tab '\t.\torigin/ops/main-base\tdesign/harness/indices\n'; [ "$(libr harness)" = origin/main ] && ok "ⓒ 팀 이름 빈 호출 → 표 안 봄" || bad "ⓒ 빈 팀"
[ "$( ( unset FT_CARD_REF; . "$RBIN/ft-team-lib.sh" && ft_card_ref "$REPO" ) )" = origin/main ] && ok "ⓒ 팀 인자 없음 → origin/main" || bad "ⓒ 팀 인자 없음"
lap ⓒ
echo "== ⓓ 다른 팀 = «*» 행 · 팀 행이 «*» 행을 이긴다"
tab "$TAB_STAR"; [ "$(libr v65)" = origin/ops/main-base ] && ok "ⓓ v65 → «*» 행 ref" || bad "ⓓ «*» 행 (실값 $(libr v65))"
tab 'harness\t.\torigin/main\tdesign/harness/indices\n*\t.\torigin/ops/main-base\tdesign/teams/*/indices\n'
[ "$(libr harness)" = origin/main ] && ok "ⓓ 팀 행 우선" || bad "ⓓ 팀 행 우선 실패"; [ "$(libr room)" = origin/ops/main-base ] && ok "ⓓ 팀 행 없는 팀 → «*»" || bad "ⓓ «*» 후퇴"; lap ⓓ
echo "== ⓔ 표 행 ref 를 리포에서 못 읽음 → rc≠0 «판정 불가» 1줄 · origin/main 후퇴 0"
tab 'harness\t.\torigin/nope\tdesign/harness/indices\n'; libout="$(libr harness)"; lrc=$?
[ "$lrc" -ne 0 ] && [ -z "$libout" ] && ok "ⓔ lib rc=$lrc · stdout 0" || bad "ⓔ lib rc=$lrc out=«${libout}» ← 후퇴 0 위반"
out="$(close)"; rc=$?
[ "$rc" -eq 1 ] && has "$out" "판정 불가" "  └ 닫기 REJECT «판정 불가»" || bad "ⓔ rc=$rc ← ${out:0:700}"
[ "$(printf "%s\n" "$out" | grep -c "^ERROR")" = 1 ] && ok "  └ ERROR 정확히 1줄" || bad "  └ ERROR 줄 수 ≠ 1"
hasnt "$out" "INFO 카드 위치" "  └ origin/main 판 후퇴 0"; hasnt "$out" "CLOSED" "  └ 닫힘 0"; lap ⓔ
echo "== ⓕ 단계 판정도 같은 ref(표=완성/ · env=진행/)"
ST='design/harness/indices/진행/st.md'; tab "$TAB_OPS"
[ "$(libs "$ST")" = "STAGE 완성" ] && ok "ⓕ 표 ref 단계 = 완성" || bad "ⓕ 표 ref 단계 (실값 «$(libs "$ST")»)"
[ "$( ( unset FT_CARD_REF; . "$RBIN/ft-team-lib.sh" && FT_CARD_REF=origin/main ft_card_stage_ref "$REPO" "$ST" ) )" = "STAGE 진행" ] && ok "ⓕ env ref 단계 = 진행" || bad "ⓕ env ref 단계"
lap ⓕ
echo "== ⓖ 변이 M1(표를 안 봄)·M2(env 를 표 뒤로) → ⓐ·ⓑ FAIL 검출"
cp "$T/bin/ft-team-lib.sh" "$T/lib.orig"
mut1() { awk '/^ft_card_ref\(\) \{/ {print; print "  printf \"origin/main\\n\"; return 0   # M1"; next} {print}' "$T/lib.orig" > "$T/bin/ft-team-lib.sh"; }
mut2() { awk '!/FT_CARD_REF:-\}" \]; then printf/ {print}' "$T/lib.orig" > "$T/bin/ft-team-lib.sh"; }
grep -q 'ref="$(ft_card_ref "$REPO" "$_t")"' "$SRC/ft-press-baseline-check.sh" && ok "press 기준선 검사도 같은 해석 함수를 부른다" || bad "press 기준선 검사 배선 0"
tab "$TAB_OPS"; mut1; cmp -s "$T/bin/ft-team-lib.sh" "$T/lib.orig" && bad "M1 사본 안 바뀜" || ok "M1 사본 바뀜"; out="$(close)"; rc=$?
hasnt "$out" "origin/ops/main-base" "M1 ⓐ FAIL 검출(ref = origin/main)" || true
printf '%s' "$out" | grep -q 'origin/ops/main-base' && bad "M1 변이 미검출" || ok "M1 변이 검출(표 무시 → ⓐ 실패)"; lap M1
mut2; cmp -s "$T/bin/ft-team-lib.sh" "$T/lib.orig" && bad "M2 사본 안 바뀜" || ok "M2 사본 바뀜"; out="$(CREF=origin/main close)"; rc=$?
printf '%s' "$out" | grep -q 'INFO 카드 위치 ← origin/ops/main-base' && ok "M2 변이 검출(env 무시 → ⓑ 실패)" || bad "M2 변이 미검출"
cp "$T/lib.orig" "$T/bin/ft-team-lib.sh"; lap M2
echo "== 마무리 — 변이 되돌린 사본으로 ⓐ 재확인"
out="$(CREF= close)"; rc=$?; has "$out" "INFO 카드 위치 ← origin/ops/main-base:$PRG" "복구 뒤 ⓐ 그대로"; [ "$rc" -eq 0 ] || bad "복구 뒤 rc=$rc"
[ "$fail" -eq 0 ] && echo "ALL PASS ($(basename "$0"))" || echo "FAILED $fail"
exit "$([ "$fail" -eq 0 ] && echo 0 || echo 1)"
