#!/usr/bin/env bash
# test_zombie_clean_prune_retired_handshake_r1172.sh — tmux_prune 은 명부 은퇴(_closed) 좌석을 kill 하기 직전에
#   `mbox.sh close-check <좌석>`([인계] 뒤 후계 [레디] 항목 전부 «받음»)을 묻고 CLOSE-OK 일 때만 kill 한다 (r1172 · 실사건 #136).
# 반례 R1~R5(카드 동결) · 가짜 tmux/pgrep/ps/tmuxc + 임시 HOME · 임시 명부 루트(가짜 comm/mbox.sh) · 임시 재개 기록 —
#   실 tmux·실 명부·실 우편함 0 · 자기 재호출 0 · 고정 sleep 0. 시험 대상은 ZC_SCRIPT 로 바꿀 수 있다(변이 확인용).
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
ZC="${ZC_SCRIPT:-$HERE/../../harness/kit/zombie-clean/zombie-clean.sh}"
fail=0; pass=0
ok()  { echo "PASS $1"; pass=$((pass+1)); }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
expect() { [ "$3" = "$2" ] && ok "$1" || bad "$1 → 기대 [$2] · 실제 [$3]"; }

bash -n "$ZC" || { echo "FAIL bash -n $ZC"; exit 1; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FAKE="$TMP/fakebin"; FIX="$TMP/fixture"; RECD="$TMP/rec"; mkdir -p "$FAKE" "$TMP/home" "$RECD" "$TMP/cwd"

# 스텁 tmux — fixture 한 줄 = `이름 입력idle분 attached(0|1)` · kill-session 은 파일에 적기만 한다
cat > "$FAKE/tmux" <<'EOF'
#!/usr/bin/env bash
now=$(date +%s)
case "$1" in
  list-sessions) while read -r n idle att _; do [ -z "$n" ] && continue; echo "$n|$((now - idle*60))|$att"; done < "$FIXTURE" ;;
  list-panes) echo 8000 ;;
  display)
    case "${5:-}" in
      '#{pane_current_path}'*) printf '%s\n' "${FIXCWD:-}" ;;
      '#{pane_pid}'*) n="${4#=}"; n="${n%:}"; printf '%s\t%s:@1.%%1\n' 8000 "$n" ;;
    esac ;;
  kill-session) echo "kill $*" >> "$TMP_KILLLOG" ;;
  has-session) n="${3#=}"; grep -qE "^$n " "$FIXTURE" && exit 0; exit 1 ;;
esac
exit 0
EOF
printf '#!/usr/bin/env bash\nif [ "$1" = "-P" ] && [ "$2" = 8000 ]; then echo 4242; exit 0; fi\nexec /usr/bin/pgrep "$@"\n' > "$FAKE/pgrep"
printf '#!/usr/bin/env bash\n[ "$2" = "lstart=" ] && { echo "Mon Jan  1 00:00:00 2001"; exit 0; }\n[ "$2" = "comm=" ] && { echo /u/.local/bin/claude; exit 0; }\n[ "$4" = "4242" ] && { echo "claude"; exit 0; }\nexec /bin/ps "$@"\n' > "$FAKE/ps"
printf '#!/usr/bin/env bash\nexit 0\n' > "$FAKE/tmuxc"
chmod +x "$FAKE/tmux" "$FAKE/pgrep" "$FAKE/ps" "$FAKE/tmuxc"

# 검증된 재개 기록(ft-seat-retire 가 쓰는 꼴) — 순번 2 보존을 푸는 조건(판정 1344)
mkrec() { # <세션명>
  local n="$1" u; u="u-$(printf '%s' "$1" | tr -c 'A-Za-z0-9' '-')"; : > "$TMP/cwd/$u.jsonl"
  printf '{"name":"%s","engine":"claude","pid":4242,"uuid":"%s","jsonl":"%s","cwd":"%s","model":"m1","retired_by":"x","at":"t","binding":{"session":"%s","window":"@1","pane":"%%1","pid":4242,"lstart":"Mon Jan  1 00:00:00 2001","source":"tmux-col"}}' \
    "$n" "$u" "$TMP/cwd/$u.jsonl" "$TMP/cwd" "$n" > "$RECD/$n.json"
}
# 명부 루트 — seats.json 본문 + (선택) 가짜 comm/mbox.sh: 인자를 CC_LOG 에 적고 mode 대로 rc·줄을 낸다
mkroot() { # <폴더> <seats JSON> [rc0|rc3|rc2|none]
  local d="$TMP/$1"; mkdir -p "$d/.fable-team/comm"; printf '%s\n' "$2" > "$d/.fable-team/seats.json"
  case "${3:-none}" in
    none) ;;
    *) cat > "$d/.fable-team/comm/mbox.sh" <<EOF
#!/usr/bin/env bash
echo "\$*" >> "$TMP/cc.log"
case "$3" in
  rc0) echo "CLOSE-OK \$2 [인계] #11 → [레디] #12 항목 2 전부 받음"; exit 0 ;;
  rc3) echo "REJECT \$2 [인계] 없음 — bash mbox.sh handover \$2 RT#2"; exit 3 ;;
  rc2) echo "boom" >&2; exit 2 ;;
esac
EOF
    ;;
  esac
  echo "$d"
}
# run <명부 루트> <fixture> [--dry-run] → kill-session 기록 수 (출력 = $TMP/out · close-check 호출 = $TMP/cc.log)
run() {
  local root="$1" body="$2"; shift 2
  printf '%s\n' "$body" > "$FIX"; : > "$TMP/kill.log"; : > "$TMP/cc.log"
  env HOME="$TMP/home" PATH="$FAKE:$PATH" FIXTURE="$FIX" FIXCWD="$TMP/cwd" ZC_CLAUDE_PROJECTS="$TMP/projects" TMP_KILLLOG="$TMP/kill.log" \
      ZC_TMUX_IDLE_MIN=120 ZC_RESUME_DIR="$RECD" ZC_ROSTER_ROOT="$root" \
      ZC_JETS_CMD=true ZC_P_SWAP_RED=999999 ZC_P_JETS_RED=999999 ZC_P_COMP_RED=999999 ZC_P_SWAP_YEL=0 \
      bash "$ZC" tmux-prune "$@" > "$TMP/out" 2>&1
  grep -c '^kill' "$TMP/kill.log" | tr -d ' '
}
RETIRED='{"_master": "RT#2", "RT#2": {"role": "master"}, "RT#1": {"role": "master", "_closed": "2026-10-30 17:06 은퇴"}}'
SEATS='RT#2 1 0
RT#1 512 0'

# R1 — 은퇴 + close-check REJECT(rc3) → kill 0 · «승계 마무리 전» keep 1줄 (변이: 관문 삭제 → kill 1 = FAIL)
rm -f "$RECD"/*; mkrec 'RT#1'
R1="$(mkroot r1 "$RETIRED" rc3)"
expect "R1 은퇴 + REJECT → kill-session 0" "0" "$(run "$R1" "$SEATS")"
expect "R1 keep 줄 1" "1" "$(grep -c '  tmux keep RT#1 (승계 마무리 전: REJECT RT#1 \[인계\] 없음' "$TMP/out")"
expect "R1 close-check 호출 = close-check RT#1" "close-check RT#1" "$(cat "$TMP/cc.log")"

# R2 — 같은 상황 · CLOSE-OK(rc0) → kill 1 (지금과 같음)
R2="$(mkroot r2 "$RETIRED" rc0)"
expect "R2 은퇴 + CLOSE-OK → kill-session 1" "1" "$(run "$R2" "$SEATS")"
grep -q 'tmux kill RT#1 ' "$TMP/out" && ok "R2 kill 줄" || bad "R2 kill 줄 없음: $(cat "$TMP/out")"

# R3 — 도구 없음 · rc 2 → kill 0 · «판정 불가: close-check rc=<n>» 1줄
R3A="$(mkroot r3a "$RETIRED" none)"
expect "R3a 도구 없음 → kill-session 0" "0" "$(run "$R3A" "$SEATS")"
expect "R3a 판정 불가 줄 1" "1" "$(grep -cE '  tmux keep RT#1 \(판정 불가: close-check rc=[0-9]+\)' "$TMP/out")"
R3B="$(mkroot r3b "$RETIRED" rc2)"
expect "R3b rc 2 → kill-session 0" "0" "$(run "$R3B" "$SEATS")"
expect "R3b 판정 불가 rc=2 줄 1" "1" "$(grep -c '  tmux keep RT#1 (판정 불가: close-check rc=2)' "$TMP/out")"

# R4 — 은퇴 아닌 옛 세대(명부에 없음 · keep 밖 · idle ≥ 임계) → close-check 호출 0 · kill 1
rm -f "$RECD"/*
SLUG="$(printf '%s' "$TMP/cwd" | tr '/.' '--')"; mkdir -p "$TMP/projects/$SLUG"   # 은퇴 아닌 좌석은 jsonl 활동 판정을 탄다 — 999분 전(활동 없음)
printf '{"type":"summary","agentName":"NR#1"}\n' > "$TMP/projects/$SLUG/nr1.jsonl"; touch -t "$(date -v-999M '+%Y%m%d%H%M')" "$TMP/projects/$SLUG/nr1.jsonl"
R4="$(mkroot r4 '{}' rc3)"
expect "R4 은퇴 아님 → kill-session 1" "1" "$(run "$R4" 'NR#3 1 0
NR#2 512 0
NR#1 512 0')"
expect "R4 close-check 호출 0" "0" "$(grep -c . "$TMP/cc.log" | tr -d ' ')"

# R5 — --dry-run · R1 상황 → kill-session 0 · «승계 마무리 전» keep 줄 · [dry] kill 줄 0
rm -f "$RECD"/*; mkrec 'RT#1'
expect "R5 dry-run kill-session 0" "0" "$(run "$R1" "$SEATS" --dry-run)"
expect "R5 dry keep 줄 1" "1" "$(grep -c '  tmux keep RT#1 (승계 마무리 전: REJECT' "$TMP/out")"
expect "R5 [dry] kill 줄 0" "0" "$(grep -c '\[dry\] tmux kill RT#1' "$TMP/out")"

total=$((pass+fail))
echo "$pass/$total PASS"
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
