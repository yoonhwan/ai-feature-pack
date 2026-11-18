#!/usr/bin/env bash
# test_oppa_slack_tail_word_r2195.sh — 끝: 오빠 답 «네 ENFORCE» 처럼 덧말에 이 sha 의 열쇠가 아닌 영문·숫자 낱말이 있으면 그 sha 는 승인 0 · «네 9025» 처럼 제 열쇠면 승인 (카드 r2195-oppa-slack-tail-word-other-item-no-approve)
#   ②~⑪ · bin·kit cmp0 · 변이 M1~M4(+원본 대조) · ① 기존 시험은 따로 돌린다(시험 1개 70초)
#   FT_R2195_CHECK = 판정기 경로 덮어쓰기(기준판 Red 대조용) · FT_R2195_BASE = 기준판 경로(⑦⑩ 출력 같은 바이트 대조 · 없으면 고정 문자열만)
# 격리: 임시 루트 · 가짜 슬랙 조회(FT_SLACK_REPLIES_CMD) · 실 Slack 0 · 네트워크 0 · 고정 sleep 0 · 실 스레드 글 0(지어낸 같은 꼴 글) · 안전선 ulimit -u(현재+64) · timeout 70
NPROC=$(ulimit -u 2>/dev/null || echo 3000); ulimit -u $((NPROC + 64)) 2>/dev/null || true
TO=70
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/autonomy_scope_setup.sh"
CHECK="${FT_R2195_CHECK:-$BIN/ft_oppa_slack_check.py}"
P=1794100000.000100; A=1794100000.000300
OPPA=U0AC2JF0M7D; S="$(sha 9025)"; S2="$(sha 9001)"
export FT_SLACK_REPLIES_CMD="cat $T/replies.json"
say() { printf '{"ok":true,"messages":[{"ts":"%s","user":"UBOT1","bot_id":"B0BOT1","text":"%s"},{"ts":"%s","user":"%s","text":"%s"}]}' "$P" "$1" "$A" "$OPPA" "$2" > "$T/replies.json"; }  # say <질문 글> <답>
ok_() { run timeout $TO python3 "${F:-$CHECK}" "$P" "$1"; [ "$rc" = 0 ] && [ "$out" = "SLACK-OK $1 parent=$P reply=$A" ]; }  # ok_ <sha>
no_() { run timeout $TO python3 "${F:-$CHECK}" "$P" "$1"; [ "$rc" = 2 ] && ! grep -q '^SLACK-OK' <<<"$out" && { [ -z "${2:-}" ] || grep -q -- "$2" <<<"$out"; }; }  # no_ <sha> [사유 글]
all() { local bad=0 c; for c in "$@"; do eval "$c" || { bad=1; echo "  어긋남: $c :: rc=$rc ${out:0:120}"; }; done; return $bad; }
UW="판정 불가: 답글 내용 승인 낱말 아님"
QK="[오빠 할 일]\\n1. ENFORCE 켜기\\n2. PR 9025 착지\\n9025 $S"     # 열쇠 줄 1개(지어낸 묶음 글)
Q2="[오빠 할 일]\\n9001 $S2\\n9025 $S"                              # 열쇠 줄 2개
QN="[오빠 할 일]\\n근거 head $S 입니다"                              # 열쇠 줄 없음
QD="[오빠 할 일]\\n9025 $S\\n9025 $S2"                              # 같은 열쇠가 두 sha
QT="[오빠 할 일]\\n9025 $S\\n9026 $S"                               # 이 sha 열쇠 2개

all 'say "$QK" "네 ENFORCE"; no_ $S "$UW"'; ck "② «네 ENFORCE» → 승인 0 rc2" $?
all 'say "$QK" "승인 enforce"; no_ $S "$UW"'; ck "③ «승인 enforce» → 승인 0 rc2" $?
all 'say "$QK" "네 ENFORCE켜요"; no_ $S "$UW"'; ck "④ «네 ENFORCE켜요» → 승인 0 rc2" $?
all 'say "$Q2" "네 9001"; no_ $S "$UW"' 'ok_ $S2'; ck "⑤ 열쇠 둘 · «네 9001» → 9025 승인 0 · 9001 SLACK-OK" $?
all 'say "$Q2" "네 9025"; ok_ $S' 'no_ $S2 "$UW"'; ck "⑥ 열쇠 둘 · «네 9025» → 9025 SLACK-OK · 9001 승인 0" $?
S7=('네 9025' '네 PR 9025' '네, 9025' '네 넓혀요' '네 ok' '네')
bad=0; for w in "${S7[@]}"; do say "$QK" "$w"; ok_ "$S" || { bad=1; echo "  승인 아님: «$w» rc=$rc ${out:0:100}"; }
  if [ -n "${FT_R2195_BASE:-}" ]; then b="$out"; F="$FT_R2195_BASE" ok_ "$S"; [ "$out" = "$b" ] || { bad=1; echo "  기준판과 다름: «$w» $b ≠ $out"; }; fi; done
ck "⑦ «네 9025»·«네 PR 9025»·«네, 9025»·«네 넓혀요»·«네 ok»·«네» → SLACK-OK${FT_R2195_BASE:+(기준판과 같은 바이트)}" $bad
all 'say "$QN" "네 9025"; no_ $S "$UW"'; ck "⑧ 열쇠 줄 없음 · «네 9025» → 승인 0 rc2(한계 1)" $?
all 'say "$QD" "네 9025"; no_ $S "$UW"' 'say "$QT" "네 9025"; no_ $S "$UW"'; ck "⑨ 열쇠 9025 가 두 sha · 이 sha 열쇠 2개 → 승인 0 rc2" $?
bad=0; say "$QK" "네 ENFORCE 아니오"; no_ $S "오빠 거절 답글 reply=$A" || { bad=1; echo "  거절 아님: rc=$rc $out"; }
if [ -n "${FT_R2195_BASE:-}" ]; then b="$out"; run timeout $TO python3 "$FT_R2195_BASE" "$P" "$S"; [ "$out" = "$b" ] || { bad=1; echo "  기준판과 다름: $b ≠ $out"; }; fi
ck "⑩ «네 ENFORCE 아니오» → 거절 rc2${FT_R2195_BASE:+(기준판과 같은 줄)}" $bad
all 'say "$QK" "네 1번"; no_ $S "$UW"' 'say "$QK" "네 2"; no_ $S "$UW"' 'say "$QK" "네 1,2"; no_ $S "$UW"' 'say "$QK" "네 PR 9025"; ok_ $S'; ck "⑪ «네 1번»·«네 2»·«네 1,2» → 승인 0 · «네 PR 9025» → SLACK-OK" $?
cmp -s "$BIN/ft_oppa_slack_check.py" "$ROOT/harness/kit/fable-team/bin/ft_oppa_slack_check.py"; ck "bin·kit cmp0" $?

if [ -z "${FT_R2195_CHECK:-}" ]; then
mut() {  # mut <이름> <바꿀 글> <바꾼 글> → $MUT · 안 먹으면 FAIL
  MUT="$T/mut-$1.py"; cp "$CHECK" "$MUT"
  python3 - "$MUT" "$2" "$3" <<'PY' || { rc=1; out="변이 미적용: $1"; ck "변이 적용($1)" 1; }
import pathlib, sys
p = pathlib.Path(sys.argv[1]); t = p.read_text(encoding="utf-8")
assert t.count(sys.argv[2]) == 1, sys.argv[2]
p.write_text(t.replace(sys.argv[2], sys.argv[3], 1), encoding="utf-8")
PY
}
# 변이마다: 변이판에서 시험이 잡는지(F=$MUT) + 원본에서 같은 사례가 반대 결과인지
mut M1 'if t in yes and tail_words_ok(fc, sha, text)]' 'if t in yes]'
all 'say "$QK" "네 ENFORCE"; F=$MUT ok_ $S' 'say "$QK" "승인 enforce"; F=$MUT ok_ $S' 'say "$QK" "네 ENFORCE켜요"; F=$MUT ok_ $S' \
    'say "$QK" "네 ENFORCE"; no_ $S "$UW"'; ck "M1 B2 검사 삭제 → ②③④ SLACK-OK(= 시험이 잡음) · 원본 승인 0" $?
mut M2 'len(mine) == 1 and' 'len(mine) >= 1 and'
all 'say "$QT" "네 9025"; F=$MUT ok_ $S' 'no_ $S "$UW"'; ck "M2 «정확히 1개» → «1개 이상» → ⑨ 이 sha 열쇠 2개 승인(= 시험이 잡음) · 원본 승인 0" $?
mut M2b ' and mine[0] not in others' ''
all 'say "$QD" "네 9025"; F=$MUT ok_ $S' 'no_ $S "$UW"'; ck "M2b 다른 sha 열쇠 겹침 검사 삭제 → ⑨ 같은 열쇠 두 sha 승인(= 시험이 잡음) · 원본 승인 0" $?
mut M3 'b == key or b in APPROVE_WORDS' 'b == key'
all 'say "$QK" "네 ok"; F=$MUT ok_ $S' 'ok_ $S'; ck "M3 APPROVE_WORDS 통과 삭제 → ⑦ «네 ok» 는 첫 갈래라 그대로 SLACK-OK · 원본 같음" $?
mut M4 'b.isdigit() or len(b) >= 3' 'len(b) >= 3'
all 'say "$QK" "네 1번"; F=$MUT ok_ $S' 'no_ $S "$UW"'; ck "M4 숫자 조각도 3자 이상만 → ⑪ «네 1번» 승인(= 시험이 잡음) · 원본 승인 0" $?
fi

echo "단계 합계 ${SECONDS}s"; [ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILURES: $fail"; exit 1; }
