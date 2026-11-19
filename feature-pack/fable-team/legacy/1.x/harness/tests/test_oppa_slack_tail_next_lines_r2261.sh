#!/usr/bin/env bash
# test_oppa_slack_tail_next_lines_r2261.sh — 끝: 오빠 답이 «네» 뒤 줄바꿈·« / » 다음 조각에서 이 sha 열쇠가 아닌 영문·숫자 낱말(«ENFORCE»)을 말하면 그 sha 는 승인 0 · 한글 설명 줄·제 열쇠·이 sha 머리 글자는 승인 (카드 r2261-oppa-slack-tail-word-next-lines)
#   ②~⑪ · bin·kit cmp0 · 변이 M1~M4(+원본 대조) · ① 기존 시험은 따로 돌린다(시험 1개 70초)
#   FT_R2261_CHECK = 판정기 경로 덮어쓰기(기준판 Red 대조용) · FT_R2261_BASE = 기준판 경로(④⑧⑨⑩ 출력 같은 바이트 대조 · 없으면 고정 문자열만)
# 격리: 임시 루트 · 가짜 슬랙 조회(FT_SLACK_REPLIES_CMD) · 실 Slack 0 · 네트워크 0 · 고정 sleep 0 · 실 스레드 글 0(⑩ 만 r1696 ⓙ 본문 재생) · 안전선 ulimit -u(현재+64) · timeout 70
NPROC=$(ulimit -u 2>/dev/null || echo 3000); ulimit -u $((NPROC + 64)) 2>/dev/null || true
TO=70
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/autonomy_scope_setup.sh"
CHECK="${FT_R2261_CHECK:-$BIN/ft_oppa_slack_check.py}"
P=1794100000.000100; A=1794100000.000300
OPPA=U0AC2JF0M7D; S="457ae87$(printf '%033x' 9025)"; S2="$(sha 9001)"
export FT_SLACK_REPLIES_CMD="cat $T/replies.json"
say() { printf '{"ok":true,"messages":[{"ts":"%s","user":"UBOT1","bot_id":"B0BOT1","text":"%s"},{"ts":"%s","user":"%s","text":"%s"}]}' "$P" "$1" "$A" "$OPPA" "$2" > "$T/replies.json"; }  # say <질문 글> <답>
ok_() { run timeout $TO python3 "${F:-$CHECK}" "$P" "$1"; [ "$rc" = 0 ] && [ "$out" = "SLACK-OK $1 parent=$P reply=$A" ]; }  # ok_ <sha>
no_() { run timeout $TO python3 "${F:-$CHECK}" "$P" "$1"; [ "$rc" = 2 ] && ! grep -q '^SLACK-OK' <<<"$out" && { [ -z "${2:-}" ] || grep -q -- "$2" <<<"$out"; }; }  # no_ <sha> [사유 글]
all() { local bad=0 c; for c in "$@"; do eval "$c" || { bad=1; echo "  어긋남: $c :: rc=$rc ${out:0:120}"; }; done; return $bad; }
same() { [ -z "${FT_R2261_BASE:-}" ] && return 0; local b="$out" r="$rc"; run timeout $TO python3 "$FT_R2261_BASE" "$P" "$1"; [ "$out" = "$b" ] && [ "$rc" = "$r" ] || { echo "  기준판과 다름: $b ≠ $out"; return 1; }; }  # same <sha> = 직전 출력이 기준판과 같은 바이트
UW="판정 불가: 답글 내용 승인 낱말 아님"
QK="[오빠 할 일]\\n1. ENFORCE 켜기\\n2. PR 9025 착지\\n9025 $S"     # 열쇠 줄 1개(지어낸 묶음 글)
Q2="[오빠 할 일]\\n9001 $S2\\n9025 $S"                              # 열쇠 줄 2개
Q9="승인 요청\\n1. PR 9001 착지\\n2. PR 9025 착지\\n9001 $S2\\n9025 $S"  # 번호 답 꼴(r2194)
RJ="예\\n\\n헤드는 안꼬이게 메인을 서로 올릴수있도록 이제 플랜팀에서\\n각 팀장들이 웨크트리와.브랜치를 관리 지원 이것도 2.0.0의 메인축으로 있다"  # r1696 ⓙ 오빠 실제 답

all 'say "$QK" "네\\nENFORCE 켜요"; no_ $S "$UW"'; ck "② «네 ⏎ ENFORCE 켜요» → 승인 0 rc2" $?
all 'say "$QK" "네 / ENFORCE"; no_ $S "$UW"'; ck "③ «네 / ENFORCE» → 승인 0 rc2" $?
all 'say "$QK" "예\\n\\n헤드는 충돌 해소 1파일입니다"; ok_ $S && same $S'; ck "④ «예 ⏎ ⏎ 헤드는 충돌 해소 1파일입니다» → SLACK-OK${FT_R2261_BASE:+(기준판과 같은 바이트)}" $?
all 'say "$QK" "네\\n9025 진행해 주세요"; ok_ $S'; ck "⑤ «네 ⏎ 9025 진행해 주세요» → SLACK-OK(제 열쇠)" $?
all 'say "$QK" "네\\n457ae87 확인"; ok_ $S' 'say "$QK" "네\\nhead 457ae87"; no_ $S "$UW"' 'say "$QK" "네 457ae87"; ok_ $S'
ck "⑥ «네 ⏎ 457ae87 확인» SLACK-OK · «네 ⏎ head 457ae87» 승인 0 · «네 457ae87» SLACK-OK" $?
all 'say "$Q2" "네\\n9001"; no_ $S "$UW"' 'ok_ $S2'; ck "⑦ 열쇠 둘 · «네 ⏎ 9001» → 9025 승인 0 · 9001 SLACK-OK" $?
all 'say "$QK" "네\\n근데 보류"; no_ $S "오빠 거절 답글 reply=$A" && same $S'; ck "⑧ «네 ⏎ 근데 보류» → 거절 rc2${FT_R2261_BASE:+(기준판과 같은 줄)}" $?
all 'say "$Q9" "1.네\\n2.네"; ok_ $S && same $S'; ck "⑨ 번호 답 «1.네 ⏎ 2.네» → SLACK-OK${FT_R2261_BASE:+(기준판과 같은 바이트)}" $?
all 'say "$QK" "$RJ"; ok_ $S && same $S'; ck "⑩ r1696 ⓙ 실사건 답 재생 → SLACK-OK${FT_R2261_BASE:+(기준판과 같은 바이트)}" $?
all 'say "$QK" "네\\n1번 켜요"; ok_ $S' 'say "$QK" "네\\nhead 0000000"; no_ $S "$UW"'; ck "⑪ «네 ⏎ 1번 켜요» SLACK-OK(한계 3) · «네 ⏎ head 0000000» 승인 0" $?
cmp -s "$BIN/ft_oppa_slack_check.py" "$ROOT/harness/kit/fable-team/bin/ft_oppa_slack_check.py"; ck "bin·kit cmp0" $?

if [ -z "${FT_R2261_CHECK:-}" ]; then
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
mut M1 'yes = [t for t in yes if bits_ok(rest[t], sha, text)]' 'yes = yes'
all 'say "$QK" "네\\nENFORCE 켜요"; F=$MUT ok_ $S' 'no_ $S "$UW"' 'say "$QK" "네 / ENFORCE"; F=$MUT ok_ $S' 'no_ $S "$UW"'
ck "M1 다음 조각 검사 뺌 → ②③ SLACK-OK(= 시험이 잡음) · 원본 승인 0" $?
mut M2 ' or head(b)' ''
all 'say "$QK" "네\\n457ae87 확인"; F=$MUT no_ $S "$UW"' 'ok_ $S'; ck "M2 sha 머리 글자 허용 뺌 → ⑥ 승인 0(= 시험이 잡음) · 원본 SLACK-OK" $?
mut M3 'TAIL_BIT.findall(c.lower())' 're.findall(r"[A-Za-z0-9_가-힣-]+", c.lower())'
all 'say "$QK" "예\\n\\n헤드는 충돌 해소 1파일입니다"; F=$MUT no_ $S "$UW"' 'ok_ $S'; ck "M3 다음 조각에 한글도 뽑음 → ④ 승인 0(= 시험이 잡음) · 원본 SLACK-OK" $?
mut M4 'if len(b) >= 3]' 'if b.isdigit() or len(b) >= 3]'
all 'say "$QK" "예\\n\\n헤드는 충돌 해소 1파일입니다"; F=$MUT no_ $S "$UW"' 'ok_ $S' 'say "$QK" "$RJ"; F=$MUT no_ $S "$UW"' 'ok_ $S'
ck "M4 다음 조각 숫자를 길이 무관 → ④⑩ 승인 0(= 시험이 잡음) · 원본 SLACK-OK" $?
fi

echo "단계 합계 ${SECONDS}s"; [ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILURES: $fail"; exit 1; }
