#!/usr/bin/env bash
# test_seat_mbox_name_split_r2109.sh — r2109 좌석 우편함 env 이름 = FT_SEAT_MBOX_DIR (반례 ④~⑨ ⑪ · 변이 M1 M3~M8 · ① ② ③ = ft2/tests/test_launch_seat_mbox_name_r2109.py).
#  ④~⑦ ⑪ 스킬 래퍼 사본(조상 없는 자리 · 조상 있는 자리)을 팩 꼴 worktree cwd 에서 send — py 1회 · sh 1회(sh 가 고른 우편함 = 가짜 ft-inbox 가 받은 FT_ROOT)
#  ⑧ plan_of 가 낸 -e 칸을 env 로 옮긴 셸에서 FT_ROOT=<B> 로 ft-seat-close.sh REJECT 1회(감싸기 켠 채) → B 만 +1 · 좌석 comm(A) 앞뒤 같음
#  ⑨ 팩 사본에서 FT_SEAT_MBOX_DIR 글자 파일(tests · design 빼고) = 6개
# 임시 루트 · 가짜 tmux · 가짜 comm/mbox.sh 만 · 실 tmux · 실 pi · 실 우편함 0 · sleep 0.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
for v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY FT_ROOT FT_MBOX_DIR FT_SEAT_MBOX_DIR FT_MBOX FT_SEATS_JSON \
  FT_CRITICAL_OFF FT_CRITICAL_IN FT_CRITICAL_STATE_DIR FT_CRITICAL_NOW FT_CRITICAL_DEDUPE_S FT_CRITICAL_BUDGET_S; do unset "$v"; done
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
PACK="$(cd -- "$HERE/../../../../../.." && pwd)"
SKILL=feature-pack/fable-team/legacy/1.x/skill/scripts; HBIN=feature-pack/fable-team/legacy/1.x/harness/bin; PLAN=feature-pack/fable-team/ft2/adapters/pi/launch_plan.py
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
fail=0; T0=$SECONDS; STEPS=""; _S0=$SECONDS
step() { STEPS="$STEPS $1=$((SECONDS - _S0))s"; _S0=$SECONDS; }
ok() { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
eqn() { [ "$1" = "$2" ] || { echo "    $3 got=[$1] want=[$2]" >&2; return 1; }; }
lines() { [ -f "$1/mailbox.jsonl" ] && grep -c . "$1/mailbox.jsonl" || echo 0; }
n=0; fresh() { n=$((n+1)); W="$T/w$n"; mkdir -p "$W"; }

mkdir -p "$T/fake"; cat > "$T/fake/tmux" <<'EOF'
#!/usr/bin/env bash
echo "$*" >> "${TMUX_LOG:-/dev/null}"
case "$1" in display-message) echo caller#0;; has-session) exit 1;; esac
exit 0
EOF
chmod +x "$T/fake/tmux"; export PATH="$T/fake:$PATH" TMUX_LOG="$T/tmux.log"

world() {  # <P> → $W/{A(좌석 루트 · comm 실재),pack,pack-wt,tool(조상 없음),T/.fable-team/bin(조상 있음)} · 래퍼 사본 2자리 · 가짜 ft-inbox
  fresh; mkdir -p "$W/A/.fable-team/comm" "$W/pack/.fable-team/comm" "$W/tool" "$W/T/.fable-team/bin" "$W/T/.fable-team/comm"
  for d in "$W/tool" "$W/T/.fable-team/bin"; do
    cp "$1/$SKILL/ft-mbox.py" "$1/$SKILL/ft-mbox.sh" "$1/$SKILL/ft-lib.sh" "$d/"
    printf '#!/usr/bin/env bash\necho "$FT_ROOT" >> "%s/ingest.log"; echo "INGEST seq=$2 cls=⑥ x"\n' "$W" > "$d/ft-inbox.sh"
  done
  git -C "$W/pack" init -q && echo 1 > "$W/pack/f" && git -C "$W/pack" add f && git -C "$W/pack" -c user.email=t@t -c user.name=t commit -qm i \
    && git -C "$W/pack" worktree add -q --detach "$W/pack-wt" || { echo "    준비 실패" >&2; return 1; }
}
send() {  # <py|sh> <래퍼 폴더> [env K=V…] → cwd 팩 꼴 worktree 에서 send 1회 · rc 를 $W/rc 에
  local kind="$1" dir="$2"; shift 2
  local cmd=(python3 "$dir/ft-mbox.py"); [ "$kind" = sh ] && cmd=(bash "$dir/ft-mbox.sh")
  ( cd "$W/pack-wt" && env "$@" timeout 25 "${cmd[@]}" send byz-x-da byz-x-nano "r2109 $kind" --force >"$W/out" 2>&1 ); echo $? > "$W/rc"
}
picked() {  # <py|sh> <기대 우편함 이름 A|pack|T|Z> — 그 우편함만 +1 · rc 0 · sh 는 적재 루트도 그 자리
  local want="$2" got
  got="A=$(lines "$W/A/.fable-team/comm") pack=$(lines "$W/pack/.fable-team/comm") T=$(lines "$W/T/.fable-team/comm") Z=$(lines "$W/Z/.fable-team/comm") rc=$(cat "$W/rc")"
  local exp="A=0 pack=0 T=0 Z=0 rc=0"; exp="${exp/$want=0/$want=1}"
  eqn "$got" "$exp" "$1 우편함 줄 수(출력: $(tail -c 300 "$W/out"))" || return 1
  [ "$1" = py ] && return 0
  local root; root="$W/$want"; [ "$want" = pack ] && root="$W/pack"
  eqn "$(tail -n1 "$W/ingest.log" 2>/dev/null)" "$(cd "$root" && pwd -P)" "sh 적재 루트"
}
c4() { local k; for k in ${KINDS:-py sh}; do world "$1" && send $k "$W/tool" FT_SEAT_MBOX_DIR="$W/A/.fable-team/comm" && picked $k A || return 1; done; }
c5() { local k; for k in ${KINDS:-py sh}; do world "$1" && mkdir -p "$W/Z/.fable-team/comm" && send $k "$W/tool" FT_MBOX_DIR="$W/Z/.fable-team/comm" FT_SEAT_MBOX_DIR="$W/A/.fable-team/comm" && picked $k Z || return 1; done; }
c6() { local k; for k in ${KINDS:-py sh}; do world "$1" && send $k "$W/T/.fable-team/bin" FT_SEAT_MBOX_DIR="$W/A/.fable-team/comm" && picked $k T || return 1; done; }
c7() {  # 없는 경로 → 생기지 않음 · 결과 = 이름 안 준 때와 같음(팩 꼴 우편함 +1 · 출력 꼴 · rc)
  local k a b; for k in ${KINDS:-py sh}; do
    world "$1" && send $k "$W/tool" && a="$(cat "$W/rc") $(sed -E 's/seq=[0-9]+/seq=N/g; s/ts=[^ ]+//g' "$W/out" | tr -d '\n' | cut -c1-60)" || return 1
    world "$1" && send $k "$W/tool" FT_SEAT_MBOX_DIR="$W/없음/.fable-team/comm" && picked $k pack || return 1
    b="$(cat "$W/rc") $(sed -E 's/seq=[0-9]+/seq=N/g; s/ts=[^ ]+//g' "$W/out" | tr -d '\n' | cut -c1-60)"
    eqn "$([ -e "$W/없음" ] && echo 생김 || echo 없음) $b" "없음 $a" "$k 없는 경로" || return 1
  done; }
c11() { local k; for k in ${KINDS:-py sh}; do world "$1" && send $k "$W/tool" FT_MBOX_DIR="$W/A/.fable-team/comm" && picked $k A || return 1; done; }

droot() {  # <루트> — 가짜 하네스 루트: comm/mbox.sh(자기 우편함에 1줄) · seats-planner.json _desk · state
  mkdir -p "$1/.fable-team/comm" "$1/.fable-team/state"
  printf '{"_master":"byz-x-master#1","_desk":"byz-x-desk#1"}\n' > "$1/.fable-team/seats-planner.json"
  cat > "$1/.fable-team/comm/mbox.sh" <<'EOF'
#!/usr/bin/env bash
f="$(cd "$(dirname "$0")" && pwd)/mailbox.jsonl"; n=$(( $( (grep -c . "$f" 2>/dev/null) || true) + 1 ))
printf '{"seq": %s, "to": "%s", "from": "%s"}\n' "$n" "$2" "$3" >> "$f"; echo "QUEUED seq=$n to=$2"
EOF
}
cells() {  # <P> <좌석 루트> → plan_of 가 낸 tmux -e K=V 칸(줄당 1)
  python3 - "$1/$PLAN" "$2" <<'PY'
import importlib.util, re, sys
s = importlib.util.spec_from_file_location("lp2109", sys.argv[1]); m = importlib.util.module_from_spec(s); s.loader.exec_module(m)
r = sys.argv[2]; env = {"FT2_ROOT": r, "FT2_TEAM": "harness", "FT2_WORK": "w", "FT2_HOLDER": "byz-harness-nano-w#0", "FT2_ATTEMPT": "a1"}
a = m.plan_of(r + "/i", "w@a1", r, "harness", "byz-harness-nano-w#0", [], None, r, env, "b")["tmux"]
print("\n".join(w for e, w in zip(a, a[1:]) if e == "-e" and re.match(r"[A-Z_][A-Z0-9_]*=", w)))
PY
}
c8() {  # 줄 수 지킴 — 좌석 env + FT_ROOT=<B> 로 닫기 도구 REJECT 1회
  fresh; local A="$W/seat" B="$W/B" e=() l
  droot "$A"; droot "$B"
  while IFS= read -r l; do [ -n "$l" ] && e+=("$l"); done < <(cells "$1" "$A")
  printf '{"_master":"M#1","M#1":{"role":"master","tick":"t"}}\n' > "$W/seats.json"
  local before; before="$(lines "$A/.fable-team/comm") $(grep -c . "$A/.fable-team/state/critical-sent.jsonl" 2>/dev/null || echo 0)"
  (cd "$W" && env "${e[@]}" FT_ROOT="$B" FT_SEAT_REAP_BIN=/bin/true timeout 60 bash "$1/$HBIN/ft-seat-close.sh" 'M#1' --reason r --seats "$W/seats.json" >"$W/out" 2>&1); local rc=$?
  eqn "$rc ${#e[@]}" "1 6" "REJECT rc · 좌석 칸 수" || return 1
  eqn "B=$(lines "$B/.fable-team/comm") $(grep -c . "$B/.fable-team/state/critical-sent.jsonl" 2>/dev/null || echo 0) A=$(lines "$A/.fable-team/comm") $(grep -c . "$A/.fable-team/state/critical-sent.jsonl" 2>/dev/null || echo 0)" \
    "B=1 1 A=$before" "B 알림 쪽지·기록 · 좌석 comm(A) 쪽지·기록 앞뒤"
}
c9() {  # 팩 사본에서 이름 글자 파일(tests · design 빼고) = 정확히 6
  local got; got="$(cd "$1" && grep -rl --exclude-dir=tests --exclude-dir=design --exclude-dir=.git --exclude-dir=__pycache__ --exclude='*.pyc' FT_SEAT_MBOX_DIR . | sed 's|^\./||' | LC_ALL=C sort | tr '\n' ' ')"
  eqn "$got" "$SKILL_LIST" "이름 글자 파일"
}
SKILL_LIST="feature-pack/fable-team/ft2/adapters/pi/launch.py $PLAN feature-pack/fable-team/legacy/1.x/harness/kit/fable-team/bin/ft-mbox.py feature-pack/fable-team/legacy/1.x/harness/kit/fable-team/bin/ft-mbox.sh $SKILL/ft-mbox.py $SKILL/ft-mbox.sh "

tc() { if "$2" "$PACK"; then ok "$1"; else bad "$1"; fi; }
tc "④ 조상 없음 · FT_SEAT_MBOX_DIR 만 → A +1 · 팩 꼴 +0 (py · sh)" c4
tc "⑤ FT_MBOX_DIR 와 함께 → Z +1 · A +0" c5
tc "⑥ 조상 있음 → T +1 · A +0" c6
tc "⑦ 없는 경로 → 안 생김 · 이름 안 준 때와 같음" c7
tc "⑪ 옛 좌석(FT_MBOX_DIR 만) → A +1 · 팩 꼴 +0" c11
tc "⑧ 좌석 칸 + FT_ROOT=B 닫기 REJECT → B 만 +1 · 좌석 comm 앞뒤 같음" c8
tc "⑨ 이름 글자 파일 = 6" c9
step 반례

# 변이 — 사본 SB 에서 파일 하나(또는 래퍼 둘)만 바꿈 → 그 사례 FAIL · 원본 PACK 으로 같은 사례 1회 더 = PASS · 사례 뒤 원복
SB="$T/sb"; rsync -a --exclude .git --exclude __pycache__ --exclude '*.pyc' "$PACK/" "$SB/" || { bad "변이 사본 못 만듦"; }
mut() {  # <파일> <옛 글> <새 글> [<옛> <새>…] — 옛 글은 정확히 1곳
  python3 - "$SB/$1" "${@:2}" <<'PY'
import io, sys
p, pairs = sys.argv[1], sys.argv[2:]; s = io.open(p, encoding="utf-8").read()
for a, b in zip(pairs[0::2], pairs[1::2]):
    if s.count(a) != 1: sys.exit(3)
    s = s.replace(a, b)
io.open(p, "w", encoding="utf-8").write(s)
PY
}
restore() { local f; for f in "$PLAN" "$SKILL/ft-mbox.py" "$SKILL/ft-mbox.sh" "$HBIN/ft-harness-root.sh"; do cp "$PACK/$f" "$SB/$f"; done; }
mcase() {  # <M> <사례 함수> [KINDS] — 변이 사본 FAIL · 원본 PASS
  local m="$1" fn="$2"
  if KINDS="${3:-}" "$fn" "$SB" 2>/dev/null; then bad "$m $fn 변이에서 PASS(못 가름)"; return; fi
  if KINDS="${3:-}" "$fn" "$PACK"; then ok "$m $fn 변이 FAIL · 원본 PASS"; else bad "$m $fn 원본 FAIL"; fi
}
PYSEAT=$'elif os.path.isdir(_SEAT):\n    CANON = _SEAT\n'
SHSEAT='  [ -n "${FT_SEAT_MBOX_DIR:-}" ] && [ -d "$FT_SEAT_MBOX_DIR" ] && { printf '"'%s'"' "$FT_SEAT_MBOX_DIR"; return; }   # r2109 ③ 좌석 우편함 · 실재 폴더일 때만'$'\n'
SHONE='  [ -n "${FT_MBOX_DIR:-}" ] && { printf '"'%s'"' "$FT_MBOX_DIR"; return; }'$'\n'
PYHEAD='CANON = os.environ.get("FT_MBOX_DIR") or ('
mrun() { local m="$1"; shift; if "$@"; then :; else bad "$m 변이 패턴 없음"; restore; return 1; fi; }
mrun M1 mut "$PLAN" '[("FT_SEAT_MBOX_DIR", box)]' '[("FT_MBOX_DIR", box)]' && { mcase M1 c8; restore; }
mrun M3 mut "$SKILL/ft-mbox.py" "$PYSEAT" "" && { mcase M3 c4 py; restore; }
mrun M4 mut "$SKILL/ft-mbox.sh" "$SHSEAT" "" && { mcase M4 c4 sh; restore; }
mrun M5 mut "$SKILL/ft-mbox.py" "$PYHEAD" 'CANON = (_SEAT if os.path.isdir(_SEAT) else None) or os.environ.get("FT_MBOX_DIR") or (' \
  && mrun M5 mut "$SKILL/ft-mbox.sh" "$SHSEAT" "" "$SHONE" "$SHSEAT$SHONE" && { mcase M5 c5; restore; }
mrun M6 mut "$SKILL/ft-mbox.py" "$PYHEAD" 'CANON = os.environ.get("FT_MBOX_DIR") or (_SEAT if os.path.isdir(_SEAT) else None) or (' \
  && mrun M6 mut "$SKILL/ft-mbox.sh" "$SHSEAT" "" "$SHONE" "$SHONE$SHSEAT" && { mcase M6 c6; restore; }
mrun M7 mut "$SKILL/ft-mbox.py" 'elif os.path.isdir(_SEAT):' 'elif _SEAT:' \
  && mrun M7 mut "$SKILL/ft-mbox.sh" '[ -n "${FT_SEAT_MBOX_DIR:-}" ] && [ -d "$FT_SEAT_MBOX_DIR" ] &&' '[ -n "${FT_SEAT_MBOX_DIR:-}" ] &&' && { mcase M7 c7; restore; }
mrun M8 mut "$HBIN/ft-harness-root.sh" 'if [ -n "${FT_MBOX_DIR:-}" ]; then c="$FT_MBOX_DIR"' 'if [ -n "${FT_MBOX_DIR:-${FT_SEAT_MBOX_DIR:-}}" ]; then c="${FT_MBOX_DIR:-$FT_SEAT_MBOX_DIR}"' \
  && { mcase M8 c8; mcase M8 c9; restore; }
step 변이
echo "단계별 초: 전체=$((SECONDS - T0))s ·$STEPS"
[ "$fail" -eq 0 ] && echo "ALL PASS" || { echo "FAILED $fail"; exit 1; }
