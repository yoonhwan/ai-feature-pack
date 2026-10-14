#!/usr/bin/env bash
# test_mbox_guard.sh — N3 쪽지 가드: 수신자 판정(D3) + planner 앞 허용 머리(D4) + ft-seat-retire 원자 쓰기.
# 명부 픽스처 = tests/fixtures/mbox_guard/<variant>/seats*.json · 기대 rc 표 = matrix.tsv (reject 모드).
# 임시 폴더에 정본 mbox*.py·mbox*.sh 를 복사해 격리 큐(FT_MBOX_DIR)로만 돈다 — 실 큐·실 doorbell(tmux 스텁)·루트 .fable-team/ 쓰기 0.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; REPO="$HERE/../.."
SRC="$REPO/tools/comm-canonical"; FX="$REPO/tests/fixtures/mbox_guard"
RETIRE="$REPO/scripts/fable-team-bin/ft-seat-retire.sh"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0; ok() { echo "PASS $1"; }; bad() { echo "FAIL $1"; fail=$((fail+1)); }
mkdir -p "$T/stub"; printf '#!/bin/sh\nexit 1\n' > "$T/stub/tmux"; chmod +x "$T/stub/tmux"
HEADS=(DECIDE_OK DECIDE_BAD HIL URGENT MERGE DONE BOOT PROGRESS)
body_of() { case "$1" in
  DECIDE_OK)  printf '[결정] 브랜치 삭제 승인\n비가역: 브랜치 삭제\n선례: 없음(ft-precedent "x" 0건)\n선택지: 보존(추천)·삭제';;
  DECIDE_BAD) printf '[결정] 뭔가 정하자\n비가역: 모름';;
  HIL)        printf '[HIL] 막힌 명령\n①막힌 명령: rm x\n②막은 훅: block-destructive\n③영향: 없음\n④선택지: 허용·거부';;
  URGENT)     printf '[긴급] 결제 중단';;
  MERGE)      printf '[합치기] cfo #1234 abc1234 — 큐 행 추가';;
  DONE)       printf '[완료] 끝\n세트: abc · 시험: x rc=0 · 이슈: 0';;
  BOOT)       printf '[부팅 보고] 세션=x 모델=y';;
  PROGRESS)   printf '[진행] 50%% 했다';;
esac; }

# new_env <variant> — 격리 루트 하나를 만들고 ENVROOT 에 둔다(정본 사본 + 명부 픽스처).
new_env() {
  ENVROOT="$(mktemp -d "$T/env.XXXXXX")"; mkdir -p "$ENVROOT/.fable-team/comm" "$ENVROOT/.fable-team/state"
  cp "$SRC"/mbox*.py "$SRC"/mbox*.sh "$SRC"/bang_command_check.py "$ENVROOT/.fable-team/comm/"; git -C "$ENVROOT" init -q
  mkdir -p "$ENVROOT/seats"; cp "$FX/$1"/seats*.json "$ENVROOT/seats/"
  return 0
}
# send_as <to> <body> [reject|warn|none] — 모드는 env FT_PLANNER_HEAD_MODE(기본 reject · none = env 없이 queues.conf·기본값). rc·stderr = RC·OUT.
send_as() {
  local mode="${3:-reject}"; local -a menv=(); [ "$mode" = none ] || menv=(FT_PLANNER_HEAD_MODE="$mode")
  OUT="$(cd "$ENVROOT" && env -u FT_PLANNER_HEAD_MODE PATH="$T/stub:$PATH" FT_SEATS_JSON="$ENVROOT/seats/seats.json" ${menv[@]+"${menv[@]}"} \
    FT_MBOX_DIR="$ENVROOT/.fable-team/comm" FT_MBOX_RATE_N=999 FT_MBOX_FANOUT_WINDOW=0 \
    bash "$ENVROOT/.fable-team/comm/mbox.sh" send "$1" "me#1" "$2" 2>&1)"; RC=$?
}
queued_to() { local n; n="$(grep -c "\"to\": *\"$1\"" "$ENVROOT/.fable-team/comm/mailbox.jsonl" 2>/dev/null)"; echo "${n:-0}"; }

# ── 1. 명부 8종 × 머리 8종 기대 rc 표 (reject 모드)
while IFS=$'\t' read -r variant to rcs; do
  case "$variant" in ''|'#'*) continue;; esac
  read -r -a want <<< "$rcs"
  for i in "${!HEADS[@]}"; do
    new_env "$variant"; send_as "$to" "$(body_of "${HEADS[$i]}")"
    [ "$RC" = "${want[$i]}" ] && ok "matrix $variant × ${HEADS[$i]} rc=$RC" || bad "matrix $variant × ${HEADS[$i]} rc=$RC want=${want[$i]} :: $OUT"
  done
done < "$FX/matrix.tsv"

# ── 2. REJECT 문구·후계 이름·전달
new_env retired; send_as 'byz-planner-master-claude#8' "$(body_of PROGRESS)"
case "$OUT" in *'현역 byz-planner-master-claude#10'*) ok "은퇴 REJECT 에 후계 체인 끝 이름";; *) bad "후계 이름 없음 :: $OUT";; esac
[ "$(queued_to 'byz-planner-master-claude#8')" = 0 ] && ok "REJECT 는 큐 적재 0" || bad "REJECT 인데 큐에 들어감"
new_env retired; send_as 'byz-planner-master-claude#8' "$(body_of HIL)"
[ "$RC" = 0 ] && [ "$(queued_to 'byz-planner-master-claude#10')" = 1 ] && ok "은퇴 수신자 + [HIL] → 후계로 전달" || bad "HIL 후계 전달 rc=$RC :: $OUT"
new_env broken; send_as 'byz-planner-master-claude#9' "$(body_of HIL)"
[ "$RC" = 0 ] && case "$OUT" in *'명부 미확인'*) true;; *) false;; esac && ok "깨진 명부 + [HIL] → WARN 명부 미확인 + 전송" || bad "깨진 명부 HIL rc=$RC :: $OUT"
grep -q . "$ENVROOT/.fable-team/state/mbox-guard.log" 2>/dev/null && ok "mbox-guard.log 1줄 이상" || bad "mbox-guard.log 없음"
new_env broken; send_as 'byz-planner-master-claude#9' "$(body_of PROGRESS)"
case "$OUT" in *'명부 읽기 실패'*'다시 보내라'*) ok "깨진 명부 REJECT 문구";; *) bad "읽기 실패 문구 :: $OUT";; esac
new_env dup; send_as 'byz-planner-master-claude#9' "$(body_of BOOT)"
case "$OUT" in *'명부 충돌'*) ok "중복 키 REJECT 문구";; *) bad "명부 충돌 문구 :: $OUT";; esac
new_env other_broken; send_as 'byz-planner-master-claude#9' "$(body_of BOOT)"
[ "$RC" = 0 ] && case "$OUT" in *'읽기 실패'*'이 판정에는 미사용'*) true;; *) false;; esac && ok "타 팀 명부 깨짐 = WARN 만 + 전송" || bad "타 팀 깨짐 rc=$RC :: $OUT"

# ── 3. 정지 레디 · 미등록 · 닫힌 팀 보존 좌석 · v65 명부
new_env stopready; send_as 'byz-planner-master-claude#9' "$(body_of BOOT)"
[ "$RC" = 0 ] && case "$OUT" in *WARN*) true;; *) false;; esac && ok "stop-ready(은퇴 표시 없음) = WARN + 전송" || bad "stop-ready rc=$RC :: $OUT"
new_env unreg; send_as 'ft-airag-x#1' "일반 쪽지"
[ "$RC" = 0 ] && case "$OUT" in *'미등록'*) true;; *) false;; esac && ok "행 없음 = WARN 미등록 + 전송" || bad "미등록 rc=$RC :: $OUT"
new_env kept; send_as 'byz-cfo-master-claude#5' "일반 쪽지"
[ "$RC" = 3 ] && case "$OUT" in *'닫힌 좌석(cfo _closed=2026-10-09T12:00:00Z)'*) true;; *) false;; esac && ok "닫힌 팀 보존 좌석(stopped+_kept) = REJECT 닫힌 좌석" || bad "kept rc=$RC :: $OUT"
new_env kept; send_as 'byz-v65-master-claude#3' "일반 쪽지"
[ "$RC" = 0 ] && ok "byz-v65-* 는 seats.json 이 authoritative · 현역 전송" || bad "v65 rc=$RC :: $OUT"

# ── 4. planner 머리 모드(warn 기본) · 별칭 · lint WARN
new_env ok; send_as 'byz-planner-master-claude#9' "$(body_of PROGRESS)" warn
[ "$RC" = 0 ] && grep -q . "$ENVROOT/.fable-team/state/planner-head.log" 2>/dev/null && ok "warn 모드: 진행 쪽지 전송 + planner-head.log 1줄" || bad "warn 모드 rc=$RC :: $OUT"
new_env ok; send_as 'byz-planner-master-claude#9' "$(body_of PROGRESS)" none
[ "$RC" = 0 ] && ok "모드 값 없음 = 기본 warn(전송)" || bad "기본 모드 rc=$RC :: $OUT"
new_env ok; printf '# 큐\nplanner_head_mode=reject\n' > "$ENVROOT/.fable-team/comm/queues.conf"; send_as 'byz-planner-master-claude#9' "$(body_of PROGRESS)" none
[ "$RC" = 3 ] && ok "queues.conf planner_head_mode=reject 가 env 없이 적용" || bad "queues.conf 모드 rc=$RC :: $OUT"
new_env ok; send_as 'byz-planner-master-claude#9' "[HIL·merge] cfo #1234 abc1234"
[ "$RC" = 0 ] && grep -q '합치기' "$ENVROOT/.fable-team/state/planner-head.log" 2>/dev/null && ok "[HIL·merge] → [합치기] 별칭 치환 로그" || bad "별칭 rc=$RC :: $OUT"
new_env ok; send_as 'byz-planner-master-claude#9' "[HIL] 막힘"
[ "$RC" = 0 ] && case "$OUT" in *WARN*) true;; *) false;; esac && ok "[HIL] ①②④ 줄 없음 = WARN 만 전송" || bad "HIL lint rc=$RC :: $OUT"
new_env ok; send_as 'byz-planner-master-claude#9' "[완료] 끝"
[ "$RC" = 0 ] && case "$OUT" in *WARN*) true;; *) false;; esac && ok "[완료] 증거 줄 없음 = WARN 만 전송" || bad "완료 lint rc=$RC :: $OUT"
new_env ok; send_as 'byz-planner-master-claude#9' "$(body_of PROGRESS)" reject
case "$OUT" in *'[결정]·[HIL]·[긴급]·[합치기]·[정지 레디]·[완료]·[부팅 보고]'*) ok "reject 문구에 허용 머리 목록";; *) bad "reject 문구 :: $OUT";; esac

# ── 5. relay 도 같은 문을 지난다
new_env retired; printf '긴 본문\n' > "$ENVROOT/long.txt"
OUT="$(cd "$ENVROOT" && PATH="$T/stub:$PATH" FT_SEATS_JSON="$ENVROOT/seats/seats.json" FT_MBOX_DIR="$ENVROOT/.fable-team/comm" FT_MBOX_RELAY_DIR="$ENVROOT/relay" \
  bash "$ENVROOT/.fable-team/comm/mbox.sh" relay 'byz-planner-master-claude#8' me#1 "$ENVROOT/long.txt" "[진행] 요약" 2>&1)"; RC=$?
[ "$RC" = 3 ] && ok "relay 도 은퇴 수신자 REJECT rc=3" || bad "relay rc=$RC :: $OUT"

# ── 6. ft-seat-retire 원자 쓰기 — 쓰기 중 죽어도 원본 무손상
mkdir -p "$T/sc"; cat > "$T/sc/sitecustomize.py" <<'PY'
import json, os
_real = json.dump
def _die(obj, fp, *a, **k):
    fp.write('{"half'); fp.flush(); os._exit(137)
json.dump = _die
PY
S="$T/seats-r.json"; cp "$FX/ok/seats-planner.json" "$S"; cp "$S" "$T/seats-r.orig"
PYTHONPATH="$T/sc" bash "$RETIRE" 'byz-planner-master-claude#9' 'byz-planner-master-claude#10' --seats "$S" >/dev/null 2>&1; rc=$?
[ "$rc" = 137 ] && ok "쓰기 중 kill 흉내 rc=137" || bad "kill 흉내 rc=$rc"
cmp -s "$S" "$T/seats-r.orig" && python3 -c 'import json,sys;json.load(open(sys.argv[1]))' "$S" && ok "쓰기 중 죽어도 원본 무손상(cmp 동일·JSON 유효)" || bad "원본이 깨졌다/바뀌었다"
rm -f "$T"/seats-r.json.tmp-*   # 죽은 실행이 남긴 tmp 는 원본이 아니다 — 아래는 «정상 실행이 잔류 0» 을 본다
out="$(bash "$RETIRE" 'byz-planner-master-claude#9' 'byz-planner-master-claude#10' --seats "$S" 2>&1)"; rc=$?
out="$(printf '%s\n' "$out" | grep -v '^bash: warning: setlocale')"   # 없는 LC_ALL 이면 bash 가 첫 줄에 내는 경고만 뺀다(다른 출력은 그대로 단언)
[ "$rc" = 0 ] && case "$out" in 'RETIRED byz-planner-master-claude#9 -> byz-planner-master-claude#10 file='*'keys=['*) true;; *) false;; esac && ok "정상 은퇴 출력 무변경" || bad "정상 은퇴 rc=$rc out=$out"
python3 -c 'import json,sys;d=json.load(open(sys.argv[1]));assert d["byz-planner-master-claude#9"]["_replaced_by"]=="byz-planner-master-claude#10" and d["_master"]=="byz-planner-master-claude#10"' "$S" && ok "은퇴 결과(_replaced_by·_master 전환)" || bad "은퇴 결과 틀림"
ls "$T" | grep -q 'seats-r.json.tmp' && bad "tmp 파일 잔류" || ok "tmp 파일 잔류 0"
ls "$T"/seats-r.json.tmp* >/dev/null 2>&1 && bad "tmp 파일 잔류(glob)" || ok "tmp 파일 잔류 0(glob)"

# ── 7a. 상태는 이름별 authoritative 파일에서만 — 다른 팀 파일 행 하나가 정상 쪽지를 막지 않는다(DA⑥ G1)
new_env foreign_closed; send_as 'byz-planner-master-claude#9' "$(body_of BOOT)"
[ "$RC" = 0 ] && case "$OUT" in *'미등록'*'다른 명부 seats-feature.json 에만'*) true;; *) false;; esac && ok "G1(a) 타 팀 파일의 closed 행만 있음 → 미등록 WARN + 전송" || bad "G1(a) rc=$RC :: $OUT"
new_env foreign_retired; send_as 'byz-planner-master-claude#9' "$(body_of BOOT)"
[ "$RC" = 0 ] && [ "$(queued_to 'byz-planner-master-claude#9')" = 1 ] && [ "$(queued_to 'byz-planner-master-claude#10')" = 0 ] && ok "G1(b) 타 팀 파일의 _replaced_by 로 후계 전환 0 · 원 이름 적재" || bad "G1(b) rc=$RC :: $OUT"
C_WANT='후계 byz-feature-master-claude#1 도 닫힘(_closed=2026-10-11T00:00:00Z)'   # _closed 값 = 후계 팀 파일(seats-feature.json)을 읽었다는 유일 증거
c_ok() { [ "$RC" = 3 ] && case "$OUT" in *"$C_WANT"*) true;; *) false;; esac; }
new_env succ_closed; send_as 'byz-planner-master-claude#9' "$(body_of BOOT)"
c_ok && ok "G1(c) 후계가 속한 팀 파일의 closed 상태 판정 → REJECT + 후계 파일의 _closed 문구" || bad "G1(c) rc=$RC :: $OUT"
# V6 변이(사본만): 후계 파일 선택을 auth 로 바꾸면 «후계 행 없음 → 현역 … 다시 보내라» 로 rc 3 은 같지만 c_ok 문구 검사가 가른다
new_env succ_closed; sed -i '' 's/cfile = tfile(cur)/cfile = auth/' "$ENVROOT/.fable-team/comm/mbox_guard.sh"
grep -q 'cfile = auth' "$ENVROOT/.fable-team/comm/mbox_guard.sh" && ok "V6 변이 사본 생성(원본 무변경)" || bad "V6 변이 사본 생성 실패"
send_as 'byz-planner-master-claude#9' "$(body_of BOOT)"
[ "$RC" = 3 ] && ! c_ok && case "$OUT" in *'도 닫힘'*) false;; *'현역 byz-feature-master-claude#1 — 후계 이름으로 다시 보내라'*) true;; *) false;; esac \
  && ok "V6 변이 사본 = (c) 문구 빨강 확인(rc 3 이어도 c_ok 거짓)" || bad "V6 변이가 (c) 에 안 잡힘 rc=$RC :: $OUT"
new_env dup; send_as 'byz-planner-master-claude#9' "$(body_of BOOT)"
[ "$RC" = 3 ] && case "$OUT" in *'명부 충돌'*) true;; *) false;; esac && ok "G1(d) 전역 키 검색은 충돌 검사로 유지(dup rc 3)" || bad "G1(d) rc=$RC :: $OUT"

# ── 8. check-drift 가 mbox_guard.sh 를 본다 — mbox.sh 가 source 하므로 한쪽만 깔리면 전 좌석 send 정지(무증상 방지)
D="$T/drift"; mkdir -p "$D/tools/comm-canonical" "$D/.fable-team/comm"
cp "$SRC/check-drift.sh" "$SRC/mbox_guard.sh" "$D/tools/comm-canonical/"; cp "$SRC/mbox_guard.sh" "$D/.fable-team/comm/"
drift_line() { bash "$D/tools/comm-canonical/check-drift.sh" 2>&1 | grep -E ' mbox_guard\.sh( |$)'; }
case "$(drift_line)" in SAME*) ok "drift: mbox_guard.sh MAP 행 · 동일 = SAME";; *) bad "drift: SAME 행 없음 :: $(drift_line)";; esac
printf '#\n' >> "$D/.fable-team/comm/mbox_guard.sh"
case "$(drift_line)" in DRIFT*) ok "drift: 라이브 1바이트 변경 = DRIFT";; *) bad "drift: DRIFT 아님 :: $(drift_line)";; esac
cp "$SRC/mbox_guard.sh" "$D/.fable-team/comm/mbox_guard.sh"
case "$(drift_line)" in SAME*) ok "drift: 원복 = SAME";; *) bad "drift: 원복 후 SAME 아님 :: $(drift_line)";; esac

# ── 9. R106 오빠 `!` 명령 줄 가드 — 모든 수신자 · [HIL] 도 REJECT(보낸 좌석이 rc≠0 + 안내를 본다)
BANG_BAD='! bash /private/tmp/claude-501/x/scratchpad/d6-apply.sh'
new_env ok; send_as 'byz-planner-master-claude#9' "$(printf '[HIL] 막힌 명령\n①막힌 명령: rm x\n②막은 훅: y\n④선택지: 허용·거부\n%s' "$BANG_BAD")"
[ "$RC" = 3 ] && case "$OUT" in *'ft-hil.sh --add'*'/tmp/h<N>'*'! bash /private/tmp'*) true;; *) false;; esac && [ "$(queued_to 'byz-planner-master-claude#9')" = 0 ] \
  && ok "R106: planner 앞 [HIL] 위반 = REJECT rc=3 + 안내 + 위반 줄 앞부분 + 큐 0" || bad "R106 planner [HIL] rc=$RC :: $OUT"
new_env unreg; send_as 'ft-airag-x#1' "$(printf '일반 보고\n%s' "$BANG_BAD")"
[ "$RC" = 3 ] && case "$OUT" in *'ft-hil.sh --add'*) true;; *) false;; esac && ok "R106: 다른 좌석 앞 위반도 REJECT" || bad "R106 타 좌석 rc=$RC :: $OUT"
new_env ok; send_as 'byz-planner-master-claude#9' "$(printf '[HIL] 막힌 명령\n①막힌 명령: cd /Users/x && rm y\n②막은 훅: y\n④선택지: 허용·거부\n! bash /tmp/h7')"
[ "$RC" = 0 ] && [ "$(queued_to 'byz-planner-master-claude#9')" = 1 ] && ok "R106: ①막힌 명령 원문 + ! bash /tmp/h7 = 전송" || bad "R106 정상 꼴 rc=$RC :: $OUT"

# ── 7. 문법
for f in "$SRC/mbox.sh" "$SRC/mbox_guard.sh" "$RETIRE"; do bash -n "$f" 2>/dev/null && ok "bash -n $(basename "$f")" || bad "bash -n $(basename "$f")"; done

[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
