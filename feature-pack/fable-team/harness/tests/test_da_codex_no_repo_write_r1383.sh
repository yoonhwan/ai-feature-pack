#!/usr/bin/env bash
# test_da_codex_no_repo_write_r1383.sh — r1383 시험: ft-da-codex.sh 가 codex 를 읽기 전용 sandbox 로 부르고,
# 실행 뒤 cwd 저장소(HEAD·작업 트리)가 바뀌면 «판정 불가 — DA 가 저장소를 바꿈(…)» rc3 으로 끝낸다.
# 픽스처 = PATH 앞 가짜 codex(받은 인자를 FAKE_LOG 에 적고, FAKE_ACT 에 따라 cwd 에 커밋 1개 / 추적 안 되는 파일 1개 / 아무것도 안 함)
#          + 임시 git 저장소 · 실 codex·실 저장소·실 원격 0 · 실 ~/.codex 0(HOME·CODEX_HOME 임시) · 고정 sleep 0.
# 반례: D1 인자 없음 → -s read-only · D2 --sandbox workspace-write · D3 --sandbox danger-full-access → rc2 · codex 0
#       D4 커밋 1개 → rc3 · D5 추적 안 되는 파일 1개 → rc3 · D6 아무것도 안 함 → rc0 (out-dir 가 cwd 안이어도) · D7 git 밖 cwd → rc0 + INFO
# 변이: -s 삭제 → D1·D2 FAIL · 사후 확인 삭제 → D4·D5 FAIL · 허용 값에 danger-full-access 추가 → D3 FAIL
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
TOOL="${DA_CODEX_TOOL:-$HERE/../kit/fable-team/bin/ft-da-codex.sh}"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/fakebin" "$T/home" "$T/codex"
cat > "$T/fakebin/codex" <<'EOF'
#!/usr/bin/env bash
: > "$FAKE_LOG"
for a in "$@"; do printf '%s\n' "$a" >> "$FAKE_LOG"; done
d=""; prev=""
for a in "$@"; do [ "$prev" = "-C" ] && d="$a"; prev="$a"; done
case "${FAKE_ACT:-none}" in
  commit)    echo x > "$d/c.txt"; git -C "$d" add c.txt; git -C "$d" -c user.name=t -c user.email=t@t -c commit.gpgsign=false commit -q -m fake ;;
  untracked) echo x > "$d/u.txt" ;;
esac
printf '판정: APPROVE\n'
exit 0
EOF
chmod +x "$T/fakebin/codex"
export PATH="$T/fakebin:$PATH" FAKE_LOG="$T/args.log" HOME="$T/home" CODEX_HOME="$T/codex"
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
printf '[model_providers.headroom]\nname = "headroom"\n' > "$CODEX_HOME/config.toml"
printf '질문 1: 이 설계가 맞는가\n' > "$T/p.txt"

mkrepo() {   # 새 임시 git 저장소 1개(커밋 1개) 경로를 찍는다(부분 셸이라 번호 대신 mktemp)
  local r; r="$(mktemp -d "$T/repo.XXXXXX")"
  { git init -q "$r" && echo a > "$r/f.txt" && git -C "$r" add f.txt \
    && git -C "$r" -c user.name=t -c user.email=t@t -c commit.gpgsign=false commit -q -m base; } >/dev/null 2>&1
  echo "$r"
}
run() { bash "$TOOL" "$@" > "$T/stdout" 2> "$T/stderr"; echo $?; }
sb_after_s() { grep -x -A1 -- '-s' "$T/args.log" | tail -1; }   # codex 인자에서 -s 바로 뒤 값
out_of() { tail -1 "$T/stdout" | sed -n 's/^OUT \(.*\) rc=[0-9]*$/\1/p'; }

if [ ! -f "$TOOL" ]; then bad "래퍼 없음: $TOOL"; echo "FAILED=$fail"; exit "$fail"; fi

# D1 인자 없음 → codex 인자에 -s 다음 read-only
r="$(mkrepo)"; rm -f "$FAKE_LOG"
rc="$(run --cwd "$r" --prompt-file "$T/p.txt" --out-dir "$T/o1")"
[ "$rc" = 0 ] && ok "D1 rc0" || bad "D1 rc=$rc ($(head -2 "$T/stderr"))"
[ "$(sb_after_s)" = read-only ] && ok "D1 기본 = -s read-only" || bad "D1 -s 값: '$(sb_after_s)'"

# D2 --sandbox workspace-write → 인자에 workspace-write
rm -f "$FAKE_LOG"
rc="$(run --cwd "$r" --prompt-file "$T/p.txt" --out-dir "$T/o2" --sandbox workspace-write)"
[ "$rc" = 0 ] && [ "$(sb_after_s)" = workspace-write ] && ok "D2 명시 workspace-write → -s workspace-write" || bad "D2 rc=$rc -s='$(sb_after_s)'"

# D3 --sandbox danger-full-access(와 임의 값) → usage rc2 · codex 호출 0 · 출력 파일 0
for v in danger-full-access bogus; do
  rm -f "$FAKE_LOG"
  rc="$(run --cwd "$r" --prompt-file "$T/p.txt" --out-dir "$T/o3-$v" --sandbox "$v")"
  [ "$rc" = 2 ] && [ ! -e "$FAKE_LOG" ] && [ ! -d "$T/o3-$v" ] && grep -q 'read-only|workspace-write' "$T/stderr" \
    && ok "D3 --sandbox $v → rc2 · codex 0 · 출력 0" || bad "D3 $v rc=$rc log=$([ -e "$FAKE_LOG" ] && echo 있음 || echo 없음)"
done

# D4 가짜 codex 가 cwd 에 커밋 1개 → 판정 불가 rc3 · .meta rc=3
r="$(mkrepo)"
rc="$(FAKE_ACT=commit run --cwd "$r" --prompt-file "$T/p.txt" --out-dir "$T/o4")"
o4="$(out_of)"
[ "$rc" = 3 ] && grep -q '판정 불가 — DA 가 저장소를 바꿈(HEAD ' "$T/stderr" && ok "D4 커밋 → 판정 불가 rc3" || bad "D4 rc=$rc $(head -2 "$T/stderr")"
[ -n "$o4" ] && grep -qE '(^| )rc=3( |$)' "$o4.meta" && ok "D4 .meta rc=3" || bad "D4 .meta: $(cat "$o4.meta" 2>/dev/null)"

# D5 가짜 codex 가 cwd 에 추적 안 되는 파일 1개 → 판정 불가 rc3(작업 트리 1줄)
r="$(mkrepo)"
rc="$(FAKE_ACT=untracked run --cwd "$r" --prompt-file "$T/p.txt" --out-dir "$T/o5")"
o5="$(out_of)"
[ "$rc" = 3 ] && grep -q '판정 불가 — DA 가 저장소를 바꿈(작업 트리 1줄)' "$T/stderr" && ok "D5 새 파일 → 판정 불가 rc3(작업 트리 1줄)" || bad "D5 rc=$rc $(head -2 "$T/stderr")"
[ -n "$o5" ] && grep -qE '(^| )rc=3( |$)' "$o5.meta" && ok "D5 .meta rc=3" || bad "D5 .meta: $(cat "$o5.meta" 2>/dev/null)"

# D6 아무것도 안 바꿈 + 판정 줄 → rc0 · out-dir 에만 .out·.meta(지금과 같음)
r="$(mkrepo)"
rc="$(run --cwd "$r" --prompt-file "$T/p.txt" --out-dir "$T/o6")"
o6="$(out_of)"
[ "$rc" = 0 ] && [ "$(ls "$T/o6" | wc -l | tr -d ' ')" = 2 ] && [ -s "$o6" ] && [ -s "$o6.meta" ] && ! grep -q '판정 불가' "$T/stderr" \
  && ok "D6 안 바꿈 → rc0 · out-dir 파일 .out·.meta 2개" || bad "D6 rc=$rc 파일=$(ls "$T/o6" | tr '\n' ' ')"
[ "$(git -C "$r" status --porcelain | wc -l | tr -d ' ')" = 0 ] && ok "D6 cwd 작업 트리 변화 0" || bad "D6 cwd 가 바뀜"
# D6b out-dir 가 cwd 안(추적 안 되는 폴더)이어도 거짓 판정 불가 0
r="$(mkrepo)"
rc="$(run --cwd "$r" --prompt-file "$T/p.txt" --out-dir "$r/da-out")"
[ "$rc" = 0 ] && ! grep -q '판정 불가' "$T/stderr" && ok "D6b out-dir 가 cwd 안 → rc0(거짓 판정 불가 0)" || bad "D6b rc=$rc $(head -2 "$T/stderr")"

# D7 git 밖 cwd → 사후 확인 생략 + INFO · rc0
mkdir -p "$T/plain"
rc="$(FAKE_ACT=untracked run --cwd "$T/plain" --prompt-file "$T/p.txt" --out-dir "$T/o7")"
[ "$rc" = 0 ] && grep -q 'git 밖' "$T/stderr" && ok "D7 git 밖 cwd → 사후 확인 생략 · INFO · rc0" || bad "D7 rc=$rc $(head -2 "$T/stderr")"

# 변이 — 재진입 표지: 안쪽 실행(FT_R1383_INNER=1)은 여기서 끝낸다
if [ "${FT_R1383_INNER:-0}" = 1 ]; then echo "FAILED=$fail"; exit "$fail"; fi
mutate() {   # <이름> <sed 식> <FAIL 이어야 하는 칸 정규식>
  sed "$2" "$TOOL" > "$T/mut_$1.sh"
  cmp -s "$TOOL" "$T/mut_$1.sh" && { bad "변이 $1 생성 실패(식 미일치)"; return; }
  FT_R1383_INNER=1 DA_CODEX_TOOL="$T/mut_$1.sh" bash "${BASH_SOURCE[0]:-$0}" > "$T/mut_$1.log" 2>&1 \
    && bad "변이 $1 이 통과함" || ok "변이 $1 = 실패"
  grep -qE "^FAIL ($3)( |$)" "$T/mut_$1.log" && ok "변이 $1 → $3 FAIL" || bad "변이 $1 에 $3 FAIL 없음"
}
mutate nosandbox 's/ -s "\$sandbox"//' 'D1|D2'
mutate nopost 's/^if \[ "\$is_git" = 1 \] && changed=.*$/:/' 'D4|D5'
mutate allowdanger 's/read-only|workspace-write)/read-only|workspace-write|danger-full-access)/' 'D3'

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILED=$fail"
exit "$fail"
