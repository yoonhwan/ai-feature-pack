#!/usr/bin/env bash
# test_jsonl_last_ts.sh — R53: ft-nano-close ③ 유휴 게이트 = jsonl «timestamp 있는 마지막 기록» 시각 (파일 mtime 아님)
# 임시 디렉터리 가짜 jsonl 만 쓴다 — 실제 tmux·좌석·~/.claude/projects 조회 0.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
TRK="$HERE/../../scripts/fable-team-bin"
KIT="$HERE/../../scripts/harness-install/fable-team/bin"
LTS="${LTS_UNDER_TEST:-$TRK/ft-jsonl-last-ts.py}"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3 — 기대 «$2» 실제 «$1»"; }

# 사건 좌석 꼬리(22:4x 실측): turn_duration 13:34:23Z 뒤에 timestamp 없는 last-prompt · cost-state
EPOCH="$(python3 -c 'from datetime import datetime;print(int(datetime(2026,10,8,13,34,23).replace(tzinfo=__import__("datetime").timezone.utc).timestamp()))')"
cat > "$T/seat.jsonl" <<'EOF'
{"type":"attachment","timestamp":"2026-10-08T13:34:20.100Z"}
{"type":"assistant","timestamp":"2026-10-08T13:34:23.371Z"}
{"type":"system","subtype":"stop_hook_summary","timestamp":"2026-10-08T13:34:23.371Z"}
{"type":"system","subtype":"turn_duration","timestamp":"2026-10-08T13:34:23.371Z"}
{"type":"last-prompt","lastPrompt":"x"}
{"type":"cost-state","cost":1}
EOF
touch "$T/seat.jsonl"   # mtime = 지금 (덧붙임이 민 것과 같은 상태)

# ① 꼬리의 timestamp 없는 두 줄을 건너뛰고 turn_duration 시각
out="$("$LTS" "$T/seat.jsonl" 2>/dev/null)"; rc=$?
eq "$out" "$EPOCH system/turn_duration" "① epoch + type (timestamp 없는 꼬리 2줄 건너뜀)"; eq "$rc" 0 "① rc=0"
echo "  ①출력: $out"

# ② 마지막 줄이 깨진 JSON
{ cat "$T/seat.jsonl"; printf '{"type":"x","timestamp":"2026-10-08T14:00:00Z"'; } > "$T/broken.jsonl"
eq "$("$LTS" "$T/broken.jsonl" 2>/dev/null)" "$EPOCH system/turn_duration" "② 깨진 줄 건너뛰고 그 앞 기록"

# ③ timestamp 기록 0
printf '{"type":"last-prompt"}\n{"type":"cost-state"}\n' > "$T/none.jsonl"
out="$("$LTS" "$T/none.jsonl" 2>"$T/err")"; rc=$?
eq "$rc" 1 "③ rc=1"; eq "$out" "" "③ stdout 0"; case "$(cat "$T/err")" in ERROR:*) ok "③ stderr ERROR:";; *) bad "③ stderr ERROR: 아님";; esac

# ④ 없는 파일
"$LTS" "$T/nope.jsonl" >/dev/null 2>&1; eq "$?" 1 "④ 없는 파일 rc=1"

# ⑤ ft-nano-close.sh 에 mtime 읽기 0 · 헬퍼 호출 1
NC="$TRK/ft-nano-close.sh"
eq "$(grep -c 'stat -f %m "\$f"' "$NC")" 0 "⑤ stat -f %m \"\$f\" 0건"
eq "$(grep -c 'FT_JSONL_LAST_TS:-' "$NC")" 1 "⑤ 헬퍼 호출 1건"

# ⑥ ③ 블록 발췌 실행 — 헬퍼를 FT_JSONL_LAST_TS 스텁으로 주입
sed -n '/_lt="\$(/,/마지막 기록(/p' "$NC" > "$T/block.sh"
[ "$(wc -l < "$T/block.sh")" -ge 4 ] && ok "⑥ ③ 블록 발췌" || bad "⑥ ③ 블록 발췌 실패"
run_block() { # $1 = 스텁 본문
  printf '#!/usr/bin/env bash\n%s\n' "$1" > "$T/stub.sh"; chmod +x "$T/stub.sh"
  ( HERE="$T"; f="$T/seat.jsonl"; IDLE_MIN=3; bad=(); age=; FT_JSONL_LAST_TS="$T/stub.sh"
    . "$T/block.sh"; printf '%s|' "${bad[@]:-}" ; echo "age=${age:-}" )
}
out="$(run_block 'echo "$(( $(date +%s) - 600 )) system/turn_duration"')"; eq "${out%%|*}" "" "⑥ 10분 전 → 통과"
out="$(run_block 'echo "$(( $(date +%s) - 60 )) system/turn_duration"')"
case "$out" in *"③jsonl 마지막 기록(system/turn_duration) 1분 전 < 3분"*) ok "⑥ 1분 전 → 반송";; *) bad "⑥ 반송 문구: $out";; esac
echo "  ⑥반송: ${out%%|*}"
out="$(run_block 'echo "ERROR: x 에 timestamp 기록 없음" >&2; exit 1')"
case "$out" in *"③jsonl 기록 시각 없음: ERROR: x 에 timestamp 기록 없음"*) ok "⑥ rc=1 → 기록 시각 없음";; *) bad "⑥ rc=1 문구: $out";; esac
echo "  ⑥반송: ${out%%|*}"

# ⑦ 변이 대조: 마지막 «줄» 의 timestamp 를 보는 헬퍼(=mtime 과 같은 오판) 면 ① 이 FAIL
sed 's/for raw in lines_from_end(path):/for raw in list(lines_from_end(path))[:1]:/' "$TRK/ft-jsonl-last-ts.py" > "$T/mut.py"; chmod +x "$T/mut.py"
out="$("$T/mut.py" "$T/seat.jsonl" 2>/dev/null)"
[ "$out" = "$EPOCH system/turn_duration" ] && bad "⑦ 변이가 ① 을 못 깨뜨림" || ok "⑦ 변이(마지막 줄만 봄) → ① 출력 달라짐: «${out:-<없음 rc=1>}»"

# 사본 동일(바이트·실행 비트)
for n in ft-jsonl-last-ts.py ft-nano-close.sh; do
  cmp -s "$TRK/$n" "$KIT/$n" && [ "$(stat -f %Lp "$TRK/$n")" = "$(stat -f %Lp "$KIT/$n")" ] && ok "키트 사본 $n" || bad "키트 사본 불일치 $n"
done

echo "FAIL=$fail"; [ "$fail" = 0 ]
