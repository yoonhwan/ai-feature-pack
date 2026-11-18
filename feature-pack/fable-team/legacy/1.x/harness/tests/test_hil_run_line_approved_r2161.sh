#!/usr/bin/env bash
# test_hil_run_line_approved_r2161.sh — r2161: 계획이 승인값(HIL_APPROVED)을 읽는 h 는 실행 줄 뒤에 «승인값 필요(사람 …)» 표지 · «HIL_APPROVED=1» 글자 0 (반례 ①~⑦ · 변이 M1~M4)
# 네 자리 = ft-hil.sh --add stdout(+클립보드) · ft-hil-notify.sh issue 쪽지 · done «다음 실행 줄» · ft-tick hil_watch [HIL 미실행] 쪽지(함수만 떼어 대역으로 부름)
# 격리: 임시 HIL_DIR · 임시 계획 · 가짜 mbox(받은 줄을 파일에) · 가짜 pbcopy(파일에) — 실 /tmp/h* · 실 쪽지 · 실 h 실행 0 · sleep 0
# 기준판 대조: FT_R2161_BIN=<팩 origin/main bin 사본> 이면 ①~④ FAIL(표지 0)
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="${FT_R2161_BIN:-$HERE/../bin}"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
TAG=' · 승인값 필요(사람 · 변수 HIL_APPROVED · 오빠 ! 줄로만)'
SEAT='byz-planner-desk-pi#125'
FBIN="$T/fakebin"; mkdir -p "$FBIN" "$T/home"
printf '#!/bin/bash\ncat > "$CLIPF"\n' > "$FBIN/pbcopy"; chmod +x "$FBIN/pbcopy"
plan() { printf '#!/usr/bin/env bash\n%s\necho ok\n' "$2" > "$T/$1.sh.hil"; echo "$T/$1.sh.hil"; }
PA="$(plan A '[ "${HIL_APPROVED:-}" = 1 ] || exit 2')"      # 읽기(가드)
PA2="$(plan A2 'echo "$HIL_APPROVED"')"                      # 읽기($ 꼴)
PB="$(plan B 'HIL_APPROVED=1 bash sub.sh')"                  # 대입만
PC="$(plan C '  # needs $HIL_APPROVED')"                     # 주석 줄에만
PD="$(plan D 'echo plain')"                                  # 글자 0

world() {  # <폴더> — hil/ · comm/mbox.sh(가짜 · to·본문 적기) · seats-planner.json
  mkdir -p "$1/hil" "$1/comm"
  printf '#!/usr/bin/env bash\nd="$(cd -- "$(dirname -- "$0")" && pwd)"; printf "%%s\\t%%s\\n" "$2" "$4" >> "$d/sent"\n' > "$1/comm/mbox.sh"
  printf '{"_master":"byz-planner-master-pi#9"}\n' > "$1/seats-planner.json"
}
add() {  # <bin> <world> <계획> [--notify] → stdout = 등록 출력
  local b="$1" w="$2" p="$3" n=(); [ "${4:-}" = --notify ] && n=(--notify "$SEAT" --notify-comm "$w/comm")
  env -i HOME="$T/home" PATH="$FBIN:/usr/bin:/bin" HIL_DIR="$w/hil" HIL_CLIP=1 CLIPF="$w/clip" FT_SECRET_JUDGE="$T/none.py" FT_MBOX_DIR="$T/else" \
    bash "$b/ft-hil.sh" --add "$p" ${n[@]+"${n[@]}"} 2>>"$w/err"
}
fin() { printf '%s\nrc=0 %s\n' "$(date +%s)" "$(date +%s)" > "$1.ran"; }
aging() { touch -t "$(date -v-45M +%Y%m%d%H%M 2>/dev/null || date -d '45 minutes ago' +%Y%m%d%H%M)" "$1"; }
tick() {  # <bin> <world> → hil_watch 1회(ft-tick.sh 의 hil_watch 만 떼어 · 쪽지 = 파일) · stdout = 보낸 본문
  local b="$1" w="$2"
  awk '/^hil_watch\(\) \{/{p=1} p{print} p&&/^\}/{p=0}' "$b/ft-tick.sh" > "$w/fns.sh"
  env -i HOME="$T/home" PATH="/usr/bin:/bin" /bin/bash -c "HIL_BIN='$b/ft-hil.sh'; STATE_DIR='$w/state'; DRY=0; HIL_NOTIFY_MIN=30; SEATS='$w/seats.json'; export HIL_DIR='$w/hil'
    log() { :; }; hil_marker() { :; }; notify_team() { printf '%s\n' \"\$1\" >> '$w/tick'; }; hil_notify_marker() { notify_team \"\$3\"; }
    . '$w/fns.sh'; hil_watch" 2>>"$w/err"
  cat "$w/tick" 2>/dev/null
}
four() {  # <bin> <계획> [rm] → O_ADD O_CLIP O_ISSUE O_NEXT O_TICK (h1 = 그 계획 · h2 = 끝난 다른 계획 · rm = 등록 뒤 계획 지움)
  local b="$1" w; w="$(mktemp -d "$T/w.XXXXXX")"; world "$w"
  O_ADD="$(add "$b" "$w" "$2" --notify)"; O_CLIP="$(cat "$w/clip" 2>/dev/null)"; O_ISSUE="$(cut -f2 "$w/comm/sent" 2>/dev/null | head -1)"
  [ "${3:-}" != rm ] || rm -f "$2"
  add "$b" "$w" "$PD" >/dev/null; fin "$w/hil/h2"
  O_NEXT="$(env -i PATH="/usr/bin:/bin" bash "$b/ft-hil-notify.sh" done "$w/hil/h2" 0 "$w/comm" 2>>"$w/err" | grep '^다음 실행 줄')"
  aging "$w/hil/h1"; O_TICK="$(tick "$b" "$w")"; WD="$w"
}
no1() { case "$1" in *HIL_APPROVED=1*) return 1;; esac; }   # «=1» 글자 0
c1() { four "$1" "$PA"; local h="$WD/hil/h1"
  [ "$O_ADD" = "! bash $h$TAG" ] && [ "$O_CLIP" = "bash $h" ] && no1 "$O_ADD$O_CLIP" || { echo "① add=«${O_ADD}» clip=«${O_CLIP}»"; return 1; }; }
c2() { four "$1" "$PA"; case "$O_ISSUE" in *"실행 줄 = ! bash $WD/hil/h1$TAG"*) no1 "$O_ISSUE" && return 0;; esac; echo "② issue=«${O_ISSUE}»"; return 1; }
c3() { four "$1" "$PA"; [ "$O_NEXT" = "다음 실행 줄 = ! bash $WD/hil/h1$TAG" ] && no1 "$O_NEXT" || { echo "③ next=«${O_NEXT}»"; return 1; }; }
c4() { four "$1" "$PA"; case "$O_TICK" in *"오빠가 칠 줄 = ! bash $WD/hil/h1$TAG"*) no1 "$O_TICK" && return 0;; esac; echo "④ tick=«${O_TICK}»"; return 1; }
plain() {  # <bin> <계획> [rm] — 네 자리 모두 지금 줄 그대로(표지 0)
  four "$1" "$2" "${3:-}"; local h="$WD/hil/h1" e=""
  [ "${3:-}" = rm ] || [ "$O_ADD" = "! bash $h" ] || e="$e add=«${O_ADD}»"
  [ "${3:-}" = rm ] || case "$O_ISSUE" in *"실행 줄 = ! bash $h (자율 ON"*) ;; *) e="$e issue=«${O_ISSUE}»";; esac
  [ "$O_NEXT" = "다음 실행 줄 = ! bash $h" ] || e="$e next=«${O_NEXT}»"
  case "$O_TICK" in *"오빠가 칠 줄 = ! bash $h (이미"*) ;; *) e="$e tick=«${O_TICK}»";; esac
  [ -z "$e" ] || { echo "${2##*/}:$e"; return 1; }; }
c5() { plain "$1" "$PB" && plain "$1" "$PC"; }
c6() { local o rc; plain "$1" "$PD" || return 1; cp "$PA" "$T/gone.sh.hil"; plain "$1" "$T/gone.sh.hil" rm || return 1
  o="$(bash "$1/ft-hil-gate.sh" run-line "$T/none-h" 2>/dev/null)"; rc=$?
  [ "$rc" = 0 ] && [ "$o" = "bash $T/none-h" ] || { echo "⑥ 없는 h run-line rc=$rc «${o}»"; return 1; }; }
c7() { local w o p q; w="$(mktemp -d "$T/w.XXXXXX")"; world "$w"; : > "$w/hil/h12344"; o="$(add "$1" "$w" "$PA2")"
  p="${o%% · *}"; q="! bash /tmp/${p##*/}"
  [ "$p" = "! bash $w/hil/h12345" ] && [ "${o#"$p"}" = "$TAG" ] && [ "${#q}" -le 60 ] || { echo "⑦ «${o}» q=${#q}"; return 1; }; }
chk() { local o; o="$("$1" "$2")" && ok "$3" || bad "$3 — $o"; }

t0=$(date +%s)
echo "== 계약 ①~⑦ (bin = ${BIN})"
chk c1 "$BIN" "① 등록 출력 = ! bash h · 표지 · 클립보드 = bash h · =1 글자 0"
chk c2 "$BIN" "② issue 쪽지 실행 줄 + 표지 · =1 글자 0"
chk c3 "$BIN" "③ done 다음 실행 줄 + 표지 · =1 글자 0"
chk c4 "$BIN" "④ ft-tick [HIL 미실행] 오빠가 칠 줄 + 표지 · =1 글자 0"
chk c5 "$BIN" "⑤ 대입만 · 주석 줄에만 = 네 자리 지금 줄"
chk c6 "$BIN" "⑥ 글자 0 · 계획 지움 = 지금 줄 · 없는 h run-line rc 0"
chk c7 "$BIN" "⑦ 앞부분 ! bash /tmp/h<N> 불변 · ≤60자(h 5자리)"
K="$HERE/../kit/fable-team/bin"
if [ -z "${FT_R2161_BIN:-}" ]; then
  for f in ft-hil-gate.sh ft-hil.sh ft-hil-notify.sh ft-tick.sh; do cmp -s "$BIN/$f" "$K/$f" && ok "cmp0 kit $f" || bad "kit 사본 다름: $f"; done
  echo "== 변이 (사본 · 변이마다 원본 같은 사례 1회 더)"
  mut() {  # <이름> <파일> <옛 글자> <새 글자> <사례…>
    local m="$T/$1" c r; mkdir -p "$m"; cp -R "$BIN/." "$m/"; shift
    python3 -c 'import sys;p,a,b=sys.argv[1:4];s=open(p,encoding="utf-8").read();assert a in s,a;open(p,"w",encoding="utf-8").write(s.replace(a,b))' "$m/$1" "$2" "$3" \
      || { bad "${m##*/} 변이 글자 못 찾음"; return; }
    local f="$1"; shift 3
    for c in "$@"; do
      r="$("$c" "$m")" && bad "${m##*/} 가 $c 를 못 깬다" || ok "${m##*/}: $c FAIL — ${r:0:160}"
      "$c" "$BIN" >/dev/null && ok "  └ 원본 $c PASS" || bad "  └ 원본 $c FAIL"
    done; }
  mut M1 ft-hil-gate.sh '|| t="$TAG_R"' '|| :' c1 c2 c3 c4
  mut M2 ft-hil-gate.sh "awk '!/^[[:space:]]*#/ && (/\\\$HIL_APPROVED/ || /\\\$[{]HIL_APPROVED/) {f=1} END {exit !f}'" "awk '/HIL_APPROVED/ {f=1} END {exit !f}'" c5
  mut M3 ft-hil-notify.sh 'rl() { local l;' 'rl() { printf "bash %s" "$1"; return; local l;' c2 c3
  mut M4 ft-hil-gate.sh 'echo "bash ${2:-}$t"' 'echo "${t:+HIL_APPROVED=1 }bash ${2:-}"' c1 c2 c3 c4
fi
echo "단계별 초: 전체 $(( $(date +%s) - t0 ))초"
[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILED $fail"
exit "$fail"
