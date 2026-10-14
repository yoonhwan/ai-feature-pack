#!/usr/bin/env bash
# test_resource_gate.sh — 자원 문지기(ft-resource-gate.sh) + spawn 3종의 문지기 호출 + 키트 두 곳 일치 시험 (R161).
# 임시 루트·임시 HOME·git/tmux/tmuxc 스텁만 쓴다 — 실 동결 파일·라이브 bin·실 tmux 세션 0.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="$(cd -- "$HERE/../.." && pwd)"
K1="$REPO/scripts/fable-team-bin"
K2="$REPO/scripts/harness-install/fable-team/bin"
FILES="ft-resource-gate.sh ft-resource-watch.sh ft-nano-spawn.sh ft-role-spawn.sh ft-successor-open.sh"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
R="$T/R"; mkdir -p "$R/.fable-team/state" "$T/home" "$T/cwd" "$T/stub"
LOG="$T/stub.log"; : > "$LOG"
for s in git tmux tmuxc; do printf '#!/bin/sh\necho "%s $*" >> "%s"\nexit 1\n' "$s" "$LOG" > "$T/stub/$s"; chmod 755 "$T/stub/$s"; done
# pgrep 스텁 — macOS 처럼 `-a` 가 없으면 호출 조상(PG_*_ANC)을 결과에서 뺀다. `-a -x claude` / `-a -x codex` 만 허용, 그 외(옛 `-f` 등 모르는 인자)는 rc 99.
mkdir -p "$T/pg"; cat > "$T/pg/pgrep" <<'PG'
#!/bin/sh
emit() { # <OUT> <ANC> <RC> <with_ancestors 0|1>
  o="$1"; [ "$4" = 1 ] || { [ -z "$2" ] || o="$(printf '%s\n' "$o" | grep -vx "$2")"; }
  printf '%s' "$o"; [ -z "$o" ] || echo; exit "$3"
}
a=0; [ "$1" = "-a" ] && { a=1; shift; }
case "$*" in
  "-x claude") emit "${PG_CLAUDE_OUT:-}" "${PG_CLAUDE_ANC:-}" "${PG_CLAUDE_RC:-1}" $a;;
  "-x codex")  emit "${PG_CODEX_OUT:-}" "${PG_CODEX_ANC:-}" "${PG_CODEX_RC:-1}" $a;;
  *) echo "pgrep unexpected args: $*" >&2; exit 99;;
esac
PG
chmod 755 "$T/pg/pgrep"
CARD="$T/card.md"; echo 카드 > "$CARD"; BODY="$T/body.txt"; echo 본문 > "$BODY"

LOW='FT_DISK_MIN_GIB=0 FT_SWAP_MAX_MIB=999999999 FT_MEM_FREE_MIN_PCT=0 FT_AGENT_MAX=999999'
# gate <bin 폴더> <env...> -- <인자> : 출력 OUT · rc RC
gate() { local d="$1"; shift; OUT="$(env FT_RES_ROOT="$R" "$@" bash "$d/ft-resource-gate.sh" 2>&1)"; RC=$?; }
mk_freeze() { echo "시험 동결" > "$R/.fable-team/state/RESOURCE_FREEZE"; }
rm_freeze() { rm -f "$R/.fable-team/state/RESOURCE_FREEZE"; }

# gate_checks <bin 폴더> — ⓐ~ⓔ. 전부 맞으면 rc 0.
gate_checks() {
  local d="$1" e=0
  rm_freeze
  OUT="$(env FT_RES_ROOT="$R" $LOW bash "$d/ft-resource-gate.sh" check 2>&1)"; RC=$?
  [ $RC -eq 0 ] && echo "$OUT" | grep -q '^OK ' || { echo "ⓐ rc=$RC $OUT"; e=1; }
  OUT="$(env FT_RES_ROOT="$R" $LOW FT_DISK_MIN_GIB=999999 bash "$d/ft-resource-gate.sh" check 2>&1)"; RC=$?
  [ $RC -eq 3 ] && echo "$OUT" | grep -q '^REJECT resource disk' || { echo "ⓑ rc=$RC $OUT"; e=1; }
  mk_freeze
  OUT="$(env FT_RES_ROOT="$R" $LOW bash "$d/ft-resource-gate.sh" check 2>&1)"; RC=$?
  [ $RC -eq 3 ] && echo "$OUT" | grep -q '^REJECT resource freeze' || { echo "ⓒ rc=$RC $OUT"; e=1; }
  OUT="$(env FT_RES_ROOT="$R" $LOW bash "$d/ft-resource-gate.sh" status 2>&1)"; RC=$?
  [ $RC -eq 0 ] && [ "$(echo "$OUT" | grep -c '^disk=')" = 1 ] && echo "$OUT" | grep -q '^disk=.* freeze=1$' || { echo "ⓓ rc=$RC $OUT"; e=1; }
  rm_freeze
  OUT="$(env FT_RES_ROOT="$R" bash "$d/ft-resource-gate.sh" 2>&1)"; RC=$?
  [ $RC -eq 2 ] || { echo "ⓔ rc=$RC $OUT"; e=1; }
  return $e
}

# pg <bin 폴더> <env...> — 스텁 pgrep 으로 check. OUT·RC.
pg() { local d="$1"; shift; OUT="$(env FT_RES_ROOT="$R" $LOW PATH="$T/pg:$PATH" "$@" bash "$d/ft-resource-gate.sh" check 2>&1)"; RC=$?; }
# pgrep_checks <bin 폴더> — ⓗ~ⓛ·ⓝ. 전부 맞으면 rc 0.
pgrep_checks() {
  local d="$1" e=0
  rm_freeze
  pg "$d" PG_CLAUDE_RC=2 PG_CODEX_RC=2
  { [ $RC -eq 4 ] && echo "$OUT" | grep -q '^ERROR resource measure' && ! echo "$OUT" | grep -q '^OK'; } || { echo "ⓗ rc=$RC $OUT"; e=1; }
  pg "$d" PG_CLAUDE_RC=0 PG_CLAUDE_OUT=sensor-error PG_CODEX_RC=1
  { [ $RC -eq 4 ] && echo "$OUT" | grep -q '^ERROR resource measure'; } || { echo "ⓘ rc=$RC $OUT"; e=1; }
  pg "$d" PG_CLAUDE_RC=0 PG_CLAUDE_OUT=111 PG_CODEX_RC=2
  { [ $RC -eq 4 ] && echo "$OUT" | grep -q '^ERROR resource measure'; } || { echo "ⓙ(codex) rc=$RC $OUT"; e=1; }
  pg "$d" PG_CLAUDE_RC=2 PG_CODEX_RC=0 PG_CODEX_OUT=222
  { [ $RC -eq 4 ] && echo "$OUT" | grep -q '^ERROR resource measure'; } || { echo "ⓙ(claude) rc=$RC $OUT"; e=1; }
  pg "$d" PG_CLAUDE_RC=1 PG_CODEX_RC=1
  { [ $RC -eq 0 ] && echo "$OUT" | grep -q '^OK .* agents=0$'; } || { echo "ⓚ rc=$RC $OUT"; e=1; }
  pg "$d" PG_CLAUDE_RC=0 PG_CLAUDE_OUT=111 PG_CODEX_RC=0 PG_CODEX_OUT=111
  { [ $RC -eq 0 ] && echo "$OUT" | grep -q '^OK .* agents=1$'; } || { echo "ⓛ rc=$RC $OUT"; e=1; }
  # ⓝ 조상 포함(`-a`) + 벤더 바이너리(`-x`)만 — claude 2(조상 11) + codex 3(조상 21) = 5. `-a` 가 없으면 3, 옛 `-f` 호출은 스텁이 99 로 실패시킨다.
  OUT="$(env FT_RES_ROOT="$R" $LOW PATH="$T/pg:$PATH" PG_CLAUDE_RC=0 PG_CLAUDE_OUT="$(printf '11\n12')" PG_CLAUDE_ANC=11 PG_CODEX_RC=0 PG_CODEX_OUT="$(printf '21\n22\n23')" PG_CODEX_ANC=21 bash "$d/ft-resource-gate.sh" status 2>&1)"; RC=$?
  { [ $RC -eq 0 ] && echo "$OUT" | grep -q ' agents=5 '; } || { echo "ⓝ rc=$RC $OUT"; e=1; }
  return $e
}

# spawn_checks <bin 폴더> — ⓕ 동결 상태에서 spawn 3종 모두 REJECT resource rc=3 · 스텁 호출 0 · 임시 HOME 비어 있음.
spawn_checks() {
  local d="$1" e=0 n s out rc
  mk_freeze; : > "$LOG"
  for n in nano role succ; do
    case "$n" in
      nano) s=ft-nano-spawn.sh;      set -- "$CARD";;
      role) s=ft-role-spawn.sh;      set -- arch;;
      succ) s=ft-successor-open.sh;  set -- old "$T/cwd" --name x#1 --agent claude --model m --body-file "$BODY";;
    esac
    out="$(cd "$T/cwd" && env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE -u GIT_COMMON_DIR -u GIT_OBJECT_DIRECTORY \
      HOME="$T/home" PATH="$T/stub:$PATH" FT_RES_ROOT="$R" $LOW bash "$d/$s" "$@" 2>&1)"; rc=$?
    { [ $rc -eq 3 ] && echo "$out" | grep -q 'REJECT resource'; } || { echo "ⓕ $s rc=$rc $out"; e=1; }
  done
  [ ! -s "$LOG" ] || { echo "ⓕ 부작용(스텁 호출): $(cat "$LOG")"; e=1; }
  [ -z "$(ls -A "$T/home")" ] || { echo "ⓕ 임시 HOME 변화"; e=1; }
  rm_freeze
  return $e
}

# spawn_pgrep_err <bin 폴더> — ⓜ pgrep 오류(rc 2) → spawn 3종 stdout ERROR resource measure · rc 4 · 부작용 0.
spawn_pgrep_err() {
  local d="$1" e=0 n s out rc
  rm_freeze; : > "$LOG"
  for n in nano role succ; do
    case "$n" in
      nano) s=ft-nano-spawn.sh;      set -- "$CARD";;
      role) s=ft-role-spawn.sh;      set -- arch;;
      succ) s=ft-successor-open.sh;  set -- old "$T/cwd" --name x#1 --agent claude --model m --body-file "$BODY";;
    esac
    out="$(cd "$T/cwd" && env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE -u GIT_COMMON_DIR -u GIT_OBJECT_DIRECTORY \
      HOME="$T/home" PATH="$T/pg:$T/stub:$PATH" PG_CLAUDE_RC=2 PG_CODEX_RC=2 FT_RES_ROOT="$R" $LOW bash "$d/$s" "$@" 2>&1)"; rc=$?
    { [ $rc -eq 4 ] && echo "$out" | grep -q 'ERROR resource measure'; } || { echo "ⓜ $s rc=$rc $out"; e=1; }
  done
  [ ! -s "$LOG" ] || { echo "ⓜ 부작용(스텁 호출): $(cat "$LOG")"; e=1; }
  [ -z "$(ls -A "$T/home")" ] || { echo "ⓜ 임시 HOME 변화"; e=1; }
  return $e
}

run_suite() {
  local tag="$1" d
  for d in "$K1" "$K2"; do
    gate_checks "$d" >"$T/o" 2>&1 && ok "$tag ⓐ~ⓔ $(basename "$(dirname "$d")")" || bad "$tag ⓐ~ⓔ $d: $(cat "$T/o")"
    spawn_checks "$d" >"$T/o" 2>&1 && ok "$tag ⓕ spawn 3종 $(basename "$(dirname "$d")")" || bad "$tag ⓕ $d: $(cat "$T/o")"
    pgrep_checks "$d" >"$T/o" 2>&1 && ok "$tag ⓗ~ⓛ·ⓝ pgrep 센서 $(basename "$(dirname "$d")")" || bad "$tag ⓗ~ⓛ $d: $(cat "$T/o")"
    spawn_pgrep_err "$d" >"$T/o" 2>&1 && ok "$tag ⓜ spawn 3종 pgrep 오류 $(basename "$(dirname "$d")")" || bad "$tag ⓜ $d: $(cat "$T/o")"
  done
}

for f in $FILES; do bash -n "$K1/$f" && bash -n "$K2/$f" && ok "bash -n $f" || bad "bash -n $f"; done

# ⓖ 키트 두 곳 5파일 cmp 0
for f in $FILES; do cmp -s "$K1/$f" "$K2/$f" && ok "ⓖ cmp $f" || bad "ⓖ cmp $f"; done

run_suite default
LC_ALL=C.UTF-8 run_suite C.UTF-8

# 변이 1 — spawn 사본 하나에서 문지기 호출 줄 삭제 → ⓕ 가 «실패»해야 한다
for s in ft-nano-spawn.sh ft-role-spawn.sh ft-successor-open.sh; do
  M="$T/mut-$s"; mkdir -p "$M"; cp "$K1"/ft-*.sh "$M"/
  grep -v 'ft-resource-gate.sh" check' "$K1/$s" | grep -v '_rgrc' > "$M/$s"
  spawn_checks "$M" >/dev/null 2>&1 && bad "변이1 $s: 문지기 줄 삭제가 검출되지 않음" || ok "변이1 $s 검출"
done

# 변이 2 — gate 의 동결 검사 삭제 → ⓒ 가 «실패»해야 한다
M="$T/mut-gate"; mkdir -p "$M"; cp "$K1"/ft-*.sh "$M"/
awk '/^if \[ "\$FREEZE_FLAG" = 1 \]; then$/{skip=1} skip{ if ($0=="fi") {skip=0}; next } {print}' "$K1/ft-resource-gate.sh" > "$M/ft-resource-gate.sh"
grep -q 'REJECT resource freeze' "$M/ft-resource-gate.sh" && bad "변이2 준비 실패(동결 검사가 남음)" || {
  gate_checks "$M" >/dev/null 2>&1 && bad "변이2: 동결 검사 삭제가 검출되지 않음" || ok "변이2 검출"; }

# 변이 3 — gate 에서 pgrep rc 검사 제거(rc 를 0 으로 취급) → ⓗ 가 «실패»해야 한다
M="$T/mut-rc"; mkdir -p "$M"; cp "$K1"/ft-*.sh "$M"/
sed 's/out="$(pgrep "$@" 2>\/dev\/null)"; rc=$?/out="$(pgrep "$@" 2>\/dev\/null)"; rc=0/' "$K1/ft-resource-gate.sh" > "$M/ft-resource-gate.sh"
cmp -s "$M/ft-resource-gate.sh" "$K1/ft-resource-gate.sh" && bad "변이3 준비 실패(치환 0)" || {
  pgrep_checks "$M" >/dev/null 2>&1 && bad "변이3: rc 검사 제거가 검출되지 않음" || ok "변이3 검출"; }

# 변이 5 — gate 의 두 센서에서 `-a`(조상 포함) 제거 → ⓝ 이 «실패»해야 한다
M="$T/mut-noa"; mkdir -p "$M"; cp "$K1"/ft-*.sh "$M"/
sed 's/^agent_scan \([a-z]*\) -a -x /agent_scan \1 -x /' "$K1/ft-resource-gate.sh" > "$M/ft-resource-gate.sh"
cmp -s "$M/ft-resource-gate.sh" "$K1/ft-resource-gate.sh" && bad "변이5 준비 실패(치환 0)" || {
  pgrep_checks "$M" >/dev/null 2>&1 && bad "변이5: -a 제거가 검출되지 않음" || ok "변이5 검출"; }

# 변이 4 — gate 의 codex 센서를 옛 `-f 'codex( |$)'` 로 되돌림 → ⓝ 이 «실패»해야 한다
M="$T/mut-codexf"; mkdir -p "$M"; cp "$K1"/ft-*.sh "$M"/
sed "s/^agent_scan codex -a -x codex\$/agent_scan codex -f 'codex( |\$)'/" "$K1/ft-resource-gate.sh" > "$M/ft-resource-gate.sh"
cmp -s "$M/ft-resource-gate.sh" "$K1/ft-resource-gate.sh" && bad "변이4 준비 실패(치환 0)" || {
  pgrep_checks "$M" >/dev/null 2>&1 && bad "변이4: codex -f 복귀가 검출되지 않음" || ok "변이4 검출"; }

[ "$(git -C "$REPO" config --get core.bare)" = false ] && ok "core.bare=false" || bad "core.bare"
echo "fail=$fail"; [ $fail -eq 0 ]
