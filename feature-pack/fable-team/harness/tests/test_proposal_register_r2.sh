#!/usr/bin/env bash
# test_proposal_register_r2.sh — ft-proposal-register.sh r2 시험(설계 §r2-4 1 · DA r2 교정 1 ①②): 본문 전문 · 분할 · 식별자 · 불명 · 확정 거절.
#   test_proposal_register.sh 가 끝에서 부른다(단독 실행도 된다). 원격 0 — 가짜 Tank + 가짜 gh 읽기.
set -uo pipefail
# shellcheck source=_proposal_register_env.sh
. "$(dirname "${BASH_SOURCE[0]:-$0}")/_proposal_register_env.sh"

run() { bash "$REG" "$1" --apply "${@:2}" 2>&1; }   # 출력만 — rc 는 호출 쪽이 $? 로
expect() {  # <이름> <rc조건 0|nz> <create횟수> <comment횟수> <label횟수>
  local name="$1" want="$2" rc="$3"
  local c l m; c="$(n_of create)"; m="$(n_of comment)"; l="$(n_of label)"
  local rcok=1; if [ "$want" = 0 ]; then [ "$rc" -eq 0 ] && rcok=0; else [ "$rc" -ne 0 ] && rcok=0; fi
  echo "    [$name] rc=$rc · create=$c comment=$m label=$l"
  [ $rcok -eq 0 ] && [ "$c" = "$4" ] && [ "$m" = "$5" ] && [ "$l" = "$6" ] && ok "$name" || bad "$name (create=$c comment=$m label=$l rc=$rc)"
}

# ── 1 본문 = 숨은 표식 + 보이는 ID + 머리말 + 경로@sha + 판정 + 증거 폴더 + 제안서 전문(바이트 그대로)
reset
P="$(mkn PROPOSAL-ko-line-20261008.md '승인 — 판정 351' "$GOODV")"
mkdir -p "$R/design/feature/evidence/proposal-ko-line"; echo png > "$R/design/feature/evidence/proposal-ko-line/render.png"
git -C "$R" add -A >/dev/null 2>&1; git -C "$R" commit -qm ev >/dev/null 2>&1
ID="$(pid_of "$P" 351)"
out="$(run "$P")"; rc=$?
B="$T/body-1"; SHA="$(git -C "$R" log -1 --format=%H -- design/feature/PROPOSAL-ko-line-20261008.md | cut -c1-10)"
[ "$(sed -n 1p "$B")" = "<!-- byz-proposal-id: $ID -->" ] && ok "본문 1줄 = 숨은 표식 ID" || bad "표식 줄: $(sed -n 1p "$B")"
sed -n 2p "$B" | grep -qF "$ID" && ok "본문 2줄 = 보이는 ID" || bad "보이는 ID"
grep -q '^구현 시 이 본문을 참고 — 제안서 전문(판정 351 승인본)$' "$B" && ok "머리말" || bad "머리말"
grep -qx "제안서: design/feature/PROPOSAL-ko-line-20261008.md @ $SHA" "$B" && ok "제안서: 경로 @ 마지막 커밋 sha 10자" || bad "경로@sha"
grep -qx '오빠 컨펌: 판정 351 (승인)' "$B" && ok "오빠 컨펌 줄" || bad "컨펌 줄"
grep -qx '증거 폴더: design/feature/evidence/proposal-ko-line/' "$B" && grep -qx -- '- design/feature/evidence/proposal-ko-line/render.png' "$B" && ok "증거 폴더 + 파일 목록" || bad "증거 폴더"
N="$(awk '/^---$/{print NR; exit}' "$B")"
tail -n +$((N+1)) "$B" | cmp -s - "$P" && ok "--- 뒤 = 제안서 전문(바이트 그대로)" || bad "전문 불일치"
expect "승인 → create 1 · comment 0 · label 1" 0 "$rc" 1 0 1
grep -q '^done$' <(python3 -c 'import json,sys;d=json.load(open(sys.argv[1]));print(d[sys.argv[2]]["phase"])' "$FT_PROPOSAL_STATE" "$ID") && ok "시도 기록 phase=done" || bad "기록 done 아님"

# ── 2 60,000자 초과 → create 1 + comment N-1(순서 · «(이어서 k/N)») · 조각 ≤60,000자 · 이어 붙이면 원문
reset
P="$(mkn PROPOSAL-big-20261008.md '승인 — 판정 351' "$GOODV" "## 부록")"
yes "$(printf 'a%.0s' $(seq 1 99))" | head -n 1500 >> "$P"; git -C "$R" add -A >/dev/null 2>&1; git -C "$R" commit -qm big >/dev/null 2>&1
out="$(run "$P")"; rc=$?
NCH="$(calls)"; echo "    총 호출 $NCH"; expect "분할 → create 1 · comment 2 · label 1" 0 "$rc" 1 2 1
[ "$(sed -n 1p "$T/body-2")" = "(이어서 2/3)" ] && [ "$(sed -n 1p "$T/body-3")" = "(이어서 3/3)" ] && ok "각 조각 첫 줄 (이어서 k/N)" || bad "이어서 줄: $(sed -n 1p "$T/body-2") / $(sed -n 1p "$T/body-3")"
[ "$(wc -m < "$T/body-1")" -le 60000 ] && [ "$(wc -m < "$T/body-2")" -le 60000 ] && [ "$(wc -m < "$T/body-3")" -le 60000 ] && ok "조각 ≤ 60,000자" || bad "조각 크기"
N="$(awk '/^---$/{print NR; exit}' "$T/body-1")"
{ tail -n +$((N+1)) "$T/body-1"; tail -n +2 "$T/body-2"; tail -n +2 "$T/body-3"; } | cmp -s - "$P" && ok "조각을 이으면 제안서 원문" || bad "이은 결과 불일치"

# ── 3 comment 2번째 실패 → 멈춤 · label 0 · 「#M 등록됨 · 분할 3/3 부터 수동」
reset
out="$(TANK_FAIL_COMMENT_N=2 run "$P")"; rc=$?
expect "comment 2번째 실패 → rc≠0 · label 0" nz "$rc" 1 2 0
echo "$out" | grep -q '#901 등록됨 · 분할 3/3 부터 수동' && ok "「#901 등록됨 · 분할 3/3 부터 수동」" || bad "수동 안내: $out"
python3 -c 'import json,sys;d=json.load(open(sys.argv[1]));print(list(d.values())[0]["phase"])' "$FT_PROPOSAL_STATE" | grep -qx 'comment-2' && ok "기록 phase=comment-2 (실패한 3은 안 올림)" || bad "기록 phase"

# ── 4 식별자: 같은 ID = 채택(create 0) · 같은 제목·다른 ID = 충돌 · 기록 creating + 원격 없음 = 불명 · --force-create 뒤에만
reset
P="$(mkn PROPOSAL-dup-20261008.md '승인 — 판정 351' "$GOODV")"; ID="$(pid_of "$P" 351)"
list_json 850; view_json 850 "$ID"
out="$(run "$P")"; rc=$?; expect "같은 ID Issue 있음 → 채택 rc=0 · create 0" 0 "$rc" 0 0 0
echo "$out" | grep -q '^ALREADY #850 판정 351 — 이미 등록됨 #850(채택)' && ok "출력 ALREADY #850 · 머리줄 기입 안내" || bad "ALREADY 줄: $out"
reset; list_json 851; view_json 851 "test/repo:다른/제안서@판정9#0000000000000000"
out="$(run "$P")"; rc=$?; expect "같은 제목·다른 ID → 충돌 rc≠0 · create 0" nz "$rc" 0 0 0
echo "$out" | grep -q '제목 충돌 #851' && ok "출력 「제목 충돌 #851」" || bad "충돌 줄: $out"
reset; python3 "$LIB" rec "$FT_PROPOSAL_STATE" set "$ID" creating >/dev/null
out="$(run "$P")"; rc=$?; expect "기록 creating + 원격 없음 → 불명 rc≠0 · create 0" nz "$rc" 0 0 0
echo "$out" | grep -q '불명: .* 생성 결과 확인 필요' && ok "출력 「불명 … 확인 필요」" || bad "불명 줄: $out"
out="$(run "$P" --force-create)"; rc=$?; expect "--force-create 뒤에만 create" 0 "$rc" 1 0 1

# ── 5 조회 실패·불완전 → rc≠0 · Tank 0
reset
out="$(GH_FAIL=1 run "$P")"; rc=$?; expect "조회 실패 → rc≠0 · Tank 0" nz "$rc" 0 0 0
python3 -c 'import json;print(json.dumps([{"number":i,"title":"x"} for i in range(1,101)]))' > "$T/gh-list.json"
out="$(run "$P")"; rc=$?; expect "목록이 상한(100)에 닿음(끝 미확인) → rc≠0 · Tank 0" nz "$rc" 0 0 0
echo "$out" | grep -q '끝을 못 봤다' && ok "불완전 사유 출력" || bad "불완전 줄: $out"

# ── 6 [DA 교정 ①] create 확정 거절은 rc=2(원격 호출 전)만 — 그 밖은 «불명» (기록 creating 유지)
reset
out="$(TANK_FAIL_CREATE=1 TANK_FAIL_CREATE_RC=2 run "$P")"; rc=$?; expect "확정 거절(rc=2) → rc≠0 · label 0 · comment 0" nz "$rc" 1 0 0
python3 -c 'import json,sys;print(sys.argv[2] in json.load(open(sys.argv[1])))' "$FT_PROPOSAL_STATE" "$ID" | grep -qx False && ok "확정 거절 → 시도 기록 삭제" || bad "기록이 남음"
reset; out="$(TANK_FAIL_CREATE=1 run "$P")"; rc=$?; expect "일반 실패(rc=1) → 불명 · label 0" nz "$rc" 1 0 0
python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))[sys.argv[2]]["phase"])' "$FT_PROPOSAL_STATE" "$ID" | grep -qx creating && ok "일반 실패 → creating 유지(삭제 0)" || bad "creating 아님"
reset; out="$(TANK_CREATE_NO_NUMBER=1 run "$P")"; rc=$?; expect "rc=0 인데 번호 없는 출력 → 불명" nz "$rc" 1 0 0
python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))[sys.argv[2]]["phase"])' "$FT_PROPOSAL_STATE" "$ID" | grep -qx creating && ok "번호 없는 출력 → creating 유지" || bad "creating 아님"
out="$(run "$P")"; rc=$?; expect "다음 실행은 불명으로 막힌다(자동 새 create 0)" nz "$rc" 1 0 0

# ── 7 [DA 교정 ②] 기록에 Issue 번호가 있으면 검색에 안 보여도 새 create 0 — 그 번호를 직접 확인
reset; python3 "$LIB" rec "$FT_PROPOSAL_STATE" set "$ID" comment-2 --issue 852 >/dev/null; view_json 852 "$ID"
out="$(run "$P")"; rc=$?; expect "기록 #852 + 검색 0건 + 직접 확인 일치 → 채택 · create 0" 0 "$rc" 0 0 0
echo "$out" | grep -q 'comment-2' && ok "기록 phase 를 안내에 싣는다" || bad "phase 안내: $out"
rm -f "$T/gh-view-852.json"; out="$(run "$P")"; rc=$?; expect "기록 #852 직접 확인 불가 → 보이는 오류 · create 0" nz "$rc" 0 0 0
view_json 852 "test/repo:다른@판정1#1111111111111111"; out="$(run "$P")"; rc=$?; expect "기록 #852 의 표식이 다름 → rc≠0 · create 0" nz "$rc" 0 0 0

# ── 8 커밋 안 된/수정된 제안서는 거부(경로@sha 거짓 표기 방지)
reset; P2="$(mk '승인 — 판정 5' "$GOODV")"; echo "- 덧붙임" >> "$P2"
out="$(run "$P2")"; rc=$?; expect "커밋 뒤 수정된 제안서 → rc≠0 · Tank 0" nz "$rc" 0 0 0

# shellcheck disable=SC2154  # fail 은 env 파일에서 정의
[ $fail -eq 0 ] && { echo "R2 ALL PASS"; exit 0; } || { echo "R2 FAILED $fail"; exit 1; }
