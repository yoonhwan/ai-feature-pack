#!/usr/bin/env bash
# test_r928_watch_rearm_grace.sh — r928: planner 감시 «다시 걸기 틈» 유예 + 긴급 근거 줄.
#   ⓐ 끝 표식 5분 안 + 프로세스 0 → 긴급 0 · stderr `WATCH-REARM 대기 <분>` 1줄
#   ⓑ 끝 표식 5분 넘음/없음 + 프로세스 0 → 긴급 1통 · 본문에 «감시 프로세스 0(pgrep) · 마지막 감시 끝 HH:MM(또는 기록 없음)»
#   ⓒ 프로세스 있음 → 긴급 0 (기존 그대로) · ⓓ 같은 좌석 10분 1회 제한 회귀 0
#   격리 FT_ROOT · 가짜 pgrep(FT_PGREP) · 가짜 tmux · 실 tmux·홈·BYZ 쓰기 0.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="$HERE/../.."
WATCH="$REPO/harness/bin/ft-inbox-watch.sh"
KIT="$REPO/harness/kit/fable-team/bin"
T="$(mktemp -d)"; trap 'kill "${WP:-0}" 2>/dev/null; rm -rf "$T"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
eq()  { [ "$2" = "$3" ] && ok "$1" || bad "$1 (기대 '$3' 실제 '$2')"; }

# ── ① 감시 스크립트가 끝날 때 상태 표식을 남긴다 (ⓐ 의 입력)
W="$T/w1"; mkdir -p "$W/.fable-team/state/inbox"
export FT_ROOT="$W" FT_INBOX_WATCH_POLL=0.1
bash "$WATCH" planner-y#7 >/dev/null 2>"$T/werr" & WP=$!
sleep 0.8; kill -TERM "$WP" 2>/dev/null; wait "$WP" 2>/dev/null
LM1="$W/.fable-team/state/planner-watch-last.planner-y#7"
[ -f "$LM1" ] && ok "① SIGTERM 뒤 끝 표식 생성" || bad "① 끝 표식 없음 ($LM1) · stderr=$(cat "$T/werr")"
grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}' "$LM1" 2>/dev/null && ok "① 표식 첫 칸 = «YYYY-MM-DD HH:MM:SS» 시각" || bad "① 표식 시각 형식: $(cat "$LM1" 2>/dev/null)"
[ -n "$(find "$LM1" -mmin -1 2>/dev/null)" ] && ok "① 표식 mtime = 끝난 시각(1분 안)" || bad "① 표식 mtime 이 오래됨"
# 짝 사본 = 같은 내용(설치 cmp0 의 근거)
cmp -s "$REPO/harness/bin/ft-inbox-watch.sh" "$KIT/ft-inbox-watch.sh" && ok "① 짝 cmp0 ft-inbox-watch.sh(bin ↔ kit)" || bad "① 짝 불일치 ft-inbox-watch.sh"
cmp -s "$KIT/ft-mbox.sh" "$REPO/skill/scripts/ft-mbox.sh" && ok "① 짝 cmp0 ft-mbox.sh(kit ↔ skill/scripts)" || bad "① 짝 불일치 ft-mbox.sh"

# ── ② 보내는 쪽(좌석 경로 comm/mbox.sh · 팩 키트 ft-mbox.sh) — 유예·근거 줄이 같은 값
R="$T/r928"; C="$R/.fable-team/comm"; mkdir -p "$C" "$R/.fable-team/bin" "$R/.fable-team/state"
cp "$REPO/harness/comm/"mbox*.sh "$REPO/harness/comm/"mbox*.py "$C/"
cp "$REPO/harness/bin/ft-inbox.sh" "$REPO/harness/bin/ft-inbox.py" "$REPO/harness/bin/ft_inbox_core.py" "$R/.fable-team/bin/"
P='byz-planner-master-claude#72'; H='byz-harness-master-claude#9'
echo '{}' > "$R/.fable-team/seats.json"
printf '{"_master":"%s"}\n' "$P" > "$R/.fable-team/seats-planner.json"
printf '{"_master":"%s"}\n' "$H" > "$R/.fable-team/seats-harness.json"
PROCS="$T/procs.txt"; printf '#!/bin/sh\ncat %s\n' "$PROCS" > "$T/fake-pgrep"; chmod +x "$T/fake-pgrep"
printf '#!/bin/sh\nexit 1\n' > "$T/fake-haiku"; chmod +x "$T/fake-haiku"
mkdir -p "$T/fakebin"; printf '#!/bin/sh\nexit 1\n' > "$T/fakebin/tmux"; chmod +x "$T/fakebin/tmux"
procs_live() { { echo "60861 /opt/x/Python -u - $KIT $P"
                  echo "60863 bash $C/mbox.sh send $P x [결정] 시작: bash $KIT/ft-inbox-watch.sh $P"; } > "$PROCS"; }
procs_none() { : > "$PROCS"; }
LM="$R/.fable-team/state/planner-watch-last.$P"; MK="$R/.fable-team/state/planner-watch-missing.$P"
env928() { env PATH="$T/fakebin:$PATH" FT_ROOT="$R" FT_MBOX_DIR="$C" FT_SEATS_JSON="$R/.fable-team/seats.json" FT_INBOX_HAIKU="$T/fake-haiku" FT_PGREP="$T/fake-pgrep" FT_BIN="$KIT" "$@"; }
abodies() { python3 - "$C/mailbox.jsonl" "$H" <<'PY'
import json, sys
try:
    f = open(sys.argv[1], encoding="utf-8")
except OSError:
    sys.exit(0)
for l in f:
    r = json.loads(l) if l.strip() else {}
    if r.get("to") == sys.argv[2] and r.get("from") == "ft-watch-alarm":
        print(r.get("body", "").replace("\n", " "))
PY
}
alarms() { abodies | grep -c 'planner watch 없음' || true; }
dbv() { sed -n 's/.*doorbell=\(.*\)$/\1/p' <<<"$1" | tail -1; }
ELD() { touch -t "$(date -v-11M +%Y%m%d%H%M)" "$1"; }

for S in comm kit; do
  rm -f "$MK" "$LM"; env928 bash "$C/mbox.sh" recv "$H" --all >/dev/null 2>&1
  if [ "$S" = comm ]; then snd() { env928 bash "$C/mbox.sh" send "$P" "t$1#1" "[결정] r928 시험 $S $1" 2>"$T/err928"; }
  else snd() { env928 bash "$KIT/ft-mbox.sh" send "$P" "t$1#1" "[결정] r928 시험 $S $1" 2>"$T/err928"; }; fi
  # ⓐ 끝 표식 5분 안 + 프로세스 0 → 긴급 0 · stderr 1줄 · 표식(10분 제한) 안 남김
  procs_none; : > "$LM"; b="$(alarms)"; o="$(snd 1)"
  eq "ⓐ[$S] 유예 중 → 긴급 0통" "$(alarms)" "$b"
  grep -q 'WATCH-REARM 대기 [0-9]*분' "$T/err928" && ok "ⓐ[$S] stderr «WATCH-REARM 대기 <분>»: $(grep -o 'WATCH-REARM 대기 [0-9]*분' "$T/err928" | head -1)" || bad "ⓐ[$S] stderr: $(cat "$T/err928")"
  eq "ⓐ[$S] 유예 중에도 db 꼬리는 (WATCH 없음) 그대로" "$(dbv "$o")" "quiet(WATCH 없음)"
  [ ! -f "$MK" ] && ok "ⓐ[$S] 유예는 10분 제한 표식을 만들지 않음(유예 끝나면 바로 울린다)" || bad "ⓐ[$S] 유예 중 표식 생성됨"
  # ⓑ 끝 표식 11분 경과 + 프로세스 0 → 긴급 1통 · 근거 줄(HH:MM)
  rm -f "$MK"; ELD "$LM"; HH="$(date -r "$LM" +%H:%M)"; b="$(alarms)"; snd 2 >/dev/null
  eq "ⓑ[$S] 유예 밖 → 긴급 1통" "$(( $(alarms) - b ))" "1"
  abodies | grep -F "감시 프로세스 0(pgrep) · 마지막 감시 끝 $HH" >/dev/null && ok "ⓑ[$S] 근거 줄 «프로세스 0 · 마지막 끝 ${HH}»" || bad "ⓑ[$S] 근거 줄: $(abodies | tail -1)"
  # ⓑ' 끝 표식 자체가 없음 → 같은 긴급 · «기록 없음»
  rm -f "$MK" "$LM"; b="$(alarms)"; snd 3 >/dev/null
  eq "ⓑ'[$S] 표식 없음 → 긴급 1통" "$(( $(alarms) - b ))" "1"
  abodies | grep -F '마지막 감시 끝 기록 없음' >/dev/null && ok "ⓑ'[$S] 근거 줄 «기록 없음»" || bad "ⓑ'[$S] 근거 줄: $(abodies | tail -1)"
  # ⓒ 프로세스 있음 → 긴급 0 (표식 없어도)
  procs_live; rm -f "$MK" "$LM"; b="$(alarms)"; o="$(snd 4)"
  eq "ⓒ[$S] 감시 있음 → doorbell=quiet" "$(dbv "$o")" "quiet"
  eq "ⓒ[$S] 감시 있음 → 긴급 0통" "$(alarms)" "$b"
  # ⓓ 같은 좌석 10분 1회 제한 회귀 0
  procs_none; rm -f "$MK" "$LM"; b="$(alarms)"; snd 5 >/dev/null; snd 6 >/dev/null
  eq "ⓓ[$S] 10분 안 두 번 → 긴급 1통" "$(( $(alarms) - b ))" "1"
  ELD "$MK"; snd 7 >/dev/null
  eq "ⓓ[$S] 표식 11분 경과 → 다시 1통" "$(( $(alarms) - b ))" "2"
done
# 유예 폭 환경값(FT_WATCH_REARM_GRACE) — 0 이면 유예 없음 · 60 이면 11분 끝 표식도 유예
procs_none; rm -f "$MK"; : > "$LM"; b="$(alarms)"
env928 env FT_WATCH_REARM_GRACE=0 bash "$KIT/ft-mbox.sh" send "$P" t8#1 "[결정] r928 유예 0" >/dev/null 2>&1
eq "유예 0 → 끝 표식이 방금이어도 긴급 1통" "$(( $(alarms) - b ))" "1"
rm -f "$MK"; ELD "$LM"; b="$(alarms)"
env928 env FT_WATCH_REARM_GRACE=60 bash "$KIT/ft-mbox.sh" send "$P" t9#1 "[결정] r928 유예 60" >/dev/null 2>&1
eq "유예 60 → 11분 끝 표식도 긴급 0통" "$(alarms)" "$b"

echo "---"; [ "$fail" = 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
