#!/usr/bin/env bash
# test_ft_now_r1473.sh — ft-now.sh(r1473) 계약 시험 T1~T6 (카드 «계약↔시험 대응표» 그대로).
#   T1 상주형 «loaded · last exit 0 · state 없음» = 실패(DA 반례1) · «state=running+pid» = OK · 종료형 «exit 0» = OK
#   T2 금지 라벨 1개 loaded → ①줄 실패 · 0개 → OK
#   T3 측정 파일: 오늘 rc124 = 신선도 오늘 + 원 결과 «판정 불가 rc=124» · 3일 전 OK · 파일 없음 = 판정 불가 (DA 반례2)
#   T4 한 항목 rc≠0(스텁 exit 3) → 그 줄 «판정 불가 rc=3» · 나머지 8줄은 나온다 · 전체 rc1
#   T5 항목 스텁 sleep 9 → 그 줄 «판정 불가(시간 초과)» · 전체 25초 안 종료
#   T6 출력 ≤30줄 · 마지막 줄 `실패 N · 판정 불가 M` · 전부 OK 입력 = rc0 · 쓰기 0(폴더 mtime 불변) · 세션 크론 = 판정 불가(세션 내부)
# 전부 합성(임시 루트·가짜 launchctl/tmux/hil·합성 명부·우편함·측정 파일) · 실 launchctl·실 명부·실 우편함·실 tmux 쓰기 0 · sleep 은 T5 스텁만.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
S="$HERE/../bin/ft-now.sh"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
[ -f "$S" ] || { echo "FAIL ft-now.sh 없음: $S"; echo "FAILED 1"; exit 1; }
bash -n "$S" && ok "bash -n" || bad "bash -n"

NOW=1794138422                                  # 고정 시각(2026-11-08 20:47 KST) — 시계 의존 0
TODAY="$(date -r "$NOW" +%Y-%m-%d 2>/dev/null || date -d "@$NOW" +%Y-%m-%d)"
FB='com.t.f1 com.t.f2 com.t.f3'                  # 금지 라벨 대역
RS='com.t.r1 com.t.r2'                           # 상주형 대역
OS='com.t.o1 com.t.o2'                           # 종료형 대역
mkdir -p "$T/fakebin" "$T/state/events" "$T/la" "$T/root/.fable-team/comm" "$T/root/.fable-team/state"

# 가짜 launchctl: gui/<uid>/<label> → $T/lc.conf 의 kind(running|exited0|nopid|absent|error:N)
cat > "$T/fakebin/launchctl" <<'EOS'
#!/usr/bin/env bash
l="${2##*/}"
[ -n "${FAKE_LC_LOG:-}" ] && printf '%s\n' "$l" >> "$FAKE_LC_LOG"
k="$(awk -F'|' -v l="$l" '$1==l{print $2; exit}' "${FAKE_LC_CONF:-/dev/null}")"
case "${k:-absent}" in
  running) printf '%s\n' "$l"; printf '\tstate = running\n\tpid = 4242\n\tlast exit code = (never exited)\n'; exit 0;;
  exited0) printf '%s\n' "$l"; printf '\tstate = not running\n\tlast exit code = 0\n'; exit 0;;
  exited*) printf '%s\n' "$l"; printf '\tstate = not running\n\tlast exit code = %s\n' "${k#exited}"; exit 0;;
  nopid) printf '%s\n' "$l"; printf '\tstate = not running\n\tlast exit code = 0\n'; exit 0;;   # loaded·exit0·state 없음 = DA 반례1
  error:*) echo "Bootstrap failed: input/output error" >&2; exit "${k#error:}";;
  *) echo "Could not find service \"$l\" in domain for user gui: 501" >&2; exit 113;;
esac
EOS
# 가짜 tmux: ls = $T/tmux.ls 그대로
cat > "$T/fakebin/tmux" <<'EOS'
#!/usr/bin/env bash
shift || true
cat "${FAKE_TMUX_LS:-/dev/null}" 2>/dev/null; exit 0
EOS
# 가짜 ft-harness-info.sh: $T/info.txt · 가짜 ft-seat-status.sh: $T/seatst.txt
cat > "$T/fakebin/info.sh" <<'EOS'
#!/usr/bin/env bash
cat "${FAKE_INFO:-/dev/null}" 2>/dev/null; exit "${FAKE_INFO_RC:-0}"
EOS
cat > "$T/fakebin/seatst.sh" <<'EOS'
#!/usr/bin/env bash
cat "${FAKE_SEATST:-/dev/null}" 2>/dev/null; exit 0
EOS
# 가짜 ft-name-lint.sh: FAKE_LINT_REJECT 에 이름이 들어 있으면 REJECT rc1
cat > "$T/fakebin/lint.sh" <<'EOS'
#!/usr/bin/env bash
case " ${FAKE_LINT_REJECT:-} " in *" $1 "*) echo "REJECT 역할 'x' 은 예약어가 아니다"; exit 1;; esac
exit 0
EOS
cat > "$T/fakebin/hil.sh" <<'EOS'
#!/usr/bin/env bash
[ -n "${FAKE_HIL_RC:-}" ] && exit "$FAKE_HIL_RC"
[ -n "${FAKE_HIL_SLEEP:-}" ] && sleep "$FAKE_HIL_SLEEP"
cat "${FAKE_HIL:-/dev/null}" 2>/dev/null; exit 0
EOS
chmod +x "$T/fakebin/launchctl" "$T/fakebin/tmux" "$T/fakebin/info.sh" "$T/fakebin/seatst.sh" "$T/fakebin/lint.sh" "$T/fakebin/hil.sh"   # 픽스처만 실행 비트

# 카드 대역 = 팀 체크아웃($ROOT/.worktrees/harness-ops) 안의 _cards 3폴더 · git repo 는 FETCH_HEAD 나이용
CW="$T/root/.worktrees/harness-ops/design/harness/indices"
mkdir -p "$CW/대기" "$CW/진행" "$CW/완성"
for i in 1 2; do echo "# card $i" > "$CW/대기/c$i.md"; done
echo "# card j" > "$CW/진행/cj.md"
for i in 1 2 3; do echo "# done $i" > "$CW/완성/d$i.md"; done
git -C "$T/root" init -q 2>/dev/null
git -C "$T/root" -c user.email=t@t -c user.name=t add -A >/dev/null 2>&1
git -C "$T/root" -c user.email=t@t -c user.name=t commit -qm base >/dev/null 2>&1
git -C "$T/root" update-ref refs/remotes/origin/main HEAD 2>/dev/null
: > "$T/root/.git/FETCH_HEAD"

# 명부 대역 — harness 한 팀(master·arch·desk)
M_S='byz-t-master-claude#7'; A_S='byz-t-arch-claude#8'; D_S='byz-t-desk-claude#9'
printf '{"_master":"%s","_arch":"%s","_desk":"%s","_cards":"design/harness/indices","_cards_wt":"harness-ops","_label":"t"}\n' \
  "$M_S" "$A_S" "$D_S" > "$T/root/.fable-team/seats-t.json"
: > "$T/root/.fable-team/comm/mailbox.jsonl"
printf '%s: 1 windows\n%s: 1 windows\n' "$M_S" "$A_S" > "$T/tmux.ls"
printf '%s                                PASS\n' "$M_S" > "$T/info.txt"
: > "$T/seatst.txt"
printf '미실행 h 1개 · 가장 오래된 12분 · 보류 0개\n' > "$T/hil.txt"
printf '{"claude":{"until":%s,"release_at":%s}}\n' "$((NOW-3600))" "$((NOW-3600))" > "$T/pause-expired.json"
printf '{"claude":{"until":%s,"release_at":%s}}\n' "$((NOW+3600))" "$((NOW+3600))" > "$T/pause-active.json"

# 기본 lc.conf = 전부 정상(금지 absent · 상주 running · 종료 exited0)
{ for l in $FB; do echo "$l|absent"; done; for l in $RS; do echo "$l|running"; done; for l in $OS; do echo "$l|exited0"; done; } > "$T/lc.conf"
printf 'ts=1 rc=0 ok\n' > "$T/state/events/$TODAY.tsv"
printf 'ts=1 a=0 b=0\n' > "$T/state/postboot-measure.tsv"
printf 'WASTE ok rewrite=10%%\n' > "$T/state/waste-check.log"

run() {
  env FT_NOW_ROOT="$T/root" FT_NOW_STATE="$T/state" \
      FT_NOW_LAUNCHCTL="$T/fakebin/launchctl" FT_NOW_TMUX="$T/fakebin/tmux" \
      FT_NOW_FORBIDDEN="$FB" FT_NOW_RESIDENT="$RS" FT_NOW_ONESHOT="$OS" \
      FT_NOW_ACCT_PAUSE="${FAKE_PAUSE:-$T/pause-expired.json}" FT_NOW_LAUNCHAGENTS="$T/la" \
      FT_NOW_HARNESS_INFO="$T/fakebin/info.sh" FT_NOW_SEAT_STATUS="$T/fakebin/seatst.sh" \
      FT_NOW_NAME_LINT="$T/fakebin/lint.sh" \
      FT_NOW_HIL="$T/fakebin/hil.sh" FT_NOW_MBOX_JSONL="$T/root/.fable-team/comm/mailbox.jsonl" \
      FT_NOW_SEATS_DIR="$T/root/.fable-team" \
      FT_NOW_EVENTS_DIR="$T/state/events" FT_NOW_POSTBOOT="$T/state/postboot-measure.tsv" \
      FT_NOW_WASTE_LOG="$T/state/waste-check.log" FT_NOW_NOW="$NOW" FT_NOW_UID=501 \
      FAKE_LC_CONF="$T/lc.conf" FAKE_TMUX_LS="$T/tmux.ls" FAKE_INFO="$T/info.txt" \
      FAKE_SEATST="$T/seatst.txt" FAKE_HIL="$T/hil.txt" \
      ${FAKE_LC_LOG:+FAKE_LC_LOG="$FAKE_LC_LOG"} ${FAKE_LINT_REJECT:+FAKE_LINT_REJECT="$FAKE_LINT_REJECT"} \
      ${FAKE_HIL_RC:+FAKE_HIL_RC="$FAKE_HIL_RC"} ${FAKE_HIL_SLEEP:+FAKE_HIL_SLEEP="$FAKE_HIL_SLEEP"} \
      bash "$S" 2>&1
}
item_of() { printf '%s\n' "$1" | grep -F -- "$2 | " | head -1; }   # 항목 줄 1개

# ── T6-a 전부 OK 입력 = rc0 · ≤30줄 · 마지막 줄 꼴 · 9항 · 세션 크론 고정
t0="$(date +%s)"
out="$(run)"; rc=$?
el=$(( $(date +%s) - t0 ))
n="$(printf '%s\n' "$out" | wc -l | tr -d ' ')"
[ "$rc" -eq 0 ] && ok "T6 전부 OK → rc0" || bad "T6 rc=$rc out=$(printf '%s' "$out" | tr '\n' '/')"
[ "${n:-99}" -le 30 ] && ok "T6 출력 ${n}줄 ≤30" || bad "T6 출력 ${n}줄 >30"
[ "$el" -le 25 ] && ok "T6 소요 ${el}초 ≤25" || bad "T6 소요 ${el}초 >25"
printf '%s\n' "$out" | tail -1 | grep -qx '실패 0 · 판정 불가 0' && ok "T6 마지막 줄 «실패 0 · 판정 불가 0»" || bad "T6 마지막 줄: $(printf '%s\n' "$out" | tail -1)"
miss=""
for k in "모델 깨우는 주기 잡" "bash 허용 잡" "정지 의도 vs 스위치" "좌석" "우편함" "카드" "h" "마지막 측정" "세션 크론"; do
  printf '%s\n' "$out" | grep -qF -- "$k | " || miss="$miss $k"
done
[ -z "$miss" ] && ok "T6 항목 9줄 전부" || bad "T6 항목 줄 없음:$miss"
item_of "$out" "세션 크론" | grep -q '판정 불가(세션 내부)' && ok "T6 세션 크론 = 판정 불가(세션 내부) 고정" || bad "T6 세션 크론 줄: $(item_of "$out" "세션 크론")"
item_of "$out" "세션 크론" | grep -q '집계' && bad "T6 세션 크론이 집계에 섞였다" || ok "T6 세션 크론은 집계 제외"
printf '%s\n' "$out" | grep -qE '^[^|]+ \| [^|]+ \| (OK|실패|판정 불가[^|]*) \| [^|]+$' && ok "T6 줄 꼴 «항목 | 값 | 판정 | 담당»" || bad "T6 줄 꼴 위반"

# ── T6-b 쓰기 0 — 두 번 돌려도 폴더 mtime·파일 수 불변
before="$(stat -f '%m %z' "$T/root/.fable-team/comm/mailbox.jsonl" 2>/dev/null)$(ls "$T/state" | tr '\n' ',')"
run >/dev/null 2>&1
after="$(stat -f '%m %z' "$T/root/.fable-team/comm/mailbox.jsonl" 2>/dev/null)$(ls "$T/state" | tr '\n' ',')"
[ "$before" = "$after" ] && ok "T6 쓰기 0(우편함·상태 폴더 불변)" || bad "T6 파일이 바뀌었다: $before → $after"

# ── T1 상주형 판정 — «loaded · exit0 · state 없음» 은 실패(DA 반례1) · running+pid 는 OK · 종료형 exit0 은 OK
printf '%s|nopid\n' com.t.r1 > "$T/lc.conf.nopid"
{ cat "$T/lc.conf" | grep -v '^com.t.r1|'; echo 'com.t.r1|nopid'; } > "$T/lc.conf.x"; mv "$T/lc.conf.x" "$T/lc.conf"
out="$(run)"; rc=$?
b="$(item_of "$out" "bash 허용 잡")"
printf '%s' "$b" | grep -q '실패' && ok "T1 state·pid 없는 상주형 = 실패" || bad "T1 반례1 미탐지: $b"
printf '%s' "$b" | grep -q 'com.t.r1' && ok "T1 실패한 라벨 이름을 값에 남긴다" || bad "T1 라벨 이름 없음: $b"
[ "$rc" -eq 1 ] && ok "T1 상주형 실패 → 전체 rc1" || bad "T1 rc=$rc"
{ cat "$T/lc.conf" | grep -v '^com.t.r1|'; echo 'com.t.r1|running'; } > "$T/lc.conf.x"; mv "$T/lc.conf.x" "$T/lc.conf"
out="$(run)"; rc=$?
[ "$rc" -eq 0 ] && ok "T1 running+pid 복귀 → rc0" || bad "T1 복귀 rc=$rc b=$(item_of "$out" "bash 허용 잡")"
{ cat "$T/lc.conf" | grep -v '^com.t.o1|'; echo 'com.t.o1|exited5'; } > "$T/lc.conf.x"; mv "$T/lc.conf.x" "$T/lc.conf"
out="$(run)"; rc=$?
printf '%s' "$(item_of "$out" "bash 허용 잡")" | grep -q '실패' && ok "T1 종료형 last exit 5 = 실패" || bad "T1 종료형 오판: $(item_of "$out" "bash 허용 잡")"
printf '%s' "$(item_of "$out" "bash 허용 잡")" | grep -q 'com.t.o1' && ok "T1 종료형 위반 라벨 이름 표시" || bad "T1 종료형 라벨명 없음"
{ cat "$T/lc.conf" | grep -v '^com.t.o1|'; echo 'com.t.o1|exited0'; } > "$T/lc.conf.x"; mv "$T/lc.conf.x" "$T/lc.conf"

# ── T2 금지 라벨 1개 loaded → ①줄 실패 · 0개 → OK
{ cat "$T/lc.conf" | grep -v '^com.t.f2|'; echo 'com.t.f2|running'; } > "$T/lc.conf.x"; mv "$T/lc.conf.x" "$T/lc.conf"
out="$(run)"; rc=$?
printf '%s' "$(item_of "$out" "모델 깨우는 주기 잡")" | grep -q '실패' && ok "T2 금지 라벨 loaded = 실패" || bad "T2 미탐지: $(item_of "$out" "모델 깨우는 주기 잡")"
printf '%s' "$(item_of "$out" "모델 깨우는 주기 잡")" | grep -q 'com.t.f2' && ok "T2 로드된 라벨 이름 표시" || bad "T2 라벨명 없음"
{ cat "$T/lc.conf" | grep -v '^com.t.f2|'; echo 'com.t.f2|absent'; } > "$T/lc.conf.x"; mv "$T/lc.conf.x" "$T/lc.conf"
out="$(run)"; rc=$?
[ "$rc" -eq 0 ] && ok "T2 금지 라벨 0 = OK" || bad "T2 0개인데 rc=$rc: $(item_of "$out" "모델 깨우는 주기 잡")"

# ── T7 카드 = 팀 체크아웃(_cards_wt)에서 센다(main 0 오판 금지) · 못 읽으면 0 이 아니라 판정 불가
out="$(run)"; rc=$?
b="$(item_of "$out" "카드")"
printf '%s' "$b" | grep -q '대기 2 · 진행 1 · 완성 3' && ok "T7 _cards_wt 아래 카드 수(대기2·진행1·완성3)" || bad "T7 카드 줄: $b"
printf '%s' "$b" | grep -q 'OK' && ok "T7 읽을 수 있으면 OK" || bad "T7 판정: $b"
printf '{"_master":"%s","_arch":"%s","_cards":"design/harness/indices","_cards_wt":"gone-wt","_label":"t"}\n' \
  "$M_S" "$A_S" > "$T/root/.fable-team/seats-t.json"
out="$(run)"; rc=$?
b="$(item_of "$out" "카드")"
printf '%s' "$b" | grep -q '판정 불가' && ok "T7 못 읽는 팀 = 판정 불가(0 치환 금지)" || bad "T7 0 치환: $b"
printf '%s' "$b" | grep -q '못 읽은 팀' && ok "T7 못 읽은 팀 이름 표시" || bad "T7 팀명 없음: $b"
printf '{"_master":"%s","_arch":"%s","_desk":"%s","_cards":"design/harness/indices","_cards_wt":"harness-ops","_label":"t"}\n' \
  "$M_S" "$A_S" "$D_S" > "$T/root/.fable-team/seats-t.json"   # 원복

# T7b 진행 > (그 팀 라이브 좌석+2) = 실패 식이 실제로 돈다
for i in 2 3 4 5; do echo "# more $i" > "$CW/진행/cj$i.md"; done
out="$(run)"; rc=$?
printf '%s' "$(item_of "$out" "카드")" | grep -q '진행>좌석+2' && ok "T7b 진행>좌석+2 = 실패" || bad "T7b 미탐지: $(item_of "$out" "카드")"
for i in 2 3 4 5; do rm -f "$CW/진행/cj$i.md"; done

# ── T1d 좌석 = 이름 린트 위반이면 실패 · 없으면 PASS 수
FAKE_LINT_REJECT="bad-seat#1"
printf '%s: 1 windows\n' bad-seat#1 >> "$T/tmux.ls"
out="$(run)"; rc=$?
unset FAKE_LINT_REJECT
printf '%s' "$(item_of "$out" "좌석")" | grep -q '실패' && ok "T1d 린트 위반 좌석 = 실패" || bad "T1d 미탐지: $(item_of "$out" "좌석")"
printf '%s' "$(item_of "$out" "좌석")" | grep -q 'bad-seat#1' && ok "T1d 위반 좌석 이름 표시" || bad "T1d 이름 없음: $(item_of "$out" "좌석")"
grep -v '^bad-seat#1' "$T/tmux.ls" > "$T/tmux.ls.x"; mv "$T/tmux.ls.x" "$T/tmux.ls"
out="$(run)"; rc=$?
[ "$rc" -eq 0 ] && ok "T1d 위반 좌석 제거 → rc0" || bad "T1d 복귀 rc=$rc: $(item_of "$out" "좌석")"

# ── T1c 정지 의도 vs 스위치 — 유효 정지 + 틱 plist 살아 있음 = 실패 · plist 없으면 OK
touch "$T/la/com.t.f1.plist"
FAKE_PAUSE="$T/pause-active.json"
out="$(run)"; rc=$?
unset FAKE_PAUSE
b="$(item_of "$out" "정지 의도 vs 스위치")"
printf '%s' "$b" | grep -q '실패' && ok "T1c 정지 중인데 틱 plist 살아 있음 = 실패" || bad "T1c 미탐지: $b"
rm -f "$T/la/com.t.f1.plist"
FAKE_PAUSE="$T/pause-active.json"
out="$(run)"; rc=$?
unset FAKE_PAUSE
printf '%s' "$(item_of "$out" "정지 의도 vs 스위치")" | grep -q 'OK' && ok "T1c 정지 + plist 0 = OK" || bad "T1c: $(item_of "$out" "정지 의도 vs 스위치")"

# ── T4 한 항목 rc≠0(스텁 exit 3) → 그 줄 «판정 불가 rc=3» · 나머지 8줄 계속 · rc1
{ cat "$T/lc.conf" | grep -v '^com.t.f1|'; echo 'com.t.f1|error:3'; } > "$T/lc.conf.x"; mv "$T/lc.conf.x" "$T/lc.conf"
out="$(run)"; rc=$?
[ "$rc" -eq 1 ] && ok "T4 항목 조회 실패 → rc1" || bad "T4 rc=$rc"
item_of "$out" "모델 깨우는 주기 잡" | grep -q '판정 불가 rc=3' && ok "T4 «판정 불가 rc=3»" || bad "T4 줄: $(item_of "$out" "모델 깨우는 주기 잡")"
n9="$(printf '%s\n' "$out" | grep -c ' | ')"
[ "$n9" -ge 9 ] && ok "T4 나머지 항목 ${n9}줄 계속" || bad "T4 항목 줄 ${n9}개"
item_of "$out" "카드" | grep -q 'OK' && ok "T4 다른 항목(카드)은 정상 판정" || bad "T4 카드: $(item_of "$out" "카드")"
{ cat "$T/lc.conf" | grep -v '^com.t.f1|'; echo 'com.t.f1|absent'; } > "$T/lc.conf.x"; mv "$T/lc.conf.x" "$T/lc.conf"

# ── T3 측정 파일 — 오늘 rc124 = 신선도 오늘 + 원 결과 «판정 불가 rc=124»(집계 포함) · 3일 전 OK · 없음 = 판정 불가
printf 'ts=1 rc=124 timeout\n' > "$T/state/events/$TODAY.tsv"
old="$(date -r "$((NOW-3*86400))" +%Y%m%d%H%M 2>/dev/null || date -d "@$((NOW-3*86400))" +%Y%m%d%H%M)"
printf 'ts=old rc=0 ok\n' > "$T/state/postboot-measure.tsv"; touch -t "$old" "$T/state/postboot-measure.tsv"
out="$(run)"; rc=$?
b="$(item_of "$out" "마지막 측정")"
printf '%s' "$b" | grep -q '판정 불가 rc=124' && ok "T3 오늘 rc124 = 원 결과 «판정 불가 rc=124»" || bad "T3 rc124 미표시: $b"
printf '%s' "$b" | grep -q '신선도=오늘' && ok "T3 신선도 칸이 따로 있다(오늘)" || bad "T3 신선도 없음: $b"
printf '%s' "$b" | grep -q '3일 전' && ok "T3 3일 전 파일 = 신선도 3일 전" || bad "T3 3일 전 미표시: $b"
[ "$rc" -eq 1 ] && ok "T3 실패·불가가 있으면 rc1" || bad "T3 rc=$rc"
printf '%s\n' "$out" | tail -1 | grep -qE '판정 불가 [1-9]' && ok "T3 불가 수에 포함(오늘 날짜에 가려지지 않는다)" || bad "T3 집계: $(printf '%s\n' "$out" | tail -1)"
printf 'ts=1 rc=0 ok\n' > "$T/state/events/$TODAY.tsv"; rm -f "$T/state/postboot-measure.tsv" "$T/state/waste-check.log"
out="$(run)"; rc=$?
b="$(item_of "$out" "마지막 측정")"
printf '%s' "$b" | grep -q 'postboot 신선도=없음' && ok "T3 파일 없음 = 신선도 없음" || bad "T3 없음 미표시: $b"
printf '%s' "$b" | grep -q '판정 불가' && ok "T3 파일 없음 = 판정 불가" || bad "T3 없음 판정: $b"
printf 'ts=1 a=0 b=0\n' > "$T/state/postboot-measure.tsv"; printf 'WASTE ok rewrite=10%%\n' > "$T/state/waste-check.log"

# ── T5 항목 스텁 sleep 9 → «판정 불가(시간 초과)» · 전체 25초 안
t0="$(date +%s)"
FAKE_HIL_SLEEP=9
out="$(run)"; rc=$?
unset FAKE_HIL_SLEEP
el=$(( $(date +%s) - t0 ))
item_of "$out" "h" | grep -q '판정 불가(시간 초과)' && ok "T5 sleep 9 = «판정 불가(시간 초과)»" || bad "T5 줄: $(item_of "$out" "h")"
[ "$el" -le 25 ] && ok "T5 소요 ${el}초 ≤25" || bad "T5 소요 ${el}초 >25"
[ "$rc" -eq 1 ] && ok "T5 시간 초과 → rc1" || bad "T5 rc=$rc"
item_of "$out" "카드" | grep -q 'OK' && ok "T5 다른 항목은 계속 돈다" || bad "T5 카드: $(item_of "$out" "카드")"

[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "FAILED $fail"
exit "$fail"
