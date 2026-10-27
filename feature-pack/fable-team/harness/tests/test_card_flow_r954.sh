#!/usr/bin/env bash
# test_card_flow_r954.sh — r954: ft-card-flow.sh 숫자 줄 + ft-news-tick ④-b 줄 + ft-nano-spawn 앞 «이동 먼저» WARN(rc 불변). 축 ⓐ~ⓖ.
# 전부 mktemp — 임시 저장소·가짜 tmux(PATH)·가짜 docker. 실 좌석·실 워크트리·실 kill 0.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
export FT_ALLOW_TRACKED_BIN=1
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY FT_NEWS_ROOT FT_NEWS_TREE FT_TEAMS_REF FT_FINISHED_MAIN
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="$HERE/../.."; BIN="$REPO/harness/bin"; KIT="$REPO/harness/kit/fable-team/bin"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
has() { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «$2» ← ${1:0:400}";; esac; }
hasnt() { case "$1" in *"$2"*) bad "$3 — 있으면 안 됨: «$2»";; *) ok "$3";; esac; }

for f in ft-card-flow.sh ft-news-tick.sh ft-nano-spawn.sh; do
  bash -n "$BIN/$f" && ok "bash -n $f" || bad "bash -n $f"
  cmp -s "$BIN/$f" "$KIT/$f" && ok "키트 사본 cmp 0 $f" || bad "키트 사본 불일치 $f"
done
CF="$KIT/ft-card-flow.sh"

# 가짜 tmux — 세션 목록은 $SESS 파일 · SESS 없으면 «서버 없음» · 다른 오류는 TMUX_FAIL
FAKE="$T/fake"; SESS="$T/sessions.txt"; mkdir -p "$FAKE"
cat > "$FAKE/tmux" <<EOF
#!/bin/sh
[ -f "$T/tmux.fail" ] && { echo "error connecting to /tmp/x (Permission denied)" >&2; exit 1; }
[ -f "$SESS" ] || { echo "no server running on /tmp/x" >&2; exit 1; }
case "\$1" in ls) cat "$SESS";; *) exit 1;; esac
EOF
chmod 755 "$FAKE/tmux"
printf '#!/bin/sh\nexit 1\n' > "$FAKE/docker"; chmod 755 "$FAKE/docker"
sess() { : > "$SESS"; for n in "$@"; do echo "$n" >> "$SESS"; done; }

# 픽스처 저장소: main 에 landed 커밋 · side 가지에 비조상 커밋
R="$T/repo"; git init -q -b main "$R"; G() { git -C "$R" -c user.name=t -c user.email=t@t "$@"; }
mkdir -p "$R"/design/alpha/indices/{대기,진행,완성} "$R/.fable-team/comm" "$R/.fable-team/state"
echo x > "$R/f"; G add -A >/dev/null; G commit -q -m base
LANDED="$(G rev-parse HEAD)"
G checkout -q -b side; echo y > "$R/g"; G add -A >/dev/null; G commit -q -m side; SIDE="$(G rev-parse HEAD)"; G checkout -q main
card() { printf '# %s\n## 상태\n%s\n' "$2" "${3:-}" > "$R/design/alpha/indices/$1/$2.md"; }
export FT_FINISHED_MAIN=main
run() { PATH="$FAKE:$PATH" bash "$CF" --team alpha --root "$R" --dir "$R/design/alpha" "$@" 2>&1; }

# ⓐ 숫자 1줄: 대기 2 · 진행 4(좌석 2 = 세션 있는 카드) · 착지됐는데 진행 1
card 대기 w1; card 대기 w2
card 진행 live1; card 진행 live2; card 진행 done1 "- 착지: $LANDED (DA 닫힘 x#§1)"; card 진행 stale1 "- 착지: $SIDE"
sess "byz-alpha-nano-live1#0" "byz-alpha-nano-live2#0"
o="$(run)"; rc=$?
[ "$rc" = 0 ] && [ "$o" = "카드 대기 2 · 진행 4(좌석 2) · 착지됐는데 진행 1" ] && ok "ⓐ 숫자 1줄 꼴 · rc0" || bad "ⓐ rc=$rc «${o}»"

# ⓑ 거짓 양성 0: 착지 줄 없음·비조상 sha·착지 줄 없는 카드는 K 에 안 센다(위 stale1·live1·live2 → K=1 이 이미 증명) · 착지 줄이 전혀 없는 폴더 → K 0
mkdir -p "$T/d2/indices/진행" "$T/d2/indices/대기"; printf '# a\n- 착지: $SIDE\n' > "$T/d2/indices/진행/a.md"; printf '# b\n' > "$T/d2/indices/진행/b.md"
o="$(PATH="$FAKE:$PATH" bash "$CF" --team beta --root "$R" --dir "$T/d2" 2>&1)"
[ "$o" = "카드 대기 0 · 진행 2(좌석 0) · 착지됐는데 진행 0" ] && ok "ⓑ 근거 없는 카드·비조상 sha → K 0" || bad "ⓑ «${o}»"
# ⓑ-2 ft-finished-check FINISHED 인 가지 카드는 K 에 센다(대역) · ACTIVE 면 안 센다
G branch nano/fin1; G branch nano/act1; card 진행 fin1; card 진행 act1
printf '#!/bin/sh\ncase "$1" in nano/fin1) echo "FINISHED $1";; *) echo "ACTIVE $1";; esac\n' > "$T/fchk.sh"
o="$(FT_CARD_FLOW_FINISHED="$T/fchk.sh" run --branch-check)"
has "$(FT_CARD_FLOW_FINISHED="$T/fchk.sh" run)" "착지됐는데 진행 1" "ⓑ-2 기본(옵션 없음)은 가지 판정을 안 한다 → K 1"
has "$o" "착지됐는데 진행 2" "ⓑ-2 finished-check FINISHED 1건 + 착지 sha 1건 = K 2 (ACTIVE 는 안 셈)"
rm -f "$R/design/alpha/indices/진행/fin1.md" "$R/design/alpha/indices/진행/act1.md"

# ⓑ2 (r2 반례 1) 착지 값은 토큰 «전체» — 41자(40자+1)·16진수 아님·6자는 근거 없음(K 0) · 40자 전체/7자 전체는 인정
mkdir -p "$T/d4/indices/진행" "$T/d4/indices/대기"
k4() { rm -f "$T"/d4/indices/진행/*.md; printf '# c\n- 착지: %s (DA)\n' "$1" > "$T/d4/indices/진행/c.md"; PATH="$FAKE:$PATH" bash "$CF" --team g --root "$R" --dir "$T/d4" 2>&1; }
[ "$(k4 "${LANDED}0")" = "카드 대기 0 · 진행 1(좌석 0) · 착지됐는데 진행 0" ] && ok "ⓑ2 41자(40자+1) → K 0" || bad "ⓑ2 41자 «$(k4 "${LANDED}0")»"
[ "$(k4 "${LANDED}g")" = "카드 대기 0 · 진행 1(좌석 0) · 착지됐는데 진행 0" ] && ok "ⓑ2 40자+비16진수 글자 → K 0" || bad "ⓑ2 혼합"
[ "$(k4 "${LANDED:0:6}")" = "카드 대기 0 · 진행 1(좌석 0) · 착지됐는데 진행 0" ] && ok "ⓑ2 6자 → K 0" || bad "ⓑ2 6자"
[ "$(k4 "${LANDED}")" = "카드 대기 0 · 진행 1(좌석 0) · 착지됐는데 진행 1" ] && ok "ⓑ2 40자 전체 → K 1" || bad "ⓑ2 40자 전체"
[ "$(k4 "${LANDED:0:7}")" = "카드 대기 0 · 진행 1(좌석 0) · 착지됐는데 진행 1" ] && ok "ⓑ2 7자 약식 sha → 착지 인정 K 1 (r4 보강 ①)" || bad "ⓑ2 7자 «$(k4 "${LANDED:0:7}")»"
[ "$(k4 "${LANDED:0:8}")" = "카드 대기 0 · 진행 1(좌석 0) · 착지됐는데 진행 1" ] && ok "ⓑ2 8자 약식 sha → K 1" || bad "ⓑ2 8자"

# ⓝ (r3) 낱말 전체만 — 40자 뒤에 무엇을 붙여도 K 0 (DA r2 반례 1 + 꼴 묶음) · 대문자 hex 도 K 0 · 백틱 한 쌍·뒤 공백 설명은 인정
Z="카드 대기 0 · 진행 1(좌석 0) · 착지됐는데 진행 0"
for suf in "-invalid" "-x" "." "/" "가" ",x" ":" "_"; do [ "$(k4 "${LANDED}${suf}")" = "$Z" ] && ok "ⓝ 40자+«${suf}» → K 0" || bad "ⓝ 40자+«${suf}» «$(k4 "${LANDED}${suf}")»"; done
U="$(printf '%s' "$LANDED" | tr a-f A-F)"; [ "$(k4 "$U")" = "$Z" ] && ok "ⓝ 대문자 hex → K 0" || bad "ⓝ 대문자"
[ "$(k4 "\`${LANDED}\` (DA 닫힘)")" = "카드 대기 0 · 진행 1(좌석 0) · 착지됐는데 진행 1" ] && ok "ⓝ 백틱 한 쌍 + 뒤 설명 → K 1" || bad "ⓝ 백틱"
[ "$(k4 "\`${LANDED}")" = "$Z" ] && ok "ⓝ 백틱 한쪽만 → K 0" || bad "ⓝ 한쪽 백틱"
[ "$(k4 "TODO ${LANDED}")" = "$Z" ] && ok "ⓝ 둘째 낱말이 40hex(첫 낱말 아님) → K 0 (r4 보강 ①)" || bad "ⓝ 둘째 낱말 «$(k4 "TODO ${LANDED}")"""
[ "$(k4 "\`${LANDED:0:7}\` (약식)")" = "카드 대기 0 · 진행 1(좌석 0) · 착지됐는데 진행 1" ] && ok "ⓝ 백틱 벗긴 7자 → K 1" || bad "ⓝ 백틱 7자"

# ⓒ 좌석 M: tmux 서버 없음 = M 0 · 그 밖 tmux 실패 = rc1(조용한 0 금지)
rm -f "$SESS"; o="$(run)"; has "$o" "진행 4(좌석 0)" "ⓒ 서버 없음 → 좌석 0"
sess "byz-alpha-nano-live1#0"; touch "$T/tmux.fail"; o="$(run)"; rc=$?
{ [ "$rc" = 1 ] && [[ "$o" == *"FAIL ft-card-flow"* ]]; } && ok "ⓒ tmux 실패 → rc1 + FAIL 줄" || bad "ⓒ rc=$rc «${o}»"; rm -f "$T/tmux.fail"

# ⓓ 시간 초과 → 숫자 대신 «확인 불가» 줄(빈칸·0 아님) rc3
sess "byz-alpha-nano-live1#0" "byz-alpha-nano-live2#0"
o="$(FT_CARD_FLOW_TIMEOUT_SEC=0 run)"; rc=$?
{ [ "$rc" = 3 ] && [[ "$o" == *"카드 숫자 확인 불가(시간 초과)"* ]] && [[ "$o" != *"진행 "*"(좌석"* ]]; } && ok "ⓓ 시간 초과 → 확인 불가 줄 rc3" || bad "ⓓ rc=$rc «${o}»"
# ⓓ-2 ft-news-tick 출력에 팀마다 ⓐ 줄 1개 + 확인 불가 줄도 그대로
NR="$R"; echo '{}' > "$NR/.fable-team/seats.json"; mkdir -p "$T/tmpn"
printf '| 팀 | 폴더 |\n|---|---|\n| alpha | `design/alpha/` |\n' > "$R/design/TEAMS.md"
tick() { (cd "$NR" && PATH="$FAKE:$PATH" TMPDIR="$T/tmpn" FT_NEWS_ROOT="$NR" FT_ME=me FT_CARD_FLOW_TEAMS="${TEAMS:-alpha}" bash "$KIT/ft-news-tick.sh" 2>&1); }
o="$(tick)"
has "$o" "alpha: 카드 대기 2 · 진행 4(좌석 2) · 착지됐는데 진행 1" "ⓓ news-tick 에 팀 숫자 줄 1개"
[ "$(printf '%s\n' "$o" | grep -c '^alpha: 카드 대기')" = 1 ] && ok "ⓓ 팀당 정확히 1줄" || bad "ⓓ 줄 수"
o="$(FT_CARD_FLOW_TIMEOUT_SEC=0 tick)"; has "$o" "alpha: 카드 숫자 확인 불가(시간 초과)" "ⓓ news-tick 시간 초과 = 확인 불가 줄(빈칸 0)"

# ⓓ2 (r2 반례 2) --branch-check 가지 판정이 상한 초과·실패 → K 에 안 세고 «확인 불가 n» (숫자 0 으로 보이는 길 0)
# r4: 시험 흔들림 대응 — 상한 3초 · 대역 sleep 12초(상한의 4배) · 완료 판정 sluck 8초(상한의 2.6배, 부하 29 에서도 안 흔들림)
mkdir -p "$T/d5/indices/진행" "$T/d5/indices/대기"; printf '# tb\n' > "$T/d5/indices/진행/tb.md"; G branch nano/tb
printf '#!/bin/sh\nsleep 12\necho "FINISHED $1"\n' > "$T/slow.sh"; printf '#!/bin/sh\necho "ERROR x"; exit 2\n' > "$T/err.sh"
t0=$SECONDS; o="$(FT_CARD_FLOW_TIMEOUT_SEC=3 FT_CARD_FLOW_FINISHED="$T/slow.sh" PATH="$FAKE:$PATH" bash "$CF" --team g --root "$R" --dir "$T/d5" --branch-check 2>&1)"; el=$((SECONDS-t0))
{ [[ "$o" == *"착지됐는데 진행 0 · 확인 불가 1(가지 판정 시간 초과)"* ]] && [ "$el" -le 8 ]; } && ok "ⓓ2 판정 시간 초과 → 확인 불가 1 줄 (${el}초 · 대역 12초를 기다리지 않음)" || bad "ⓓ2 el=${el} «${o}»"
o="$(FT_CARD_FLOW_FINISHED="$T/err.sh" PATH="$FAKE:$PATH" bash "$CF" --team g --root "$R" --dir "$T/d5" --branch-check 2>&1)"
has "$o" "확인 불가 1(가지 판정 실패)" "ⓓ2 판정 rc≠0 → 확인 불가 1(실패)"
printf '#!/bin/sh\necho "FINISHED $1"\n' > "$T/fast.sh"
o="$(FT_CARD_FLOW_FINISHED="$T/fast.sh" PATH="$FAKE:$PATH" bash "$CF" --team g --root "$R" --dir "$T/d5" --branch-check 2>&1)"
[ "$o" = "카드 대기 0 · 진행 1(좌석 0) · 착지됐는데 진행 1" ] && ok "ⓓ2 제때 FINISHED → K 1 · 확인 불가 줄 0" || bad "ⓓ2 정상 «${o}»"

# ⓞ (r3) 가지 판정 실패·시간 초과 × 모든 모드(일반 · --warn) × (시간 초과 · rc2 · 빈 출력) → 모드마다 «확인 불가» 줄 ≥1 · 상한 안에서 끝남
printf '#!/bin/sh\nsleep 12\necho "ACTIVE $1"\n' > "$T/slow2.sh"; printf '#!/bin/sh\nexit 2\n' > "$T/rc2.sh"; printf '#!/bin/sh\nexit 0\n' > "$T/empty.sh"
for mode in "" "--warn"; do for kind in slow2 rc2 empty; do
  t0=$SECONDS; o="$(FT_CARD_FLOW_TIMEOUT_SEC=3 FT_CARD_FLOW_FINISHED="$T/$kind.sh" PATH="$FAKE:$PATH" bash "$CF" --team g --root "$R" --dir "$T/d5" --branch-check $mode 2>&1)"; el=$((SECONDS-t0))
  { [[ "$o" == *"확인 불가 1("* ]] && [ "$el" -le 8 ]; } && ok "ⓞ 모드«${mode:-일반}» × ${kind} → 확인 불가 줄 (${el}초)" || bad "ⓞ 모드«${mode:-일반}» × ${kind} el=${el} «${o}»"
done; done
# ⓞ-2 (r4 보강 4) «--warn 건강 + 시간 초과» — 건강한 카드(d5 = 좌석 0·K 0)에서도 시간 초과면 --warn 이 빈 출력이 아니고 WARN 줄이다
for mode in "--warn"; do
  o="$(FT_CARD_FLOW_TIMEOUT_SEC=3 FT_CARD_FLOW_FINISHED="$T/slow2.sh" PATH="$FAKE:$PATH" bash "$CF" --team g --root "$R" --dir "$T/d5" --branch-check $mode 2>&1)"
  { [[ "$o" == WARN* ]] && [[ "$o" == *"확인 불가 1(가지 판정 시간 초과)"* ]]; } && ok "ⓞ-2 건강 + 시간 초과 → --warn 경보 1줄(빈 출력 0)" || bad "ⓞ-2 «${o}»"
done

# ⓟ (r4 DA r3 반례 1) 카드 폴더 권한 000 = 빈 목록이 아니라 «확인 불가» — 일반 · --warn 두 모드
mkdir -p "$T/d6/indices/진행" "$T/d6/indices/대기"; printf '# p\n- 착지: %s\n' "$LANDED" > "$T/d6/indices/진행/p1.md"
if [ "$(id -u)" = 0 ]; then ok "ⓟ (root — 권한 000 시험 건너뜀)"; else
  chmod 000 "$T/d6/indices/진행"
  for mode in "" "--warn"; do
    o="$(PATH="$FAKE:$PATH" bash "$CF" --team g --root "$R" --dir "$T/d6" $mode 2>&1)"; rc=$?
    { [ "$rc" = 3 ] && [[ "$o" == *"확인 불가(카드 폴더 못 읽음"* ]] && [[ "$o" != *"진행 0"* ]]; } && ok "ⓟ 권한 000 모드«${mode:-일반}» → 확인 불가 줄 rc3" || bad "ⓟ 권한 000 모드«${mode:-일반}» rc=$rc «${o}»"
  done
  chmod 755 "$T/d6/indices/진행"
fi
# ⓟ-2 (r4 DA r3 반례 2) 판정 스크립트가 없는 파일(--branch-check) = 건너뛰지 않고 «확인 불가» — 일반 · --warn
for mode in "" "--warn"; do
  o="$(FT_CARD_FLOW_FINISHED="$T/nope.sh" PATH="$FAKE:$PATH" bash "$CF" --team g --root "$R" --dir "$T/d5" --branch-check $mode 2>&1)"; rc=$?
  { [ "$rc" = 0 ] && [[ "$o" == *"확인 불가 1(가지 판정 시작 실패)"* ]]; } && ok "ⓟ-2 판정 스크립트 없음 모드«${mode:-일반}» → 확인 불가 줄" || bad "ⓟ-2 모드«${mode:-일반}» rc=$rc «${o}»"
done
# ⓟ-3 (r4 보강 ③) git show-ref 오류(rc≥2) = 확인 불가 · 가지 없음(rc1) 만 «대상 아님»
FG="$T/fakegit"; mkdir -p "$FG"; REALGIT="$(command -v git)"
printf '#!/bin/sh\ncase " $* " in *" show-ref "*) exit 2;; esac\nexec "%s" "$@"\n' "$REALGIT" > "$FG/git"; chmod 755 "$FG/git"
o="$(PATH="$FG:$FAKE:$PATH" FT_CARD_FLOW_FINISHED="$T/fast.sh" bash "$CF" --team g --root "$R" --dir "$T/d5" --branch-check 2>&1)"
has "$o" "확인 불가 1(가지 판정 시작 실패)" "ⓟ-3 show-ref rc2 → 확인 불가 줄(건너뛰지 않음)"
mkdir -p "$T/d7/indices/진행" "$T/d7/indices/대기"; printf '# nb\n' > "$T/d7/indices/진행/nb.md"
o="$(PATH="$FAKE:$PATH" FT_CARD_FLOW_FINISHED="$T/fast.sh" bash "$CF" --team g --root "$R" --dir "$T/d7" --branch-check 2>&1)"
[ "$o" = "카드 대기 0 · 진행 1(좌석 0) · 착지됐는데 진행 0" ] && ok "ⓟ-3 가지 없음(show-ref rc1) → 확인 불가 0(대상 아님)" || bad "ⓟ-3 rc1 «${o}»"
# ⓟ-4 (r4) 카드 파일 자체를 못 읽음(권한 000) → 빈 카드 아니라 «확인 불가»
mkdir -p "$T/d8/indices/진행" "$T/d8/indices/대기"; printf '# u\n- 착지: %s\n' "$LANDED" > "$T/d8/indices/진행/u1.md"
if [ "$(id -u)" = 0 ]; then ok "ⓟ-4 (root — 파일 권한 000 시험 건너뜀)"; else
  chmod 000 "$T/d8/indices/진행/u1.md"
  o="$(PATH="$FAKE:$PATH" bash "$CF" --team g --root "$R" --dir "$T/d8" 2>&1)"; rc=$?
  { [ "$rc" = 3 ] && [[ "$o" == *"확인 불가(카드 파일 못 읽음"* ]]; } && ok "ⓟ-4 카드 파일 권한 000 → 확인 불가 줄 rc3" || bad "ⓟ-4 rc=$rc «${o}»"
  chmod 644 "$T/d8/indices/진행/u1.md"
fi

# ⓥ (r5 재설계) 읽기 창구 1개 — ENOENT 만 «없음» · 그 밖 OSError = «확인 불가(… errno …)» rc 3 · os.path.* 선판정 0
ISROOT=0; [ "$(id -u)" = 0 ] && ISROOT=1
vrun() { PATH="$FAKE:$PATH" bash "$CF" --team alpha --root "$R" --dir "$1" ${2:-} 2>&1; }
# ⓥ1 = r4 반례 그대로: 카드 폴더 상위(design/alpha/indices) 권한 000 → 확인 불가(EACCES) rc 3 · --warn 도 같은 줄
mkdir -p "$T/r5/design/alpha/indices/대기" "$T/r5/design/alpha/indices/진행"
printf '# p\n- 착지: %s\n' "$LANDED" > "$T/r5/design/alpha/indices/진행/p1.md"
if [ "$ISROOT" = 1 ]; then ok "ⓥ1 (root — 권한 000 시험 건너뜀)"; e1=""; else
  chmod 000 "$T/r5/design/alpha/indices"
  for mode in "" "--warn"; do
    o="$(vrun "$T/r5/design/alpha" "$mode")"; rc=$?
    [ -n "$mode" ] || e1="$o"
    { [ "$rc" = 3 ] && [[ "$o" == *"확인 불가(카드 폴더 못 읽음 "*"EACCES"* ]] && [[ "$o" != *"진행 1"* ]] && [[ "$o" != *"진행 0"* ]]; } \
      && ok "ⓥ1 상위 000 모드«${mode:-일반}» → 확인 불가(EACCES) rc3 · 숫자 0" || bad "ⓥ1 모드«${mode:-일반}» rc=$rc «${o}»"
  done
  chmod 755 "$T/r5/design/alpha/indices"
fi
# ⓥ2 같은 류 3꼴 — ①카드 파일 권한 000(EACCES) ②진행/ 이 끊긴 심볼릭 링크(없음 아님) ③진행/x.md 가 폴더(EISDIR)
mkdir -p "$T/r6/design/alpha/indices/대기" "$T/r6/design/alpha/indices/진행"
printf '# u\n- 착지: %s\n' "$LANDED" > "$T/r6/design/alpha/indices/진행/u1.md"
if [ "$ISROOT" = 1 ]; then ok "ⓥ2-① (root — 파일 권한 000 시험 건너뜀)"; e2a=""; else
  chmod 000 "$T/r6/design/alpha/indices/진행/u1.md"
  o="$(vrun "$T/r6/design/alpha" "")"; rc=$?; e2a="$o"
  { [ "$rc" = 3 ] && [[ "$o" == *"확인 불가(카드 파일 못 읽음 "*"EACCES"* ]] && [[ "$o" != *"진행 1"* ]]; } \
    && ok "ⓥ2-① 카드 파일 000 → 확인 불가(EACCES) rc3" || bad "ⓥ2-① rc=$rc «${o}»"
  chmod 644 "$T/r6/design/alpha/indices/진행/u1.md"
fi
mkdir -p "$T/r7/design/alpha/indices/대기"; ln -s "$T/r7-no-such-target" "$T/r7/design/alpha/indices/진행"
o="$(vrun "$T/r7/design/alpha" "")"; rc=$?
{ [ "$rc" = 3 ] && [[ "$o" == *"확인 불가(카드 폴더 못 읽음"* ]] && [[ "$o" == *"ENOENT"* ]] && [[ "$o" == *"끊긴"* ]] && [[ "$o" != *"진행 0"* ]]; } \
  && ok "ⓥ2-② 진행/ 끊긴 링크 → 확인 불가(ENOENT 끊긴 링크) rc3 — «없음» 아님" || bad "ⓥ2-② rc=$rc «${o}»"
e2b="$o"
mkdir -p "$T/r8/design/alpha/indices/대기" "$T/r8/design/alpha/indices/진행/x.md"
o="$(vrun "$T/r8/design/alpha" "")"; rc=$?
{ [ "$rc" = 3 ] && [[ "$o" == *"확인 불가(카드 파일 못 읽음"* ]] && [[ "$o" == *"EISDIR"* ]] && [[ "$o" != *"진행 1"* ]]; } \
  && ok "ⓥ2-③ 진행/x.md 가 폴더 → 확인 불가(EISDIR) rc3" || bad "ⓥ2-③ rc=$rc «${o}»"
e2c="$o"
# ⓥ3 ENOENT 만 «없음» — 대기/ 폴더 자체가 없음 = 그 상태 카드 0장(현행 유지 rc0) · indices/ 자체가 없음 = 확인 불가 rc3
mkdir -p "$T/r9/design/alpha/indices/진행"; printf '# n\n' > "$T/r9/design/alpha/indices/진행/n1.md"
o="$(vrun "$T/r9/design/alpha" "")"; rc=$?
{ [ "$rc" = 0 ] && [ "$o" = "카드 대기 0 · 진행 1(좌석 0) · 착지됐는데 진행 0" ]; } \
  && ok "ⓥ3 대기/ 폴더 없음 → 카드 0장 정상 rc0(현행 유지)" || bad "ⓥ3 rc=$rc «${o}»"
mkdir -p "$T/r10/design/alpha"
o="$(vrun "$T/r10/design/alpha" "")"; rc=$?
{ [ "$rc" = 3 ] && [[ "$o" == *"확인 불가(카드 폴더 없음 또는 못 읽음"* ]] && [[ "$o" != *"진행 0"* ]]; } \
  && ok "ⓥ3 indices/ 자체 없음 → 확인 불가(없음 또는 못 읽음) rc3" || bad "ⓥ3 indices rc=$rc «${o}»"
# ⓥ4 사유 글자 — errno 이름이 들어 있고 «폴더 아님» 뭉갬 0
hasnt "$e1$e2a$e2b$e2c" "폴더 아님" "ⓥ4 «폴더 아님» 뭉갬 0"
if [ "$ISROOT" = 1 ]; then ok "ⓥ4 (root — EACCES 두 꼴 건너뜀)"; else
  has "$e1" "EACCES" "ⓥ4 폴더 상위 000 사유에 EACCES"
  has "$e2a" "EACCES" "ⓥ4 카드 파일 000 사유에 EACCES"
fi
has "$e2b" "ENOENT" "ⓥ4 끊긴 링크 사유에 ENOENT"
has "$e2c" "EISDIR" "ⓥ4 폴더 카드 사유에 EISDIR"
# ⓥ4b 읽기 창구 1개 — os.path.lexists|exists|isdir|isfile 로 폴더·카드를 묻는 줄 0 (r5 계약 ①)
q="$(grep -E 'os\.path\.(lexists|exists|isdir|isfile)' "$BIN/ft-card-flow.sh" | grep -cvE '^[[:space:]]*#')"
[ "${q:-1}" = 0 ] && ok "ⓥ4b os.path.* 폴더·카드 선판정 줄 0" || bad "ⓥ4b os.path.* 선판정 ${q}줄 남음"
# ⓥ (r6) python↔셸 줄 규약 — 이름 안 제어 문자가 한 줄로 이스케이프되어 건너간다 · 대기도 같은 읽기 창구
# ⓥ5 DA 반례 1 그대로: 진행/«a⏎C L 0 b.md»(착지 줄 없음) → 카드 1장으로 세고 K 0 · --warn 이동 대상에 «b.md» 조각 0 · 이름은 «a\nC L 0 b.md» 한 줄
mkdir -p "$T/v5/design/alpha/indices/대기" "$T/v5/design/alpha/indices/진행"
printf '# no landing\n' > "$T/v5/design/alpha/indices/진행/$(printf 'a\nC L 0 b').md"
for n in c1 c2 c3; do printf '# c\n' > "$T/v5/design/alpha/indices/진행/$n.md"; done
o="$(vrun "$T/v5/design/alpha" "")"; rc=$?
{ [ "$rc" = 0 ] && [ "$o" = "카드 대기 0 · 진행 4(좌석 0) · 착지됐는데 진행 0" ]; } \
  && ok "ⓥ5 개행 이름 카드 = 1장 · K 0(이름 조각을 카드 줄로 읽지 않는다)" || bad "ⓥ5 일반 rc=$rc «${o}»"
o="$(vrun "$T/v5/design/alpha" "--warn")"; rc=$?
{ [ "$rc" = 0 ] && [ "$(printf '%s\n' "$o" | wc -l | tr -d ' ')" = 1 ] \
  && [[ "$o" == *'이동 먼저: a\nC L 0 b.md c1.md c2.md c3.md'* ]]; } \
  && ok "ⓥ5 --warn 이동 대상 = 이스케이프한 한 줄 · «b.md» 조각 카드 추가 0" || bad "ⓥ5 --warn rc=$rc «${o}»"
# ⓥ6 DA 반례 2 그대로: 대기/a.md 권한 000 → 확인 불가(EACCES) rc3 (일반·--warn 같은 줄) · 대기/x.md 가 폴더 → EISDIR rc3
mkdir -p "$T/v6/design/alpha/indices/대기" "$T/v6/design/alpha/indices/진행"
printf '# w\n' > "$T/v6/design/alpha/indices/대기/a.md"
if [ "$ISROOT" = 1 ]; then ok "ⓥ6 (root — 대기 카드 권한 000 시험 건너뜀)"; e6=""; else
  chmod 000 "$T/v6/design/alpha/indices/대기/a.md"
  for mode in "" "--warn"; do
    o="$(vrun "$T/v6/design/alpha" "$mode")"; rc=$?; [ -n "$mode" ] || e6="$o"
    { [ "$rc" = 3 ] && [[ "$o" == *"확인 불가(카드 파일 못 읽음 "*"EACCES"* ]] && [[ "$o" != *"카드 대기 1"* ]] && [[ "$o" != *"카드 대기 0"* ]]; } \
      && ok "ⓥ6 대기 카드 000 모드«${mode:-일반}» → 확인 불가(EACCES) rc3" || bad "ⓥ6 모드«${mode:-일반}» rc=$rc «${o}»"
  done
  chmod 644 "$T/v6/design/alpha/indices/대기/a.md"
fi
mkdir -p "$T/v6b/design/alpha/indices/진행" "$T/v6b/design/alpha/indices/대기/x.md"
o="$(vrun "$T/v6b/design/alpha" "")"; rc=$?
{ [ "$rc" = 3 ] && [[ "$o" == *"확인 불가(카드 파일 못 읽음 "*"EISDIR"* ]]; } \
  && ok "ⓥ6 대기/x.md 가 폴더 → 확인 불가(EISDIR) rc3" || bad "ⓥ6 폴더 카드 rc=$rc «${o}»"
# ⓥ7 DA 반례 3 그대로: 진행/«a⏎b.md» 가 폴더 → rc3 · 사유 «한 줄» 에 EISDIR 글자와 경로 전체(a\nb.md)
mkdir -p "$T/v7/design/alpha/indices/대기" "$T/v7/design/alpha/indices/진행/$(printf 'a\nb').md"
o="$(vrun "$T/v7/design/alpha" "")"; rc=$?
{ [ "$rc" = 3 ] && [ "$(printf '%s\n' "$o" | wc -l | tr -d ' ')" = 1 ] && [[ "$o" == *"EISDIR"* ]] && [[ "$o" == *'a\nb.md'* ]]; } \
  && ok "ⓥ7 개행 이름 폴더 카드 → 사유 한 줄에 EISDIR + 경로 전체" || bad "ⓥ7 rc=$rc «${o}»"

# ⓔ ft-nano-spawn: 진행 > 좌석 + 2 또는 K > 0 → WARN «이동 먼저» 1줄 · spawn 계속 · rc 불변
. "$HERE/lib/fake_resource_env.sh"; fake_resource_env "$T" ok
MD="$T/TEAMSET.md"; cat > "$MD" <<'EOF'
## 표 1 — 역할
| 역할 | 수 | 모델 | effort | 명부 키 | 승계 | 닫기 |
|---|---|---|---|---|---|---|
| nano | 상한 N | `sonnet-5-5` | high | — | a | b |
- 나노 상한 기본: 9
## 표 2 — 팀
| 팀 | 나노 상한 | tester | arch 상시 |
|---|---|---|---|
| alpha | 9 | 0 | 상시 |
EOF
echo '{"_name":"alpha"}' > "$R/.fable-team/seats-alpha.json"; printf '2026-10-21T00:00:00\toff\tinstall\tinit\n' > "$R/.fable-team/state/all-stop.log"
echo "# 카드" > "$R/design/alpha/indices/대기/x.md"
sp() { ( cd "$R" && export FT_ROOT="$R" FT_NANO_PREFIX="byz-alpha-nano-" FT_SEATS_JSON="$R/.fable-team/seats-alpha.json" FT_TEAMSET_MD="$MD" \
  && PATH="$FAKE:$PATH" bash "$KIT/ft-nano-spawn.sh" design/alpha/indices/대기/x.md --from byz-alpha-master-claude#1 --dry-run "$@" 2>&1 ); }
sess "byz-alpha-nano-live1#0" "byz-alpha-nano-live2#0"
o="$(sp)"; rc_on=$?; o_off="$(FT_CARD_FLOW=0 sp)"; rc_off=$?
has "$o" "WARN 카드 흐름 — alpha 진행 4(좌석 2) · 착지됐는데 진행 1 · 이동 먼저: done1.md" "ⓔ K>0 → WARN 이동 먼저(착지 카드 지목)"
[ "$(printf '%s\n' "$o" | grep -c 'WARN 카드 흐름')" = 1 ] && ok "ⓔ WARN 정확히 1줄" || bad "ⓔ WARN 줄 수"
[ "$rc_on" = "$rc_off" ] && ok "ⓔ rc 불변(경보 $rc_on = 끔 $rc_off)" || bad "ⓔ rc 바뀜 on=$rc_on off=$rc_off"
hasnt "$o_off" "WARN 카드 흐름" "ⓔ FT_CARD_FLOW=0 → 경보 0"
# ⓔ-2 K=0 이고 진행 ≤ 좌석+2 → 경보 0 (건강)
rm -f "$R/design/alpha/indices/진행/done1.md" "$R/design/alpha/indices/진행/stale1.md"
o="$(sp)"; hasnt "$o" "WARN 카드 흐름" "ⓔ 건강(진행 2 ≤ 좌석 2+2 · K 0) → 경보 0"
# ⓔ-3 K=0 이어도 진행 > 좌석 + 2 → WARN (좌석 0 · 고아 카드 지목)
card 진행 o1; card 진행 o2; card 진행 o3; sess "byz-alpha-nano-other#0"
o="$(sp)"; has "$o" "WARN 카드 흐름 — alpha 진행 5(좌석 0) · 착지됐는데 진행 0 · 이동 먼저:" "ⓔ 진행 > 좌석+2 → WARN"

# ⓕ 기존 시험(test_nano_spawn*·news 트리·harness_root) rc0 — /bin/bash 3.2 로
for t in $(cd "$HERE" && ls test_nano_spawn_*.sh) test_news_tree_root.sh; do
  /bin/bash "$HERE/$t" > "$T/f.out" 2>&1; r=$?; [ "$r" = 0 ] && ok "ⓕ $t rc0 (/bin/bash 3.2)" || { bad "ⓕ $t rc=${r} «$(tail -1 "$T/f.out")»"; }
done

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILED $fail"
exit $fail
