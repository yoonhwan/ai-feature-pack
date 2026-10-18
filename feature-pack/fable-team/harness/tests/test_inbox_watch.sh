#!/usr/bin/env bash
# test_inbox_watch.sh — ft-inbox-watch.sh(세션 안 쪽지 감시) 시험. 임시 FT_ROOT 큐 픽스처 · tmux·claude·실 planner pane 호출 0.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="$HERE/../.."
WATCH="$REPO/harness/bin/ft-inbox-watch.sh"
T="$(mktemp -d)"; trap 'kill "${WP:-0}" 2>/dev/null; rm -rf "$T"' EXIT
export FT_ROOT="$T/root" FT_INBOX_WATCH_POLL=0.1
mkdir -p "$FT_ROOT/.fable-team/state/inbox" "$FT_ROOT/.fable-team/comm/bodies"
Q="$FT_ROOT/.fable-team/state/inbox/planner-x.jsonl"
OUT="$T/out.txt"; ERR="$T/err.txt"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
eq()  { [ "$2" = "$3" ] && ok "$1" || bad "$1 (기대 '$3' 실제 '$2')"; }

row() {  # <seq> <cls> <from> [본문 — 비우면 body_path 없는 행]
  python3 - "$Q" "$FT_ROOT/.fable-team/comm/bodies" "$@" <<'PY'
import json, sys
q, bd, seq, cls, frm = sys.argv[1:6]
x = {"seq": int(seq), "cls": cls, "from": frm, "via": "rule"}
if len(sys.argv) > 6:
    p = f"{bd}/{seq}.txt"
    open(p, "w", encoding="utf-8").write(sys.argv[6] + "\n둘째 줄\n")
    x["body_path"] = p
open(q, "a", encoding="utf-8").write(json.dumps(x, ensure_ascii=False) + "\n")
PY
}
rewrite_all() {  # 분류기처럼 큐를 통째로 다시 쓴다(cls 갱신)
  python3 - "$Q" <<'PY'
import json, os, sys
q = sys.argv[1]
rows = [json.loads(l) for l in open(q, encoding="utf-8") if l.strip()]
for x in rows:
    x["cls"], x["via"] = "⑤", "haiku"
open(q + ".tmp", "w", encoding="utf-8").writelines(json.dumps(x, ensure_ascii=False) + "\n" for x in rows)
os.replace(q + ".tmp", q)
PY
}
lines() { grep -c '^\[쪽지\]' "$OUT" 2>/dev/null || true; }
waitfor() {  # <줄 수>
  for _ in $(seq 1 50); do [ "$(lines)" -ge "$1" ] && return 0; sleep 0.1; done; return 1
}
start() { : > "$OUT"; : > "$ERR"; bash "$WATCH" planner-x#3 >"$OUT" 2>"$ERR" & WP=$!; sleep 0.6; }
stop() { kill -TERM "$WP" 2>/dev/null; wait "$WP" 2>/dev/null; STOP_RC=$?; }  # 서브셸로 부르면 wait 가 127 — 변수로 받는다

# ② 시작 전 행 → 출력 0
row 1 ② a#1 "[a#1->planner-x#3] 시작 전 쪽지"
start
sleep 0.5; eq "② 시작 전 행은 출력 0" "$(lines)" "0"
# ① 시작 뒤 새 행 1 → 1줄(형식 일치)
row 2 ② byz-x#4 "[HIL] 행#3 질문입니다 — 이 본문은 사십 자를 넘기게 길게 적어서 잘리는지 본다"
waitfor 1 && ok "① 새 행 1 → 출력 1줄" || bad "① 새 행 출력 없음"
L1="$(grep '^\[쪽지\]' "$OUT" | head -1)"
printf '%s' "$L1" | grep -Eq '^\[쪽지\] #2 ② byz-x#4 .+' && ok "① 형식 [쪽지] #<seq> <분류> <from> <첫 줄>" || bad "① 형식 불일치: $L1"
BODY40="${L1#\[쪽지\] #2 ② byz-x#4 }"
[ "${#BODY40}" -le 40 ] && ok "① 본문 40자 이내(${#BODY40}자) · 첫 줄만" || bad "① 본문 40자 초과 ${#BODY40}"
printf '%s' "$L1" | grep -q '둘째 줄' && bad "① 둘째 줄 노출" || ok "① 둘째 줄 미노출"
# ③ 큐 통째 다시 쓰기(cls 갱신) → 추가 출력 0
rewrite_all; sleep 0.6
eq "③ 통째 다시 쓰기 뒤 줄 수 불변" "$(lines)" "1"
# ④ 새 행 2개 연속 → 2줄 추가
row 3 ③ b#1 "[b#1->planner-x#3] 판정 요청 하나"; row 4 ⑥ c#1 "[c#1->planner-x#3] 참고 둘"
waitfor 3 && ok "④ 새 행 2개 연속 → 2줄 추가" || bad "④ 줄 수 $(lines) (기대 3)"
eq "④ 순서(#3 다음 #4)" "$(grep '^\[쪽지\]' "$OUT" | sed -n '2,3p' | cut -d' ' -f2 | tr '\n' ' ')" "#3 #4 "
# ⑥ body_path 없음 → (본문 없음)
row 5 미상 d#1
waitfor 4 && ok "⑥ body_path 없는 행도 출력" || bad "⑥ 출력 없음"
grep '^\[쪽지\] #5 ' "$OUT" | grep -q '(본문 없음)$' && ok "⑥ (본문 없음)" || bad "⑥ (본문 없음) 아님"
stop; eq "SIGTERM 종료 코드 0" "$STOP_RC" "0"

# ⑤ 큐 파일 없음 → 경고·계속, 생기면 그 뒤 새 행 출력
rm -f "$Q"; start
sleep 0.5; kill -0 "$WP" 2>/dev/null && ok "⑤ 큐 없음에도 감시 계속" || bad "⑤ 감시가 죽음"
grep -q 'WARN ft-inbox-watch' "$ERR" && ok "⑤ stderr 경고" || bad "⑤ 경고 없음"
row 6 ① e#1 "[e#1->planner-x#3] 큐 생긴 뒤 쪽지"
waitfor 1 && ok "⑤ 큐 생긴 뒤 새 행 출력" || bad "⑤ 출력 없음"
printf 'not-json\n' >> "$Q"; row 7 ④ f#1 "[f#1->planner-x#3] 깨진 줄 뒤"
waitfor 2 && ok "⑤ 깨진 줄 무시하고 계속" || bad "⑤ 깨진 줄 뒤 출력 없음"
stop

# ── r408 — planner `_master` 앞 send 의 quiet 는 감시 실재와 한 쌍(판정 876·881) · 감시 없음 = 출력 + 하네스 master 긴급 1통(10분 1회) + teamset ERR
#   격리 루트 + 가짜 pgrep(FT_PGREP) + 가짜 tmux · 실 tmux·홈·BYZ 쓰기 0. 송신 경로 둘(comm/mbox.sh = 좌석들이 쓰는 경로 · 키트 ft-mbox.sh) 모두 같은 판정.
KIT="$REPO/harness/kit/fable-team/bin"
R="$T/r408"; C="$R/.fable-team/comm"; mkdir -p "$C" "$R/.fable-team/bin" "$R/.fable-team/state"
cp "$REPO/harness/comm/"mbox*.sh "$REPO/harness/comm/"mbox*.py "$C/"
cp "$REPO/harness/bin/ft-inbox.sh" "$REPO/harness/bin/ft-inbox.py" "$REPO/harness/bin/ft_inbox_core.py" "$R/.fable-team/bin/"
P='byz-planner-master-claude#72'; H='byz-harness-master-claude#9'
echo '{}' > "$R/.fable-team/seats.json"
printf '{"_master":"%s"}\n' "$P" > "$R/.fable-team/seats-planner.json"
printf '{"_master":"%s"}\n' "$H" > "$R/.fable-team/seats-harness.json"
PROCS="$T/procs.txt"; printf '#!/bin/sh\ncat %s\n' "$PROCS" > "$T/fake-pgrep"; chmod +x "$T/fake-pgrep"
printf '#!/bin/sh\nexit 1\n' > "$T/fake-haiku"; chmod +x "$T/fake-haiku"
mkdir -p "$T/fakebin"; printf '#!/bin/sh\nexit 1\n' > "$T/fakebin/tmux"; chmod +x "$T/fakebin/tmux"   # doorbell·teamset 이 실 tmux 를 못 건드리게
procs_live() {  # 감시 실체 1 + 미끼 3(접두 #7 · 본문에 시작 명령을 실은 send · 다른 bin 의 같은 좌석은 실체 꼴이지만 ft-inbox-watch.sh 없음)
  { echo "60861 /opt/x/Python -u - $KIT $P"
    echo "60862 /opt/x/Python -u - $KIT ${P%2}"
    echo "60863 bash $C/mbox.sh send $P x [결정] 시작: bash $KIT/ft-inbox-watch.sh $P"
    echo "60864 /opt/x/Python -u - $T/nobin $P"; } > "$PROCS"; }
procs_none() { procs_live; sed -i '' '1d' "$PROCS"; }   # 실체 줄만 빼고 미끼 3 은 남긴다
MK="$R/.fable-team/state/planner-watch-missing.$P"
env408() { env PATH="$T/fakebin:$PATH" FT_ROOT="$R" FT_MBOX_DIR="$C" FT_SEATS_JSON="$R/.fable-team/seats.json" FT_INBOX_HAIKU="$T/fake-haiku" FT_PGREP="$T/fake-pgrep" FT_BIN="$KIT" "$@"; }
abodies() { python3 - "$C/mailbox.jsonl" "$H" <<'PY'
import json, sys
for l in open(sys.argv[1], encoding="utf-8"):
    r = json.loads(l) if l.strip() else {}
    if r.get("to") == sys.argv[2] and r.get("from") == "ft-watch-alarm":
        print(r.get("body", "").replace("\n", " "))
PY
}
alarms() { abodies | grep -c 'planner watch 없음' || true; }
dbv() { sed -n 's/.*doorbell=\(.*\)$/\1/p' <<<"$1" | tail -1; }

for S in comm kit; do
  rm -f "$MK"; env408 bash "$C/mbox.sh" recv "$H" --all >/dev/null 2>&1
  if [ "$S" = comm ]; then snd() { env408 bash "$C/mbox.sh" send "$P" "t$1#1" "[결정] r408 시험 $S $1" 2>"$T/err408"; }
  else snd() { env408 bash "$KIT/ft-mbox.sh" send "$P" "t$1#1" "[결정] r408 시험 $S $1" 2>"$T/err408"; }; fi
  # ⓐ 감시 있음 → quiet 그대로 · 긴급 0
  procs_live; o="$(snd 1)"
  eq "ⓐ[$S] 감시 있음 → doorbell=quiet" "$(dbv "$o")" "quiet"
  eq "ⓐ[$S] 감시 있음 → 긴급 0통" "$(alarms)" "0"
  # ⓑ 감시 없음(미끼만) → quiet(WATCH 없음) + 긴급 1통(좌석·시작 명령) + 표식
  procs_none; o="$(snd 2)"
  eq "ⓑ[$S] 감시 없음 → doorbell=quiet(WATCH 없음)" "$(dbv "$o")" "quiet(WATCH 없음)"
  eq "ⓑ[$S] 감시 없음 → 긴급 1통" "$(alarms)" "1"
  abodies | grep -F "[긴급 · planner watch 없음] $P" | grep -qF "ft-inbox-watch.sh $P" && ok "ⓑ[$S] 긴급 본문 = 좌석 + 시작 명령: $(abodies | tail -1)" || bad "ⓑ[$S] 긴급 본문: $(abodies | tail -1)"
  [ -f "$MK" ] && ok "ⓑ[$S] 표식 파일 생성" || bad "ⓑ[$S] 표식 없음"
  # ⓒ 10분 안 재send → 긴급 0통 추가 · 10분 지난 표식 → 다시 1통
  o="$(snd 3)"; eq "ⓒ[$S] 10분 안 재send → 여전히 quiet(WATCH 없음)" "$(dbv "$o")" "quiet(WATCH 없음)"
  eq "ⓒ[$S] 10분 안 재send → 긴급 추가 0" "$(alarms)" "1"
  touch -t "$(date -v-11M +%Y%m%d%H%M)" "$MK"; snd 4 >/dev/null
  eq "ⓒ[$S] 표식 11분 경과 → 긴급 다시 1통" "$(alarms)" "2"
  # ⓓ 명시 ring → 울림 경로 그대로(WATCH 꼬리 0 · 긴급 추가 0)
  o="$(env408 bash "$C/mbox.sh" ring "$P" 2>&1)"
  [[ "$o" == "RING $P doorbell="* && "$o" != *WATCH* ]] && ok "ⓓ[$S] ring 명시 명령 불변: $o" || bad "ⓓ[$S] ring: $o"
  eq "ⓓ[$S] ring → 긴급 추가 0" "$(alarms)" "2"
done
# 하네스 master 없음 → stderr 1줄 · 표식 0(다음 send 재시도)
rm -f "$MK"; mv "$R/.fable-team/seats-harness.json" "$T/sh.bak"; procs_none
o="$(env408 bash "$C/mbox.sh" send "$P" t9#1 "[결정] r408 master 없음" 2>"$T/err408")"
{ [ "$(dbv "$o")" = "quiet(WATCH 없음)" ] && grep -q '하네스 master 를 못 찾음' "$T/err408" && [ ! -f "$MK" ]; } && ok "master 없음 → stderr 1줄 · 표식 0" || bad "master 없음: $o / $(cat "$T/err408")"
mv "$T/sh.bak" "$R/.fable-team/seats-harness.json"
# 판정기 없음(FT_BIN 틀림) → quiet(WATCH 판정 불가) · 조용한 통과 0
o="$(env408 env FT_BIN="$T/nobin" bash "$C/mbox.sh" send "$P" t10#1 "[결정] r408 판정기 없음" 2>"$T/err408")"
eq "판정기 없음 → quiet(WATCH 판정 불가)" "$(dbv "$o")" "quiet(WATCH 판정 불가)"
# planner 아닌 좌석 앞 send 는 감시 판정 0(quiet/ring 기존 규칙)
o="$(env408 bash "$C/mbox.sh" send other-seat#1 t11#1 "[결정] r408 남의 좌석" 2>"$T/err408")"
[[ "$(dbv "$o")" != *WATCH* ]] && ok "planner 아닌 좌석 → WATCH 판정 0" || bad "남의 좌석: $o"

# ⓔ ft-teamset-check planner 행 — 감시 0 → ERR rc1 · 감시 1 → OK (판정기 = ft-mbox.sh watch-alive 하나)
TS="$T/TEAMSET408.md"
printf '# t\n## 표 1 — 역할\n| 역할 | 수 | 모델 | effort | 명부 키 | 승계 | 닫기 |\n|---|---|---|---|---|---|---|\n| master | 1 | `sonnet-5-5` | high | `_master` | a | b |\n- 나노 상한 기본: 3\n- 명부 공용 키: `_name`\n## 표 2 — 팀\n| 팀 | 나노 상한 | tester | arch 상시 |\n|---|---|---|---|\n| planner | 3 | 0 | 없음 |\n' > "$TS"
printf '#!/bin/sh\ncase "$1" in list-sessions) echo "%s";; *) exit 1;; esac\n' "$P" > "$T/fakebin/tmux"
printf '#!/bin/sh\necho "IDLE - - - jsonl"\n' > "$T/fake-st"; printf '#!/bin/sh\nexit 0\n' > "$T/fake-mb"
tsc() { env408 env FT_TEAMSET_MBOX="$T/fake-mb" FT_SEAT_STATUS="$T/fake-st" FT_TEAMSET_ROOT="$R" FT_TEAMSET_MD="$TS" ZC_RESUME_DIR="$T" bash "$KIT/ft-teamset-check.sh" planner 2>&1; }
procs_none; o="$(tsc)"; rc=$?
{ [ "$rc" = 1 ] && [[ "$o" == "planner ERR "*"planner watch 없음(ft-inbox-watch.sh $P)"* ]]; } && ok "ⓔ 감시 0 → ERR planner watch 없음 rc1: $o" || bad "ⓔ-1 rc=$rc $o"
procs_live; o="$(tsc)"; rc=$?
{ [ "$rc" = 0 ] && [[ "$o" == "planner OK "* ]]; } && ok "ⓔ 감시 1 → OK rc0: $o" || bad "ⓔ-2 rc=$rc $o"
# 짝 사본 cmp 0 · 600/300 0
cmp -s "$KIT/ft-mbox.sh" "$REPO/skill/scripts/ft-mbox.sh" && ok "짝 cmp 0 ft-mbox.sh(키트 ↔ skill/scripts)" || bad "짝 불일치 ft-mbox.sh"
for f in ft_teamset.py ft-teamset-check.sh; do cmp -s "$KIT/$f" "$REPO/harness/bin/$f" && ok "짝 cmp 0 $f" || bad "짝 불일치 $f"; done
! grep -nE '\b(600|300)\b' "$KIT/ft-mbox.sh" "$REPO/harness/comm/mbox.sh" "$KIT/ft_teamset.py" | grep -i 'timeout\|sleep' >/dev/null && ok "600/300 0" || bad "600/300 발견"

echo "---"; [ "$fail" = 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
