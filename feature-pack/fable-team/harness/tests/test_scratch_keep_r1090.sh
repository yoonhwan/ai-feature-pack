#!/usr/bin/env bash
# test_scratch_keep_r1090.sh — ft-scratch-repo.sh r1090 «보관 성공 길»(ⓑ2 ⓐⓑⓗ ⓓ2 ⓗ3 ⓙ ⓙ2 ⓘ) — 칸 내용·변이 그대로
#   하드 룰 22 «시험 1개 단독 70초»: 4864 칸(ⓗ2)은 test_scratch_keep_r1090_big.sh, 거절·분류는 …_refuse.sh 로 나눴다
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
  # ── ⓑ2(R2 가지 · DA② 결정 1): 가지 사본 보관 = meta 가지 칸이 가지 이름(«-»·«detached» 아님) ──
  arm; PB="$(mkcopy 20)"; git -C "$PB" checkout -q -b brKeep2 2>/dev/null; printf 'z\n' >> "$PB/a.txt"
  KEEP_ON=1 scs --sweep
  { [ ! -d "$PB" ] && kept "$PB" && [ "$(awk -F'\t' 'NR==1{print $4}' "$(kd "$PB")/meta.txt" 2>/dev/null)" = brKeep2 ]; } \
    && ok "r1090-ⓑ2 가지 사본 보관 = meta 4칸 «brKeep2»(가지 이름 · «-» 아님) + 삭제" \
    || bad "r1090-ⓑ2 meta4=[$(awk -F'\t' '{print $4}' "$(kd "$PB")/meta.txt" 2>/dev/null)] 남음=$([ -d "$PB" ] && echo y) [$OUT]"
  rm -rf "$PB"; awk -F'\t' -v a="$PB" '$1!=a' "$TSV" > "$TSV.n" && mv "$TSV.n" "$TSV"
  #   ★기본 = 깨끗 1 · 수정 1 · 추적 안 한 파일 0 (사본 3개 · 회차 한 번) — lsof 1회가 1.1~1.6초(부하 시 5초+)라
  #     34개를 기본 시험에 넣으면 «시험 1개 70초»(하드 룰 22)를 넘는다. 카드 숫자 그대로(깨끗 26 · 수정 7 · 4864 1 = 34개)는
  #     FT_HEAVY=1 로 따로 1회 잰다(같은 칸·같은 판정 · 기본은 모양만 작게)★
  if [ "${FT_CASES:-all}" != none ]; then
    NC="${NCLEAN:-1}"; NDI="${NODIRTY:-1}"; NU="${NUNTRACKED:-0}"
    [ "${FT_HEAVY:-0}" != 1 ] || { NC=26; NDI=7; NU=4864; }   # 카드 숫자 그대로(FT_HEAVY=1 · 1회 실측)
    T0=$(date +%s); CLEAN=(); DIRTY=()
    for i in $(seq 1 "$NC"); do CLEAN+=("$(mkcopy "$i")"); done
    for i in $(seq $((NC+1)) $((NC+NDI))); do p="$(mkcopy "$i")"; printf 'z\n' >> "$p/a.txt"; DIRTY+=("$p"); done
    PBIG="$(mkcopy $((NC+NDI+1)))"; mkdir -p "$PBIG/u"
    [ "$NU" = 0 ] || python3 -c 'import sys; [open("%s/u/f%d" % (sys.argv[1], i), "w").close() for i in range(int(sys.argv[2]))]' "$PBIG" "$NU"
    T_BUILD=$(( $(date +%s) - T0 )); ROUNDS=0; SLOW=0
    while [ "$ROUNDS" -lt 6 ]; do   # 회차마다 70초 예산 — 남은 것은 다음 회차가 잇는다(하드 룰 12)
      ROUNDS=$((ROUNDS+1)); T1=$(date +%s); KEEP_ON=1 scs --sweep; DT=$(( $(date +%s) - T1 ))
      echo "TIME r1090 회차$ROUNDS: ${DT}초"
      [ "$DT" -gt "$SLOW" ] && SLOW="$DT"
      left=0; for p in "${CLEAN[@]}" "${DIRTY[@]}" "$PBIG"; do [ ! -d "$p" ] || left=$((left+1)); done
      [ "$left" = 0 ] && break
    done
    nc=0; for p in "${CLEAN[@]}"; do [ ! -d "$p" ] && ! kept "$p" && nc=$((nc+1)); done
    [ "$nc" = "$NC" ] && ok "r1090-ⓐ 깨끗 $NC = 전부 삭제 · 보관 0(R1)" || bad "r1090-ⓐ 남은/보관된 깨끗 사본 $((NC-nc))개 [$OUT]"
    nd=0; for p in "${DIRTY[@]}"; do
      [ ! -d "$p" ] && kept "$p" && grep -q '^+z' "$(kd "$p")/diff.patch" && [ -f "$(kd "$p")/meta.txt" ] && [ -f "$(kd "$p")/status.txt" ] && [ -f "$(kd "$p")/untracked.tar" ] && [ "$(awk -F'\t' 'NR==1{print $4}' "$(kd "$p")/meta.txt" 2>/dev/null)" = detached ] && nd=$((nd+1))
    done
    [ "$nd" = "$NDI" ] && ok "r1090-ⓑ 1줄 수정 $NDI = 보관 4파일 + 삭제 · diff.patch 에 그 줄 · meta 4칸 «detached»(R2 · DA② 결정 1)" || bad "r1090-ⓑ 보관/삭제·meta 칸 불일치 $((NDI-nd))개 [$OUT]"
    ntar=$(tar -tf "$(kd "$PBIG")/untracked.tar" 2>/dev/null | awk 'END{print NR+0}')
    if [ "$NU" = 0 ]; then
      { [ ! -d "$PBIG" ] && ! kept "$PBIG"; } && ok "r1090-ⓑ 추적 안 한 파일 0 = 깨끗 = 삭제 · 보관 0(작은 기본 회차)" || bad "r1090-ⓑ 깨끗한 사본이 남음 [$OUT]"
    else
      { [ ! -d "$PBIG" ] && kept "$PBIG" && [ "$ntar" = "$NU" ] && [ "$(awk 'END{print NR}' "$(kd "$PBIG")/status.txt")" = "$NU" ]; } \
        && ok "r1090-ⓑ 추적 안 한 파일 ${NU} = tar 항목 ${NU} + status ${NU}줄 + 삭제(R3)" || bad "r1090-ⓑ 추적 안 한 파일 ${NU} 인데 tar=$ntar 남음=$([ -d "$PBIG" ] && echo y) [$OUT]"
    fi
    { [ "$SLOW" -le 70 ]; } && ok "r1090-ⓗ 회차 최대 ${SLOW}초 ≤ 70초(사본 $((NC+NDI+1))개 · ${ROUNDS}회차 · 만들기 ${T_BUILD}초)" || bad "r1090-ⓗ 회차 ${SLOW}초 > 70초"
    # 계약⑧ 정정(arch#176): «34개 회차 70초» = sweep 호출 1회마다 70초 상한 · 남은 사본은 다음 호출 · 34개 전부 = 호출 2회 이내
    [ "${FT_HEAVY:-0}" != 1 ] || { [ "$ROUNDS" -le 2 ] && [ "$left" = 0 ] && ok "r1090-ⓗ HEAVY 34개 = 호출 ${ROUNDS}회 ≤ 2회(호출별 최대 ${SLOW}초)" || bad "r1090-ⓗ HEAVY 호출 ${ROUNDS}회(≤2 이어야) 남은 $left"; }
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
  # ── ⓓ2(계약④ · DA② 결정 2): 보관 확인의 HEAD 는 «저장한 meta.txt 를 다시 읽어» 지금 HEAD 와 맞춘다 ──
  #   주입: 보관 단계의 HEAD 읽기(1번째)만 가짜 sha 를 내고 실제 HEAD 는 그대로 → meta 에는 가짜가 적힌다
  #         → meta 를 다시 읽는 지금 코드는 «HEAD 가 바뀜» 으로 거절(사본·보관 폴더 남음) · 메모리 $head 를 쓰는 변이는 가짜끼리 맞아 «통과» 한다
  arm; PD2="$(mkcopy 61)"; printf 'u\n' > "$PD2/new.txt"; rm -f "$T/gh.n"
  KEEP_ON=1 GPRE="$T/gbin2/" GT_HEAD_AT=1 scs --sweep
  { [ -d "$PD2" ] && kept "$PD2" && printf '%s' "$OUT" | grep -q 'HEAD 가 바뀜' \
    && [ "$(awk -F'\t' 'NR==1{print $3}' "$(kd "$PD2")/meta.txt" 2>/dev/null)" = 1111111111111111111111111111111111111111 ]; } \
    && ok "r1090-ⓓ2 meta.txt 를 다시 읽어 HEAD 대조 = 가짜 HEAD 주입 → 거절 · 사본·보관 폴더 남음(계약④)" \
    || bad "r1090-ⓓ2 rc=$RC 남음=$([ -d "$PD2" ] && echo y) meta3=[$(awk -F'\t' '{print $3}' "$(kd "$PD2")/meta.txt" 2>/dev/null)] [$OUT]"
  rm -rf "$PD2"; awk -F'\t' -v b="$PD2" '$1!=b' "$TSV" > "$TSV.n" && mv "$TSV.n" "$TSV"
  # ── ⓗ3(하드 룰 12 · DA② 결정 4): 추적 안 한 파일 묶기가 느린 사본(3초)도 남은 예산 상한 안에서 통과한다 ──
  #   상한 = min(5초 + 7초×ceil(파일 수/1000), 남은 회차 예산, 70초) — 고정 7초도, 무제한도 아니다
  arm; PS="$(mkcopy 62)"; printf 'u\n' > "$PS/new.txt"; rm -f "$T/gt.n"
  T3=$(date +%s); KEEP_ON=1 GPRE="$T/gbin2/" GT_LS_SLEEP=3 scs --sweep; DT3=$(( $(date +%s) - T3 ))
  { [ ! -d "$PS" ] && kept "$PS" && [ "$DT3" -le 70 ] && [ "$(awk 'END{print NR+0}' "$(kd "$PS")/status.txt" 2>/dev/null)" = 1 ]; } \
    && ok "r1090-ⓗ3 느린 ls-files(3초) 사본 = 보관 성공 + 삭제 · 호출 ${DT3}초 ≤ 70초(상한 5+7×ceil(1/1000)=12초)" \
    || bad "r1090-ⓗ3 rc=$RC 남음=$([ -d "$PS" ] && echo y) 호출=${DT3}초 [$OUT]"
  rm -rf "$PS"; awk -F'\t' -v b="$PS" '$1!=b' "$TSV" > "$TSV.n" && mv "$TSV.n" "$TSV"
  # ── ⓙ(계약⑧ · DA② 결정 1·2): stat 은 «호출마다» 남은 예산을 다시 잰다 · 남은 예산 1초 + 2초 stat = «보관 시간 초과» 거절 · 사본 남음 ──
  #   제품 함수 keep_copy 를 그대로 부르고 «예산 시계만» 스텁한다(remtmo = 앞 5번 7초, 그 뒤 1초 — 6번째가 stat 첫 호출) · bounded 는 진짜로 자식을 끊는다
  KSLOW="$T/gbin4"; mkdir -p "$KSLOW"; STATREAL="$(command -v stat)"
  printf '#!/bin/sh\necho x >> "%s"\nsleep 2\nexec %s "$@"\n' "$T/stat.n" "$STATREAL" > "$KSLOW/stat"; chmod 755 "$KSLOW/stat"
  ukeep() { # <RBUD|0> → "rc=<n> why=<KEEP_WHY>"
    local URBUD="$1"
    ( PATH="$KSLOW:$PATH"; KEEPDIR="$T/unit-keep"; KEEP_MAX_MB=500; RBUD="$URBUD"
      cap() { local v="$1"; shift; local oc orc; oc="$("$@")"; orc=$?; printf -v "$v" '%s' "$oc"; return "$orc"; }
      bounded() { local s="$1"; shift; local p w r; "$@" & p=$!; ( sleep "$s"; kill -TERM "$p" 2>/dev/null ) & w=$!; wait "$p"; r=$?; kill "$w" 2>/dev/null; wait "$w" 2>/dev/null; [ "$r" -lt 124 ] || return 124; return "$r"; }
      isnum() { case "$1" in ''|*[!0-9]*) return 1;; esac; }
      remtmo() { local cn; cn=$(( $(/bin/cat "$T/rn.n" 2>/dev/null || echo 0) + 1 )); echo "$cn" > "$T/rn.n"; if [ "$cn" -le 5 ]; then printf '7\n'; else printf '1\n'; fi; }
      . "$(dirname -- "$SUT")/_scratch_keep.sh"
      keep_copy "$UP" gone-rd branch "$UN"; echo "rc=$? why=$KEEP_WHY" )
  }
  UP="$T/unit-copy"; git -C "$G" worktree add -q --detach "$UP" "$SHA" >/dev/null 2>&1; printf 'z\n' >> "$UP/a.txt"
  UN=$(git -C "$UP" status --porcelain --untracked-files=all | awk 'END{print NR+0}'); rm -f "$T/stat.n" "$T/rn.n"
  TU="$(ukeep 0)"; echo "UNIT keep_copy(stat 예산 1초): $TU"
  KU="$T/unit-keep/gone-rd/unit-copy"; NS=$(awk 'END{print NR+0}' "$T/stat.n" 2>/dev/null)
  { [ -d "$UP" ] && printf '%s' "$TU" | grep -q 'rc=3' && printf '%s' "$TU" | grep -q '보관 시간 초과' && [ "$NS" = 2 ]; } \
    && ok "r1090-ⓙ 남은 예산 1초 + 2초 stat = «보관 시간 초과» 거절(rc3) · 사본 남음 · stat 2회에서 끊김(3번째 호출 0 · 계약⑧)" \
    || bad "r1090-ⓙ [$TU] stat 호출 ${NS}회 남음=$([ -d "$UP" ] && echo y)"
  # ── ⓙ2(DA② 결정 2): 남은 예산 0 이면 keeptmo 가 0 = tar 호출 0 · 1초로 올리지 않는다 ──
  rm -rf "$T/unit-keep"; rm -f "$T/rn.n" "$T/stat.n"; TU2="$(ukeep "$(date +%s)")"; echo "UNIT keep_copy(예산 0): $TU2"
  NS2=0; [ ! -f "$T/stat.n" ] || NS2=$(awk 'END{print NR+0}' "$T/stat.n" 2>/dev/null)
  { printf '%s' "$TU2" | grep -q 'rc=3' && printf '%s' "$TU2" | grep -q '보관 시간 초과' && [ ! -f "$KU/untracked.tar" ] && [ "$NS2" = 0 ]; } \
    && ok "r1090-ⓙ2 예산 0 = «보관 시간 초과» 거절 · tar·stat 호출 0(1초 올림 0)" || bad "r1090-ⓙ2 [$TU2] stat ${NS2}회"
  rm -rf "$T/unit-keep"; git -C "$G" worktree remove --force "$UP" >/dev/null 2>&1
  # ── ⓘ bin·kit 같은 내용(새 파일 _scratch_keep.sh 포함) ──
  { cmp -s "$REPO/harness/bin/ft-scratch-repo.sh" "$REPO/harness/kit/fable-team/bin/ft-scratch-repo.sh" \
    && cmp -s "$REPO/harness/bin/_scratch_keep.sh" "$REPO/harness/kit/fable-team/bin/_scratch_keep.sh"; } \
    && ok "r1090-ⓘ bin·kit 같은 내용(cmp0 · ft-scratch-repo.sh + _scratch_keep.sh)" || bad "r1090-ⓘ bin·kit 다름"
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
    mut tartmo-off lib 's#^  t=\$(( 5 + 7 \* ( (n + 999) / 1000 ) ))#  t=1#' 'r1090-ⓗ3'
    mut statbudget-off lib 's#^    cap r remtmo$#    r=7#' 'r1090-ⓙ'
  fi
fi

[ $fail -eq 0 ] && echo "ALL PASS" || echo "($fail failed)"
exit $fail

