#!/usr/bin/env bash
# test_nano_close_ledger_wt_fresh_r1668.sh — 카드 r1668: ft-nano-close 의 «원장 워크트리(LEDGER_WT)» 가 카드 ref 보다 뒤일 때
#   ⑥ 이 «디스크 사본 없음» 으로 닫기를 막지 않는다. 깨끗하면 ff-only 로 따라가고, 못 따라가면 원인 1줄로 멈춘다. 호출자가 export 한 FT_NANO_LEDGER_WT 는 팀 env 가 덮지 않는다.
#   사건 = h8214·h8215: 라이브 harness-env.sh 가 원장 WT 를 507커밋 뒤 워크트리로 고정 · 그 뒤에 만든 진행/ 카드가 그 워크트리에 없다.
# 픽스처 = 임시 git 리포(ROOT) + 좌석 워크트리 + 원장 워크트리 2개 + 가짜 tmux(PATH 앞) + 명부(FT_SEATS_JSON)·팀 env(고정 대입) · 카드는 «ref(origin/ops)» 에만(디스크 0)
#   · 실 리포·실 명부·실 tmux·외부 호출 0 · sleep 0 · 사례마다 70초 안
# 축 ⓐ 뒤·깨끗 → `INFO 원장 WT ff` 1줄 + ff 로 ⑥ 이 진행/ 사본을 찾음 ⓑ 뒤·미커밋 → `원장 WT 낡음 …` 1줄(ff 0) ⓒ 호출자 export 우선
#   ⓓ ff 실패 = «판정 불가»(닫기 0 · HEAD 불변) ⓔ 최신이면 출력 불변(게이트 줄 0 · 기존 관문 그대로)
# 변이(사본에서만) M1 미커밋 검사 삭제 → ⓑ FAIL(더러운 원장을 그대로 ff) · M2 호출자 되돌림 삭제 → ⓒ FAIL(팀 env 고정값이 이김)
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행(재진입 표지 = RSG_ACTIVE)
set -uo pipefail
export FT_ALLOW_TRACKED_BIN=1   # R201: 시험은 추적 사본(*/harness/kit/fable-team/bin)을 직접 부른다
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
SRC="$HERE/../../harness/kit/fable-team/bin"                   # 부속 도구는 항상 «지금» 키트에서
SUT="${FT_TEST_SRC:-$SRC}/ft-nano-close.sh"                    # FT_TEST_SRC = 고치기 전 판 대조용
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'chmod -R u+w "$T" 2>/dev/null; rm -rf "$T"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
bash -n "$SUT" && ok "bash -n ft-nano-close.sh" || bad "bash -n ft-nano-close.sh"
bash "$HERE/lib/kit_bin_copy.sh" "$T/bin" >/dev/null || bad "kit_bin_copy"
GC() { git -C "$1" -c user.email=t@t -c user.name=t "${@:2}"; }
SEAT='byz-harness-nano-k#0'; BR='nano/k'
R="$T/repo"; RW="$R/.worktrees/harness-k"; LWT="$R/.worktrees/ledger"; TWTL="$R/.worktrees/teamledger"
SEATS="$T/seats-harness.json"; LEDGER="$R/design/harness/NANO-LEDGER.md"
mkdir -p "$T/home" "$T/fake" "$T/comm/bodies" "$T/hil" "$T/wtclean" "$T/sheet" "$R/design/harness" "$R/.fable-team/bin-harness"
echo res > "$T/result.md"; echo seq > "$T/comm/bodies/1.txt"
printf '#!/usr/bin/env bash\ncase "$1" in\n  list-panes) echo "%s|%%1";;\n  display-message) cat "$FAKE_CWD";;\n  has-session) exit 1;;\n  *) :;;\nesac\n' "$SEAT" > "$T/fake/tmux"; chmod +x "$T/fake/tmux"
printf '{"%s":{"role":"nano","agent":"pi","index":"design/harness/indices/진행/k.md"}}\n' "$SEAT" > "$SEATS"
printf '%s' "$RW" > "$T/cwd"

git -C "$R" init -q -b main; : > "$LEDGER"; printf '.fable-team/\n' > "$R/.gitignore"
GC "$R" add -A; GC "$R" commit -qm init
git -C "$R" update-ref refs/remotes/origin/main main
GC "$R" worktree add -q "$RW" -b "$BR" main; printf '{"branch":"%s","base":"origin/main"}\n' "$BR" > "$RW/.worktree-info.json"
GC "$RW" add -A; GC "$RW" commit -qm work
GC "$R" worktree add -q "$TWTL" -b teamwt main; : > "$TWTL/team-scratch.txt"          # 팀 env 가 가리키는 «낡고 더러운» 원장
printf 'export FT_NANO_PREFIX=byz-harness-nano-\nexport FT_NANO_LEDGER_WT=%s\nexport FT_SEATS_JSON=%s\n' "$TWTL" "$SEATS" > "$R/.fable-team/bin-harness/harness-env.sh"   # 사건 꼴 = 고정 대입
NLW=0
reset_lwt() { NLW=$((NLW+1)); rm -rf "$LWT"; git -C "$R" worktree prune; GC "$R" worktree add -q "$LWT" -b "lw$NLW" main; }   # 뒤진 원장 WT 로 되돌림
advance() {   # <세트 sha> — 카드를 «ref(origin/ops)» 에만 커밋한다(ROOT 작업 트리·좌석 WT 디스크 사본 0 = ⑥ 이 원장 WT 를 봐야만 찾는다)
  git -C "$R" checkout -q -f ops; mkdir -p "$R/design/harness/indices/진행"
  printf '## 상태\n- 세트: %s · 시험: bash t.sh rc=0 · 이슈: 0\n' "$1" > "$R/design/harness/indices/진행/k.md"
  GC "$R" add design/harness/indices/진행/k.md; GC "$R" commit -qm "card $1"
  git -C "$R" update-ref refs/remotes/origin/ops "$(git -C "$R" rev-parse HEAD)"; git -C "$R" checkout -q -f main; }
GC "$R" checkout -q -b ops
close() { local sut="$1"; shift; ( cd "$R" && env -i HOME="$T/home" FT_SHEET_ROOT="$T/sheet" HIL_DIR="$T/hil" HIL_CLIP=0 PATH="$T/fake:$PATH" FAKE_CWD="$T/cwd" \
  FT_ALLOW_TRACKED_BIN=1 FT_SEATS_JSON="$SEATS" FT_INBOX_ROOT="$T/comm" FT_NANO_LEDGER="$LEDGER" FT_CARD_REF=origin/ops \
  FT_NANO_IDLE_MIN=3 FT_WT_CLEAN_DIR="$T/wtclean" "$@" bash "$sut" "$SEAT" --result "$T/result.md" --recv 1 --wt "$RW" --branch "$BR" 2>&1 ); }
P="FT_NANO_PREFIX=byz-harness-nano-"
head_of() { git -C "$1" rev-parse HEAD; }
mksut(){ local m="$T/bin/ft-nano-close-$1.sh"; shift; cp "$SRC/ft-nano-close.sh" "$m"   # 변이는 «사본» 에서만(원본 0)
  while [ $# -ge 2 ]; do
    python3 -c 'import io,sys;p,a,b=sys.argv[1:4];s=io.open(p,encoding="utf-8").read();sys.exit(3) if a not in s else io.open(p,"w",encoding="utf-8").write(s.replace(a,b,1))' "$m" "$1" "$2" \
      || { bad "mksut 패턴 없음: $1"; rm -f "$m"; return 1; }; shift 2; done
  chmod +x "$m"; printf '%s' "$m"; }

advance "$(git -C "$RW" rev-parse HEAD)"
echo "== ⓐ 원장 WT 뒤·깨끗 → ff-only 1회 · ⑥ 이 진행/ 사본을 찾는다(«디스크 사본 없음» 0)"
reset_lwt; old="$(head_of "$LWT")"; o="$(close "$SUT" $P FT_NANO_LEDGER_WT=$LWT)"
case "$o" in *"INFO 원장 WT ff"*) ok "ⓐ ff INFO 1줄";; *) bad "ⓐ ff INFO 없음 ← ${o:0:300}";; esac
[ "$(head_of "$LWT")" != "$old" ] && ok "ⓐ 원장 WT HEAD 이동" || bad "ⓐ 원장 WT HEAD 그대로"
[ -f "$LWT/design/harness/indices/진행/k.md" ] && ok "ⓐ ff 뒤 원장 WT 에 진행/ 사본 실재" || bad "ⓐ ff 뒤에도 사본 없음"
case "$o" in *"디스크 사본 없음"*) bad "ⓐ 아직 «디스크 사본 없음» ← $(printf '%s' "$o" | grep -m1 '디스크 사본 없음')";; *) ok "ⓐ ⑥ «디스크 사본 없음» 0";; esac
case "$o" in *"INFO 카드 위치"*) ok "ⓐ ⑥ 카드 위치 INFO(원장 WT 사본)";; *) bad "ⓐ ⑥ 카드 위치 INFO 없음 ← ${o:0:300}";; esac

echo "== ⓑ 원장 WT 뒤·미커밋 1 → «원장 WT 낡음 1커밋 · 미커밋 1» 1줄 · 쓰기 0"
reset_lwt; : > "$LWT/scratch.txt"; old="$(head_of "$LWT")"; o="$(close "$SUT" $P FT_NANO_LEDGER_WT=$LWT)"
case "$o" in *"원장 WT 낡음 1커밋 · 미커밋 1"*) ok "ⓑ 낡음+미커밋 1줄";; *) bad "ⓑ 그 줄 없음 ← ${o:0:300}";; esac
case "$o" in *"FT_NANO_LEDGER_WT="*) ok "ⓑ 고치는 길 안내";; *) bad "ⓑ 안내 없음";; esac
[ "$(head_of "$LWT")" = "$old" ] && ok "ⓑ ff 0(쓰기 0)" || bad "ⓑ 더러운 원장을 ff 함"
case "$o" in *"디스크 사본 없음"*) bad "ⓑ ⑥ 줄로 가림";; *) ok "ⓑ ⑥ «디스크 사본 없음» 으로 안 가림";; esac

echo "== ⓒ 호출자 FT_NANO_LEDGER_WT 우선(FT_NANO_PREFIX 비움 → 팀 env source · 고정 대입이 이기면 낡음)"
reset_lwt; o="$(close "$SUT" FT_NANO_LEDGER_WT=$LWT)"
case "$o" in *"원장 WT 낡음"*) bad "ⓒ 팀 env 가 호출자 값을 덮음 ← $(printf '%s' "$o" | grep -m1 '낡음')";; *) ok "ⓒ 팀 env 고정 대입 안 이김";; esac
case "$o" in *"INFO 원장 WT ff"*) ok "ⓒ 호출자 원장 WT 로 ff";; *) bad "ⓒ ff 줄 없음 ← ${o:0:400}";; esac
[ -f "$LWT/design/harness/indices/진행/k.md" ] && ok "ⓒ ⑥ 이 호출자 원장 WT 사본을 봄" || bad "ⓒ 호출자 원장 WT 에 사본 없음"

echo "== ⓓ ff 실패(index.lock) = «판정 불가» · 닫기 0 · HEAD 불변"
reset_lwt; old="$(head_of "$LWT")"; : > "$(git -C "$LWT" rev-parse --absolute-git-dir)/index.lock"; o="$(close "$SUT" $P FT_NANO_LEDGER_WT=$LWT)"; rm -f "$(git -C "$LWT" rev-parse --absolute-git-dir)/index.lock"
case "$o" in *"판정 불가"*) ok "ⓓ 판정 불가 1줄";; *) bad "ⓓ 판정 불가 없음 ← ${o:0:300}";; esac
[ "$(head_of "$LWT")" = "$old" ] && ok "ⓓ HEAD 불변" || bad "ⓓ HEAD 이동"

echo "== ⓔ 최신이면 출력 불변(게이트 줄 0)"
o="$(close "$SUT" $P FT_NANO_LEDGER_WT=$LWT)"   # ⓓ 가 ff 하지 않았으므로 아직 뒤 — 먼저 따라가 둔다
o="$(close "$SUT" $P FT_NANO_LEDGER_WT=$LWT)"
case "$o" in *"INFO 원장 WT ff"*|*"원장 WT 낡음"*|*"판정 불가"*) bad "ⓔ 최신인데 게이트 줄 ← $(printf '%s' "$o" | grep -m1 '원장 WT')";; *) ok "ⓔ 게이트 줄 0";; esac
case "$o" in *"INFO 카드 위치"*) ok "ⓔ ⑥ 사본 찾기 그대로";; *) bad "ⓔ ⑥ 사본 못 찾음 ← ${o:0:300}";; esac

echo "== 변이 M1(미커밋 검사 삭제 → ⓑ FAIL: 더러운 원장을 그대로 ff)"
M1="$(mksut m1 '  [ "$dirty" -eq 0 ] || { echo "원장 WT 낡음' '  [ "$dirty" -ge 0 ] || { echo "원장 WT 낡음')"
[ -n "$M1" ] && { reset_lwt; : > "$LWT/scratch.txt"; o="$(close "$M1" $P FT_NANO_LEDGER_WT=$LWT)"
  case "$o" in *"INFO 원장 WT ff"*) ok "M1 재현 — 검사 없으면 더러운 원장을 ff(ⓑ FAIL 확인)";; *) bad "M1 재현 실패 ← $(printf '%s' "$o" | grep -F '원장 WT' | head -2)";; esac; }

echo "== 변이 M2(호출자 되돌림 삭제 → ⓒ FAIL: 팀 env 고정값이 이김)"
M2="$(mksut m2 '  [ -z "$_FT_CALLER_LEDGER_WT" ] || FT_NANO_LEDGER_WT="$_FT_CALLER_LEDGER_WT"' '  :')"
[ -n "$M2" ] && { reset_lwt; o="$(close "$M2" FT_NANO_LEDGER_WT=$LWT)"
  case "$o" in *"원장 WT 낡음"*) ok "M2 재현 — 팀 env 고정값이 이김(ⓒ FAIL 확인)";; *) bad "M2 재현 실패 ← $(printf '%s' "$o" | grep -F '원장 WT' | head -2)";; esac; }

echo "== 기존 nano_close 시험 rc0(⑥ 사본 · r842 후퇴 0)"
for t in test_nano_close_card_stage_ref_r842.sh; do
  [ -f "$HERE/$t" ] || { ok "  └ $t 없음(sparse) — 건너뜀"; continue; }
  o="$(timeout 70 bash "$HERE/$t" 2>&1)"; rc=$?
  [ "$rc" -eq 0 ] && ok "  └ $t rc=0" || bad "  └ $t rc=$rc ← $(printf '%s' "$o" | grep -m2 '^FAIL')"
done
echo
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
