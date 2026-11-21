# _pushahead_r2368_fixture.sh — r2368 시험 공용(source 전용 · r2355 격리 위에 얹는다): «하네스 코드 루트를 풀 수 있는» 임시 리포(HR·W2) · 설치 검사 스텁(앞 대조/뒤 검사 구분 = PRE/POST) · 느린 press/push 가짜 도구(push 뒤 $PUSHED 표식) · 알림 관측
#   pa_init <임시폴더> = fx_init(r2355) + HR(팩 꼴 임시 리포 · kit/fable-team 있음) + 스텁 1벌 · pa_fix = 사본 + press EAT 스텁 + 알림 줄 · pa_bin = W2(같은 origin 의 다른 체크아웃)
#   pa_tool <bin> <번호> <바깥초> <플래그> [KEY=VAL…] = 착지 1회(PRE/POST 로그·$PUSHED 초기화 · PATH = 느린 push) · icpre/icpost = 부른 횟수 · qsha = 착지 sha · pend = 대기 파일 자리
#   PRESS_EAT=<초> / PUSH_EAT=<초> = 가짜 도구가 «마감 남은 초를 그 값까지 깎는다»(① 의 «뒤 단계 남은 0» 주입) · DL_OFF=<초> = 호출 직전 마감(pa_tool) · 실 원격·실 gh·실 mbox 0 · sleep 은 가짜 도구 안에서만
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/_reserve_r2355_fixture.sh"

SHIMNOTE='OK n=0 skip=0 (하네스 루트가 --repo 밖 · 범위에 하네스 파일 0)'
EATSRC='import sys, time
d = int(sys.argv[1]); t = float(sys.argv[2])
mode = sys.argv[3] if len(sys.argv) > 3 else "cap"
c = float(sys.argv[4]) if len(sys.argv) > 4 else 99.0
if mode == "align":
    while time.time() % 1.0 < 0.30: pass
    s = (d - time.time()) - t
else:
    s = (d - time.time()) - t
    if s > c: s = c
print("%.2f" % (0.0 if s < 0 else s))'
pa_init() {   # pa_init <임시 폴더> — r2355 격리 + 이 카드용 스텁
  fx_init "$1"
  HR="$T/hr"; mkdir -p "$HR/kit/fable-team/bin" "$W/kit/fable-team/bin"
  printf '#!/bin/bash\necho x\n' > "$HR/kit/fable-team/bin/ft-x.sh"
  printf 'hr\n' > "$HR/README"; git -C "$HR" init -q 2>/dev/null
  git -C "$HR" -c user.name=t -c user.email=t@t add -A >/dev/null 2>&1
  git -C "$HR" -c user.name=t -c user.email=t@t commit -qm hr >/dev/null 2>&1
  PUSHED="$T/pushed"; ICLOG="$T/ic.log"; PEND="$D/.fable-team/state/install-pending"; export PUSHED ICLOG
  mkdir -p "$T/pbin"
  printf '%s\n' "$EATSRC" > "$T/eat.py"
  # push 만 감싼다 — PUSH_EAT 면 마감 남은 초를 그 값까지 깎고, 끝나면 $PUSHED 표식(앞 대조/뒤 검사를 가르는 축)
  cat > "$T/pbin/git" <<EOF
#!/bin/bash
_p=0; for a in "\$@"; do case "\$a" in push) _p=1;; esac; done
[ "\$_p" = 0 ] && exec "$REAL_GIT" "\$@"
if [ -n "\${PUSH_EAT:-}" ] && [ -n "\${FT_LAND_DEADLINE:-}" ]; then sleep "\$(python3 "$T/eat.py" "\$FT_LAND_DEADLINE" "\$PUSH_EAT" cap "\${PUSH_EAT_CAP:-99}")"; fi
"$REAL_GIT" "\$@"; _r=\$?
[ -z "\${PUSHED:-}" ] || : > "\$PUSHED"
exit \$_r
EOF
  printf '#!/bin/bash\nif [ -e "${PUSHED:-/nonexistent}" ]; then echo "POST $*" >> "$ICLOG"; p="${IC_POST:-0}"; else echo "PRE $*" >> "$ICLOG"; p="${IC_PRE:-0}"; fi\ncase "$p" in 0) echo "%s"; exit 0;; 1) echo "OK n=1 (뒤 검사 스텁)"; exit 0;; 2) echo "OK n=2 diff"; exit 0;; 3) echo "ERROR 범위에 옛 하네스 경로 파일(스텁)"; exit 3;; h) while :; do :; done;; esac\nexit 0\n' "$SHIMNOTE" > "$T/ic-stub"
  chmod +x "$T/pbin/git" "$T/ic-stub"
  export FT_INSTALL_CHECK="$T/ic-stub"
}
pa_fix() {   # pa_fix — 스텁 투입 사본 + press 상한을 마감까지 깎는 스텁(PRESS_EAT) + 알림 1줄(NOTIFIED … install=<irc>)
  fx_fix
  cat > "$FIX/ft-press-evidence.sh" <<EOF
#!/bin/bash
if [ -n "\${PRESS_EAT:-}" ] && [ -n "\${FT_LAND_DEADLINE:-}" ]; then sleep "\$(python3 "$T/eat.py" "\$FT_LAND_DEADLINE" "\$PRESS_EAT" "\${PRESS_ALIGN:+align}" )"; fi
[ -z "\${PRESS_RC:-}" ] || exit "\$PRESS_RC"
exit 0
EOF
  cat > "$FIX/ft-bg-loop-lint.sh" <<EOF
#!/bin/bash
[ -z "\${LINT_EAT:-}" ] || sleep "\$(python3 "$T/eat.py" "\$FT_LAND_DEADLINE" "\$LINT_EAT")"
exit 0
EOF
  printf '#!/bin/bash\nexit 0\n' > "$FIX/ft-tmux-target-lint.sh"
  chmod +x "$FIX/ft-press-evidence.sh" "$FIX/ft-bg-loop-lint.sh" "$FIX/ft-tmux-target-lint.sh"
  printf 'fm_land_notify_land() { echo "NOTIFIED pr=$2 sha=$3 install=$5"; }\n' >> "$FIX/ft-merge-lib.sh"
}
pa_bin() {   # pa_bin — 같은 origin 의 다른 체크아웃(⑨): 하네스 코드 루트가 REPO 밖 다른 경로
  W2="$T/w2"; git clone -q "$ORIGIN" "$W2" 2>/dev/null; mkdir -p "$W2/kit/fable-team/bin"
  printf '#!/bin/bash\necho x\n' > "$W2/kit/fable-team/bin/ft-x.sh"; printf 'w2\n' > "$W2/README"
}
pa_tool() {   # pa_tool <bin> <번호> <바깥초> <플래그> [KEY=VAL…]
  local b="$1" n="$2" o="$3" fl="$4" s; shift 4
  mkpr "$n"; apv --approve-sha "${APSH:-$PRSHA}"; : > "$STUB_LOG"; rm -f "$PFILE" "$PUSHED" "$ICLOG"; : > "$ICLOG"
  s=$SECONDS
  # shellcheck disable=SC2086
  if [ -n "${DL_OFF:-}" ]; then
    out="$(env "FT_LAND_DEADLINE=$(( $(date +%s) + DL_OFF ))" PATH="$T/pbin:$PATH" "$@" "$TBIN" "$o" bash "$b/ft-merge-land.sh" "$n" --approve-sha "${APSH:-$PRSHA}" --repo "$W" $fl 2>&1)"
  else
    out="$(env PATH="$T/pbin:$PATH" "$@" "$TBIN" "$o" bash "$b/ft-merge-land.sh" "$n" --approve-sha "${APSH:-$PRSHA}" --repo "$W" $fl 2>&1)"
  fi
  rc=$?; el=$((SECONDS - s)); qsha="$(sed -n 's/^LANDED pr=[0-9]* sha=\([0-9a-f]*\).*/\1/p' <<<"$out")"
}
icpre() { grep -c '^PRE ' "$ICLOG" 2>/dev/null; }   # 앞 대조(= push 앞) 부른 횟수
icpost() { grep -c '^POST ' "$ICLOG" 2>/dev/null; }   # 뒤 검사 부른 횟수
pend() { [ -f "$PEND/$1.txt" ]; }
ltail() { grep -m1 '^LAND-TAIL ' <<<"$out"; }
closes() { grep -c 'pr-close' "$STUB_LOG" 2>/dev/null; }
# ① 의 «뒤 단계 남은 0» 주입: 마감 12초 · press 가 마감을 8.5초까지 깎고 push 가 0.6초까지 깎는다 → 꼬리 남은 ≤ 3(K1 은 그 앞이라 상한 ≥ 1)
PA_DL=20; PA_PRESSEAT=9.5; PA_PUSHEAT=0.6; PA_PUSHCAP=7.5
# ② 의 «남은 − PV < 1» 주입: press 가 마감을 «7.98초»(초 경계 0.30 뒤 정렬)까지 깎는다 → 남은 = 8 = PV · K1 상한 0 · push 는 그대로 시도(REM 8 ≥ PV 8)

# ── 반례 사례 p* (①~⑬ · 변이·기준판 Red 시험도 같은 함수를 쓴다) ──
p1() {   # ①⑩ 하네스 밖 리포 · 앞 대조 ok · 뒤 단계 남은 0(총 마감 11 · push 7초) → 대기 파일 0 · r2368 줄 1 · 앞 대조 1 · 착지 1 · 알림 설치 칸 0
  local a=0 b=0 lt
  IC_PRE=0 IC_POST=0 FT_HARNESS_ROOT="$HR" DL_OFF=$PA_DL PRESS_EAT=$PA_PRESSEAT PUSH_EAT=$PA_PUSHEAT PUSH_EAT_CAP=$PA_PUSHCAP FT_PUSH_FIXED_S=1 pa_tool "$1" 201 40 ""
  { [ "$rc" = 0 ] && grep -q '^LANDED pr=201 ' <<<"$out" && [ -n "$qsha" ] && [ "$(icpre)" = 1 ] && [ "$(icpost)" = 0 ] && ! pend "$qsha" && \
    grep -qxF "INSTALL $SHIMNOTE · push 앞 대조(r2368)" <<<"$out"; } && a=1
  lt="$(ltail)"
  { [ "$rc" = 0 ] && { [ "$(closes)" = 1 ] || grep -q '^WARN 착지는 성공 — PR #201 코멘트/닫기 실패' <<<"$out"; } && \
    grep -q "^NOTIFIED pr=201 sha=${qsha:0:10} install=0$" <<<"$out" && \
    { [ -z "$lt" ] || [[ "$lt" == *" install=0 "* ]]; } && grep -qE '^(SKIP 카드 없음|WARN 카드 토큰 0|판정 불가 — 카드 파일만)' <<<"$out"; } && b=1
  [ "$a$b" = 11 ]
}
p2() {   # ② 하네스 밖 리포 · push 앞 남은 − PV < 1 → 앞 대조 호출 0 · push 시도 1 · REJECT «push 몫 예약» 0
  local a=0
  rm -f "$TSV"
  DL_OFF=12 PRESS_EAT=7.98 PRESS_ALIGN=1 IC_PRE=0 IC_POST=1 FT_HARNESS_ROOT="$HR" FT_PUSH_FIXED_S=1 pa_tool "$1" 202 40 ""
  unset DL_OFF
  { [ "$rc" = 0 ] && grep -q '^LANDED pr=202 ' <<<"$out" && [ "$(icpre)" = 0 ] && [ "$(icpost)" = 1 ] && \
    grep -q '^push ok objects=' <<<"$out" && [ "$(grep -c . "$TSV" 2>/dev/null)" = 1 ] && ! grep -q '^REJECT .*push 몫 예약' <<<"$out"; } && a=1
  [ "$a" = 1 ]
}
p3() {   # ③⑬ 팩 리포(코드 루트가 REPO 안) → 앞 대조 0 · 뒤 검사 1 · ⑬ 기준판과 같은 꼴(설치 줄·닫기·LAND-PHASE 칸 이름·rc·대기 파일)
  local a=0 b=0 f1 f2 ph1 ph2 cl1=0
  mkdir -p "$W/kit/fable-team/bin"; printf '#!/bin/bash\necho x\n' > "$W/kit/fable-team/bin/ft-x.sh"
  IC_PRE=0 IC_POST=0 FT_HARNESS_ROOT="$W" FT_PUSH_FIXED_S=1 pa_tool "$1" 203 40 ""
  f1="$out"; cl1="$(closes)"; { [ "$rc" = 0 ] && [ "$(icpre)" = 0 ] && [ "$(icpost)" = 1 ] && grep -q "^INSTALL $SHIMNOTE$" <<<"$out" && [ -n "$qsha" ] && ! pend "$qsha"; } && a=1
  if [ -z "${BASE:-}" ]; then [ "$a" = 1 ]; return $?; fi
  ph1="$(grep -oE '(pr|close|view|fetch|gate|overlap|equiv|press|lint|push|etc|total|left|skip)=' <<<"$(grep -m1 '^LAND-PHASE ' <<<"$f1")" | tr '\n' ' ')"
  IC_PRE=0 IC_POST=0 FT_HARNESS_ROOT="$W" FT_PUSH_FIXED_S=1 pa_tool "$BASE" 214 40 ""
  f2="$out"; ph2="$(grep -oE '(pr|close|view|fetch|gate|overlap|equiv|press|lint|push|etc|total|left|skip)=' <<<"$(grep -m1 '^LAND-PHASE ' <<<"$f2")" | tr '\n' ' ')"
  { [ "$rc" = 0 ] && grep -q '^LANDED pr=214 ' <<<"$f2" && [ "$(grep -c '^INSTALL ' <<<"$f1")" = "$(grep -c '^INSTALL ' <<<"$f2")" ] && \
    [ "$(grep '^INSTALL ' <<<"$f1")" = "$(grep '^INSTALL ' <<<"$f2")" ] && [ "$ph1" = "$ph2" ] && [ -n "$ph1" ] && \
    [ "$(grep -c '^LAND-TAIL' <<<"$f1")" = "$(grep -c '^LAND-TAIL' <<<"$f2")" ] && [ "$cl1" = 1 ]; } && b=1
  [ "$a$b" = 11 ]
}
p4() {   # ④ --dry · 하네스 밖 리포 → 앞 대조 부름 0 · DRY 출력이 기준판과 «같은 글자»
  local a=0 d1="" d2=""
  mkpr 204; apv --approve-sha "$PRSHA"; : > "$STUB_LOG"; rm -f "$PUSHED" "$ICLOG"
  [ -z "${BASE:-}" ] || { out="$(env PATH="$T/pbin:$PATH" FT_HARNESS_ROOT="$HR" FT_PUSH_FIXED_S=1 "$TBIN" 40 bash "$BASE/ft-merge-land.sh" 204 --approve-sha "$PRSHA" --repo "$W" --dry 2>&1)"; d2="$(grep -m1 '^DRY ' <<<"$out")"; }
  rm -f "$PUSHED" "$ICLOG"
  out="$(env PATH="$T/pbin:$PATH" FT_HARNESS_ROOT="$HR" FT_PUSH_FIXED_S=1 "$TBIN" 40 bash "$1/ft-merge-land.sh" 204 --approve-sha "$PRSHA" --repo "$W" --dry 2>&1)"; rc=$?
  d1="$(grep -m1 '^DRY ' <<<"$out")"
  { [ "$rc" = 0 ] && [[ "$d1" == "DRY ALLOW pr=204 "* ]] && [ ! -s "$ICLOG" ] && [ -z "${BASE:-}" -o "$d1" = "$d2" ]; } && a=1
  [ "$a" = 1 ]
}
p5() {   # ⑤ 하네스 밖 리포 · --ff 착지 · 뒤 단계 남은 0 → 앞 대조 부름 1 · 대기 파일 0 · 착지 1
  local a=0
  IC_PRE=0 IC_POST=0 FT_HARNESS_ROOT="$HR" DL_OFF=$PA_DL PRESS_EAT=$PA_PRESSEAT PUSH_EAT=$PA_PUSHEAT PUSH_EAT_CAP=$PA_PUSHCAP FT_PUSH_FIXED_S=1 pa_tool "$1" 205 40 "--ff"
  { [ "$rc" = 0 ] && grep -q '^LANDED pr=205 .* mode=ff$' <<<"$out" && [ "$(icpre)" = 1 ] && [ "$(icpost)" = 0 ] && [ -n "$qsha" ] && ! pend "$qsha" && \
    grep -qxF "INSTALL $SHIMNOTE · push 앞 대조(r2368)" <<<"$out"; } && a=1
  [ "$a" = 1 ]
}
p6() {   # ⑥ 앞 대조 rc3(범위에 옛 하네스 경로 파일) → HPRE 0 · 뒤 검사 부름 1 (조용한 통과 0)
  IC_PRE=3 IC_POST=1 FT_HARNESS_ROOT="$HR" FT_PUSH_FIXED_S=1 pa_tool "$1" 206 40 ""
  [ "$rc" = 0 ] && [ "$(icpre)" = 1 ] && [ "$(icpost)" = 1 ] && grep -q '^LANDED pr=206 ' <<<"$out" && \
    ! grep -q 'push 앞 대조(r2368)' <<<"$out" && [ -z "$qsha" -o -z "$(pend "$qsha" && echo y)" ]
}
p6b() {  # ⑥-b ⑥ + 뒤 검사 끊김(124) → 대기 파일 + range 줄(지금 꼴)
  IC_PRE=3 IC_POST=h FT_INSTALL_CHECK_TIMEOUT=1 FT_HARNESS_ROOT="$HR" FT_PUSH_FIXED_S=1 pa_tool "$1" 216 40 ""
  local m; m="$(sed -n 's/.*main_before=\([0-9a-f]*\).*/\1/p' <<<"$out")"
  [ "$rc" = 0 ] && [ "$(icpre)" = 1 ] && [ "$(icpost)" = 1 ] && [ -n "$qsha" ] && pend "$qsha" && \
    [ "$(head -n1 "$PEND/$qsha.txt")" = 'INSTALL-PENDING 검사 시간 초과' ] && [ "$(tail -n1 "$PEND/$qsha.txt")" = "range=$m..$qsha" ]
}
p7() {   # ⑦ 앞 대조 끊김(가짜 지연 > 상한) → HPRE 0 · push 시도 1 · 착지 1 · 뒤 길 그대로
  IC_PRE=h IC_POST=1 FT_INSTALL_CHECK_TIMEOUT=1 FT_HARNESS_ROOT="$HR" FT_PUSH_FIXED_S=1 pa_tool "$1" 207 40 ""
  [ "$rc" = 0 ] && [ "$(icpre)" = 1 ] && [ "$(icpost)" = 1 ] && grep -q '^LANDED pr=207 ' <<<"$out" && ! grep -q 'push 앞 대조(r2368)' <<<"$out"
}
p8() {   # ⑧ 앞 대조 rc0 첫 줄 «OK n=2» → HPRE 0 · 뒤 검사 부름 1
  IC_PRE=2 IC_POST=1 FT_HARNESS_ROOT="$HR" FT_PUSH_FIXED_S=1 pa_tool "$1" 208 40 ""
  [ "$rc" = 0 ] && [ "$(icpre)" = 1 ] && [ "$(icpost)" = 1 ] && grep -q '^LANDED pr=208 ' <<<"$out" && ! grep -q 'push 앞 대조(r2368)' <<<"$out"
}
p9() {   # ⑨ REPO = 팩 리포의 다른 체크아웃(코드 루트 밖 경로) · 범위에 harness/kit → 앞 대조 rc3 → HPRE 0 · 뒤 길 그대로
  IC_PRE=3 IC_POST=1 FT_HARNESS_ROOT="$W2" FT_PUSH_FIXED_S=1 pa_tool "$1" 209 40 ""
  [ "$rc" = 0 ] && [ "$(icpre)" = 1 ] && [ "$(icpost)" = 1 ] && grep -q '^LANDED pr=209 ' <<<"$out" && ! grep -q 'push 앞 대조(r2368)' <<<"$out"
}
p11() {  # ⑪ 팩 리포 · 뒤 단계 남은 ≤ 3(ITO 0) → 검사 부름 0 · «판정 불가 — 설치 검사 호출 0(남은 0초)» · 대기 파일 = «검사 시간 초과» + range 줄
  local m
  DL_OFF=$PA_DL PRESS_EAT=$PA_PRESSEAT PUSH_EAT=$PA_PUSHEAT PUSH_EAT_CAP=$PA_PUSHCAP IC_PRE=0 IC_POST=0 FT_HARNESS_ROOT="$W" FT_PUSH_FIXED_S=1 pa_tool "$1" 211 40 ""
  unset DL_OFF
  m="$(sed -n 's/.*main_before=\([0-9a-f]*\).*/\1/p' <<<"$out")"
  [ "$rc" = 0 ] && [ "$(icpre)" = 0 ] && [ "$(icpost)" = 0 ] && grep -q '^LANDED pr=211 ' <<<"$out" && [ -n "$qsha" ] && \
    grep -q '^INSTALL-PENDING 판정 불가 — 설치 검사 호출 0(남은 0초) · 손으로: ft-live-install-check.sh --range ' <<<"$out" && \
    pend "$qsha" && [ "$(head -n1 "$PEND/$qsha.txt")" = 'INSTALL-PENDING 검사 시간 초과' ] && [ "$(tail -n1 "$PEND/$qsha.txt")" = "range=$m..$qsha" ]
}
p12() {  # ⑫ 팩 리포 · 뒤 검사 끊김(124) → «설치 검사 <N>초 초과 — 손으로: …» 지금 글자 · 대기 파일 지금 꼴
  local m
  IC_POST=h FT_INSTALL_CHECK_TIMEOUT=1 FT_HARNESS_ROOT="$W" FT_PUSH_FIXED_S=1 pa_tool "$1" 212 40 ""
  m="$(sed -n 's/.*main_before=\([0-9a-f]*\).*/\1/p' <<<"$out")"
  [ "$rc" = 0 ] && [ "$(icpre)" = 0 ] && [ "$(icpost)" = 1 ] && grep -q '^INSTALL-PENDING 설치 검사 1초 초과 — 손으로: ft-live-install-check.sh --range ' <<<"$out" && \
    pend "$qsha" && [ "$(tail -n1 "$PEND/$qsha.txt")" = "range=$m..$qsha" ]
}


mut() {   # mut <M번호> <사례함수> <파일> <옛 글> <새 글> — 사본 1벌에 치환 1곳(아니면 FAIL) · 그 사례가 FAIL 이어야 · 원본 같은 사례는 PASS(반대 결과 대조)
  local m="$T/mut"; rm -rf "$m"; cp -R "$FIX" "$m"
  python3 - "$m/$3" "$4" "$5" <<'PY' || { echo "FAIL M$1 :: 변이 글자 1곳 아님($3)"; fail=$((fail+1)); return; }
import io, sys
p, a, b = sys.argv[1], sys.argv[2], sys.argv[3]
s = io.open(p, encoding="utf-8").read()
if s.count(a) != 1: sys.exit(1)
io.open(p, "w", encoding="utf-8").write(s.replace(a, b))
PY
  if ( "$2" "$m" ) >/dev/null 2>&1; then echo "FAIL M$1 :: 변이가 $2 를 통과"; fail=$((fail+1)); else echo "PASS M$1 ($2 FAIL)"; fi
  ( "$2" "$FIX" ) >/dev/null 2>&1; ck "M$1-원본 $2" $?
}

mkpr() {   # r2355 mkpr 을 덮는다 — 같은 PR 번호를 두 번(변이 + 원본) 써도 커밋이 늘 다르게(«nothing to commit» 0)
  local n="$1" k="${2:-1}" i; git -C "$W" fetch -q origin; git -C "$W" checkout -q -B "pr$n" origin/main >/dev/null 2>&1
  printf 'pr%s %s-%s-%s\n' "$n" "$$" "$SECONDS" "$RANDOM" > "$W/pr$n.txt"
  [ "$k" -lt 2 ] || for i in $(seq 2 "$k"); do printf '%s %s\n' "$i" "$RANDOM" > "$W/obj$i.txt"; done
  git -C "$W" add -A && git -C "$W" commit -q -m "pr $n work"; git -C "$W" push -q -f origin "pr$n:refs/pull/$n/head" >/dev/null 2>&1; PRSHA="$(sha "$W" HEAD)"
  python3 -c 'import json,os,sys
d = {"headRefOid":sys.argv[1],"headRefName":"pr"+sys.argv[2],"isCrossRepository":False,"title":"feat: PR "+sys.argv[2],"body":"b","state":"OPEN","baseRefName":"main"}
if os.environ.get("NO_HEAD"): d.pop("headRefName")
print(json.dumps(d))' "$PRSHA" "$n" > "$STUB_JSON"
}
