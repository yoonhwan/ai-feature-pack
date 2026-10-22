#!/usr/bin/env bash
# test_hil_notify_marker.sh — r718: h<N>.notify 수신자 표식(ft-hil.sh --add --notify) · 틱 hil_watch 의 표식 분기 · 손상 경로.
# 임시 HIL_DIR · 임시 쪽지함 폴더 3개(BYZ 꼴·aifp 꼴·못 쓰는 꼴) · 틱 쪽지 발송은 팩 harness/comm 의 «실 mbox 사본»으로 돌려 쪽지함 파일 실물로 확인한다(스텁 0) — 실 /tmp/h* · 실 .fable-team · 실 쪽지함 0.
# 빨강 대조: FT_HIL_BIN=<base 사본>/ft-hil.sh FT_TICK_BIN=<base 사본>/ft-tick.sh 로 돌리면 ⓑ·ⓖ 가 FAIL 한다.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
SRC="$HERE/../../harness/kit/fable-team/bin"
HIL="${FT_HIL_BIN:-$SRC/ft-hil.sh}"
TICK="${FT_TICK_BIN:-$SRC/ft-tick.sh}"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
has() { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «$2» ← ${1:0:300}";; esac; }
not() { case "$1" in *"$2"*) bad "$3 — 있으면 안 됨: «$2» ← ${1:0:300}»";; *) ok "$3";; esac; }

D="$T/d"; BYZ="$T/byzcomm"; AIFP="$T/aifpcomm"; mkdir -p "$D" "$BYZ" "$AIFP" "$T/home"
hilx() { env -i HOME="$T/home" PATH="/usr/bin:/bin" PYTHONDONTWRITEBYTECODE=1 HIL_DIR="$D" HIL_CLIP=0 FT_SECRET_JUDGE="$T/none.py" FT_MBOX_DIR="$BYZ" bash "$HIL" "$@"; }
plan() { printf '#!/usr/bin/env bash\necho "ran-%s"\n' "$1" > "$T/$1.sh.hil"; }

echo "== ⓐ 표식 없이 등록 = 지금 그대로(옛 꼴) · 목록 «수신=-»"
plan A; out="$(hilx --add "$T/A.sh.hil")"; [ "$out" = "! bash $D/h1" ] && ok "--add → h1" || bad "--add out=$out"
[ ! -e "$D/h1.notify" ] && ok "  └ --notify 없으면 표식 0" || bad "표식이 생겼다"
has "$(hilx)" "h1  $T/A.sh.hil  실재  미실행" "목록 = 옛 칸 그대로"
has "$(hilx)" "수신=-" "목록 수신자 칸 = -"

echo "== ⓑ --notify <좌석> — 표식 두 줄(seat= · comm=) · comm 생략 = 부른 곳 공용 루트 쪽지함"
plan B; out="$(hilx --add "$T/B.sh.hil" --notify 'byz-planner-master-claude#91')"; [ "$out" = "! bash $D/h2" ] && ok "--notify 등록 → h2" || bad "out=$out"
[ "$(cat "$D/h2.notify" 2>/dev/null)" = "seat=byz-planner-master-claude#91
comm=$BYZ" ] && ok "  └ h2.notify = seat= · comm=$BYZ(기본 ft_comm_dir)" || bad "표식: $(cat "$D/h2.notify" 2>&1)"
has "$(hilx)" "수신=byz-planner-master-claude#91@$BYZ" "목록 = 수신=<좌석>@<쪽지함>"

echo "== ⓒ --notify-comm <쪽지함 폴더> — 다른 팀 쪽지함(aifp 꼴)을 그대로 적는다"
plan C; hilx --add "$T/C.sh.hil" --notify 'aifp-worker-master-claude#90' --notify-comm "$AIFP" >/dev/null
[ "$(sed -n 's/^comm=//p' "$D/h3.notify")" = "$AIFP" ] && ok "comm = $AIFP" || bad "comm: $(cat "$D/h3.notify" 2>&1)"
has "$(hilx)" "수신=aifp-worker-master-claude#90@$AIFP" "목록 수신자 칸 = aifp 쪽지함"

echo "== ⓓ REJECT 3종 — 좌석 린트 실패 · 쪽지함 폴더 없음 · --notify-comm 단독 (전부 rc2 · 등록 0)"
E="$T/e"; mkdir -p "$E"; hile() { env -i HOME="$T/home" PATH="/usr/bin:/bin" HIL_DIR="$E" HIL_CLIP=0 FT_SECRET_JUDGE="$T/none.py" FT_MBOX_DIR="$BYZ" bash "$HIL" "$@"; }
o="$(hile --add "$T/A.sh.hil" --notify 'byz-planner-desk-claude' 2>&1)"; rc=$?
[ "$rc" = 2 ] && has "$o" "REJECT 좌석 이름 린트 실패" "린트 실패 = REJECT rc2" || bad "린트 rc=$rc $o"
o="$(hile --add "$T/A.sh.hil" --notify 'BYZ_Planner#1' 2>&1)"; rc=$?
[ "$rc" = 2 ] && has "$o" "REJECT" "대문자·_ 좌석 = REJECT rc2" || bad "대문자 rc=$rc $o"
o="$(hile --add "$T/A.sh.hil" --notify 'byz-planner-master-claude#91' --notify-comm "$T/nope" 2>&1)"; rc=$?
[ "$rc" = 2 ] && has "$o" "REJECT 쪽지함 폴더가 없다" "쪽지함 폴더 없음 = REJECT rc2" || bad "폴더 rc=$rc $o"
o="$(hile --add "$T/A.sh.hil" --notify-comm "$AIFP" 2>&1)"; rc=$?
[ "$rc" = 2 ] && has "$o" "--notify-comm 은 --notify 와 함께" "--notify-comm 단독 = usage rc2" || bad "단독 rc=$rc $o"
[ -z "$(ls "$E" | grep '^h[0-9]')" ] && ok "  └ REJECT 4건 모두 등록 0" || bad "등록이 생겼다: $(ls "$E")"
o="$(hile --add 2>&1)"; [ "$?" = 2 ] && ok "--add 값 없음 = usage rc2" || bad "usage rc=$?"

echo "== ⓔ --supersedes 와 같이 써도 둘 다 동작"
plan F; hilx --add "$T/F.sh.hil" >/dev/null          # h4(대체 대상)
plan Z; out="$(hilx --add "$T/Z.sh.hil" --supersedes h4 --notify 'byz-planner-master-claude#92')"
[ "$out" = "! bash $D/h5" ] && ok "새 장 = h5" || bad "out=$out"
[ "$(cat "$D/h4.superseded" 2>/dev/null)" = h5 ] && ok "대체 표시 그대로" || bad "superseded: $(cat "$D/h4.superseded" 2>&1)"
[ "$(sed -n 's/^seat=//p' "$D/h5.notify" 2>/dev/null)" = "byz-planner-master-claude#92" ] && ok "  └ 새 h5.notify 도 기렭" || bad "표식 없음"

echo "== ⓕ 표식 손상은 목록에 드러난다(조용한 대체 0)"
printf 'seat=byz-planner-master-claude#91\n' > "$D/h2.notify"
has "$(hilx)" "h2  $T/B.sh.hil  실재  미실행" "손상 표식 h2 목록"
has "$(hilx)" "수신=표식 손상" "comm 줄 없음 → 수신=표식 손상"

echo "== ⓖ 틱 hil_watch — 표식 있으면 그 쪽지함의 그 좌석 1통 · planner 쪽 0 (실 mbox 사본 · 쪽지함 파일 실물)"
Q="$T/q"; mkdir -p "$Q/state" "$Q/hil"
printf '%s\n' '{"_master":"byz-planner-master-claude#92","_hil_route":"byz-planner-master-claude#91","byz-planner-master-claude#92":{"role":"master","tick":null},"byz-planner-master-claude#91":{"role":"desk","tick":null}}' > "$Q/seats.json"
# 실 mbox — 팩 harness/comm(mbox.sh·mbox.py·mbox_doorbell.sh·mbox_guard*)을 통째로 사본해 «실 저장 경로»로 보낸다(가짜 로그 스텁 0).
#   틱 명부 쪽지함(BYZ 쪽) = 틱 자신의 mbox · 표식 쪽지함 = hil_notify_marker 가 FT_MBOX_DIR 로 갈아타는 곳 · tmux 없음 = 도어벨 absent(무해)
BYZMB="$T/mb/byz/.fable-team/comm"; AIFPMB="$T/mb/aifp/.fable-team/comm"; ROMB="$T/mb/ro/.fable-team/comm"
mkdir -p "$(dirname "$BYZMB")" "$(dirname "$AIFPMB")" "$(dirname "$ROMB")"
cp -R "$HERE/../comm" "$BYZMB"; cp -R "$HERE/../comm" "$AIFPMB"; cp -R "$HERE/../comm" "$ROMB"
rows() { python3 - "$1" <<'PY'
import sys
try: ls = [l for l in open(sys.argv[1], encoding="utf-8") if l.strip()]
except FileNotFoundError: ls = []
print(len(ls))
PY
}
lastmsg() { python3 - "$1" <<'PY'
import json, sys
try: r = [json.loads(l) for l in open(sys.argv[1], encoding="utf-8") if l.strip()][-1]
except Exception: r = {}
print("%s|%s|%s" % (r.get("to", ""), r.get("from", ""), r.get("body", "")))
PY
}
clear_mb() { rm -f "$AIFPMB/mailbox.jsonl" "$BYZMB/mailbox.jsonl"; }
# ★도어벨 격리(aifp#2 제보 139548 — 시험 쪽지가 실 좌석 pane 으로 타이핑된 사고)★
#   가짜 tmux 를 PATH 앞에 두고(실 tmux 못 봄) TMUX_TMPDIR 를 임시 소켓 폴더로 돌린다 — 호출은 전부 기록만
ISO="$T/tmux-sock"; FBIN="$T/fakebin"; mkdir -p "$ISO" "$FBIN"
printf '#!/bin/bash\nprintf "%%s\\t%%s\\n" "${TMUX_TMPDIR:--}" "$*" >> "${TMUX_LOG:?}"\nexit 1\n' > "$FBIN/tmux"; chmod +x "$FBIN/tmux"
ISOENV="TMUX_TMPDIR='$ISO'"
db_iso() {  # 도어벨 격리 칸 — tmux 호출이 있으면«전부» 격리 소켓을 썼는가(아니면 실 서버로 샐 수 있다)
  [ -s "$T/tmux.log" ] || { bad "도어벨 격리: tmux 호출 기록 0(경로를 안 탔다 — 칸이 무의미)"; return; }
  local n; n="$(grep -cv "^$ISO	" "$T/tmux.log")"
  [ "$n" = 0 ] && ok "도어벨 격리: tmux 호출 $(rows "$T/tmux.log")회 전부 격리 소켓($ISO)" || bad "도어벨 격리 밖 호출 $n회: $(grep -v "^$ISO	" "$T/tmux.log" | head -2)"
  [ "$(grep -c 'send-keys' "$T/tmux.log")" = 0 ] && ok "  └ 실 pane 으로 send-keys 0(가짜 tmux = 기록만)" || bad "send-keys 가 나갔다"
}
qh() { env -i HOME="$T/home" PATH="/usr/bin:/bin" HIL_DIR="$Q/hil" HIL_CLIP=0 FT_SECRET_JUDGE="$T/none.py" FT_MBOX_DIR="$BYZ" bash "$HIL" "$@"; }
mseat() { awk '/^master_seat\(\) \{/{p=1} p{print} p&&/^\}/{p=0}' "$1"; }   # notify_team 이 부르는 명부 독해 함수(줄 88) — 추출 범위 밖이라 따로 붙인다
fn="$(mseat "$TICK")"$'\n'"$(awk '/^route_seat\(\) \{/{p=1} /^hil_marker\(\) \{/{p=1} /^hil_notify_marker\(\) \{/{p=1} /^notify_team\(\) \{/{p=1} /^hil_watch\(\) \{/{p=1} p{print} p&&/^\}/{p=0}' "$TICK")"
[ -n "$fn" ] && case "$fn" in *"hil_notify_marker"*) ok "ft-tick.sh 에서 hil_marker·hil_notify_marker·hil_watch 추출" ;; *) bad "함수 추출 불완전";; esac || bad "hil_watch 추출 실패"
watch() {  # $1 = 함수 사본(기본 = 실 ft-tick.sh) → hil_watch 1회(실 함수 · 실 notify_team · 실 mbox 사본)
  local f="${1:-$fn}"
  printf '%s\n' "$f" > "$Q/fns.sh"      # 함수 본문은 파일로 넘긴다(따옴표·$ 확장으로 본문이 틀어지는 일 방지)
  env -u FT_MBOX_DIR -u FT_SEATS_JSON -u TMUX_TMPDIR /bin/bash -c "set -a; ${ISOENV:-} TMUX_LOG='$T/tmux.log' PATH='$FBIN:/usr/bin:/bin' HIL_BIN='$HIL'; set +a
    STATE_DIR='$Q/state'; DRY=0; HIL_NOTIFY_MIN=30; SEATS='$Q/seats.json'; MBOX='$BYZMB/mbox.sh'; export HIL_DIR='$Q/hil'
    log() { :; }
    . '$Q/fns.sh'
    hil_watch" 2>>"$Q/stderr"
}
aging() { touch -t "$(date -v-45M +%Y%m%d%H%M 2>/dev/null || date -d '45 minutes ago' +%Y%m%d%H%M)" "$1"; }
plan G; qh --add "$T/G.sh.hil" --notify 'aifp-worker-master-claude#90' --notify-comm "$AIFPMB" >/dev/null; aging "$Q/hil/h1"; clear_mb
watch
[ "$(rows "$AIFPMB/mailbox.jsonl")" = 1 ] && ok "대상 쪽지함 mailbox.jsonl = 1행" || bad "대상 쪽지 수 $(rows "$AIFPMB/mailbox.jsonl"): $(lastmsg "$AIFPMB/mailbox.jsonl")"
has "$(lastmsg "$AIFPMB/mailbox.jsonl")" "aifp-worker-master-claude#90|ft-tick|[HIL 미실행] h1" "  └ to=표식 좌석 · from=ft-tick · 본문 «[HIL 미실행] h1»(실 파일)"
[ "$(rows "$BYZMB/mailbox.jsonl")" = 0 ] && ok "  └ 틱 명부 쪽지함(planner 쪽) 0행" || bad "planner 쪽지함에 쌓였다: $(lastmsg "$BYZMB/mailbox.jsonl")"
db_iso

echo "== ⓗ 표식 손상(줄 없음·폴더 없음) = 로그 ERROR 1줄 + planner «표식 손상» 1통 · 표식 보존"
: > "$Q/stderr"; clear_mb
printf 'seat=aifp-worker-master-claude#90\n' > "$Q/hil/h1.notify"; cp "$Q/hil/h1.notify" "$T/h1.before"
rm -rf "$Q/state/hil-notified"; watch
[ "$(grep -c 'ERROR 표식 손상' "$Q/stderr")" = 1 ] && ok "ERROR 1줄" || bad "ERROR 줄: $(cat "$Q/stderr")"
has "$(lastmsg "$BYZMB/mailbox.jsonl")" "byz-planner-master-claude#91|ft-tick|[HIL 미실행 · 표식 손상] h1" "planner(_hil_route) 1행 = 표식 손상"
[ "$(rows "$BYZMB/mailbox.jsonl")" = 1 ] || bad "planner 행 수 $(rows "$BYZMB/mailbox.jsonl")"
[ "$(rows "$AIFPMB/mailbox.jsonl")" = 0 ] && ok "  └ 손상 표식으로 보내지 않는다(대상 쪽지함 0행)" || bad "쪽지: $(lastmsg "$AIFPMB/mailbox.jsonl")"
cmp -s "$Q/hil/h1.notify" "$T/h1.before" && ok "  └ 표식 그대로 보존" || bad "표식이 바뀌었다"
printf 'seat=aifp-worker-master-claude#90\ncomm=%s/nope\n' "$T" > "$Q/hil/h1.notify"
: > "$Q/stderr"; clear_mb; rm -rf "$Q/state/hil-notified"; watch
has "$(cat "$Q/stderr")" "폴더 없음" "쪽지함 폴더 없음도 손상으로 읽는다"
has "$(lastmsg "$BYZMB/mailbox.jsonl")" "표식 손상" "  └ planner 1행"
[ "$(rows "$BYZMB/mailbox.jsonl")" = 1 ] || bad "planner 행 수 $(rows "$BYZMB/mailbox.jsonl")"

echo "== ⓘ 표식 없는 h = 지금처럼 planner(_hil_route)"
rm -f "$Q"/hil/h[0-9]*                    # 남은 h 는 한 개만(둘 다 오래되면 알림이 2통이 된다)
plan I; p="$(qh --add "$T/I.sh.hil")"; h="${p##*/h}"   # 표식 없는 h(번호는 상태에 달렸다)
clear_mb; rm -rf "$Q/state/hil-notified"; aging "$Q/hil/h$h"; watch
[ "$(rows "$AIFPMB/mailbox.jsonl")" = 0 ] && ok "표식 쪽지함 송신 0" || bad "쪽지: $(lastmsg "$AIFPMB/mailbox.jsonl")"
has "$(lastmsg "$BYZMB/mailbox.jsonl")" "byz-planner-master-claude#91|ft-tick|[HIL 미실행] h$h" "planner 1행(옛 꼴 그대로)"
[ "$(rows "$BYZMB/mailbox.jsonl")" = 1 ] || bad "planner 행 수 $(rows "$BYZMB/mailbox.jsonl")"
clear_mb; watch
[ "$(rows "$BYZMB/mailbox.jsonl")" = 0 ] && ok "  └ 하루 1통 선점은 수신자와 무관하게 유지" || bad "중복 알림"

echo "== ⓙ 송신 실패면 선점 되돌림(다음 틱 재시도 가능) — 못 쓰는 쪽지함(chmod 500 · 실 mbox)"
rm -f "$Q"/hil/h[0-9]*; rm -rf "$Q/state/hil-notified"; clear_mb
chmod 500 "$ROMB"
p="$(qh --add "$T/G.sh.hil" --notify 'aifp-worker-master-claude#90' --notify-comm "$ROMB")"; h="${p##*/h}"
aging "$Q/hil/h$h"; : > "$Q/stderr"; watch
chmod 700 "$ROMB"
[ ! -e "$Q/state/hil-notified/h$h.$(date +%Y%m%d)" ] && ok "실패 = 선점 해제" || bad "선점 잔류: $(ls "$Q/state/hil-notified" 2>&1)"
[ "$(rows "$ROMB/mailbox.jsonl")" = 0 ] && ok "  └ 못 쓴 쪽지함 0행" || bad "쪽지: $(rows "$ROMB/mailbox.jsonl")"
has "$(cat "$Q/stderr")" "hil_notify_marker: mbox failed" "  └ 송신 실패 stderr 1줄"
printf 'seat=aifp-worker-master-claude#90\ncomm=%s\n' "$AIFPMB" > "$Q/hil/h$h.notify"; watch
[ "$(rows "$AIFPMB/mailbox.jsonl")" = 1 ] && ok "재시도 성공 = 1행" || bad "재시도: $(rows "$AIFPMB/mailbox.jsonl") $(lastmsg "$AIFPMB/mailbox.jsonl")"

echo "== ⓚ 진입 파일 본문 변경 0 — 표식이 붙어도 옛 h 는 그대로 실행"
H="$T/hd"; mkdir -p "$H"; plan K
env -i HOME="$T/home" PATH="/usr/bin:/bin" HIL_DIR="$H" HIL_CLIP=0 FT_SECRET_JUDGE="$T/none.py" FT_MBOX_DIR="$BYZ" bash "$HIL" --add "$T/K.sh.hil" --notify 'byz-planner-master-claude#91' >/dev/null
[ "$(bash "$H" 2>/dev/null; bash "$H/h1" 2>&1)" = "ran-K" ] && ok "h1 실행 = 계획 본문만(ran-K)" || bad "실행: $(bash "$H/h1" 2>&1)"
[ -z "$(grep -v '^#' "$H/h1" | grep -E 'notify|FT_MBOX_DIR|hil_marker')" ] && ok "  └ 진입 파일 본문에 표식 코드 0" || bad "진입 파일이 바뀌었다"

echo "== 변이 1: 틱 표식 분기 삭제 → ⓖ 가 FAIL(검출)"
M="$T/mut"; mkdir -p "$M"; sed 's|^    mk="$(hil_marker "$h")"|    mk=""|' "$TICK" > "$M/ft-tick.sh"
! cmp -s "$TICK" "$M/ft-tick.sh" && ok "변이 사본이 원본과 다르다" || bad "변이 사본 = 원본"
mfn="$(mseat "$TICK")"$'\n'"$(awk '/^route_seat\(\) \{/{p=1} /^hil_marker\(\) \{/{p=1} /^hil_notify_marker\(\) \{/{p=1} /^notify_team\(\) \{/{p=1} /^hil_watch\(\) \{/{p=1} p{print} p&&/^\}/{p=0}' "$M/ft-tick.sh")"
rm -f "$Q"/hil/h[0-9]*; rm -rf "$Q/state/hil-notified"; clear_mb
plan V1; qh --add "$T/V1.sh.hil" --notify 'aifp-worker-master-claude#90' --notify-comm "$AIFPMB" >/dev/null; aging "$Q/hil/h1"
watch "$mfn"
[ "$(rows "$AIFPMB/mailbox.jsonl")" = 0 ] && has "$(lastmsg "$BYZMB/mailbox.jsonl")" "byz-planner-master-claude#91|ft-tick|[HIL 미실행] h1" "변이: 표식 쪽 0행 · planner 로 감 = ⓖ FAIL" || bad "변이가 ⓖ 를 못 깬다: $(rows "$AIFPMB/mailbox.jsonl") $(lastmsg "$AIFPMB/mailbox.jsonl")"

echo "== 변이 2: 손상 경로의 ERROR 로그 제거 → ⓗ 가 FAIL(검출)"
sed 's|^      !\*) echo "$(date .+%F %T.) hil_watch: ERROR 표식 손상.*$|      !*) :|' "$TICK" > "$M/ft-tick2.sh"
! cmp -s "$TICK" "$M/ft-tick2.sh" && ok "변이 사본이 원본과 다르다" || bad "변이 2 사본 = 원본"
mfn="$(mseat "$TICK")"$'\n'"$(awk '/^route_seat\(\) \{/{p=1} /^hil_marker\(\) \{/{p=1} /^hil_notify_marker\(\) \{/{p=1} /^notify_team\(\) \{/{p=1} /^hil_watch\(\) \{/{p=1} p{print} p&&/^\}/{p=0}' "$M/ft-tick2.sh")"
rm -f "$Q"/hil/h[0-9]*; rm -rf "$Q/state/hil-notified"; clear_mb
plan V2; qh --add "$T/V2.sh.hil" >/dev/null; printf 'seat=aifp-worker-master-claude#90\n' > "$Q/hil/h1.notify"; aging "$Q/hil/h1"
: > "$Q/stderr"
watch "$mfn"
not "$(cat "$Q/stderr")" "ERROR 표식 손상" "변이: ERROR 0줄 = ⓗ FAIL"

echo "== 변이 3: hil_notify_marker 의 FT_MBOX_DIR 주입 삭제 → ⓖ(실 파일) 가 FAIL(검출)"
sed 's|^  FT_MBOX_DIR="$2" bash "$MBOX" send|  bash "$MBOX" send|' "$TICK" > "$M/ft-tick3.sh"
! cmp -s "$TICK" "$M/ft-tick3.sh" && ok "변이 사본이 원본과 다르다" || bad "변이 3 사본 = 원본"
mfn3="$(mseat "$TICK")"$'\n'"$(awk '/^route_seat\(\) \{/{p=1} /^hil_marker\(\) \{/{p=1} /^hil_notify_marker\(\) \{/{p=1} /^notify_team\(\) \{/{p=1} /^hil_watch\(\) \{/{p=1} p{print} p&&/^\}/{p=0}' "$M/ft-tick3.sh")"
rm -f "$Q"/hil/h[0-9]*; rm -rf "$Q/state/hil-notified"; clear_mb
plan V3; qh --add "$T/V3.sh.hil" --notify 'aifp-worker-master-claude#90' --notify-comm "$AIFPMB" >/dev/null; aging "$Q/hil/h1"
watch "$mfn3"
[ "$(rows "$AIFPMB/mailbox.jsonl")" = 0 ] && has "$(lastmsg "$BYZMB/mailbox.jsonl")" "aifp-worker-master-claude#90|ft-tick|[HIL 미실행] h1" "변이: 대상 쪽지함 0행(틱 명부 쪽지함으로 샘) = ⓖ FAIL" || bad "변이 3 이 ⓖ 를 못 깬다: $(rows "$AIFPMB/mailbox.jsonl") $(lastmsg "$AIFPMB/mailbox.jsonl")"

echo "== 변이 4: 도어벨 격리(TMUX_TMPDIR) 삭제 → 격리 칸 FAIL(검출)"
rm -f "$T/tmux.log"
ISOENV=""            # 격리 삭제 = 진짜 tmux 기본 소켓을 보게 된다(가짜 tmux 가 마지막 방어)
rm -f "$Q"/hil/h[0-9]*; rm -rf "$Q/state/hil-notified"; clear_mb
plan V4; qh --add "$T/V4.sh.hil" --notify 'aifp-worker-master-claude#90' --notify-comm "$AIFPMB" >/dev/null; aging "$Q/hil/h1"
watch
ISOENV="TMUX_TMPDIR='$ISO'"
[ -n "$(grep -cv "^$ISO	" "$T/tmux.log" 2>/dev/null)" ] && ok "변이: 격리 밖 tmux 호출 = 격리 칸 FAIL" || bad "변이 4 가 격리 칸을 못 깬다"

echo "== 키트 두 벌 cmp"
cmp -s "$HERE/../../harness/bin/ft-hil.sh" "$SRC/ft-hil.sh" && ok "ft-hil.sh cmp 0" || bad "ft-hil.sh 키트 다름"
cmp -s "$HERE/../../harness/bin/ft-tick.sh" "$SRC/ft-tick.sh" && ok "ft-tick.sh cmp 0" || bad "ft-tick.sh 키트 다름"

[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
