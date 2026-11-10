#!/usr/bin/env bash
# test_anchor_a_request_log_r1571.sh — 카드 r1571 시험 (알림 · 크기 경보 · 전환 추출 · 변이 M1·M3·M4·M5·M10 · 비밀 0)
#   격리 HOME · 가짜 로그 · 가짜 시계(FT_ANCHOR_NOW) · 가짜 mbox(보낸 본문만 기록) · 가짜 seats.json — 실 우편함·실 로그에 쓰지 않는다.
#   실행: bash feature-pack/fable-team/legacy/1.x/harness/tests/test_anchor_a_request_log_r1571.sh   (실행 비트 불필요)
set -uo pipefail
T="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
B="$T/../bin"; S="$B/ft-anchor-a-request-log.sh"; P="$B/ft-anchor-a-request-log.plist"
D="$T/../docs/h-r1571-anchor-a-account-request-log.md"
END=1794888000; PASS=0; FAIL=0; W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
ok(){ PASS=$((PASS+1)); printf 'OK   %s\n' "$1"; }
no(){ FAIL=$((FAIL+1)); printf 'FAIL %s\n' "$1"; }
chk(){ if [ "$2" = "$3" ]; then ok "$1"; else no "$1 (기대 «$3» · 실제 «$2»)"; fi }

mkdir -p "$W/logs" "$W/state"
printf '{"_desk":"seat-desk#0","_hil_route":"seat-plan#0"}' > "$W/seats.json"
SENT="$W/sent.tsv"; : > "$SENT"
cat > "$W/mbox.sh" <<EOF
#!/usr/bin/env bash
printf '%s\t%s\n' "\$2" "\$4" >> "$SENT"
EOF
count(){ wc -l < "$SENT" | tr -d ' '; }
reset_sent(){ : > "$SENT"; }
OUT="$W/state/anchor-a-transitions.tsv"
run(){ FT_ANCHOR_NOW="$1" FT_ANCHOR_MBOX="$W/mbox.sh" FT_ANCHOR_SEATS="$W/seats.json" FT_ANCHOR_LOGS="$W/logs" \
       FT_ANCHOR_STATE_DIR="$W/state" FT_ANCHOR_DONE="$W/state/anchor-a-done" FT_ANCHOR_CAP_MB="${2:-1024}" \
       FT_ANCHOR_ME=seat-test bash "$S" >"$W/out" 2>"$W/err"; }
A(){ printf '%s Use OAuth a@x for model m\n' "$1" >> "$W/logs/main-2026-11-10.log"; }
B(){ printf '%s Use OAuth b@y for model m\n' "$1" >> "$W/logs/main-2026-11-10.log"; }

# ── ① 끝 시각 전: 요청 알림 0 · 로그는 읽기만 ───────────────────────────────
A 2026-11-10T10:00:00; A 2026-11-10T10:01:00; B 2026-11-10T10:02:00; B 2026-11-10T10:03:00; B 2026-11-10T10:04:00
SUM_BEFORE="$(cksum < "$W/logs/main-2026-11-10.log")"; MT_BEFORE="$(stat -f%m "$W/logs/main-2026-11-10.log")"
chk "상태 파일 없음 → 상태 폴더 생성" "$( [ -d "$W/state" ] && echo y )" "y"
run $((END-3600)); chk "끝 시각 전 — 발신 0" "$(count)" 0
chk "로그 내용 보존(추출은 읽기만)" "$(cksum < "$W/logs/main-2026-11-10.log")" "$SUM_BEFORE"
chk "로그 mtime 보존" "$(stat -f%m "$W/logs/main-2026-11-10.log")" "$MT_BEFORE"

# ── ④ 전환 추출: 계정이 바뀐 첫 줄만 1행 (M4) ───────────────────────────────
chk "전환 행 1개(같은 계정 연속은 전환 아님)" "$(wc -l < "$OUT" 2>/dev/null | tr -d ' ')" 1
chk "전환 행 = 시각·a@x·b@y" "$(cat "$OUT")" "$(printf '2026-11-10T10:02:00\ta@x\tb@y')"
chk "추출 결과 = 일반 파일(심링크 아님)" "$( [ -f "$OUT" ] && [ ! -L "$OUT" ] && echo y )" "y"

# ── ④' 실제 로그 형식(DA #279622 반례) = «Use OAuth provider=<p> auth_file=<계정> for model» ──
rm -rf "$W/real"; mkdir -p "$W/real/logs" "$W/real/state"
R(){ printf '%s Use OAuth provider=claude auth_file=%s for model m\n' "$1" "$2" >> "$W/real/logs/main-2026-11-10.log"; }
runreal(){ FT_ANCHOR_NOW="$1" FT_ANCHOR_MBOX="$W/mbox.sh" FT_ANCHOR_SEATS="$W/seats.json" FT_ANCHOR_LOGS="$W/real/logs" \
  FT_ANCHOR_STATE_DIR="$W/real/state" FT_ANCHOR_DONE="$W/real/state/anchor-a-done" FT_ANCHOR_ME=seat-test bash "$S" >"$W/real/out" 2>"$W/real/err"; }
ROUT="$W/real/state/anchor-a-transitions.tsv"
R 2026-11-10T13:00:00 a@x; R 2026-11-10T13:01:00 a@x; R 2026-11-10T13:02:00 b@y
reset_sent; runreal $((END-6000))
chk "실제 형식 — 추출 ERROR 0" "$(grep -c ERROR "$W/real/err" 2>/dev/null | tr -d ' ')" 0
chk "실제 형식 A→B = 전환 1행(같은 계정 연속 0)" "$(wc -l < "$ROUT" 2>/dev/null | tr -d ' ')" 1
chk "실제 형식 전환 행 = 시각·a@x·b@y" "$(cat "$ROUT" 2>/dev/null)" "$(printf '2026-11-10T13:02:00\ta@x\tb@y')"
# 옛 형식과 실제 형식이 같은 계정이면 전환 0 (두 파서가 같은 계정 이름으로 정규화)
rm -rf "$W/mix"; mkdir -p "$W/mix/logs" "$W/mix/state"
{ printf '2026-11-10T14:00:00 Use OAuth a@x for model m\n'
  printf '2026-11-10T14:01:00 Use OAuth provider=claude auth_file=a@x for model m\n'; } > "$W/mix/logs/main-2026-11-10.log"
FT_ANCHOR_NOW=$((END-5000)) FT_ANCHOR_MBOX="$W/mbox.sh" FT_ANCHOR_SEATS="$W/seats.json" FT_ANCHOR_LOGS="$W/mix/logs" \
  FT_ANCHOR_STATE_DIR="$W/mix/state" FT_ANCHOR_DONE="$W/mix/state/anchor-a-done" FT_ANCHOR_ME=seat-test bash "$S" >/dev/null 2>"$W/mix/err"
chk "옛 형식↔실제 형식 같은 계정 = 전환 0" "$(wc -l < "$W/mix/state/anchor-a-transitions.tsv" 2>/dev/null | tr -d ' ')" 0

# ── ② 끝 시각: 요청 1통 = desk + planner 2줄 · 반복 규칙 (M1) ───────────────
reset_sent; run $END
chk "끝 시각 — desk·planner 2줄" "$(count)" 2
chk "끝 시각 — 받는이 순서" "$(cut -f1 "$SENT" | tr '\n' ' ')" "seat-desk#0 seat-plan#0 "
grep -q '앵커 A 끄기·지우기 h 실행 요청' "$SENT" && ok "요청 본문 = 끄기·지우기 h 실행 요청" || no "요청 본문"
reset_sent; run $((END+3600)); chk "끝 시각 +1시간 — 반복 0" "$(count)" 0
reset_sent; run $((END+86400-3600)); chk "24시간 직전 — 반복 0" "$(count)" 0
reset_sent; run $((END+86400)); chk "끝 시각 +24시간 — 다시 1통 (M1)" "$(count)" 2

# ── ③ 완료 표식: 해제 안내 1줄 뒤 알림·경보 0 (M10) ────────────────────────
: > "$W/state/anchor-a-done"; reset_sent; run $((END+2*86400))
chk "표식 첫 실행 — 해제 안내 1줄(desk 만)" "$(count)" 1
grep -q '앵커 A 해제' "$SENT" && ok "해제 안내 본문" || no "해제 안내 본문"
reset_sent; run $((END+3*86400)); chk "표식 이후 — 알림 0 (M10)" "$(count)" 0
head -c 870000 /dev/zero | tr '\0' 'x' > "$W/logs/main-big.log"
reset_sent; run $((END+4*86400)) 1; chk "표식 이후 — 크기 경보도 0 (M10)" "$(count)" 0
rm -f "$W/state/anchor-a-done" "$W/logs/main-big.log"

# ── 크기 경보: 80% 이상 1통 · 같은 구간 반복 0 · 내려갔다 다시 위 = 1통 (M5) ──
rm -rf "$W/logs"; mkdir -p "$W/logs"; head -c 870000 /dev/zero | tr '\0' 'x' > "$W/logs/main-big.log"
reset_sent; run $((END-7200)) 1; chk "80% 이상 — 2줄(desk·planner)" "$(count)" 2
grep -q '앵커 A 크기 경보' "$SENT" && ok "크기 경보 본문" || no "크기 경보 본문"
reset_sent; run $((END-3600)) 1; chk "같은 구간 다음 회 — 반복 0 (M5)" "$(count)" 0
printf 'x' > "$W/logs/main-big.log"; reset_sent; run $((END-3000)) 1; chk "80% 아래 — 발신 0(재무장만)" "$(count)" 0
head -c 870000 /dev/zero | tr '\0' 'y' > "$W/logs/main-big.log"
reset_sent; run $((END-2400)) 1; chk "재무장 뒤 다시 80% — 1회 더" "$(count)" 2

# ── 비밀 0 (ⓗ): API key 이름은 가리고 본문·추출에 값 0 ──────────────────────
rm -rf "$W/logs"; mkdir -p "$W/logs"
{ printf '2026-11-10T11:00:00 Use OAuth a@x for model m\n'; printf '2026-11-10T11:01:00 Use API key sk-live-SECRET for model m\n'
  printf '2026-11-10T11:02:00 Use OAuth a@x for model m\n'; } > "$W/logs/main-2026-11-10.log"
rm -f "$OUT" "$W/state/anchor-a-alert.state"; reset_sent; run $((END-5000))
if grep -q 'sk-live-SECRET' "$SENT" "$OUT" 2>/dev/null; then no "비밀 값이 본문·추출에 남음"; else ok "비밀 값 0(본문·추출)"; fi
grep -q '(api-key-id)' "$OUT" && ok "API key 이름은 (api-key-id) 로 가림" || no "API key 이름 가림"
chk "a@x→(api-key-id)→a@x = 전환 2행" "$(wc -l < "$OUT" | tr -d ' ')" 2

# ── 변이 검출 (M1·M4·M5·M10): 코드를 변이시킨 사본이 «옳은 시험» 에 걸리는지 ──────
mut(){ local d="$W/$1"; rm -rf "$d"; mkdir -p "$d/logs" "$d/state"; cp "$S" "$d/m.sh"
  sed -i '' "$2" "$d/m.sh"; printf '{"_desk":"seat-desk#0","_hil_route":"seat-plan#0"}' > "$d/seats.json"; }
runm(){ local d="$W/$1"; FT_ANCHOR_NOW="$2" FT_ANCHOR_MBOX="$W/mbox.sh" FT_ANCHOR_SEATS="$d/seats.json" FT_ANCHOR_LOGS="$d/logs" \
  FT_ANCHOR_STATE_DIR="$d/state" FT_ANCHOR_DONE="$d/state/anchor-a-done" FT_ANCHOR_CAP_MB=1 FT_ANCHOR_ME=seat-test bash "$d/m.sh" >/dev/null 2>&1; }
mut m1 's/if \[ "\$now" -ge "\$END_TS" \]/if false/'; reset_sent; runm m1 $END
chk "변이 M1(끝 시각 알림 제거) — 시험에 걸림(발신 0)" "$(count)" 0
mut m4 's/acct!=prev/1/'; printf '2026-11-10T12:00:00 Use OAuth a@x for model m\n2026-11-10T12:01:00 Use OAuth a@x for model m\n' > "$W/m4/logs/main-x.log"
reset_sent; runm m4 $((END-9000)); chk "변이 M4(같은 계정도 전환으로 셈) — 시험에 걸림(1행·정답 0행)" "$(wc -l < "$W/m4/state/anchor-a-transitions.tsv" | tr -d ' ')" 1
mut m5 's/ && \[ "\$ARMED" = 1 \]//'; head -c 870000 /dev/zero | tr '\0' 'z' > "$W/m5/logs/main-big.log"
reset_sent; runm m5 $((END-7200)); : > "$SENT"; runm m5 $((END-3600)); chk "변이 M5(같은 구간 반복) — 시험에 걸림(2줄)" "$(count)" 2
mut m10 's/\[ "\$REL" = 1 \] && exit 0/true/'; : > "$W/m10/state/anchor-a-done"
reset_sent; runm m10 $((END+86400)); : > "$SENT"; runm m10 $((END+90000)); chk "변이 M10(표식 뒤 반복) — 시험에 걸림(1줄)" "$(count)" 1

# ── DA R1 회긍: plist 가 작업 폴더·문맥 env 를 고정 — cwd=/ 에서도 발신까지 간다 ──
for k in WorkingDirectory FT_MBOX_DIR FT_ANCHOR_SEATS FT_ANCHOR_LOGS FT_ANCHOR_STATE_DIR __WORKTREE__ __COMM__ __SEATS__ __STATE__; do
  grep -qF -- "$k" "$P" && ok "plist 문맥 «${k}»" || no "plist 문맥 «${k}» 없음"
done
rm -rf "$W/r1"; mkdir -p "$W/r1/state"; reset_sent
RRC=0; ( cd / && FT_ANCHOR_NOW=$END FT_ANCHOR_MBOX="$W/mbox.sh" FT_ANCHOR_SEATS="$W/seats.json" FT_ANCHOR_LOGS="$W/r1/logs" \
  FT_ANCHOR_STATE_DIR="$W/r1/state" FT_ANCHOR_DONE="$W/r1/state/anchor-a-done" FT_ANCHOR_ME=seat-test bash "$S" >"$W/r1/out" 2>"$W/r1/err" ) || RRC=$?
chk "cwd=/ + 로그 폴더 없음 — rc0(정상 경로)" "$RRC" 0
chk "cwd=/ — 끝 시각 발신 2통" "$(count)" 2
RRC=0; ( cd / && env -u FT_MBOX_DIR -u FT_ANCHOR_MBOX -u FT_ANCHOR_SEATS -u FT_ANCHOR_LOGS -u FT_ROOT FT_ANCHOR_NOW=$END \
  FT_ANCHOR_STATE_DIR="$W/r1/state2" FT_ANCHOR_ME=seat-test bash "$S" >/dev/null 2>"$W/r1/err2" ) || RRC=$?
if [ "$RRC" != 0 ] && grep -q 'ERROR' "$W/r1/err2"; then ok "문맥 env 없이 cwd=/ — rc≠0 + ERROR(조용한 0 없음)"; else no "문맥 없음이 조용히 0 으로 끝남(rc=$RRC)"; fi

# ── DA R2 회긍: 빈 logs 에서도 상태 저장 — 1h 0통 · 24h 2통 ──────────────────
rm -rf "$W/r2"; mkdir -p "$W/r2/logs" "$W/r2/state"
r2(){ FT_ANCHOR_NOW="$1" FT_ANCHOR_MBOX="$W/mbox.sh" FT_ANCHOR_SEATS="$W/seats.json" FT_ANCHOR_LOGS="$2" \
      FT_ANCHOR_STATE_DIR="$W/r2/state" FT_ANCHOR_DONE="$W/r2/state/anchor-a-done" FT_ANCHOR_ME=seat-test bash "$S" >/dev/null 2>"$W/r2/err"; }
reset_sent; RRC=0; r2 $END "$W/r2/logs" || RRC=$?; chk "빈 logs — 끝 시각 rc0" "$RRC" 0
chk "빈 logs — 끝 시각 발신 2통" "$(count)" 2
chk "빈 logs — 상태 저장(req_sent)" "$(sed -n 's/^req_sent=//p' "$W/r2/state/anchor-a-alert.state")" "$END"
reset_sent; r2 $((END+3600)) "$W/r2/logs"; chk "빈 logs +1시간 — 0통(24h 계약 유지)" "$(count)" 0
reset_sent; r2 $((END+86400)) "$W/r2/logs"; chk "빈 logs +24시간 — 2통" "$(count)" 2
rm -f "$W/r2/state/anchor-a-alert.state"; reset_sent; RRC=0; r2 $END "$W/r2/nope" || RRC=$?
chk "로그 폴더 자체 없음 — rc0" "$RRC" 0
chk "로그 폴더 자체 없음 — 발신 2통(정상 경로)" "$(count)" 2

# ── DA R3 회긍: h 문서 복구 확인 조건 · sampler.log 정본 경로 ─────────────────
grep -qF '(debug=false)' "$D" && ok "복구 확인 조건 = debug=false 재적재 줄" || no "복구 확인 조건 문구 없음"
grep -qF '켜기 전용' "$D" && ok "켜기 조건 재사용 금지 문구" || no "켜기 조건 재사용 금지 문구 없음"
grep -qF '여기서 멈춘다' "$D" && ok "복구 실패 = 3~6단계 진행 0 명시(DA R3-1)" || no "복구 실패 정지 문구 없음"
grep -qF '별도 폴더의 `anchor-sampler.log`' "$D" && ok "sampler.log = 별도 폴더 문구" || no "sampler.log 별도 폴더 문구 없음"
grep -qF 'sampler.log' "$S" && ok "알림 본문 삭제 목록에 sampler.log" || no "알림 본문에 sampler.log 없음"

# ── 치환 개수 일치(arch #279148 ①): plist 자리표시자 6개 = 문서 문구 ────────
PH="$(grep -o '__[A-Z]*__' "$P" | sort -u)"
chk "plist 자리표시자 = 6개" "$(printf '%s\n' "$PH" | wc -l | tr -d ' ')" 6
grep -qF '치환 6개' "$D" && ok "문서 치환 문구 = 6개" || no "문서 치환 문구(6개) 없음"
if grep -qE '치환 5개|·`__LOGS__` 치환 후' "$D"; then no "문서에 옛 치환 표기 남음"; else ok "옛 치환 표기(5개·2개) 없음"; fi
chk "문서가 plist 자리표시자 6개를 모두 적음" "$(for k in $PH; do grep -qF -- "$k" "$D" || echo x; done | wc -l | tr -d ' ')" 0
grep -qF '~/.claude/fable-team/state/capacity/anchor-sampler.log' "$D" && ok "sampler.log 정본 경로" || no "sampler.log 정본 경로 없음"
for k in __WORKTREE__ __COMM__ __SEATS__ __STATE__; do
  grep -qF -- "$k" "$D" && ok "치환 목록 «${k}»" || no "치환 목록 «${k}» 없음"
done

# ── 재기동 0 (M3) · 끝 시각 상수 1곳 · plist = 1시간 간격 ───────────────────
if grep -vE '^[[:space:]]*#' "$S" | grep -qE 'launchctl|pkill|kill |systemctl|brew services'; then
  no "재기동·정지 호출이 스크립트에 있음 (M3)"; else ok "재기동·정지 호출 0 (M3)"; fi
chk "끝 시각 상수는 스크립트 1곳" "$(grep -c '1794888000' "$S")" 1
chk "plist StartInterval 3600" "$(grep -A1 '<key>StartInterval</key>' "$P" | grep -o '3600')" "3600"
if grep -q '<key>KeepAlive</key>' "$P"; then no "plist 에 KeepAlive(상시 재기동)"; else ok "plist KeepAlive 0(1시간 간격 1개)"; fi
plutil -lint "$P" >/dev/null 2>&1 && ok "plist lint" || no "plist lint"

# ── h 묶음 문서: 켜기 · 끄기·지우기 · 알림 설치 + 기준값 문구 ────────────────
[ -f "$D" ] && ok "h 묶음 문서 있음" || no "h 묶음 문서 없음: $D"
for s in '2026-11-17 13:00' 'config.yaml.bak-anchorA-' 'logging-to-file=true' 'debug=true' 'logs-max-total-size-mb' \
         '60초' '재기동' 'logging-to-file=false' 'main*.log' 'anchor-t0.json' 'anchor-watch.py' 'anchor-snapshots.jsonl' \
         'bootout' 'accounts.env.prev' 'cap-set.py' 'ctx-plan' '30분' 'Use OAuth'; do
  grep -qF -- "$s" "$D" 2>/dev/null && ok "h 문서 문구 «${s}»" || no "h 문서 문구 «${s}» 없음"
done

chk "h 문서 삭제 글롭은 main*.log 만(M2)" "$(grep -c 'logs/\*' "$D")" 0
for s in '복구 확인' 'ⓑ1' 'ⓑ4' '보존(삭제 0)'; do
  grep -qF -- "$s" "$D" 2>/dev/null && ok "h 문서 문구 «${s}»" || no "h 문서 문구 «${s}» 없음"
done

printf '\n%s — %s건 중 PASS %s · FAIL %s\n' "$( [ "$FAIL" = 0 ] && echo PASS || echo FAIL )" "$((PASS+FAIL))" "$PASS" "$FAIL"
[ "$FAIL" = 0 ]
