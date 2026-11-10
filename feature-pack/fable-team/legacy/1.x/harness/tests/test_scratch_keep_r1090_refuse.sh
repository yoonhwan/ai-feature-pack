#!/usr/bin/env bash
# test_scratch_keep_r1090_refuse.sh — ft-scratch-repo.sh r1090 «거절·끝 줄 분류»(ⓒ ⓓ ⓔ ⓕ ⓖ ⓖ2 ⓖ3) — 칸 내용·변이 그대로
#   하드 룰 22: 보관 성공 길은 test_scratch_keep_r1090.sh 에 · 임시 repo·가짜 git/tmux/lsof 만 쓴다
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
  # ── ⓒ(R4) + ⓖ 첫 회차(R8 · KEEP 없음): 더러운 detached·가지를 한 회차에 몰아 거절 ──
  cnt() { sed -n 's/.*'"$1"'=\([0-9][0-9]*\).*/\1/p' <<<"$2"; }   # <키> <끝줄> → 수
  arm; PC="$(mkcopy 40)"; printf 'z\n' >> "$PC/a.txt"
  UB="$(mkcopy 41)"; git -C "$UB" checkout -q -b brKeep 2>/dev/null; printf 'z\n' >> "$UB/a.txt"
  PG="$(mkcopy 42)"; printf 'z\n' >> "$PG/a.txt"
  M1=$(awk 'END{print NR+0}' "$SLOG"); scs --sweep; L1="$(grep 'swept=' "$SLOG" | tail -1)"
  NR1=$(awk -v m="$M1" 'NR>m && / REFUSED /{n++} END{print n+0}' "$SLOG")
  { [ -d "$PC" ] && [ -d "$UB" ] && grep -qF "$PC" "$TSV" && printf '%s' "$OUT" | grep -q 'detached 사본 더러움' && printf '%s' "$OUT" | grep -q '가지 사본 더러움'; } \
    && ok "r1090-ⓒ KEEP 없음 = 더러운 detached·가지 둘 다 거절 · 사본 남음(R4)" || bad "r1090-ⓒ rc=$RC [$OUT]"
  { [ "$(cnt refused-dirty "$L1")" = 3 ] && [ "$NR1" = 3 ] && [ "$(cnt refused-keep "$L1")" = 0 ] && [ "$(cnt kept "$L1")" = 0 ]; } \
    && ok "r1090-ⓖ 끝 줄 refused-dirty=3 = 로그 REFUSED 3줄(R8)" || bad "r1090-ⓖ 끝 줄 [$L1] REFUSED=$NR1 [$OUT]"
  rm -rf "$PC" "$UB" "$PG"; awk -F'\t' -v a="$PC" -v b="$UB" -v c="$PG" '$1!=a && $1!=b && $1!=c' "$TSV" > "$TSV.n" && mv "$TSV.n" "$TSV"
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
  # ── ⓓ(R5) + ⓖ 둘째 회차(R8 · KEEP 켜짐): tar 항목 수가 안 맞는 사본 둘 = 보관 확인 실패로 거절 ──
  arm; PD="$(mkcopy 50)"; printf 'u\n' > "$PD/new.txt"; PH="$(mkcopy 51)"; printf 'u\n' > "$PH/new.txt"; rm -f "$T/gt.n"
  M2=$(awk 'END{print NR+0}' "$SLOG"); KEEP_ON=1 GPRE="$T/gbin2/" GT_TAR_EXTRA=1 scs --sweep; L2="$(grep 'swept=' "$SLOG" | tail -1)"
  NR2=$(awk -v m="$M2" 'NR>m && / REFUSED /{n++} END{print n+0}' "$SLOG")
  { [ -d "$PD" ] && kept "$PD" && [ -d "$PH" ] && kept "$PH" && printf '%s' "$OUT" | grep -q '보관 확인 실패' && printf '%s' "$OUT" | grep -q 'tar 항목'; } \
    && ok "r1090-ⓓ 보관 확인 실패 = 거절 · 사본·보관 폴더 둘 다 남음(R5)" || bad "r1090-ⓓ rc=$RC [$OUT] tar=$(tar -tf "$(kd "$PD")/untracked.tar" 2>/dev/null | wc -l)"
  { [ "$(cnt refused-keep "$L2")" = 2 ] && [ "$NR2" = 2 ] && [ "$(cnt kept "$L2")" = 0 ] && [ "$(cnt refused-dirty "$L2")" = 0 ]; } \
    && ok "r1090-ⓖ 끝 줄 refused-keep=2 = 로그 REFUSED 2줄 · kept=0(R8)" || bad "r1090-ⓖ 끝 줄 [$L2] REFUSED=$NR2 [$OUT]"
  rm -rf "$PD" "$PH"; awk -F'\t' -v a="$PD" -v b="$PH" '$1!=a && $1!=b' "$TSV" > "$TSV.n" && mv "$TSV.n" "$TSV"   # 다음 칸 주입이 이 사본에 걸리지 않게 먼저 치운다
  # ── ⓔ 보관 뒤·지우기 직전 새 파일 = G8 거절(R6) ──
  arm; PE="$(mkcopy 52)"; printf 'u\n' > "$PE/new.txt"; rm -f "$T/gt.n"
  KEEP_ON=1 GPRE="$T/gbin2/" GT_AT=3 GT_DIRTY=late.txt scs --sweep
  { [ -d "$PE" ] && kept "$PE" && printf '%s' "$OUT" | grep -q '보관 뒤 사본 더러움'; } \
    && ok "r1090-ⓔ 보관 뒤 지우기 직전 새 파일 = G8 거절 · 사본 남음(R6)" || bad "r1090-ⓔ rc=$RC [$OUT]"
  rm -rf "$PE"; awk -F'\t' -v b="$PE" '$1!=b' "$TSV" > "$TSV.n" && mv "$TSV.n" "$TSV"
  # ── ⓕ 보관 상한 초과 = 거절(R7) ──
  arm; PF="$(mkcopy 53)"; python3 -c 'import sys; open(sys.argv[1] + "/big.bin", "wb").write(b"x" * (2 * 1024 * 1024))' "$PF"
  KEEP_ON=1 KEEP_MAX=1 scs --sweep
  { [ -d "$PF" ] && printf '%s' "$OUT" | grep -q '보관 상한 초과'; } && ok "r1090-ⓕ 보관 상한 초과(1MB) = 거절(R7)" || bad "r1090-ⓕ rc=$RC [$OUT]"
  rm -rf "$PF"; awk -F'\t' -v a="$PF" '$1!=a' "$TSV" > "$TSV.n" && mv "$TSV.n" "$TSV"
  # ── ⓖ2·ⓖ3(DA② 결정 3): 끝 줄의 held / held-lsof 칸이 «실제 사유» 와 같나 — lsof 조회 실패만 held-lsof · 실제 점유는 held ──
  RLSOF="$(command -v lsof)"; mkdir -p "$T/gbin3"
  printf '#!/bin/sh\ncase " $* " in *"+D %s/repo-%s-9-70 "*) exit 2;; esac\nexec %s "$@"\n' "$SCR" "$SH8" "$RLSOF" > "$T/gbin3/lsof"; chmod 755 "$T/gbin3/lsof"
  arm; PL="$(mkcopy 70)"; printf 'z\n' >> "$PL/a.txt"
  M3=$(awk 'END{print NR+0}' "$SLOG"); GPRE="$T/gbin3/" KEEP_ON=1 scs --sweep; L3="$(grep 'swept=' "$SLOG" | tail -1)"
  NRL=$(awk -v m="$M3" 'NR>m && /점유 조회 실패 · 삭제 보류/{n++} END{print n+0}' "$SLOG")
  { [ -d "$PL" ] && [ "$(cnt held-lsof "$L3")" = 1 ] && [ "$(cnt held "$L3")" = 0 ] && [ "$NRL" = 1 ]; } \
    && ok "r1090-ⓖ2 lsof 조회 실패 = held-lsof=1 · held=0(로그 «점유 조회 실패» 1줄과 같음)" || bad "r1090-ⓖ2 끝 줄 [$L3] 로그=$NRL [$OUT]"
  rm -rf "$PL"; awk -F'\t' -v a="$PL" '$1!=a' "$TSV" > "$TSV.n" && mv "$TSV.n" "$TSV"
  arm; PH2="$(mkcopy 71)"; printf 'z\n' >> "$PH2/a.txt"
  ( cd "$PH2" && exec sleep 30 ) & HPID2=$!   # 진짜로 그 사본을 cwd 로 쓰는 프로세스 = «실제 점유»
  sleep 1
  M4=$(awk 'END{print NR+0}' "$SLOG"); KEEP_ON=1 scs --sweep; L4="$(grep 'swept=' "$SLOG" | tail -1)"
  { [ -d "$PH2" ] && [ "$(cnt held "$L4")" = 1 ] && [ "$(cnt held-lsof "$L4")" = 0 ]; } \
    && ok "r1090-ⓖ3 실제 점유(pid cwd) = held=1 · held-lsof=0 · 삭제 0" || bad "r1090-ⓖ3 끝 줄 [$L4] [$OUT]"
  kill "$HPID2" 2>/dev/null; wait "$HPID2" 2>/dev/null
  rm -rf "$PH2"; awk -F'\t' -v a="$PH2" '$1!=a' "$TSV" > "$TSV.n" && mv "$TSV.n" "$TSV"
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
    mut keepverify-off lib 's#^  \[ -z "\$why" \] || { KEEP_WHY="\$why · 보관 폴더 \$kd"; return 3; }#  :#' 'r1090-ⓓ|r1090-ⓖ'
    mut detach-off ft 's#^         \[ "\$ST" = 0 \] || { gfail G7 3 "detached 사본 더러움#         : || { gfail G7 3 "detached 사본 더러움#' 'r1090-ⓒ|r1090-ⓖ'
    mut count-off ft 's#\*더러움\*) RD=\$((RD+1));;#*더러움*) :;;#' 'r1090-ⓖ'
    # ※ 계약④(meta 재읽기)는 «재읽기 자체» 를 변이로 구별하지 못한다(메모리 $head 와 meta 3칸이 같은 실행 안에서 항상 같은 값) = 알려진 한계 · 대신 ⓓ2(가짜 HEAD 주입) 가 그 자리를 지킨다
    mut heldlsof-off ft 's#"\${HLSOF:-0}"#$((0))#' 'r1090-ⓖ2'
  fi
fi

[ $fail -eq 0 ] && echo "ALL PASS" || echo "($fail failed)"
exit $fail

