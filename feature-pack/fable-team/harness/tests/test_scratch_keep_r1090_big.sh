#!/usr/bin/env bash
# test_scratch_keep_r1090_big.sh — ft-scratch-repo.sh r1090 «4864 파일 사본 1개»(ⓗ2 · R3 · 기본 시험 필수) — 칸 내용 그대로
#   하드 룰 22 «시험 1개 단독 70초»: 보관 성공 길은 test_scratch_keep_r1090.sh, 거절·분류는 …_refuse.sh
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="$(cd -- "$HERE/../.." && pwd)"
SUT="${FT_SUT:-$REPO/harness/bin/ft-scratch-repo.sh}"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
[ -f "$SUT" ] || { bad "ft-scratch-repo.sh 없음"; echo "(1 failed)"; exit 1; }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
G="$T/src"; R="$T/R"; SCR="$T/scratch"; TMPD="$T/tmpdir"; mkdir -p "$G" "$R/.fable-team/state" "$SCR" "$TMPD" "$T/bin"
git -C "$G" init -q && echo a > "$G/a.txt" && git -C "$G" add a.txt && git -C "$G" -c user.name=t -c user.email=t@t commit -q -m c1
SHA="$(git -C "$G" rev-parse HEAD)"
printf '#!/bin/sh\n[ -f "%s/tmuxfail" ] && { echo "no server running" >&2; exit 1; }\n[ "$1" = list-sessions ] && cat "%s/sessions" 2>/dev/null\nexit 0\n' "$T" "$T" > "$T/bin/tmux"; chmod 755 "$T/bin/tmux"
printf 'live-owner\n' > "$T/sessions"
sc() { OUT="$(env PATH="${GPRE:+$GPRE:}$T/gbin:$T/bin:$PATH" FT_RES_ROOT="$R" FT_SCRATCH_DIR="$SCR" TMPDIR="$TMPD" FT_SCRATCH_OWNER="${OWN:-live-owner}" \
  FT_SCRATCH_KEEP_DIRTY="${KEEP_ON:-}" FT_SCRATCH_KEEP_MAX_MB="${KEEP_MAX:-}" \
  GS_AT="${GS_AT:-0}" GS_FAIL="${GS_FAIL:-}" GS_SLEEP="${GS_SLEEP:-}" GS_DIRTY="${GS_DIRTY:-}" \
  GT_AT="${GT_AT:-0}" GT_DIRTY="${GT_DIRTY:-}" GT_TAR_EXTRA="${GT_TAR_EXTRA:-}" GT_LS_SLEEP="${GT_LS_SLEEP:-}" bash "$SUT" "$@" 2>&1)"; RC=$?; }
TSV="$R/.fable-team/state/scratch-repos.tsv"
age_reg() { awk -F'\t' -v p="$1" -v t="$(( $(date +%s) - $2 ))" 'BEGIN{OFS="\t"} $1==p{$3=t} {print}' "$TSV" > "$TSV.n" && mv "$TSV.n" "$TSV"; }   # 등록 시각을 <초> 전으로

want() { case "${FT_CELLS:-all}" in all) return 0;; *"$1"*) return 0;; esac; return 1; }   # FT_CELLS 로 칸 무리 고르기
# ── r1090: 더러운 사본 = «보관 뒤 삭제»(KEEP_DIRTY) · detached 더러움 조용한 삭제 0 · 끝 줄 거절 분류 ────────
#   ⓐ 깨끗 26 = 보관 0 · 삭제(R1) ⓑ 더러운 8 = 보관 8 + 삭제 · diff 줄 · tar 4864(R2·R3) ⓒ KEEP 없음 = 거절(R4)
#   ⓓ 보관 확인 실패(tar 항목 수) = 거절 · 사본·보관 폴더 남음(R5) ⓔ 보관 뒤 새 파일 = G8 거절(R6)
#   ⓕ 보관 상한 초과 = 거절(R7) ⓖ 끝 줄 수 == 로그 줄 수(R8) ⓗ2 4864 사본 1개 단독(기본 필수 · R3) ⓗ 34개 회차 시간(HEAVY)
#   ⓖ2·ⓖ3(DA② 결정 3): held-lsof = lsof «조회 실패» 로 붙잡은 수만 · 실제 점유는 held 칸 · ⓘ bin·kit cmp0 · 변이 3종(FT_CASES=M)
if want r1090; then
  KEEP="$R/.fable-team/state/scratch-keep"; ARM="$R/.fable-team/state/scratch-sweep.armed"; SLOG="$R/.fable-team/state/scratch-sweep.log"
  mkdir -p "$R/.fable-team/state"
  arm() { date +%s > "$ARM"; }                      # 실삭제 단계로(첫 sweep 의 목록 보고만 건너뜀)
  SH8="${SHA:0:8}"; ONW=0
  mkcopy() { # <번호> → detached 사본 + 등록 줄(주인 죽음 · 25시간 전) · 사본 1개
    local p="$SCR/repo-$SH8-9-$1"
    git -C "$G" worktree add -q --detach "$p" "$SHA" >/dev/null 2>&1
    printf '%s\t%s\t%s\n' "$p" gone-rd "$(( $(date +%s) - 90000 ))" >> "$TSV"
    printf '%s' "$p"
  }
  kd() { printf '%s' "$KEEP/gone-rd/${1##*/}"; }   # <사본> → 보관 폴더
  # lsof 는 다른 프로세스가 사라지는 순간 rc≠0 을 낼 수 있다 — 제품은 그때 «삭제 0» 으로 멈추는 게 맞고(보수적),
  # 시험은 그 «정상 동작» 회차를 다시 잰다(같은 조건 3회까지 · 사유가 lsof 가 아니면 그대로 실패)
  scs() { local i; for i in 1 2 3; do sc "$@"; printf '%s' "$OUT" | grep -q '재확인 못 읽음(rc=2 · G4 lsof' || return 0; done; }
  kept() { [ -d "$(kd "$1")" ]; }
  # ── ⓗ2(R3 단독 · 기본 시험 필수): 추적 안 한 파일 4864개 사본 1개 = 보관 성공 · tar 항목 4864 · 삭제 · 호출 70초 안 ──
  #   변이 자식 회차(FT_MUT_CHILD)에서는 건너뛴다 — 변이 검출은 그 변이가 건드리는 칸만 보면 되고, 시험 1개 70초(하드 룰 22)를 지킨다
  if [ "${FT_CASES:-all}" != none ] && [ -z "${FT_MUT_CHILD:-}" ]; then
    arm; BIG="$(mkcopy 60)"; mkdir -p "$BIG/u"
    TB=$(date +%s)
    python3 -c 'import sys; [open("%s/u/f%d" % (sys.argv[1], i), "w").close() for i in range(int(sys.argv[2]))]' "$BIG" 4864
    T_BUILD_BIG=$(( $(date +%s) - TB ))
    echo "TIME r1090-ⓗ2 만들기(4864 파일): ${T_BUILD_BIG}초"
    T2=$(date +%s); KEEP_ON=1 scs --sweep; DT2=$(( $(date +%s) - T2 ))
    echo "TIME r1090-ⓗ2 sweep 호출 1회: ${DT2}초"
    ntar2=$(tar -tf "$(kd "$BIG")/untracked.tar" 2>/dev/null | awk 'END{print NR+0}')
    nst2=$(awk 'END{print NR+0}' "$(kd "$BIG")/status.txt" 2>/dev/null)
    { [ ! -d "$BIG" ] && kept "$BIG" && [ "$ntar2" = 4864 ] && [ "$nst2" = 4864 ] && [ "$DT2" -le 70 ]; } \
      && ok "r1090-ⓗ2 4864 파일 사본 1개 = 보관 성공(tar 4864 · status 4864) + 삭제 · 호출 ${DT2}초 ≤ 70초(R3)" \
      || bad "r1090-ⓗ2 tar=$ntar2 status=$nst2 남음=$([ -d "$BIG" ] && echo y) 호출=${DT2}초 [$OUT]"
  fi
  # ── 주입용 가짜 git: -uall 호출 N번째에 «새 파일» 을 만들거나(ⓔ) / 추적 안 한 파일 목록에 없는 파일을 더한다(ⓓ) ──
  GITREAL="$(command -v git)"; mkdir -p "$T/gbin2"
  cat > "$T/gbin2/git" <<EOF
#!/bin/sh
case "\$*" in
  *"--untracked-files=all"*)
    n=\$(( \$(/bin/cat "$T/gt.n" 2>/dev/null || echo 0) + 1 )); echo "\$n" > "$T/gt.n"
    if [ "\$n" = "\${GT_AT:-0}" ]; then
      p=""; prev=""; for a in "\$@"; do [ "\$prev" = -C ] && p="\$a"; prev="\$a"; done
      [ -z "\${GT_DIRTY:-}" ] || { [ -n "\$p" ] && printf 'late\\n' > "\$p/\${GT_DIRTY}"; }
    fi;;
  *"rev-parse HEAD"*)
    case "\${GT_HEAD_AT:-0}" in 0) ;; *) n=\$(( \$(/bin/cat "$T/gh.n" 2>/dev/null || echo 0) + 1 )); echo "\$n" > "$T/gh.n"
      [ "\$n" = "\$GT_HEAD_AT" ] && { printf '1111111111111111111111111111111111111111\\n'; exit 0; };; esac;;
  *"ls-files --others"*)
    [ -z "\${GT_LS_SLEEP:-}" ] || sleep "\$GT_LS_SLEEP"
    [ -z "\${GT_TAR_EXTRA:-}" ] || printf 'a.txt\\0';;
  *) ;;
esac
exec "$GITREAL" "\$@"
EOF
  chmod 755 "$T/gbin2/git"
  # ── 변이 3종: 조건 하나만 끄는 패치로 기대 칸만 빨강일 때만 검출(FT_CASES=M) ──
  if [ "${FT_CASES:-all}" = M ]; then
    mut() { # <이름> <ft|lib> <sed 식> <기대 FAIL 정규식> — FT_MUTS 를 주면 그 이름만 돈다(시험 1개 70초 · 하드 룰 22)
      case "${FT_MUTS:-}" in ''|*"$1"*) ;; *) return 0;; esac
      local m="$T/mut-$1" nf nx r src
      mkdir -p "$m"; cp "$SUT" "$m/ft-scratch-repo.sh"; cp "$(dirname -- "$SUT")/_scratch_keep.sh" "$m/_scratch_keep.sh"
      case "$2" in lib) src="$m/_scratch_keep.sh";; *) src="$m/ft-scratch-repo.sh";; esac
      sed -i '' -e "$3" "$src" 2>/dev/null || { bad "변이 $1 sed 실패"; return; }
      cmp -s "$(dirname -- "$SUT")/$([ "$2" = lib ] && echo _scratch_keep.sh || echo ft-scratch-repo.sh)" "$src" && { bad "변이 $1 이 안 바뀜"; return; }
      bash -n "$src" 2>/dev/null || { bad "변이 $1 문법 깨짐(가짜 변이)"; return; }
      FT_MUT_CHILD=1 FT_CELLS=r1090 FT_CASES=none FT_SUT="$m/ft-scratch-repo.sh" bash "${BASH_SOURCE[0]}" > "$T/mut-$1.log" 2>&1; r=$?
      nf="$(grep -c '^FAIL' "$T/mut-$1.log")"; nx="$(grep -cE "^FAIL ($4)" "$T/mut-$1.log")"
      { [ "$r" != 0 ] && [ "$nf" -gt 0 ] && [ "$nf" = "$nx" ]; } && ok "변이 $1 → 기대 칸만 빨강($4 · ${nf}칸)" \
        || bad "변이 $1 이 기대 칸으로 안 잡힘(rc=$r · FAIL $nf · 기대 $nx) $(grep '^FAIL' "$T/mut-$1.log" | head -2 | tr '\n' ' ')"
    }
    # ※ 계약④(meta 재읽기)는 «재읽기 자체» 를 변이로 구별하지 못한다(메모리 $head 와 meta 3칸이 같은 실행 안에서 항상 같은 값) = 알려진 한계 · 대신 ⓓ2(가짜 HEAD 주입) 가 그 자리를 지킨다
  fi
fi

[ $fail -eq 0 ] && echo "ALL PASS" || echo "($fail failed)"
exit $fail

