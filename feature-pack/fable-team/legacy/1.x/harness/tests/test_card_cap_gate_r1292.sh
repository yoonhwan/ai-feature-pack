#!/usr/bin/env bash
# test_card_cap_gate_r1292.sh — r1292: 진행 카드 > 일하는 좌석 + 2 인 팀의 «대기» 카드 spawn 과 «새 카드» 커밋을 막는다.
#   판정 = ft-card-flow.sh --gate · 막는 곳 = ft-nano-spawn.sh(대기 카드만) · kit githooks/pre-commit(staged A 의 */indices/대기/*.md 만) · 우회 = FT_CARD_CAP_OK=<번호> ∧ state/card-cap-ok.<번호> · 판정 불가 = 막지 않음 + WARN.
# 임시 git 리포(실 git · 가짜 git 0) · 가짜 tmux(PATH) · 가짜 자원 센서 · 네트워크 0 · 실 좌석·실 쪽지·실 state 0 · 고정 sleep 0 · 자기 재호출 0.
# 돌리기: ulimit -u <지금+여유>; timeout 70 bash harness/tests/test_card_cap_gate_r1292.sh
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
export FT_ALLOW_TRACKED_BIN=1
ulimit -u "$(( $(ps -u "$(id -u)" 2>/dev/null | wc -l | tr -d ' ') + 300 ))" 2>/dev/null || true   # r1041
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY FT_NEWS_ROOT FT_FINISHED_MAIN FT_CARD_CAP_OK FT_CARD_CAP FT_CARD_FLOW
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="$HERE/../.."; BIN="$REPO/harness/bin"; KIT="$REPO/harness/kit/fable-team/bin"; HOOK="$REPO/harness/kit/fable-team/githooks/pre-commit"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }

# ── 대역: tmux(세션 목록 파일) · 자원 센서 ────────────────────────────────────────
FAKE="$T/fake"; SESS="$T/sessions.txt"; mkdir -p "$FAKE"
cat > "$FAKE/tmux" <<EOF
#!/bin/sh
[ -f "$T/tmux.slow" ] && sleep 2
[ -f "$SESS" ] || { echo "no server running on /tmp/x" >&2; exit 1; }
case "\$1" in ls) cat "$SESS";; *) exit 1;; esac
EOF
chmod 755 "$FAKE/tmux"
cat > "$FAKE/tmm" <<EOF
#!/bin/sh
case "\$1" in ls) [ "\$2" = --names ] && shift; [ -f "$SESS" ] || exit 0; grep "^\${2}-" "$SESS"; exit 0;; *) exit 0;; esac
EOF
chmod 755 "$FAKE/tmm"
. "$HERE/lib/fake_resource_env.sh"; fake_resource_env "$T" ok
PATH="$FAKE:$PATH"; export PATH
sess() { : > "$SESS"; local s; for s in "$@"; do echo "$s" >> "$SESS"; done; }
sesssp() { local t="$1"; shift; sess "byz-$t-master-claude#1" "$@"; }   # spawn 은 보고 대상(master)이 좌석 집합에 있어야 한다
G() { local r="$1"; shift; git -C "$r" -c user.name=t -c user.email=t@t "$@"; }

# ── 픽스처 ────────────────────────────────────────────────────────────────────────
card() { local r="$1" t="$2" st="$3" n="$4" d; d="$r/design/$t/indices/$st"; [ -d "$d" ] || d="$r/design/teams/$t/indices/$st"; printf '# %s\n## 상태\n%s\n' "$n" "${5:-}" > "$d/$n.md"; }
mkrepo() { # $1 = 리포 경로 (alpha 만)
  local r="$1"; mkdir -p "$r/design/alpha/indices/"{대기,진행,완성} "$r/.fable-team/state" "$r/.fable-team/comm"
  git init -q -b main "$r"; echo x > "$r/f"; G "$r" add -A >/dev/null; G "$r" commit -q -m base
  echo '{"_name":"alpha"}' > "$r/.fable-team/seats-alpha.json"
  printf '2026-10-21T00:00:00\toff\tinstall\tinit\n' > "$r/.fable-team/state/all-stop.log"
}
cat > "$T/TEAMSET.md" <<'EOF'
## 표 1 — 역할
| 역할 | 수 | 모델 | effort | 명부 키 | 승계 | 닫기 |
|---|---|---|---|---|---|---|
| nano | 상한 N | `sonnet-5-5` | high | — | a | b |
- 나노 상한 기본: 9
## 표 2 — 팀
| 팀 | 나노 상한 | tester | arch 상시 |
|---|---|---|---|
| alpha | 9 | 0 | 상시 |
| beta | 9 | 0 | 상시 |
EOF
CFCUR="$KIT/ft-card-flow.sh"; SPAWN="$KIT/ft-nano-spawn.sh"; HOOKCUR="$HOOK"
cfrun() { local r="$1" t="$2"; shift 2; bash "$CFCUR" --team "$t" --root "$r" --dir "$r/design/$t" "$@" 2>&1; }
sp() { local r="$1" t="$2" c="$3"; shift 3
  ( cd "$r" && FT_ROOT="$r" FT_NANO_PREFIX="byz-$t-nano-" FT_SEATS_JSON="$r/.fable-team/seats-$t.json" FT_TEAMSET_MD="$T/TEAMSET.md" \
    bash "$SPAWN" "$c" --from "byz-$t-master-claude#1" "$@" 2>&1 ); }
mkhookrepo() { # $1 = 리포 · $2 = 훅 파일 · $3 = "alpha" 이면 alpha 만 / "both" 면 beta(design/teams/)도
  local r="$1"; mkrepo "$r"; mkdir -p "$r/.fable-team/bin" "$r/.fable-team/githooks"
  printf '# old\n' > "$r/design/alpha/indices/대기/old.md"
  if [ "$3" = both ]; then
    mkdir -p "$r"/design/teams/beta/indices/{대기,진행,완성}; printf '# b\n' > "$r/design/teams/beta/indices/진행/bp1.md"
    echo '{"_name":"beta"}' > "$r/.fable-team/seats-beta.json"
  fi
  G "$r" add -A design >/dev/null; G "$r" commit -q -m base-cards
  cp "$KIT/ft-card-flow.sh" "$KIT/ft-team-lib.sh" "$KIT/ft-evidence-lib.sh" "$r/.fable-team/bin/" 2>/dev/null
  cp "$2" "$r/.fable-team/githooks/pre-commit"; chmod 755 "$r/.fable-team/githooks/pre-commit"
  git -C "$r" config core.hooksPath .fable-team/githooks
}

# ── 판정 헬퍼(조용히 카운트 — 변이 칸이 같은 함수를 다시 쓴다) ─────────────────────
rfail=0; rmsg=""
chk() { [ "$1" = 0 ] || { rfail=$((rfail+1)); rmsg="$rmsg; $2"; }; }
like() { case "$1" in *"$2"*) chk 0 "$3";; *) chk 1 "$3 (없음: «$2» ← ${1:0:300})";; esac; }
nlike() { case "$1" in *"$2"*) chk 1 "$3 (있음: «$2»)";; *) chk 0 "$3";; esac; }
eq() { [ "$1" = "$2" ] && chk 0 "$3" || chk 1 "$3 ($1 ≠ $2)"; }

# ── R1~R12 ─────────────────────────────────────────────────────────────────────
r1() {  # 진행 5 · 좌석 3 → 대기 카드 spawn 통과(5 ≤ 5)
  local r="$T/r1" i o; mkrepo "$r"; for i in p1 p2 p3 p4 p5; do card "$r" alpha 진행 "$i"; done
  sesssp alpha byz-alpha-nano-p1#0 byz-alpha-nano-p2#0 byz-alpha-nano-p3#0
  card "$r" alpha 대기 new1
  o="$(sp "$r" alpha design/alpha/indices/대기/new1.md --dry-run)"
  nlike "$o" "REJECT 카드 상한" "R1 진행 5 ≤ 좌석 3+2 → 대기 spawn 통과"
  o="$(cfrun "$r" alpha --gate)"; eq "$?" 0 "R1 --gate rc0"; nlike "$o" "REJECT" "R1 --gate 줄 0"
}
r2() {  # 진행 6 · 좌석 3 → REJECT 1줄 · exit 1 · 워크트리 0 · 원장 waiting 석
  local r="$T/r2" i o rc; mkrepo "$r"; for i in p1 p2 p3 p4 p5 p6; do card "$r" alpha 진행 "$i"; done
  sesssp alpha byz-alpha-nano-p1#0 byz-alpha-nano-p2#0 byz-alpha-nano-p3#0
  card "$r" alpha 대기 new1
  o="$(sp "$r" alpha design/alpha/indices/대기/new1.md)"; rc=$?
  eq "$rc" 1 "R2 exit 1"
  like "$o" "REJECT 카드 상한 — alpha 진행 6(좌석 3) > 3+2" "R2 REJECT 1줄"
  like "$o" "이동 먼저: " "R2 이동 먼저 목록"
  eq "$(ls -d "$r"/.worktrees "$T"/.worktrees/*r2* 2>/dev/null | wc -l | tr -d ' ')" 0 "R2 워크트리 0"
  like "$(cat "$r"/.fable-team/state/card-assign/*.json 2>/dev/null)" '"waiting"' "R2 배정 원장 waiting"
  like "$(cat "$r"/.fable-team/state/card-assign/*.json 2>/dev/null)" '"석"' "R2 배정 원장 사유 석"
}
r3() {  # 같은 팀 · 진행 카드(재작업) spawn → 통과 + 지금 WARN 줄
  local r="$T/r3" i o; mkrepo "$r"; for i in p1 p2 p3 p4 p5 p6; do card "$r" alpha 진행 "$i"; done
  sesssp alpha byz-alpha-nano-p1#0 byz-alpha-nano-p2#0 byz-alpha-nano-p3#0
  o="$(sp "$r" alpha design/alpha/indices/진행/p1.md --dry-run)"
  nlike "$o" "REJECT 카드 상한" "R3 진행 카드 재작업 spawn 통과"
  like "$o" "WARN 카드 흐름 — alpha 진행 6(좌석 3)" "R3 지금 WARN 줄"
}
r4() {  # 잘린 세션 slug(40자) 는 셈 · 30자 미만 slug 는 안 셈
  local r="$T/r4" o rc; mkrepo "$r"
  card "$r" alpha 진행 "r1273-index-lint-assign-check-no-full-history-log"
  card "$r" alpha 진행 "r1234-short-head-card"; card "$r" alpha 진행 "x1"
  sess "byz-alpha-nano-r1273-index-lint-assign-check-no-full-hi#0" "byz-alpha-nano-r12#0"
  o="$(cfrun "$r" alpha)"; like "$o" "진행 3(좌석 1)" "R4 잘린 slug(≥30자) 같은 카드 · 짧은 앞머리 안 셈"
  o="$(cfrun "$r" alpha --gate)"; rc=$?; eq "$rc" 0 "R4 좌석 1 이라 3 ≤ 3 → rc0"
}
r5() {  # pre-commit: 새 대기 카드 A 만 막는다 · 이동·수정 커밋 통과
  local r="$T/r5" o rc; mkhookrepo "$r" "$HOOKCUR" alpha
  local i; for i in p1 p2 p3 p4 p5 p6; do card "$r" alpha 진행 "$i"; done
  sesssp alpha byz-alpha-nano-p1#0 byz-alpha-nano-p2#0 byz-alpha-nano-p3#0
  G "$r" add -A design >/dev/null; G "$r" commit -q -m cards
  printf '# n\n' > "$r/design/alpha/indices/대기/n.md"; G "$r" add -A design >/dev/null
  o="$(G "$r" commit -m new-card 2>&1)"; rc=$?
  [ "$rc" != 0 ] && chk 0 || chk 1 "R5 새 카드 커밋 막힘(rc=$rc)"
  like "$o" "REJECT 카드 상한 — alpha" "R5 막을 때 1줄"
  rm -f "$r/design/alpha/indices/대기/n.md"; G "$r" reset -q >/dev/null 2>&1
  git -C "$r" mv design/alpha/indices/진행/p1.md design/alpha/indices/완성/p1.md
  G "$r" add -A design >/dev/null; o="$(G "$r" commit -m move 2>&1)"; rc=$?
  eq "$rc" 0 "R5 진행→완성 이동 커밋 통과"
  printf '## 상태\n추가\n' >> "$r/design/alpha/indices/대기/old.md"; G "$r" add -A design >/dev/null
  o="$(G "$r" commit -m mod 2>&1)"; rc=$?
  eq "$rc" 0 "R5 카드 내용 수정(M) 커밋 통과"
}
r6() {  # 우회 = 번호 + 표식 둘 다 · 번호만/표식 없는 1 = REJECT
  local r="$T/r6" i o rc; mkrepo "$r"; for i in p1 p2 p3 p4 p5 p6; do card "$r" alpha 진행 "$i"; done
  sesssp alpha byz-alpha-nano-p1#0 byz-alpha-nano-p2#0 byz-alpha-nano-p3#0
  touch "$r/.fable-team/state/card-cap-ok.3070"
  o="$(FT_CARD_CAP_OK=3070 cfrun "$r" alpha --gate)"; rc=$?; eq "$rc" 0 "R6 번호+표식 → 통과"
  like "$o" "카드 상한 우회 — 승인 3070" "R6 우회 1줄"
  like "$(cat "$r/.fable-team/state/card-cap-ok.log" 2>/dev/null)" "승인 3070" "R6 우회 log 1줄"
  o="$(FT_CARD_CAP_OK=3071 cfrun "$r" alpha --gate)"; rc=$?; eq "$rc" 4 "R6 번호만(표식 없음) → REJECT"
  o="$(FT_CARD_CAP_OK=1 cfrun "$r" alpha --gate)"; rc=$?; eq "$rc" 4 "R6 1 + 표식 없음 → REJECT"
}
r7() {  # card-flow 7초 초과 → spawn 통과 + «WARN 카드 상한 판정 불가 — 막지 않음(시간 초과)»
  local r="$T/r7" i o; mkrepo "$r"; for i in p1 p2 p3 p4 p5 p6; do card "$r" alpha 진행 "$i"; done
  sesssp alpha byz-alpha-nano-p1#0 byz-alpha-nano-p2#0 byz-alpha-nano-p3#0; card "$r" alpha 대기 new1
  : > "$T/tmux.slow"
  o="$(FT_CARD_FLOW_TIMEOUT_SEC=1 sp "$r" alpha design/alpha/indices/대기/new1.md --dry-run)"
  rm -f "$T/tmux.slow"
  nlike "$o" "REJECT 카드 상한" "R7 판정 불가 → 막지 않음"
  like "$o" "WARN 카드 상한 판정 불가 — 막지 않음(시간 초과)" "R7 WARN 판정 불가 1줄"
}
r8() {  # FT_CARD_CAP=0 → --gate 호출 0 · 지금 --warn 줄 그대로
  local r="$T/r8" i o; mkrepo "$r"; for i in p1 p2 p3 p4 p5 p6; do card "$r" alpha 진행 "$i"; done
  sesssp alpha byz-alpha-nano-p1#0 byz-alpha-nano-p2#0 byz-alpha-nano-p3#0; card "$r" alpha 대기 new1
  o="$(FT_CARD_CAP=0 sp "$r" alpha design/alpha/indices/대기/new1.md --dry-run)"
  nlike "$o" "REJECT 카드 상한" "R8 끄면 막지 않음"
  like "$o" "WARN 카드 흐름 — alpha 진행 6(좌석 3)" "R8 끄면 지금 WARN 줄 그대로"
}
r9() {  # 진행 3 · 좌석 0 → REJECT(3 > 2)
  local r="$T/r9" i o rc; mkrepo "$r"; for i in p1 p2 p3; do card "$r" alpha 진행 "$i"; done
  sess; card "$r" alpha 대기 new1
  o="$(cfrun "$r" alpha --gate)"; rc=$?; eq "$rc" 4 "R9 3 > 0+2 → rc4"
  like "$o" "REJECT 카드 상한 — alpha 진행 3(좌석 0) > 0+2" "R9 REJECT 줄"
}
r10() {  # beta 상한 넘음 · alpha 상한 안 → alpha spawn·새 카드 통과
  local r="$T/r10" i o rc; mkhookrepo "$r" "$HOOK" both
  for i in p1 p2 p3; do card "$r" alpha 진행 "$i"; done
  for i in b1 b2 b3 b4 b5 b6; do card "$r" teams/beta 진행 "$i"; done   # beta 7(기본 bp1 포함) · 좌석 0 = 상한 넘음
  sesssp alpha byz-alpha-nano-p1#0 byz-alpha-nano-p2#0 byz-alpha-nano-p3#0
  G "$r" add -A design >/dev/null; G "$r" commit -q -m beta-cards
  card "$r" alpha 대기 new1
  o="$(sp "$r" alpha design/alpha/indices/대기/new1.md --dry-run)"; nlike "$o" "REJECT 카드 상한" "R10 alpha spawn 통과"
  G "$r" add -A design >/dev/null; o="$(G "$r" commit -m alpha-card 2>&1)"; rc=$?
  eq "$rc" 0 "R10 alpha 새 카드 커밋 통과(beta 넘치는 것과 무관)"
}
r11() {  # 대기 새 카드 2팀(하나만 넘음) → 커밋 0 · 넘은 팀만 1줄
  local r="$T/r11" i o rc; mkhookrepo "$r" "$HOOKCUR" both
  for i in p1 p2 p3 p4 p5 p6; do card "$r" alpha 진행 "$i"; done
  sesssp alpha byz-alpha-nano-p1#0 byz-alpha-nano-p2#0 byz-alpha-nano-p3#0
  G "$r" add -A design >/dev/null; G "$r" commit -q -m alpha-cards
  card "$r" alpha 대기 na1; card "$r" teams/beta 대기 nb1
  G "$r" add -A design >/dev/null; o="$(G "$r" commit -m two 2>&1)"; rc=$?
  [ "$rc" != 0 ] && chk 0 || chk 1 "R11 커밋 0"
  like "$o" "REJECT 카드 상한 — alpha" "R11 넘은 팀(alpha) 1줄"
  nlike "$o" "REJECT 카드 상한 — beta" "R11 안 넘은 팀(beta) 줄 0"
}
r12() {  # «이동 먼저» 목록 ≤5 · 7장이면 5장 + «외 2»
  local r="$T/r12" i o; mkrepo "$r"; for i in p1 p2 p3 p4 p5 p6 p7; do card "$r" alpha 진행 "$i"; done
  sess
  o="$(cfrun "$r" alpha --gate)"
  like "$o" "외 2" "R12 외 2 표시"
  eq "$(printf '%s' "$o" | sed -n 's/.*이동 먼저: //p' | sed 's/ 외 2$//' | wc -w | tr -d ' ')" 5 "R12 지목 카드 5장"
}

r13() {  # r1292 재작업1: 진행→대기 되돌림 = «이동» — 상한 넘은 팀이라도 커밋 통과(실사건 02:50 r1281·r1285)
  local r="$T/r13" i o rc; mkhookrepo "$r" "$HOOKCUR" alpha
  for i in p1 p2 p3 p4 p5 p6; do card "$r" alpha 진행 "$i"; done
  sesssp alpha byz-alpha-nano-p1#0 byz-alpha-nano-p2#0 byz-alpha-nano-p3#0
  G "$r" add -A design >/dev/null; G "$r" commit -q -m cards
  git -C "$r" mv design/alpha/indices/진행/p1.md design/alpha/indices/대기/p1.md
  G "$r" add -A design >/dev/null; o="$(G "$r" commit -m back 2>&1)"; rc=$?
  eq "$rc" 0 "R13 진행→대기 되돌림 커밋 통과(이동)"
  nlike "$o" "REJECT 카드 상한" "R13 되돌림에 상한 줄 0"
  # 디렉터리 이동이 git mv 로 R(rename) 로 잡혀도 --no-renames 가 A+D 로 펼치는지 확인
  eq "$(git -C "$r" ls-tree -r --name-only HEAD | grep -c 'indices/대기/p1.md')" 1 "R13 대기로 되돌아간 카드가 커밋에 실렸다"
}
r14() {  # 진짜 새 대기 카드 + 진행 초과 = 여전히 막힘(D 대조에 휘말리지 않는다)
  local r="$T/r14" i o rc; mkhookrepo "$r" "$HOOKCUR" alpha
  for i in p1 p2 p3 p4 p5 p6; do card "$r" alpha 진행 "$i"; done
  sesssp alpha byz-alpha-nano-p1#0 byz-alpha-nano-p2#0 byz-alpha-nano-p3#0
  G "$r" add -A design >/dev/null; G "$r" commit -q -m cards
  git -C "$r" mv design/alpha/indices/진행/p1.md design/alpha/indices/대기/p1.md
  card "$r" alpha 대기 brandnew
  G "$r" add -A design >/dev/null; o="$(G "$r" commit -m mix 2>&1)"; rc=$?
  [ "$rc" != 0 ] && chk 0 || chk 1 "R14 진짜 새 카드 + 되돌림 섞인 커밋 → 막힘(rc=$rc)"
  like "$o" "REJECT 카드 상한 — alpha" "R14 막을 때 1줄"
  nlike "$o" "REJECT 카드 상한 — beta" "R14 다른 팀 줄 0"
}

for n in 1 2 3 4 5 6 7 8 9 10 11 12 13 14; do
  rfail=0; rmsg=""; "r$n"; if [ "$rfail" = 0 ]; then ok "R$n"; else bad "R$n —$rmsg"; fi
done
# ── 변이 9 — 하나라도 살아남으면 시험 실패 ───────────────────────────────────────
mut() { # $1 라벨 $2 파일명 $3 sed 식 $4 대상 R번호 — 원본 = pre-commit 이면 kit githooks, 그 밖엔 kit bin
  local d="$T/mut.$1" f src; mkdir -p "$d"
  [ "$2" = pre-commit ] && src="$HOOK" || src="$KIT/$2"
  for f in "$KIT"/*; do [ -f "$f" ] && ln -sf "$f" "$d/"; done
  rm -f "$d/$2"; sed "$3" "$src" > "$d/$2"; chmod 755 "$d/$2"
  CFCUR="$d/ft-card-flow.sh"; SPAWN="$d/ft-nano-spawn.sh"; HOOKCUR="$d/pre-commit"
  rfail=0; rmsg=""; "r$4"; local rc2="$rfail"
  CFCUR="$KIT/ft-card-flow.sh"; SPAWN="$KIT/ft-nano-spawn.sh"; HOOKCUR="$HOOK"
  [ "$rc2" != 0 ] && ok "변이 $1 → R$4 FAIL 확인" || bad "변이 $1 — R$4 가 변이를 못 잡음"
}
mut 1 ft-nano-spawn.sh 's|case "\$IDX" in .*esac|_cfmode=--gate|' 3          # IDX 폴더 검사 제거 → 진행 카드도 막힘
mut 2 ft-card-flow.sh '/\[ "\$GATE" = 1 \]/s/-gt \$((seat + 2))/-ge $((seat + 2))/' 1   # > 를 ≥ 로
mut 3 ft-card-flow.sh 's/ or (len(s)>=30 and cl.startswith(s))//' 4          # 좌석 맞춤 앞머리 제거
mut 4 ft-card-flow.sh 's/(len(s)>=30 and cl.startswith(s))/(cl.startswith(s))/' 4   # 30자 하한 제거
mut 5 pre-commit 's/--diff-filter=A //' 5                                     # 모든 카드 커밋 검사
mut 6 ft-card-flow.sh 's/ && \[ -f "\$ROOT[^]]*\]//' 6                        # 표식 검사 제거
mut 7 ft-card-flow.sh 's|echo "WARN 카드 상한 판정 불가 — 막지 않음(\$1)";|true;|' 7   # 판정 불가 조용한 통과
mut 8 ft-nano-spawn.sh 's/\[ "\${FT_CARD_CAP:-1}" = 0 \] || _cfmode=--gate/_cfmode=--gate/' 8   # 끄기 무시
mut 9 pre-commit 's/--team "\$_ft_cc_t"/--team beta/' 10                      # 팀 구분 없이 한 팀 숫자로 판정
mut 10 pre-commit 's/--diff-filter=D --/--diff-filter=A --/' 13               # 진행/ D 대조 제거 → 되돌림을 새 카드로 오판

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILED $fail"
exit "$fail"
