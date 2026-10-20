#!/usr/bin/env bash
# test_seat_handover.sh — R30: ft-seat-handover.sh(snapshot·apply·status) + retired-seat-guard + no-attach-to-user
# 가짜 tmux 스텁(PATH 앞) + 가짜 명부·장부·mbox 만 쓴다 — 실제 tmux switch·kill·mbox 발신·홈 쓰기 0.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="$HERE/../.."
HO="$REPO/harness/bin/ft-seat-handover.sh"
GUARD="$REPO/harness/kit/fable-team/templates/hooks/retired-seat-guard.sh"
STOP="$REPO/harness/kit/fable-team/templates/hooks/no-attach-to-user.sh"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
has() { grep -qF -- "$2" <<<"$1"; }
for f in "$HO" "$GUARD" "$STOP"; do bash -n "$f" || bad "bash -n $f"; done; ok "bash -n 3종"
OLD="byz-t-master-claude#2"; NEW="byz-t-master-claude#3"
mkdir -p "$T/bin" "$T/root/.fable-team/state"; echo '{}' > "$T/root/.fable-team/seats.json"
cat > "$T/bin/tmux" <<'EOF'
#!/usr/bin/env bash
S="$TMUX_STUB"; sub="$1"; shift
case "$sub" in
  list-clients)
    tgt=""; fmt=""
    while [ $# -gt 0 ]; do case "$1" in -t) tgt="${2#=}"; shift 2;; -F) fmt="$2"; shift 2;; *) shift;; esac; done
    four=0; case "$fmt" in *client_session*) four=1;; esac
    awk -v t="$tgt" -v four="$four" '(t==""||$4==t){ if(four) print $1,$2,$3,$4; else print $1,$2,$3 }' "$S/clients.txt";;
  has-session) grep -qxF "${2#=}" "$S/sessions.txt";;
  switch-client)
    tty="$2"; new="${4#=}"; echo "-c $tty -t =$new" >> "$S/switch.log"
    [ -f "$S/switch-fail" ] && exit 1
    [ -f "$S/switch-noop" ] || awk -v t="$tty" -v n="$new" '$1==t{$4=n}{print}' "$S/clients.txt" > "$S/c.new" && mv "$S/c.new" "$S/clients.txt";;
  show-option) s="${2#=}"; n="${4#@}"; [ -f "$S/opts/$s.$n" ] && cat "$S/opts/$s.$n"; exit 0;;
  set-option) mkdir -p "$S/opts"; printf '%s' "$4" > "$S/opts/${2#=}.${3#@}";;
  display-message)
    pane=""; while [ $# -gt 0 ]; do case "$1" in -t) pane="$2"; shift 2;; *) shift;; esac; done
    if [ -n "$pane" ]; then awk -v p="$pane" '$1==p{print $2}' "$S/panes.txt"; else echo ambient-other; fi;;
  *) exit 2;;
esac
EOF
cat > "$T/mbox" <<'EOF'
#!/usr/bin/env bash
echo "$*" >> "$MBOX_LOG"
EOF
chmod +x "$T/bin/"* "$T/mbox"
reset() {  # reset <클라이언트 줄들(탭 구분 아님: 'tty pid created session')> — 새 스텁 상태·장부·명부
  rm -rf "$T/tm" "$T/ledger.jsonl" "$T/mbox.log"; mkdir -p "$T/tm/opts"
  printf '%s\n' "$@" > "$T/tm/clients.txt"
  printf '%s\n%s\n' "$OLD" "$NEW" > "$T/tm/sessions.txt"
  printf '%%1 %s\n%%2 %s\n' "$OLD" "$NEW" > "$T/tm/panes.txt"
  echo "{\"_master\":\"$NEW\",\"_hil_route\":\"planner-x#1\"}" > "$T/seats.json"
}
ho() { PATH="$T/bin:$PATH" TMUX_STUB="$T/tm" FT_ROOT="$T/root" FT_HANDOVER_LEDGER="$T/ledger.jsonl" FT_SEATS_JSON="$T/seats.json" \
       FT_MBOX="$T/mbox" MBOX_LOG="$T/mbox.log" bash "$HO" "$@" 2>&1; }
swlog() { cat "$T/tm/switch.log" 2>/dev/null; }
# ── handover ────────────────────────────────────────────────────────────
reset "/dev/ttys001 11 100 $OLD"
ho snapshot "$OLD" "$NEW" >/dev/null; out="$(ho apply "$OLD" "$NEW")"; rc=$?
[ "$rc" -eq 0 ] && has "$out" "moved=1 skipped=0 ambiguous=0" && has "$(swlog)" "-c /dev/ttys001 -t =$NEW" && ok "T0 1탭 → move" || bad "T0 1탭: rc=$rc $out"
echo "RESULT T0-1tab: $out"
[ "$(cat "$T/tm/opts/$OLD.handed_over_to")" = "$NEW" ] && ok "@handed_over_to 캐시 설정" || bad "옵션 캐시"
out="$(ho apply "$OLD" "$NEW")"; has "$out" "OK already-done" && ok "apply 재실행 = already-done" || bad "재실행: $out"
reset "/dev/ttys001 11 100 $OLD" "/dev/ttys002 12 90 $OLD"   # follow 1 + archive 1 = 2탭
ho snapshot "$OLD" "$NEW" >/dev/null; out="$(ho apply "$OLD" "$NEW")"; rc=$?
[ "$rc" -eq 0 ] && [ -z "$(swlog)" ] && has "$out" "ambiguous=2" && has "$out" "/dev/ttys001,/dev/ttys002" && ok "T0 2탭 → switch 0 + ambiguous 2" || bad "T0 2탭: rc=$rc $out sw=$(swlog)"
echo "RESULT T0-2tab: switch.log lines=$(swlog | wc -l | tr -d ' ')"
echo "RESULT T0-2tab: $out"
[ "$(wc -l < "$T/mbox.log" | tr -d ' ')" = 1 ] && has "$(cat "$T/mbox.log")" "send planner-x#1 $OLD [handover-ambiguous]" && ok "planner 로그 1통" || bad "mbox: $(cat "$T/mbox.log" 2>/dev/null)"
if grep -qE '\?|까요|주세요' "$T/mbox.log"; then bad "ambiguous 통보에 질문 문장"; else ok "ambiguous 통보 질문 문장 0"; fi
reset
ho snapshot "$OLD" "$NEW" >/dev/null; out="$(ho apply "$OLD" "$NEW")"; rc=$?
[ "$rc" -eq 0 ] && has "$out" "no-client" && ok "T0 0탭 → no-client" || bad "0탭: $out"
reset "/dev/ttys001 11 100 $OLD"
ho snapshot "$OLD" "$NEW" >/dev/null; echo "/dev/ttys009 19 200 $OLD" >> "$T/tm/clients.txt"   # T0 뒤 붙은 조회 탭
out="$(ho apply "$OLD" "$NEW")"
has "$out" "moved=1" && ! has "$(swlog)" "ttys009" && ok "T0 뒤 붙은 조회 탭 → switch 0" || bad "조회 탭: $out sw=$(swlog)"
reset "/dev/ttys001 11 100 $OLD"
ho snapshot "$OLD" "$NEW" >/dev/null; sed -i '' "s/$OLD/other-sess/" "$T/tm/clients.txt"
out="$(ho apply "$OLD" "$NEW")"; has "$out" "ttys001:moved-by-user" && [ -z "$(swlog)" ] && ok "오빠가 다른 세션으로 → moved-by-user" || bad "moved-by-user: $out"
reset "/dev/ttys001 11 100 $OLD"
ho snapshot "$OLD" "$NEW" >/dev/null; sed -i '' 's/ttys001 11 100/ttys001 77 555/' "$T/tm/clients.txt"
out="$(ho apply "$OLD" "$NEW")"; has "$out" "ttys001:identity-changed" && [ -z "$(swlog)" ] && ok "tty 재사용 → identity-changed" || bad "identity: $out"
reset "/dev/ttys001 11 100 $OLD"
ho snapshot "$OLD" "$NEW" >/dev/null; : > "$T/tm/clients.txt"
out="$(ho apply "$OLD" "$NEW")"; has "$out" "ttys001:gone" && ok "탭 닫힘 → gone" || bad "gone: $out"
reset "/dev/ttys001 11 100 $OLD"
ho snapshot "$OLD" "$NEW" >/dev/null; printf '%s\n' "$OLD" > "$T/tm/sessions.txt"
out="$(ho apply "$OLD" "$NEW")"; rc=$?; [ "$rc" -eq 1 ] && [ -z "$(swlog)" ] && ok "후계 세션 없음 rc 1" || bad "후계 없음: rc=$rc $out"
reset "/dev/ttys001 11 100 $OLD"
ho snapshot "$OLD" "$NEW" >/dev/null; echo "{\"_master\":\"$OLD\"}" > "$T/seats.json"
out="$(ho apply "$OLD" "$NEW")"; rc=$?; [ "$rc" -eq 1 ] && [ -z "$(swlog)" ] && has "$out" "명부 불일치" && ok "명부 불일치 rc 1" || bad "명부 불일치: rc=$rc $out"
reset "/dev/ttys001 11 100 $OLD"
ho snapshot "$OLD" "$NEW" >/dev/null; touch "$T/tm/switch-fail"
out="$(ho apply "$OLD" "$NEW")"; rc=$?; [ "$rc" -eq 1 ] && has "$out" "ttys001:switch-failed" && ok "switch 실패 rc 1 + skipped" || bad "switch 실패: rc=$rc $out"
reset "/dev/ttys001 11 100 $OLD"
ho snapshot "$OLD" "$NEW" >/dev/null; touch "$T/tm/switch-noop"
out="$(ho apply "$OLD" "$NEW")"; rc=$?; [ "$rc" -eq 1 ] && has "$out" "ttys001:switch-failed" && ok "switch 후 부착 미확인 → switch-failed rc 1" || bad "noop: rc=$rc $out"
reset "/dev/ttys001 11 100 $OLD"
out="$(ho apply "$OLD" "$NEW")"; rc=$?; [ "$rc" -eq 1 ] && has "$out" "snapshot 없음" && ok "snapshot 없는 apply rc 1" || bad "snapshot 없음: rc=$rc $out"
reset "/dev/ttys001 11 100 $OLD"
out="$(ho apply "$OLD" "$NEW" --client /dev/ttys001)"; rc=$?; [ "$rc" -eq 1 ] && [ -z "$(swlog)" ] && ok "--client seq 없음 rc 1" || bad "--client seq: rc=$rc $out"
out="$(ho apply "$OLD" "$NEW" --client /dev/ttys001 --confirmed-by abc)"; rc=$?; [ "$rc" -eq 1 ] && ok "--client seq 비숫자 rc 1" || bad "--client seq abc: rc=$rc"
reset "/dev/ttys001 11 100 $OLD" "/dev/ttys002 12 90 $OLD"
out="$(ho apply "$OLD" "$NEW" --client /dev/ttys002 --confirmed-by 62500)"; rc=$?
[ "$rc" -eq 0 ] && has "$out" "moved=1" && [ "$(swlog)" = "-c /dev/ttys002 -t =$NEW" ] && has "$(cat "$T/ledger.jsonl")" '"confirmed_by":62500' && ok "--client + seq → 그 tty 만 · 장부에 seq" || bad "--client: rc=$rc $out sw=$(swlog)"
# ── status ──────────────────────────────────────────────────────────────
st() { PATH="$T/bin:$PATH" TMUX_STUB="$T/tm" FT_ROOT="$T/root" FT_HANDOVER_LEDGER="$T/ledger.jsonl" FT_SEATS_JSON="$T/seats.json" bash "$HO" status "$@" 2>&1; }
done_row() { printf '{"state":"done","old":"%s","new":"%s","moved":[],"skipped":[],"ambiguous":[]}\n' "$1" "$2" >> "$T/ledger.jsonl"; }
reset "/dev/ttys001 11 100 $NEW"; echo "{\"_master\":\"$OLD\"}" > "$T/seats.json"
[ "$(st "$OLD")" = ACTIVE ] && ok "status 1: 장부 없음·명부 나 → ACTIVE" || bad "status1: $(st "$OLD")"
reset; done_row "$OLD" "$NEW"
[ "$(st "$OLD")" = "RETIRED $NEW" ] && ok "status 2: done 나→X·명부 X → RETIRED X" || bad "status2: $(st "$OLD")"
reset; done_row "$OLD" "$NEW"; echo '{"_master":"byz-t-master-claude#9"}' > "$T/seats.json"
has "$(st "$OLD")" "MISMATCH ledger=$NEW roster=byz-t-master-claude#9" && ok "status 3: done 나→X·명부 Y → MISMATCH" || bad "status3: $(st "$OLD")"
reset; done_row "$OLD" "$NEW"; printf '%s\n' "$OLD" > "$T/tm/sessions.txt"
has "$(st "$OLD")" "MISMATCH" && ok "status 3b: X 세션 없음 → MISMATCH" || bad "status3b: $(st "$OLD")"
reset; echo '{"_master":"byz-t-master-claude#9"}' > "$T/seats.json"
has "$(st "$OLD")" "MISMATCH ledger=none roster=byz-t-master-claude#9" && ok "status 4: 장부 없음·명부 Z → MISMATCH (이름 추측 0)" || bad "status4: $(st "$OLD")"
reset; echo "{\"_master\":\"$OLD\"}" > "$T/seats.json"; printf '{"state":"pending","old":"%s","new":"%s","follow":[],"ambiguous":[]}\n' "$OLD" "$NEW" > "$T/ledger.jsonl"
[ "$(st "$OLD")" = ACTIVE ] && ok "status 5: pending 만·명부 나 → ACTIVE" || bad "status5: $(st "$OLD")"
reset; done_row "$OLD" "$NEW"; out="$(st "$OLD")"
[ "$out" = "RETIRED $NEW" ] && [ "$(cat "$T/tm/opts/$OLD.handed_over_to")" = "$NEW" ] && ok "옵션 유실 → RETIRED + 복원" || bad "옵션 유실: $out"
reset; done_row "$OLD" "$NEW"; printf 'wrong#7' > "$T/tm/opts/$OLD.handed_over_to"; out="$(st "$OLD")"
[ "$out" = "RETIRED $NEW" ] && [ "$(cat "$T/tm/opts/$OLD.handed_over_to")" = "$NEW" ] && ok "엉뚱한 옵션 → 장부·명부가 이김" || bad "엉뚱한 옵션: $out"
reset; done_row "$OLD" "$NEW"
out="$(PATH="$T/bin:$PATH" TMUX_STUB="$T/tm" TMUX_PANE=%1 FT_ROOT="$T/root" FT_HANDOVER_LEDGER="$T/ledger.jsonl" FT_SEATS_JSON="$T/seats.json" bash "$HO" status 2>&1)"
[ "$out" = "RETIRED $NEW" ] && ok "TMUX_PANE 고정(ambient 세션 무관)" || bad "TMUX_PANE: $out"
out="$(PATH="$T/bin:$PATH" TMUX_STUB="$T/tm" FT_ROOT="$T/root" FT_HANDOVER_LEDGER="$T/ledger.jsonl" FT_SEATS_JSON="$T/seats.json" env -u TMUX_PANE bash "$HO" status 2>&1)"; rc=$?   # r537: 루트 풀이(r385)가 인자 검사보다 먼저 — 다른 호출과 같은 임시 루트
[ "$rc" -eq 2 ] && ok "세션·TMUX_PANE 둘 다 없으면 rc 2(추측 0)" || bad "무인자: rc=$rc $out"
# ── guard 훅 ────────────────────────────────────────────────────────────
guard() { echo '{}' | PATH="$T/bin:$PATH" TMUX_STUB="$T/tm" TMUX_PANE="$1" FT_BIN="${2:-$REPO/harness/bin}" FT_ROOT="$T/root" \
          FT_HANDOVER_LEDGER="$T/ledger.jsonl" FT_SEATS_JSON="$T/seats.json" bash "$GUARD" 2>&1; }
reset; done_row "$OLD" "$NEW"; out="$(guard %1)"
has "$out" "은퇴 좌석" && has "$out" "후계 $NEW" && has "$out" "도달 확인" && has "$out" "단정 문구 0" && ok "guard: RETIRED 주입" || bad "guard RETIRED: $out"
reset; done_row "$OLD" "$NEW"; echo '{"_master":"zzz#1"}' > "$T/seats.json"; out="$(guard %1)"
has "$out" "후계 관계 불일치" && has "$out" "handover-mismatch" && ok "guard: MISMATCH 주입" || bad "guard MISMATCH: $out"
out="$(guard %1)"
has "$out" "이미 보고됨" && ! has "$out" "handover-mismatch" && ok "guard: MISMATCH 2회째 → mbox 지시 0" || bad "guard MISMATCH 2회: $out"
reset; out="$(guard %2)"; [ -z "$out" ] && ok "guard: ACTIVE → 출력 0" || bad "guard ACTIVE: $out"
reset; out="$(guard %1 "$T/nobin")"; has "$out" "retired-seat-guard 오류" && ok "guard: 판정기 없음 → 보이는 오류" || bad "guard 오류: $out"
out="$(echo '{}' | env -u TMUX_PANE bash "$GUARD" 2>&1)"; [ -z "$out" ] && ok "guard: tmux 밖 → 출력 0" || bad "guard tmux 밖: $out"
# 루트 해석: 워크트리 project dir → 메인 루트 bin / 명부 없는 dir·비 git dir → 출력 0
G="$T/g"; mkdir -p "$G/repo/.fable-team/bin" "$G/plain"
cp "$HO" "$G/repo/.fable-team/bin/"; echo '{}' > "$G/repo/.fable-team/seats.json"
git -C "$G/repo" init -q && git -C "$G/repo" -c user.name=t -c user.email=t@t commit -q --allow-empty -m i && git -C "$G/repo" worktree add -q "$G/wt" -b wtb
git -C "$G/plain" init -q
guard_dir() {  # guard_dir <project dir> — FT_ROOT·FT_BIN 미지정(훅이 git 으로 루트 해석)
  echo '{}' | PATH="$T/bin:$PATH" TMUX_STUB="$T/tm" TMUX_PANE=%1 CLAUDE_PROJECT_DIR="$1" \
    FT_HANDOVER_LEDGER="$T/ledger.jsonl" FT_SEATS_JSON="$T/seats.json" bash "$GUARD" 2>&1
}
reset; done_row "$OLD" "$NEW"
out="$(guard_dir "$G/wt")"; has "$out" "후계 $NEW" && ! has "$out" "오류" && ok "guard: 워크트리 project dir → 메인 루트 bin 해석" || bad "guard 워크트리: $out"
out="$(guard_dir "$G/plain")"; [ -z "$out" ] && ok "guard: 명부 없는 dir → 출력 0" || bad "guard 명부 없음: $out"
out="$(guard_dir "$T/nogit")"; [ -z "$out" ] && ok "guard: git 아닌 dir → 출력 0" || bad "guard 비 git: $out"
rm -f "$G/repo/.fable-team/bin/ft-seat-handover.sh"; out="$(guard_dir "$G/wt")"
has "$out" "retired-seat-guard 오류" && ok "guard: 명부 있는데 도구 없음 → 보이는 오류" || bad "guard 도구 없음: $out"
# ── Stop 훅 ─────────────────────────────────────────────────────────────
LOGF="$T/root/.fable-team/state/hil-falsepos.log"
stop() {  # stop <텍스트> [active true|false] → stdout
  jq -cn --arg t "$1" '{type:"assistant",message:{content:[{type:"text",text:$t}]}}' > "$T/tr.jsonl"
  rm -f "$LOGF"
  jq -cn --arg p "$T/tr.jsonl" --argjson a "${2:-false}" '{transcript_path:$p,stop_hook_active:$a}' | FT_ROOT="$T/root" bash "$STOP" 2>&1
}
nblock() { [ "$(grep -c '"decision":"block"' <<<"$1")" -ge 1 ]; }
fence='```'
out="$(stop '이전 좌석은 "tmux attach -t X 를 실행해 주세요"라고 요청했다')"
! nblock "$out" && [ -s "$LOGF" ] && ok "인용 줄 → 기록(block 0)" || bad "인용: $out"
echo "RESULT quote: stdout='${out}' (block 0)"
echo "RESULT quote: falsepos.log: $(tail -1 "$LOGF" 2>/dev/null)"
out="$(stop "$(printf '설명:\n%s\n! tmux attach -t X\n%s\n끝' "$fence" "$fence")")"
! nblock "$out" && [ -s "$LOGF" ] && ok "코드 펜스 안 ! tmux attach → 기록" || bad "펜스: $out"
out="$(stop "$(printf '[HIL] 막힌 명령 원문\n! tmux attach -t X')")"
! nblock "$out" && [ -s "$LOGF" ] && ok "[HIL] 원문 메시지 → 기록" || bad "[HIL]: $out"
out="$(stop "$(printf '감사 보고\n! tmux attach -t X 를 실행해 주세요')")"
! nblock "$out" && [ -s "$LOGF" ] && ok "감사 문서 메시지 → 기록" || bad "감사: $out"
out="$(stop '> ! tmux attach -t X')"; ! nblock "$out" && [ -s "$LOGF" ] && ok "> 인용 줄 → 기록" || bad "blockquote: $out"
out="$(stop 'tmux attach 는 사람이 직접 칠 때 쓰는 명령이다')"; ! nblock "$out" && [ -s "$LOGF" ] && ok "요청 형태 아닌 언급 → 기록" || bad "언급: $out"
out="$(stop '붙을 곳을 알려 드릴게요')"; ! nblock "$out" && [ ! -s "$LOGF" ] && ok "패턴 없음 → 기록 0" || bad "패턴 없음: $out"
out="$(stop '! tmux attach -t X')"; nblock "$out" && ok "맨 줄 ! tmux attach -t X → block" || bad "block !: $out"
out="$(stop 'tmux attach -t X 로 접속해 주세요')"; nblock "$out" && ok "맨 줄 tmux attach … 접속해 주세요 → block" || bad "block 접속: $out"
out="$(stop 'tmux attach-session -t X 를 실행해')"; nblock "$out" && ok "맨 줄 attach-session + 실행해 → block" || bad "block attach-session: $out"
out="$(stop 'tmuxc attach X 하세요')"; nblock "$out" && ok "tmuxc attach + 하세요 → block" || bad "block tmuxc: $out"
out="$(stop '! tmux attach -t X' true)"; echo "RESULT stop_hook_active: stdout='${out}' log=$(tail -1 "$LOGF" 2>/dev/null)"
! nblock "$out" && [ -s "$LOGF" ] && ok "stop_hook_active=true + block 줄 → block 0 · 기록" || bad "active: $out"
out="$(echo '{"transcript_path":"/nonexistent","stop_hook_active":false}' | FT_ROOT="$T/root" bash "$STOP" 2>&1)"
has "$out" "transcript 읽기 실패" && ok "transcript 읽기 실패 → stderr 1줄·block 0" || bad "읽기 실패: $out"
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
