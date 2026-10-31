#!/usr/bin/env bash
# test_card_assign_watch_r1224.sh — r1224 r4 카드→좌석 배정 감시 반례 R1~R10 + 변이 3 + bin·kit 같음 + ft-role-spawn 변경 0.
# 임시 git 리포 · 배정 원장 · 실제 ft-nano-spawn 진입점(가짜 = tmux·tmm·gh·자원 센서·acct-pause·회수) · 실제 ft-spawn-hold.sh(가짜 gate) · 가짜 mbox 수집기.
# 실 STATE·실 좌석·실 쪽지 0 · 자기 재호출 0(재진입 표지) · 고정 sleep 0. 돌리기: ulimit -u <지금+여유>; timeout 70 bash harness/tests/test_card_assign_watch_r1224.sh
[ -z "${R1224_TEST_ACTIVE:-}" ] || { echo "재진입 금지 — R1224_TEST_ACTIVE 가 이미 켜져 있다"; exit 3; }; export R1224_TEST_ACTIVE=1
set -uo pipefail
export TZ=Asia/Seoul FT_ALLOW_TRACKED_BIN=1
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY FT_CARD_REQUIRE_PREVERIFY
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; REPO="$HERE/../.."
BIN="$REPO/harness/bin"; COMM="$REPO/harness/comm"; KIT="$REPO/harness/kit/fable-team/bin"; FX="$REPO/harness/tests/fixtures/card_assign"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
fail=0; ok() { echo "PASS $1"; }; bad() { echo "FAIL $1"; fail=$((fail+1)); }
T0=$(date +%s); STEP=""; lap() { STEP="$STEP $1=$(( $(date +%s) - T0 ))s"; T0=$(date +%s); }
TOOL="$BIN/ft_card_assign_watch.py"; LINT="$COMM/ft-boot-report-lint.py"
PLANNER='byz-planner-master-claude#9'; HMASTER='byz-harness-master-claude#33'; RMASTER='byz-room-master-claude#1'
NOW=$(date +%s); H=design/harness/indices
gc() { GIT_AUTHOR_DATE="$2" GIT_COMMITTER_DATE="$2" git -C "$1" -c user.name=t -c user.email=t@t commit -q --allow-empty -m "$3"; }
new_root() {  # 임시 루트 R = git 리포(main) + 카드 루트 표 + 명부(_master) + 가짜 mbox · 원장 = R/.fable-team/state/card-assign
  R="$(mktemp -d "$T/r.XXXXXX")"; mkdir -p "$R/.fable-team/state" "$R/$H/대기"
  git -C "$R" init -q -b main; printf '.fable-team/\nmbox.sh\nsent.log\n' > "$R/.gitignore"; git -C "$R" add .gitignore; gc "$R" "$((NOW - 200000)) +0900" init
  printf 'harness\t.\tmain\tdesign/harness/indices\n*\t.\tmain\tdesign/teams/*/indices\n' > "$R/.fable-team/state/directive-roots.tsv"
  printf '{"_master":"%s"}\n' "$PLANNER" > "$R/.fable-team/seats-planner.json"; printf '{"_master":"%s"}\n' "$HMASTER" > "$R/.fable-team/seats-harness.json"
  printf '{"_master":"%s"}\n' "$RMASTER" > "$R/.fable-team/seats-room.json"; printf '{}\n' > "$R/.fable-team/seats.json"
  printf '#!/usr/bin/env bash\nprintf "%%s\\x1f%%s\\n" "$2" "$(printf "%%s" "$4" | tr "\\n" "|")" >> "$(dirname "$0")/sent.log"\n[ "$2" = "${FAKE_FAIL_TO:-}" ] && { echo "REJECT 가짜"; exit 3; }\necho "QUEUED seq=1 to=$2"\n' > "$R/mbox.sh"; : > "$R/sent.log"
}
card() {  # <R> <상대경로> <커밋 epoch> <머리 줄...>
  local r="$1" p="$2" d="$3"; shift 3; mkdir -p "$(dirname "$r/$p")"; printf '%s\n' "# 카드 $(basename "$p" .md)" "$@" "## 상태" "- 시험" > "$r/$p"; git -C "$r" add -A design; gc "$r" "$d +0900" "card $p"
}
led() {  # <R> <stem> <json> — 원장 픽스처(시험 입력)
  mkdir -p "$R/.fable-team/state/card-assign"; printf '%s\n' "$3" > "$1/.fable-team/state/card-assign/$2.json"
}
run() { OUT="$(cd "$R" && env FT_ROOT="$R" FT_MBOX_SH="$R/mbox.sh" ${EXTRA_ENV:-} python3 "${TOOL_RUN:-$TOOL}" "$@" 2>&1)"; RC=$?; }
prep() { run prepare >/dev/null; }
sent() { grep -c "${1:-.}" "$R/sent.log" 2>/dev/null || true; }
hd() { printf '%s\n' "$OUT" | head -1; }

# ⓐ R1 — 원장 6(대기) + 진행 2 → «배정 없는 카드 3 · 대기 초과 2(부하 1 · 석 1)» · 선행 1시간 초과 아님 · rc1
r1_env() {
  new_root; local C=$((NOW - 90000))
  for c in a1 a2 a3 a4 a5; do card "$R" "$H/대기/$c.md" "$C" "- 상태: 대기"; done
  card "$R" "$H/대기/a6.md" "$C" "- 상태: 대기" "- 긴급: 예"; card "$R" "$H/진행/p1.md" "$C" "- 상태: 진행"; card "$R" "design/teams/room/indices/진행/p2.md" "$C" "- 상태: 진행"
  led "$R" a1 '{"state":"none","since":'$((NOW-9000))'}'; led "$R" a2 '{"state":"none","since":'$((NOW-8000))'}'
  led "$R" a3 '{"state":"waiting","reason":"부하","since":'$((NOW-18000))'}'; led "$R" a4 '{"state":"waiting","reason":"선행","since":'$((NOW-3600))'}'
  led "$R" a5 '{"state":"seat","seat":"byz-harness-nano-a5#0"}'; led "$R" a6 '{"state":"waiting","reason":"석","since":'$((NOW-7200))'}'
  led "$R" p1 '{"state":"seat","seat":"byz-harness-nano-p1#0"}'; prep
}
r1_ok() { [ "$RC" = 1 ] && case "$(hd)" in "배정 없는 카드 3 · 대기 초과 2(부하 1 · 석 1) · 정지 중 0 · 카드 없는 발주 0 · 판본 "*) true;; *) false;; esac \
  && printf '%s' "$OUT" | grep -q '^초과 harness a6 · 대기(석) · .* · 긴급$' && printf '%s' "$OUT" | grep -q '^없음 room p2 · 원장 없음' && ! printf '%s' "$OUT" | grep -qE ' (a4|a5|p1) '; }
r1_env; run status
r1_ok && ok "R1 머리 3·2(부하 1 · 석 1) · 진행 원장 없음 = 없음 · 선행 1시간·좌석 셈 0 · 긴급 석 2시간 초과 · rc1" || bad "R1 rc=$RC :: $OUT"
lap R1
# ⓑ R2 lint — installed_at 뒤 새 카드 줄 없음 REJECT · 사유 밖 REJECT · 옛 카드 OK · 완성 검사 0 · ft-index-lint 배선
new_root; card "$R" "$H/대기/old.md" "$((NOW - 9000))" "- 상태: 대기"; mkdir -p "$R/$H/진행"; git -C "$R" mv "$H/대기/old.md" "$H/진행/old.md"; gc "$R" "$((NOW - 100)) +0900" mv
mkdir -p "$R/.fable-team/state/card-assign"; echo $((NOW - 5000)) > "$R/.fable-team/state/card-assign/installed_at"
card "$R" "$H/대기/new.md" "$((NOW - 200))" "- 상태: 대기"; card "$R" "$H/대기/bad.md" "$((NOW - 200))" "- 배정: 대기(분류 · 2026-10-31T10:00)"
card "$R" "$H/완성/done.md" "$((NOW - 200))" "- 상태: 완성"; printf '%s\n' '# u' '- 상태: 대기' '## 상태' > "$R/$H/대기/unc.md"
lr() { (cd "$R" && FT_ROOT="$R" python3 "$TOOL" lint "$R/$H/$1" >/dev/null 2>&1); echo -n $?; }
v="$(lr 대기/new.md)$(lr 대기/bad.md)$(lr 대기/unc.md)$(lr 진행/old.md)$(lr 완성/done.md)"
o1="$(cd "$R" && FT_ROOT="$R" FT_GOAL_LEDGER=.gitignore bash "$KIT/ft-index-lint.sh" "$H/대기/new.md" 2>&1)"; o2="$(cd "$R" && FT_ROOT="$R" FT_GOAL_LEDGER=.gitignore bash "$KIT/ft-index-lint.sh" "$H/진행/old.md" 2>&1)"
[ "$v" = 11100 ] && printf '%s' "$o1" | grep -q '  - 머리 「- 배정: .*줄 없음 (새 카드 의무' && ! printf '%s' "$o2" | grep -q '배정' \
  && ok "R2 새 카드(설치 뒤·미커밋) 줄 없음·사유 밖 REJECT · 옛 카드(설치 전 생성 · 진행 이동 뒤에도) OK · 완성 0 · ft-index-lint 배선" || bad "R2 v=$v :: $o1 :: $o2"
lap R2
# ⓒ R3 실제 ft-nano-spawn 진입점 — 종료 분기 7종 + dry-run 0 + 정지가 카드 식별 뒤 + 공유 편집 보존 + 동시 기록
. "$HERE/lib/fake_resource_env.sh"; . "$HERE/lib/fake_tmm.sh"
SP="$T/sp"; KB="$SP/bin"; FK="$SP/fake"; mkdir -p "$SP" "$FK"; cp -R "$KIT" "$KB"; fake_resource_env "$SP" ok; fake_tmm "$FK" byz-alpha-master-claude#1
printf '#!/bin/sh\ncase "$1" in list-sessions) cat %s/sess 2>/dev/null;; has-session) exit 1;; *) exit 1;; esac\n' "$SP" > "$FK/tmux"; : > "$SP/sess"
printf '#!/bin/sh\necho "{\\"number\\":5342,\\"state\\":\\"OPEN\\",\\"url\\":\\"https://github.com/x/y/issues/5342\\",\\"labels\\":[]}"\n' > "$FK/gh"; chmod 755 "$FK"/*
printf '## 표 1 — 역할\n| 역할 | 수 | 모델 | effort | 명부 키 | 승계 | 닫기 |\n|---|---|---|---|---|---|---|\n| nano | 상한 N | `sonnet-5-5` | high | — | a | b |\n- 나노 상한 기본: 3\n## 표 2 — 팀\n| 팀 | 나노 상한 | tester | arch 상시 |\n|---|---|---|---|\n| alpha | 2 | 0 | 상시 |\n' > "$SP/TEAMSET.md"
SR="$SP/repo"; git init -q -b main "$SR"; mkdir -p "$SR/.fable-team/state" "$SR/.fable-team/comm" "$SR/design/alpha/indices/대기" "$SR/src"
printf '2026-10-21T00:00:00\toff\tinstall\tinit\n' > "$SR/.fable-team/state/all-stop.log"; echo '{"_name":"alpha","_master":"byz-alpha-master-claude#1","byz-alpha-master-claude#1":{"role":"master"}}' > "$SR/.fable-team/seats-alpha.json"
printf '| 팀 | 폴더 | x | y |\n|---|---|---|---|\n| alpha | `design/alpha/` | a | 현역 |\n' > "$SR/design/TEAMS.md"; printf 'l1\n' > "$SR/src/t.sh"
printf '골 1\n골 2\n골 3\n' > "$SP/goal.txt"; echo '원장: 닫는 증거는 이 문장 전체를 복붙한 것이어야 한다.' > "$SR/design/LEDGER.md"; printf '.fable-team/\n' > "$SR/.gitignore"
CX="$SR/design/alpha/indices/대기/x.md"; printf '# 카드\n- 상태: 대기\n## 상태\n' > "$CX"; git -C "$SR" add -A; gc "$SR" "$NOW +0900" base; git clone -q --bare "$SR" "$SP/origin.git"; git -C "$SR" remote add origin "$SP/origin.git"; git -C "$SR" fetch -q origin
sp() { ( cd "$SR" && export FT_ROOT="$SR" FT_NANO_PREFIX="byz-alpha-nano-" FT_SEATS_JSON="$SR/.fable-team/seats-alpha.json" FT_TEAMSET_MD="$SP/TEAMSET.md" FT_RECLAIM_SH="$SP/reclaim.sh" \
  FT_MBOX_SH="$SP/mbox.sh" FT_GH_READ="$FK/gh" FT_GOAL_LINES_FILE="$SP/goal.txt" FT_GOAL_LEDGER=design/LEDGER.md && PATH="$FK:$PATH" env ${SPENV:-} bash "$KB/ft-nano-spawn.sh" "${CARD:-$CX}" --from byz-alpha-master-claude#1 "$@" 2>&1 ); }
printf '#!/bin/bash\necho "RECLAIMED 0"\n' > "$SP/reclaim.sh"; chmod 755 "$SP/reclaim.sh"; printf '#!/bin/sh\necho "$2" >> %s/mbox.sent; echo "QUEUED seq=1 to=$2"\n' "$SP" > "$SP/mbox.sh"; chmod 755 "$SP/mbox.sh"
L3() { python3 -c 'import json,sys; j=json.load(open(sys.argv[1])); print(j.get("state"), j.get("reason","-"), (j.get("pause") or {}).get("kind","-"), (j.get("pause") or {}).get("key","-"))' "$SR/.fable-team/state/card-assign/${1:-x}.json" 2>/dev/null || echo none; }
lclear() { rm -f "$SR/.fable-team/state/card-assign/"*.json; }
# dry-run → 원장·카드 쓰기 0
o="$(sp --dry-run)"; dry="$(L3):$(git -C "$SR" status --porcelain | grep -c .)"
# 정지(hold) — 실제 ft-spawn-hold.sh(가짜 센서) · 판정 번호 2932 → 원장 pause hold 2932 · 카드 식별(init)이 정지 판정 앞
python3 -c 'import json,sys; json.dump({"verdict":2932,"until":"x","until_epoch":int(sys.argv[2])+3600,"release":"swap<1","reason":"r1224 시험 정지","set_at":0},open(sys.argv[1],"w"))' "$FT_RES_ROOT/.fable-team/state/SPAWN_HOLD" "$NOW"
printf '# 카드\n- 상태: 대기\n- 메모: 미커밋 한 줄 ★\n## 상태\n' > "$CX"; cp "$CX" "$SP/cx.before"; o="$(sp)"; ho="$o"; hold="$(L3)"; rm -f "$FT_RES_ROOT/.fable-team/state/SPAWN_HOLD"
keep="$(grep -v '^- 배정:' "$CX" | cmp -s - "$SP/cx.before" && grep -c '^- 배정: 대기(정지 · 20[0-9-]*T[0-9:]*)$' "$CX")"; printf '# 카드\n- 상태: 대기\n## 상태\n' > "$CX"
init_first="$(awk '/^card_assign_record "\$IDX" init$/{i=NR} /ft-spawn-hold.sh" status/{if(!h)h=NR} END{print (i && i < h) ? 1 : 0}' "$KB/ft-nano-spawn.sh")"
# 정지(acct) — 가짜 ft-acct-pause.sh status --check rc3
# 석 — 팀셋 cap+1 포화 · 회수 0 → 큐 적재 rc7
lclear; printf 'byz-alpha-nano-a#0\nbyz-alpha-nano-b#0\nbyz-alpha-nano-c#0\n' > "$SP/sess"; o="$(sp)"; seat_rc=$?; seat="$(L3)"; : > "$SP/sess"; rm -f "$SR/.fable-team/state/spawn-queue-alpha.tsv"
# 부하 — 자원 문지기 REJECT(디스크 하드 하한 주입)
lclear; o="$(SPENV="FT_DISK_HARD_MIN_MIB=9999999" sp)"; load="$(L3)"
# lint · DA(사전검증 미승인)
lclear; o="$(sp)"; lintv="$(L3)"; lclear; o="$(SPENV="FT_CARD_REQUIRE_PREVERIFY=1" sp)"; dav="$(L3)"
# 선행 — lint·제안서·이슈 게이트를 지나는 카드 + 분리 HEAD 가 origin/main 조상 아님
CY="$SR/design/alpha/indices/대기/y.md"
{ printf '%s\n' '# 인덱스: y' '- 제안서: 없음 — 시험 카드' '- Issue: #5342' '- 배정: 없음' '## 골 원문' '골 1' '골 2' '골 3' '## 골좌표' '닫는 증거: 「닫는 증거는 이 문장 전체를 복붙한 것이어야 한다.」' '## 배경' '시험.' '## 구현 범위' '1. src/t.sh 수정' '## 완료 조건' '- 시험.' '## 계약↔시험 대응표' '| 계약 | 시험 |' '|---|---|' '| ① 시험 | ⓐ 시험 |' '## 상태' '- 시험'; } > "$CY"
git -C "$SR" add -A; gc "$SR" "$NOW +0900" y; git -C "$SR" checkout -q --detach; gc "$SR" "$NOW +0900" detached
lclear; o="$(CARD="$CY" SPENV="GH_REPO=x/y" sp)"; po="$o"; prev="$(L3 y)"; git -C "$SR" checkout -q main
lclear; printf '#!/bin/sh\n[ "$3 $4 $5" = "--agent claude --model" ] && [ -n "$6" ] || exit 9\necho "PAUSED claude/sonnet-5-5 until_hhmm=12:00"; exit 3\n' > "$KB/ft-acct-pause.sh"; o="$(CARD="$CY" SPENV="GH_REPO=x/y" sp)"; acct="$(L3 y)"; rm -f "$KB/ft-acct-pause.sh"
# 면제대기 — 이 스크립트에 분기가 없다(카드 조사 근거 대조) → 도구 record 1줄로 같은 원장 꼴
lclear; (cd "$SR" && FT_ROOT="$SR" python3 "$TOOL" record "$CX" waiting 면제대기 >/dev/null); exm="$(L3)"
info="$(printf '%s' "$po" | grep -c '^INFO 계정 정지 판정 건너뜀 — ft-acct-pause.sh 없음')"
[ "$dry" = "none:0" ] && [ "$hold" = "waiting 정지 hold 2932" ] && [ "$keep" = 1 ] && [ "$init_first" = 1 ] && [ "$acct" = "waiting 정지 acct claude/sonnet-5-5" ] && [ "$info" = 1 ] \
  && [ "$seat_rc:$seat" = "7:waiting 석 - -" ] && [ "$load" = "waiting 부하 - -" ] && [ "$lintv" = "waiting lint - -" ] && [ "$dav" = "waiting DA - -" ] && [ "$prev" = "waiting 선행 - -" ] && [ "$exm" = "waiting 면제대기 - -" ] \
  && ok "R3 실제 spawn 진입점 — dry 0 · 정지 hold 2932 · 정지 acct(r1214 --agent·--model 판별 key) · 도구 없음 INFO · 석 rc7 · 부하 · lint · DA · 선행 · 면제대기(record) · init 이 정지 판정 앞 · 거절 거울 «대기(정지 · since)» 1줄 + 다른 줄 바이트 불변" \
  || bad "R3 po=$(printf '%s' "$po" | grep -E '^(REJECT|ERROR|EXPIRED|BASE)' | head -3) dry=$dry hold=$hold keep=$keep init=$init_first acct=$acct info=$info seat=$seat_rc:$seat load=$load lint=$lintv da=$dav prev=$prev exm=$exm :: $o"
# 성공 분기 — 진짜 spawn 의 함수 본문 + 성공 2줄(seat 기록 · 실제 ft-index-move)을 떼어 돌림(tmux 좌석 열기 대신) → master 이동 커밋 대역 → 커밋된 진행/ 카드에 거울 · 미커밋 줄 보존
succ() {  # $1 = spawn 파일 · $2 = stem → «원장:커밋 거울 수:미커밋 보존 수:대기 파일»
  local sp="${1:-$BIN/ft-nano-spawn.sh}" z="${2:-z1}" fn sl ml Z N
  Z="$SR/design/alpha/indices/대기/$z.md"; N="$SR/design/alpha/indices/진행/$z.md"
  sed "s/^# 인덱스: y/# 인덱스: $z/" "$CY" > "$Z"; git -C "$SR" add -- "$Z"; gc "$SR" "$NOW +0900" "$z"; printf '%s\n' '- 메모: 미커밋 ★' >> "$Z"
  fn="$(awk '/^card_assign_record\(\) \{/,/^}/' "$sp")"; sl="$(grep -F 'card_assign_record "$IDX" seat "$NAME"' "$sp")"; ml="$(grep -F 'bash "$HERE/ft-index-move.sh" "$IDX" 진행 --seat "$NAME"' "$sp")"; al="$(grep -F 'git -C "$IDX_WT" add -- "$NEW_IDX"' "$sp")"
  ( cd "$SR" && export FT_ROOT="$SR" FT_GOAL_LINES_FILE="$SP/goal.txt" FT_GOAL_LEDGER=design/LEDGER.md FT_MBOX_SH="$SP/mbox.sh" FT_GH_READ="$FK/gh" GH_REPO=x/y PATH="$FK:$PATH"
    HERE="$KB"; DRY=0; RESEARCH=0; IDX="$Z"; NAME="byz-alpha-nano-$z#0"; IDX_WT="$SR"; NEW_IDX="design/alpha/indices/진행/$z.md"; human() { echo "HUMAN $*"; }; eval "$fn"; eval "$sl"; eval "$ml"; eval "$al" ) > "$SP/succ-$z.log" 2>&1
  git -C "$SR" -c user.name=t -c user.email=t@t commit -q -m "master 이동 커밋 $z(준비된 것만 · 대리 add 0)" 2>/dev/null
  echo "$(L3 "$z"):$(git -C "$SR" show "HEAD:design/alpha/indices/진행/$z.md" 2>/dev/null | grep -c "^- 배정: 좌석 byz-alpha-nano-$z#0\$"):$(grep -c '미커밋 ★' "$N" 2>/dev/null):$([ -f "$Z" ] && echo left || echo moved):$(git -C "$SR" diff --name-only -- "$N" | grep -c .)"
}
mv_then="$(awk '/card_assign_record "\$IDX" seat "\$NAME"/{s=NR} /ft-index-move.sh" "\$IDX" 진행/{m=NR} END{print (s && m > s) ? 1 : 0}' "$BIN/ft-nano-spawn.sh")"
sv="$(succ "$BIN/ft-nano-spawn.sh" z1)"; [ "$sv" = "seat - - -:1:1:moved:0" ] && [ "$mv_then" = 1 ] && ok "R3′ 성공 — seat 기록(이동 «전») → 실제 ft-index-move → spawn 이 진행 카드 1개 재준비 → 준비된 것만 커밋(대리 add 0) · git show HEAD 진행 카드에 «좌석 <이름>» · 작업본=준비본 · 원장 seat" || bad "R3′ succ=$sv mv_then=$mv_then :: $(tail -3 "$SP/succ-z1.log")"
# 동시 기록 2건(같은 stem · 석·부하 · 시작 시각 다름) → 원장 1파일 · reason 둘 중 하나 · since = 이른 시작 · 손실 0
new_root; card "$R" "$H/대기/cc.md" "$NOW" "- 상태: 대기"
( cd "$R"; FT_ROOT="$R" FT_CARD_ASSIGN_NOW=$((NOW-10)) python3 "$TOOL" record "$R/$H/대기/cc.md" waiting 석 >/dev/null & FT_ROOT="$R" FT_CARD_ASSIGN_NOW=$((NOW-50)) python3 "$TOOL" record "$R/$H/대기/cc.md" waiting 부하 >/dev/null & wait )
cc="$(python3 -c 'import json,sys;j=json.load(open(sys.argv[1]));print(j["state"], j["reason"] in ("석","부하"), j["since"]==int(sys.argv[2]))' "$R/.fable-team/state/card-assign/cc.json" "$((NOW-50))")"
[ "$cc" = "waiting True True" ] && [ "$(ls "$R/.fable-team/state/card-assign/" | grep -c '\.json$')" = 1 ] && [ "$(grep -c '^- 배정:' "$R/$H/대기/cc.md")" = 1 ] && ok "R3″ 동시 기록 2건 → 원장 1파일 · reason 둘 중 하나 · since = 이른 시작 · 거울 1줄 · 손실 0" || bad "R3″ $cc"
lap R3
# ⓓ R4 시계 보존 — 같은 사유 재거절 3회 바이트 불변 · 사유 변경 since 유지 · 배정 since 삭제
new_root; card "$R" "$H/대기/k.md" "$NOW" "- 상태: 대기"; K="$R/.fable-team/state/card-assign/k.json"
rec() { (cd "$R" && FT_ROOT="$R" FT_CARD_ASSIGN_NOW="$1" python3 "$TOOL" record "$R/$H/대기/k.md" "${@:2}" >/dev/null); }
rec "$NOW" waiting 부하; cp "$K" "$T/k0"; rec $((NOW + 600)) waiting 부하; rec $((NOW + 1200)) waiting 부하; same="$(cmp -s "$K" "$T/k0" && echo 1)"
rec $((NOW + 1800)) waiting 석; s2="$(python3 -c 'import json,sys;j=json.load(open(sys.argv[1]));print(j["reason"], j["since"]==int(sys.argv[2]))' "$K" "$NOW")"
rec $((NOW + 2400)) seat byz-harness-nano-k#0; s3="$(python3 -c 'import json,sys;j=json.load(open(sys.argv[1]));print(j["state"], "since" in j)' "$K")"
printf '# k2\r\n- 상태: 대기\r\n- 메모: 한글 줄\r\n## 상태\r\n- 시험\r\n' > "$R/$H/대기/k2.md"; cp "$R/$H/대기/k2.md" "$T/k2.before"; (cd "$R" && FT_ROOT="$R" python3 "$TOOL" record "$R/$H/대기/k2.md" waiting 부하 >/dev/null)
crlf="$(grep -v '^- 배정:' "$R/$H/대기/k2.md" | cmp -s - "$T/k2.before" && grep -c $'^- 배정: 대기(부하 · .*)\r$' "$R/$H/대기/k2.md")"
[ "$same" = 1 ] && [ "$s2" = "석 True" ] && [ "$s3" = "seat False" ] && [ "$crlf" = 1 ] && ok "R4 재거절 3회 바이트 불변 · 부하→석 since 유지 · 배정 since 삭제 · CRLF 카드 = 거울 1줄만(CRLF 그대로) · 다른 줄 바이트 보존" || bad "R4 same=$same s2=$s2 s3=$s3 crlf=$crlf"
lap R4
# ⓔ R5 유효 정지 — 실제 ft-spawn-hold.sh status --check 2932(가짜 gate · 가짜 mbox) · 파일 바이트 불변 · 쪽지 0 · 만료 rc3 → 초과 · key 없음·도구 없음 Q · acct rc3 · released_at
r5_env() {
  new_root; card "$R" "$H/대기/h.md" "$((NOW - 90000))" "- 상태: 대기"; prep
  led "$R" h '{"state":"waiting","reason":"부하","since":'$((NOW-18000))',"pause":{"kind":"hold","key":"'"${1-2932}"'"}}'
  printf '#!/bin/sh\necho "disk=999999 swap=5000 memfree=50 level=1 rate=0 agents=10 freeze=0"\n' > "$R/gate.sh"; chmod 755 "$R/gate.sh"
  python3 -c 'import json,sys; json.dump({"verdict":2932,"until":"x","until_epoch":int(sys.argv[2]),"release":"swap<1","reason":"r1224 시험 정지","set_at":0},open(sys.argv[1],"w"))' "$R/.fable-team/state/SPAWN_HOLD" "${2:-$((NOW + 3600))}"
  cp "$R/.fable-team/state/SPAWN_HOLD" "$T/hold.before"
}
export FT_HOLD_GATE FT_HOLD_PLANNER_SEATS=/dev/null
r5_env; FT_HOLD_GATE="$R/gate.sh"; run status; a="$RC|$(hd | cut -d'·' -f1-3)"; ab="$(cmp -s "$R/.fable-team/state/SPAWN_HOLD" "$T/hold.before" && echo same):$(sent)"
r5_env 2932 $((NOW - 10)); FT_HOLD_GATE="$R/gate.sh"; run status; b="$RC|$(hd | cut -d'·' -f1-3)"; bb="$([ -f "$R/.fable-team/state/SPAWN_HOLD" ] && echo kept):$(sent)"
r5_env ""; FT_HOLD_GATE="$R/gate.sh"; run status; c="$RC|$(hd | cut -d'·' -f1-4)"
r5_env; led "$R" h '{"state":"waiting","reason":"정지","since":'$((NOW-18000))',"pause":{"kind":"acct","key":"claude/x"}}'; run status; d="$RC|$(hd | cut -d'·' -f3-4)"
printf '#!/bin/sh\necho "PAUSED $3"; exit 3\n' > "$T/ft-acct-pause.sh"; cp "$TOOL" "$BIN/ft_directive_watch.py" "$BIN/ft_penalty.py" "$BIN/ft_stall_detect.py" "$T/" 2>/dev/null; cp "$BIN"/ft_*.py "$T/" 2>/dev/null
TOOL_RUN="$T/ft_card_assign_watch.py" run status; e="$RC|$(hd | cut -d'·' -f3)"
r5_env; FT_HOLD_GATE="$R/gate.sh"; run status; rm "$R/.fable-team/state/SPAWN_HOLD"; run status; f1="$RC|$(hd | cut -d'·' -f2-3)"
run status --now $((NOW + 4 * 3600 + 120)); f2="$RC|$(hd | cut -d'·' -f2)"
[ "$a" = "0|배정 없는 카드 0 · 대기 초과 0 · 정지 중 1 " ] && [ "$ab" = "same:0" ] && [ "$b" = "1|배정 없는 카드 0 · 대기 초과 1(부하 1) · 정지 중 0 " ] && [ "$bb" = "kept:0" ] \
  && [ "$c" = "0|배정 없는 카드 0 · 대기 초과 0 · 정지 중 0 · 판정 불가 Q 1 " ] && [ "$d" = "0| 정지 중 0 · 판정 불가 Q 1 " ] && [ "$e" = "0| 정지 중 1 " ] && [ "$f1" = "0| 대기 초과 0 · 정지 중 0 " ] && [ "$f2" = "1| 대기 초과 1(부하 1) " ] \
  && ok "R5 hold --check 2932 rc0 = 정지 중 · 파일 바이트 불변 · 쪽지 0 · 만료 rc3 = 초과 1(파일 그대로) · key 없음·acct 도구 없음 = Q · acct rc3 = 정지 중 · 해제 released_at 기준 4시간" \
  || bad "R5 a=$a ab=$ab b=$b bb=$bb c=$c d=$d e=$e f1=$f1 f2=$f2"
lap R5
# ⓕ R6 inbox 발주문 사본(00 = 단위 4 · 01 = 1·2·4 + ①~⑦ = 10)
r6() {  # <00 변형 파일> <01 변형 파일> <커밋 epoch> → K
  new_root; card "$R" "$H/대기/c1.md" "$((NOW - 90000))" "- 배정: 없음"; card "$R" "$H/대기/u1.md" "$((NOW - 90000))" "- 긴급: 예"; led "$R" c1 '{"state":"seat","seat":"x#0"}'; led "$R" u1 '{"state":"seat","seat":"y#0"}'
  mkdir -p "$R/$H/inbox/arch"; cp "$1" "$R/$H/inbox/arch/00-a.md"; cp "$2" "$R/$H/inbox/arch/01-b.md"; git -C "$R" add -A design; gc "$R" "$3 +0900" inbox; prep; run status
  hd | sed -n 's/.* · 카드 없는 발주 \([0-9]*\) · .*/\1/p'
}
ptr() { python3 - "$@" <<'PY'
import re, sys
src, dst, mode = sys.argv[1:4]; out, lines = [], open(src, encoding="utf-8").read().splitlines()
for i, ln in enumerate(lines):
    out.append(ln)
    top, sub = re.match(r"^\d+[.)]\s", ln), re.match(r"^\s+[①-⑳]", ln)
    has_sub = top and any(re.match(r"^\s+[①-⑳]", x) for x in lines[i + 1:next((j for j in range(i + 1, len(lines)) if re.match(r"^\d+[.)]\s", lines[j])), len(lines))])
    if mode == "all" and (sub or top and not has_sub): out.append("   - 카드: design/harness/indices/대기/c1.md")
    if mode == "first3" and (top and not has_sub or sub and ln.strip()[0] in "①②③"): out.append("   - 카드: design/harness/indices/대기/c1.md")
    if mode == "headonly" and (top and has_sub or top and not has_sub): out.append("   - 카드: design/harness/indices/대기/c1.md")
open(dst, "w", encoding="utf-8").write("\n".join(out) + "\n")
PY
}
A0="$FX/00-fable-5342-5345-oppa-critical-20261031.md"; A1="$FX/01-parked-after-demo-autonomy-on-20261030.md"
ptr "$A0" "$T/a0all" all; ptr "$A1" "$T/a1all" all; ptr "$A1" "$T/a1f3" first3; ptr "$A1" "$T/a1head" headonly
k0="$(r6 "$A0" "$A1" $((NOW - 10800)))"; k1="$(r6 "$T/a0all" "$T/a1all" $((NOW - 10800)))"; k2="$(r6 "$T/a0all" "$T/a1f3" $((NOW - 10800)))"; k3="$(r6 "$T/a0all" "$T/a1head" $((NOW - 10800)))"; k4="$(r6 "$A0" "$A1" $((NOW - 3600)))"
printf '%s\n' '# 발주' '1. 빈 값' '   - 카드:' '2. 없는 경로' '   - 카드: design/x.md' '3. 크리티컬 건' '   - 카드: design/harness/indices/대기/c1.md' '4. 크리티컬 건 둘' '   - 카드: design/harness/indices/대기/u1.md' > "$T/s3"; printf '%s\n' '5. 자기 참조' '   - 카드: design/harness/indices/inbox/arch/00-a.md' >> "$T/s3"
k5="$(r6 "$T/s3" "$T/a1all" $((NOW - 10800)))"
[ "$k0|$k1|$k2|$k3|$k4|$k5" = "14|0|4|7|0|4" ] && ok "R6 사본 그대로 14(4+10) · 전부 연결 0 · 하위 ①②③만 4 · 묶음 머리만 7 · 1시간 0 · 빈 값·없는 경로·긴급 줄 없는 카드·inbox 자기 참조 = 미연결 4" || bad "R6 k=$k0|$k1|$k2|$k3|$k4|$k5"
lap R6
# ⓖ R7 틱 — 2통 · 같은 집합 0통 · 사유만 바뀜 1통씩 · 판본·경과만 0통 · planner 실패 → 다음 틱 그만 재송 · 실제 mbox_guard · 판정 불가 1통
r7_env() { new_root; card "$R" "$H/대기/t1.md" "$((NOW - 90000))" "- 상태: 대기"; led "$R" t1 '{"state":"waiting","reason":"부하","since":'$((NOW-18000))'}'; prep; }
r7_env; run tick; t1=$RC; s1=$(sent); run tick; s2=$(sent)
led "$R" t1 '{"state":"waiting","reason":"석","since":'$((NOW-18000))'}'; run tick; s3=$(sent); EXTRA_ENV="FT_CARD_ASSIGN_NOW=$((NOW + 600))" run tick; s4=$(sent)
r7_env; FAKE_FAIL_TO="$PLANNER" run tick; export -n FAKE_FAIL_TO 2>/dev/null; p1=$(sent "^$PLANNER"); EXTRA_ENV="FAKE_FAIL_TO=$PLANNER" run tick; run tick; p2=$(sent "^$PLANNER"); m2=$(sent "^$HMASTER")
[ "$t1" = 1 ] && [ "$s1$s2$s3$s4" = 2244 ] && [ "$p2:$m2" = "$((p1 + 2)):1" ] && grep -qF '[긴급] 배정 없는 카드 — 배정 없는 카드 0 · 대기 초과 1(부하 1)' "$R/sent.log" \
  && ok "R7 2통 · 같은 집합 0 · 사유만 바뀜 → 각 1통 · 판본·경과만 0 · planner 실패 → 다음 틱 planner 만 재송" || bad "R7 t1=$t1 s=$s1$s2$s3$s4 p=$p1/$p2 m=$m2 :: $(cat "$R/sent.log")"
mv "$R/.fable-team/state/directive-roots.tsv" "$R/.fable-team/state/roots.off"; run tick; u1=$RC; run tick
[ "$u1" = 3 ] && [ "$(sent "^$PLANNER.*배정 감시 판정 불가")" = 1 ] && ok "R7′ 판정 불가 → planner [긴급] 1통 · 다음 틱 억제" || bad "R7′ u1=$u1 :: $(tail -2 "$R/sent.log")"
r7_env; mkdir -p "$R/.fable-team/comm" "$T/stub"; cp "$COMM"/mbox*.py "$COMM"/mbox*.sh "$LINT" "$R/.fable-team/comm/"; printf '#!/bin/sh\nexit 1\n' > "$T/stub/tmux"; chmod +x "$T/stub/tmux"
OUT="$(cd "$R" && env -u FT_MBOX_SH PATH="$T/stub:$PATH" FT_ROOT="$R" FT_SEATS_JSON="$R/.fable-team/seats.json" FT_PLANNER_HEAD_MODE=reject FT_MBOX_DIR="$R/.fable-team/comm" FT_MBOX_RATE_N=999 FT_MBOX_FANOUT_WINDOW=0 python3 "$TOOL" tick 2>&1)"
q="$(grep -c "\"to\": *\"$PLANNER\"" "$R/.fable-team/comm/mailbox.jsonl" 2>/dev/null)"
[ "${q:-0}" = 1 ] && printf '%s' "$OUT" | grep -q "tick 1통 → $PLANNER" && ok "R7″ 실제 mbox_guard reject 모드 · planner [긴급] 큐 1행" || bad "R7″ q=$q :: $OUT"
lap R7
# ⓗ R8 부팅 보고 배정 칸(전용 stamps) · r1212 지시 칸 결과 불변(독립)
r1_env; run status; HEAD1="$(hd)"; ST="$(printf '%s' "$HEAD1" | sed -n 's/.*판본 \([0-9]*-[0-9a-f]*\).*/\1/p')"; CS="$R/.fable-team/state/card-assign/stamps.tsv"
mkdir -p "$T/seats7/state/directive-watch"; printf '%s\n' '{"_master":"byz-harness-master-claude#33","byz-harness-master-claude#32":{"role":"stop-ready","_replaced_by":"byz-harness-master-claude#33"},"byz-harness-master-claude#33":{"role":"master","_replaces":["byz-harness-master-claude#32"]}}' > "$T/seats7/seats-harness.json"
DST="$NOW-0000abcd"; printf '%s\t0\t0\n' "$DST" > "$T/seats7/state/directive-watch/stamps.tsv"; DIR="담당 없는 오빠 지시 0 · 멈춘 오빠 지시 0 · 판본 $DST"
BOOT="[부팅 보고] 세션=x retire=byz-harness-master-claude#32->byz-harness-master-claude#33 rc=0 cron=abc123 $DIR"
lint() { LOUT="$(printf '%s' "$1" | env FT_CARD_ASSIGN_STAMPS="${STAMPS:-$CS}" ${LENV:-} python3 "${LINT_RUN:-$LINT}" --from "$HMASTER" --seats-dir "$T/seats7" 2>&1)"; LRC=$?; }
lint "$BOOT"; r_none=$LRC; lint "$BOOT ${HEAD1/판본 $ST/판본 ${ST%%-*}-00000000}"; r_row=$LRC; lint "$BOOT ${HEAD1/배정 없는 카드 3/배정 없는 카드 4}"; r_num=$LRC
LENV="FT_DIRECTIVE_NOW=$(( ${ST%%-*} + 1860 ))" lint "$BOOT $HEAD1"; r_old=$LRC; STAMPS="$T/none.tsv" lint "$BOOT $HEAD1"; r_nof=$LRC; nof="$LOUT"
lint "$BOOT 배정 감시 판정 불가 · git 상한 넘김"; r_und=$LRC; und="$LOUT"; lint "$BOOT $HEAD1"; r_ok=$LRC
lint "${BOOT/ $DIR/} $HEAD1"; r_dir=$LRC; dir="$LOUT"
[ "$r_none$r_row$r_num$r_old$r_nof" = 11111 ] && case "$nof" in *'배정 판본 파일 없음'*) true;; *) false;; esac && [ "$r_und" = 0 ] && case "$und" in *WARN*배정*) true;; *) false;; esac && [ "$r_ok" = 0 ] \
  && [ "$r_dir" = 1 ] && case "$dir" in *'반송 — 지시 칸 없음'*) true;; *) false;; esac \
  && ok "R8 배정 칸 없음·행 없음·N 다름·31분·파일 없음 → 반송 · 판정 불가 → 통과+WARN · 맞는 머리 OK · 지시 칸 검사 그대로(독립)" || bad "R8 $r_none$r_row$r_num$r_old$r_nof und=$r_und ok=$r_ok dir=$r_dir :: $und :: $nof :: $dir"
lap R8
# ⓘ R9·R10 strict 루트·예산·prepare 분리·완성 이동 원장 삭제
new_root; rm "$R/.fable-team/state/directive-roots.tsv"; run status; a="$RC:$(printf '%s\n' "$OUT" | grep -c .):$(hd | cut -c1-26)"
new_root; printf 'harness\t\t\t\n' > "$R/.fable-team/state/directive-roots.tsv"; run status; b="$RC:$(hd | cut -c1-26)"
new_root; prep; EXTRA_ENV="FT_CARD_ASSIGN_STATUS_SEC=0" run status; c="$RC:$(hd | cut -c1-30)"
printf 'harness\t.\tno-such-ref\tdesign/harness/indices\n' > "$R/.fable-team/state/directive-roots.tsv"; run status; d="$RC:$(printf '%s\n' "$OUT" | grep -c .):$(hd | cut -c1-30)"
new_root; card "$R" "$H/대기/z.md" "$((NOW - 100))" "- 상태: 대기"; run status; e="$RC:$(hd | cut -c1-30)"
prep; s=$(date +%s); led "$R" z '{"state":"none","since":1}'; run status; dt=$(( $(date +%s) - s )); f="$RC"
mkdir -p "$R/$H/완성"; git -C "$R" mv "$H/대기/z.md" "$H/완성/z.md"; gc "$R" "$NOW +0900" done; run status; g="$RC:$([ -f "$R/.fable-team/state/card-assign/z.json" ] && echo kept || echo gone)"
pre() { case "$1" in "$2"*) echo 1;; *) echo 0;; esac; }
[ "$(pre "$a" "3:1:배정 감시 판정 불가 · 카드 루트 표 없음")$(pre "$b" "3:배정 감시 판정 불가 · 카드 루트 표 없음")$(pre "$c" "3:배정 감시 판정 불가 · git 상한")$(pre "$d" "3:1:배정 감시 판정 불가 · git rev-li")$(pre "$e" "3:배정 감시 판정 불가 · prepare 없")" = 11111 ] \
  && [ "$f" = 1 ] && [ "$dt" -le 3 ] && [ "$g" = "0:gone" ] \
  && ok "R9·R10 루트 표 없음·유효 행 0·예산 0·없는 ref → rc3 1줄 · prepare 없음 rc3 · prepare 뒤 status ${dt}초 · 완성 이동 → 원장 삭제" || bad "R9 a=$a b=$b c=$c d=$d e=$e f=$f dt=$dt g=$g"
r5_env; FT_HOLD_GATE="$R/gate.sh"; mkdir -p "$T/dl"; cp "$BIN"/ft_*.py "$T/dl/"; printf '#!/bin/sh\nexec tail -f /dev/null\n' > "$T/dl/ft-spawn-hold.sh"
s=$(date +%s); EXTRA_ENV="FT_CARD_ASSIGN_STATUS_SEC=1" TOOL_RUN="$T/dl/ft_card_assign_watch.py" run status; dl="$RC:$(( $(date +%s) - s ))"
case "$dl:$(hd)" in 3:[0-3]:"배정 감시 판정 불가 · status 마감 넘김(ft-spawn-hold.sh status --check)") ok "R9′ status 마감 1초 = 정지 확인에도 적용(멈춘 도구 주입) → rc3 1줄 · ${dl#*:}초";; *) bad "R9′ dl=$dl :: $(hd)";; esac
lap R9R10

# ── 변이 3 (그 칸만 다시 돈다)
mut() { python3 - "$1" "$2" "$3" "$4" <<'PY'
import sys
src, dst, a, b = sys.argv[1:5]; s = open(src, encoding="utf-8").read(); assert a in s, a
open(dst, "w", encoding="utf-8").write(s.replace(a, b))
PY
}
mkdir -p "$T/m"; cp "$BIN"/ft_*.py "$T/m/"; mut "$TOOL" "$T/m/ft_card_assign_watch.py" "WAIT_S, URGENT_S, ORDER_S, MUTE_S = 4 * 3600," "WAIT_S, URGENT_S, ORDER_S, MUTE_S = 10 ** 9,"
r1_env; TOOL_RUN="$T/m/ft_card_assign_watch.py" run status
r1_ok && bad "변이1(일반 임계 4시간 → 무한) 이 R1 에 안 잡힘" || { case "$(hd)" in *"대기 초과 1(석 1)"*) ok "변이1(일반 임계 → 무한) → R1 빨강(초과 2→1 · 긴급 1 남음)";; *) bad "변이1 꼴 :: $(hd)";; esac; }
mut "$BIN/ft-nano-spawn.sh" "$T/m2.sh" '  card_assign_record "$IDX" seat "$NAME"' '  :'
case "$(succ "$T/m2.sh" z2)" in seat*) bad "변이2 가 R3′ 에 안 잡힘";; *) ok "변이2(성공 기록 제거) → R3′ 빨강(seat 0 · 커밋 거울 0)";; esac
r1_env; run status; HEAD1="$(hd)"; ST="$(printf '%s' "$HEAD1" | sed -n 's/.*판본 \([0-9]*-[0-9a-f]*\).*/\1/p')"; CS="$R/.fable-team/state/card-assign/stamps.tsv"
mut "$LINT" "$T/m3.py" 'm.group(3) not in rows else "숫자 다름" if rows[m.group(3)] != [m.group(1), m.group(2)]' 'False else "숫자 다름" if False'
LINT_RUN="$T/m3.py" lint "$BOOT ${HEAD1/판본 $ST/판본 ${ST%%-*}-00000000}"
[ "$LRC" = 0 ] && ok "변이3(전용 stamps 대조 뺌) → R8 빨강(행 없음 반송 0)" || bad "변이3 이 R8 에 안 잡힘 rc=$LRC :: $LOUT"
lap mutation

# ⓙ bin·kit 같음 · 문법 · 새 파일 모드 · 줄 수 · ft-role-spawn 변경 0(기준판 blob)
for f in ft_card_assign_watch.py ft-card-assign-watch.sh ft-nano-spawn.sh ft-tick.sh; do cmp -s "$BIN/$f" "$KIT/$f" || bad "bin·kit 다름 $f"; done && ok "bin·kit 같은 내용 4파일"
python3 -m py_compile "$TOOL" "$LINT" 2>/dev/null && bash -n "$BIN/ft-card-assign-watch.sh" "$BIN/ft-nano-spawn.sh" "$BIN/ft-tick.sh" "$KIT/ft-index-lint.sh" && ok "py_compile · bash -n" || bad "문법"
m="$(stat -f %Lp "$BIN/ft_card_assign_watch.py" "$BIN/ft-card-assign-watch.sh" "$KIT/ft_card_assign_watch.py" "$KIT/ft-card-assign-watch.sh" | sort -u | tr '\n' ' ')"; [ "$m" = "644 " ] && ok "새 파일 4개 모드 644" || bad "새 파일 모드 $m"
n1="$(wc -l < "$LINT" | tr -d ' ')"; n2="$(wc -l < "$KIT/ft-index-lint.sh" | tr -d ' ')"; [ "$n1" -le 80 ] && [ "$n2" -le 160 ] && ok "부팅 lint ${n1}줄 ≤80 · 키트 index-lint ${n2}줄 ≤160" || bad "줄 수 $n1/$n2"
BASE="$(git -C "$REPO" merge-base HEAD origin/main 2>/dev/null)"; for f in harness/bin/ft-role-spawn.sh harness/kit/fable-team/bin/ft-role-spawn.sh; do
  [ -n "$BASE" ] && [ "$(git -C "$REPO" rev-parse "$BASE:feature-pack/fable-team/$f")" = "$(git -C "$REPO" hash-object "$REPO/$f")" ] || bad "ft-role-spawn 변경 있음 $f"; done && ok "ft-role-spawn.sh bin·kit blob = 기준판(역할 좌석 범위 밖)"
echo "단계별 초:$STEP"
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
