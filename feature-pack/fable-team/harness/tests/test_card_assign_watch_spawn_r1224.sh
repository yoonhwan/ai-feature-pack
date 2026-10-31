#!/usr/bin/env bash
# test_card_assign_watch_spawn_r1224.sh — r1224 반례 R3(실제 ft-nano-spawn 진입점 종료 분기 7종 · 성공 이동 커밋 · 동시 기록) + 변이 2. 나머지 R1·R2·R4~R10·변이 1·3 = test_card_assign_watch_r1224.sh(하드 룰 22 · 70초 상한 넘어 쪼갬).
# 임시 git 리포 · 배정 원장 · 실제 ft-nano-spawn 진입점(가짜 = tmux·tmm·gh·자원 센서·acct-pause·회수) · 실제 ft-spawn-hold.sh(가짜 gate) · 가짜 mbox 수집기.
# 실 STATE·실 좌석·실 쪽지 0 · 자기 재호출 0(재진입 표지) · 고정 sleep 0. 돌리기: ulimit -u <지금+여유>; timeout 70 bash harness/tests/test_card_assign_watch_spawn_r1224.sh
[ -z "${R1224_SPAWN_TEST_ACTIVE:-}" ] || { echo "재진입 금지 — R1224_SPAWN_TEST_ACTIVE 가 이미 켜져 있다"; exit 3; }; export R1224_SPAWN_TEST_ACTIVE=1
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
run() { OUT="$(cd "$R" && env FT_ROOT="$R" FT_MBOX_SH="$R/mbox.sh" python3 "${TOOL_RUN:-$TOOL}" "$@" 2>&1)"; RC=$?; }
prep() { run prepare >/dev/null; }
sent() { grep -c "${1:-.}" "$R/sent.log" 2>/dev/null || true; }
hd() { printf '%s\n' "$OUT" | head -1; }

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
  FT_MBOX_SH="$SP/mbox.sh" FT_GH_READ="$FK/gh" FT_GOAL_LINES_FILE="$SP/goal.txt" FT_GOAL_LEDGER=design/LEDGER.md && PATH="$FK:$PATH" bash "$KB/ft-nano-spawn.sh" "${CARD:-$CX}" --from byz-alpha-master-claude#1 "$@" 2>&1 ); }
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
lclear; o="$(FT_DISK_HARD_MIN_MIB=9999999 sp)"; load="$(L3)"
# lint · DA(사전검증 미승인)
lclear; o="$(sp)"; lintv="$(L3)"; lclear; o="$(FT_CARD_REQUIRE_PREVERIFY=1 sp)"; dav="$(L3)"
# 선행 — lint·제안서·이슈 게이트를 지나는 카드 + 분리 HEAD 가 origin/main 조상 아님
CY="$SR/design/alpha/indices/대기/y.md"
{ printf '%s\n' '# 인덱스: y' '- 제안서: 없음 — 시험 카드' '- Issue: #5342' '- 배정: 없음' '## 골 원문' '골 1' '골 2' '골 3' '## 골좌표' '닫는 증거: 「닫는 증거는 이 문장 전체를 복붙한 것이어야 한다.」' '## 배경' '시험.' '## 구현 범위' '1. src/t.sh 수정' '## 완료 조건' '- 시험.' '## 계약↔시험 대응표' '| 계약 | 시험 |' '|---|---|' '| ① 시험 | ⓐ 시험 |' '## 상태' '- 시험'; } > "$CY"
git -C "$SR" add -A; gc "$SR" "$NOW +0900" y; git -C "$SR" checkout -q --detach; gc "$SR" "$NOW +0900" detached
lclear; o="$(CARD="$CY" GH_REPO=x/y sp)"; po="$o"; prev="$(L3 y)"; git -C "$SR" checkout -q main
lclear; printf '#!/bin/sh\n[ "$3 $4 $5" = "--agent claude --model" ] && [ -n "$6" ] || exit 9\necho "PAUSED claude/sonnet-5-5 until_hhmm=12:00 round=t1"; exit 3\n' > "$KB/ft-acct-pause.sh"; o="$(CARD="$CY" GH_REPO=x/y sp)"; acct="$(L3 y)"; rm -f "$KB/ft-acct-pause.sh"
# 면제대기 — 이 스크립트에 분기가 없다(카드 조사 근거 대조) → 도구 record 1줄로 같은 원장 꼴
lclear; (cd "$SR" && FT_ROOT="$SR" python3 "$TOOL" record "$CX" waiting 면제대기 >/dev/null); exm="$(L3)"
[ "$dry" = "none:0" ] && [ "$hold" = "waiting 정지 hold 2932" ] && [ "$keep" = 1 ] && [ "$init_first" = 1 ] && [ "$acct" = "waiting 정지 acct claude/sonnet-5-5" ] \
  && [ "$seat_rc:$seat" = "7:waiting 석 - -" ] && [ "$load" = "waiting 부하 - -" ] && [ "$lintv" = "waiting lint - -" ] && [ "$dav" = "waiting DA - -" ] && [ "$prev" = "waiting 선행 - -" ] && [ "$exm" = "waiting 면제대기 - -" ] \
  && ok "R3 실제 spawn 진입점 — dry 0 · 정지 hold 2932 · 정지 acct(r1214 게이트 rc3 → key P/M) · 석 rc7 · 부하 · lint · DA · 선행 · 면제대기(record) · init 이 정지 판정 앞 · 거절 거울 «대기(정지 · since)» 1줄 + 다른 줄 바이트 불변" \
  || bad "R3 po=$(printf '%s' "$po" | grep -E '^(REJECT|ERROR|EXPIRED|BASE)' | head -3) dry=$dry hold=$hold keep=$keep init=$init_first acct=$acct seat=$seat_rc:$seat load=$load lint=$lintv da=$dav prev=$prev exm=$exm :: $o"
# 성공 분기 — 진짜 spawn 의 함수 본문 + 성공 2줄(seat 기록 · 실제 ft-index-move)을 떼어 돌림(tmux 좌석 열기 대신) → master 이동 커밋 대역 → 커밋된 진행/ 카드에 거울 · 미커밋 줄 보존
succ() {  # $1 = spawn 파일 · $2 = stem → «원장:커밋 거울 수:미커밋 보존 수:대기 파일»
  local sp="${1:-$BIN/ft-nano-spawn.sh}" z="${2:-z1}" fn sl ml Z N
  Z="$SR/design/alpha/indices/대기/$z.md"; N="$SR/design/alpha/indices/진행/$z.md"
  sed "s/^# 인덱스: y/# 인덱스: $z/" "$CY" > "$Z"; git -C "$SR" add -- "$Z"; gc "$SR" "$NOW +0900" "$z"; printf '%s\n' '- 메모: 미커밋 ★' >> "$Z"
  fn="$(awk '/^card_assign_record\(\) \{/,/^}/' "$sp")"; sl="$(grep -F 'card_assign_record "$IDX" seat "$NAME"' "$sp")"; ml="$(grep -F 'bash "$HERE/ft-index-move.sh" "$IDX" 진행 --seat "$NAME"' "$sp")"; al="$(grep -F 'git -C "$IDX_WT" add -- "$NEW_IDX"' "$sp")"
  ( cd "$SR" && export FT_ROOT="$SR" FT_GOAL_LINES_FILE="$SP/goal.txt" FT_GOAL_LEDGER=design/LEDGER.md FT_MBOX_SH="$SP/mbox.sh" FT_GH_READ="$FK/gh" GH_REPO=x/y PATH="$FK:$PATH"
    HERE="$KB"; DRY=0; RESEARCH=0; IDX="$Z"; NAME="byz-alpha-nano-$z#0"; IDX_WT="$SR"; NEW_IDX="design/alpha/indices/진행/$z.md"; human() { echo "HUMAN $*"; }; eval "$fn"; eval "$sl"; eval "$ml"; eval "$al" ) > "$SP/succ-$z.log" 2>&1
  git -C "$SR" -c user.name=t -c user.email=t@t commit -q -m "master 이동 커밋 $z(준비된 것만 · 대리 add 0)" 2>/dev/null
  echo "$(L3 "$z"):$(git -C "$SR" show "HEAD:design/alpha/indices/진행/$z.md" 2>/dev/null | grep -c "^- 배정: 좌석 byz-alpha-nano-$z#0\$"):$(grep -c '미커밋 ★' "$N" 2>/dev/null):$([ -f "$Z" ] && echo left || echo moved):$(git -C "$SR" diff --name-only -- "$N" | grep -c .)"   # baseline-ref: ok 임시 시험 리포(SR)의 방금 만든 이동 커밋 — 기준판 아님
}
mv_then="$(awk '/card_assign_record "\$IDX" seat "\$NAME"/{s=NR} /ft-index-move.sh" "\$IDX" 진행/{m=NR} END{print (s && m > s) ? 1 : 0}' "$BIN/ft-nano-spawn.sh")"
sv="$(succ "$BIN/ft-nano-spawn.sh" z1)"; [ "$sv" = "seat - - -:1:1:moved:0" ] && [ "$mv_then" = 1 ] && ok "R3′ 성공 — seat 기록(이동 «전») → 실제 ft-index-move → spawn 이 진행 카드 1개 재준비 → 준비된 것만 커밋(대리 add 0) · git show HEAD 진행 카드에 «좌석 <이름>» · 작업본=준비본 · 원장 seat" || bad "R3′ succ=$sv mv_then=$mv_then :: $(tail -3 "$SP/succ-z1.log")"
# 동시 기록 2건(같은 stem · 석·부하 · 시작 시각 다름) → 원장 1파일 · reason 둘 중 하나 · since = 이른 시작 · 손실 0
new_root; card "$R" "$H/대기/cc.md" "$NOW" "- 상태: 대기"
( cd "$R"; FT_ROOT="$R" FT_CARD_ASSIGN_NOW=$((NOW-10)) python3 "$TOOL" record "$R/$H/대기/cc.md" waiting 석 >/dev/null & FT_ROOT="$R" FT_CARD_ASSIGN_NOW=$((NOW-50)) python3 "$TOOL" record "$R/$H/대기/cc.md" waiting 부하 >/dev/null & wait )
cc="$(python3 -c 'import json,sys;j=json.load(open(sys.argv[1]));print(j["state"], j["reason"] in ("석","부하"), j["since"]==int(sys.argv[2]))' "$R/.fable-team/state/card-assign/cc.json" "$((NOW-50))")"
[ "$cc" = "waiting True True" ] && [ "$(ls "$R/.fable-team/state/card-assign/" | grep -c '\.json$')" = 1 ] && [ "$(grep -c '^- 배정:' "$R/$H/대기/cc.md")" = 1 ] && ok "R3″ 동시 기록 2건 → 원장 1파일 · reason 둘 중 하나 · since = 이른 시작 · 거울 1줄 · 손실 0" || bad "R3″ $cc"
lap R3

# ── 변이 1 (spawn 칸)
mut() { python3 - "$1" "$2" "$3" "$4" <<'PY'
import sys
src, dst, a, b = sys.argv[1:5]; s = open(src, encoding="utf-8").read(); assert a in s, a
open(dst, "w", encoding="utf-8").write(s.replace(a, b))
PY
}
mut "$BIN/ft-nano-spawn.sh" "$T/m2.sh" '  card_assign_record "$IDX" seat "$NAME"' '  :'
case "$(succ "$T/m2.sh" z2)" in seat*) bad "변이2 가 R3′ 에 안 잡힘";; *) ok "변이2(성공 기록 제거) → R3′ 빨강(seat 0 · 커밋 거울 0)";; esac
lap mutation
echo "단계별 초:$STEP"
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
