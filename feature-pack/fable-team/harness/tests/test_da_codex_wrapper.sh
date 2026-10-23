#!/usr/bin/env bash
# test_da_codex_wrapper.sh — r513 시험: DA 용 codex 래퍼 ft-da-codex.sh 가 헤드룸 «건너뛰기» 헤더·모델·effort·
# 머리말을 싣고, 실행마다 새 출력 파일을 만들고, 실패를 그대로 돌려준다.
# r782 추가: 건너뛰기 헤더는 설정(${CODEX_HOME:-$HOME/.codex}/config.toml)에 `[model_providers.headroom]` 절이 «있을 때만»
# 실린다 — 절이 없는데 머리만 남으면 codex 가 «provider name must not be empty» 로 rc1(전 팀 DA 정지).
# 픽스처 = PATH 앞 가짜 codex(받는 인자·stdin 을 적고, 설정에 절이 없는데 머리가 오면 그 오류를 흉내) · 외부 호출 0 · 헤드룸 0 · GIT_* env 0.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
TOOL="${DA_CODEX_TOOL:-$HERE/../kit/fable-team/bin/ft-da-codex.sh}"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/fakebin" "$T/cwd"
cat > "$T/fakebin/codex" <<'EOF'
#!/usr/bin/env bash
: > "$FAKE_LOG"
for a in "$@"; do printf '%s\n' "$a" >> "$FAKE_LOG"; done
printf '%s' "${@: -1}" > "$FAKE_LOG.prompt"
if [ -t 0 ]; then echo "STDIN=tty" >> "$FAKE_LOG"; else n=$(wc -c); echo "STDIN_BYTES=${n// /}" >> "$FAKE_LOG"; fi
if grep -qx 'model_providers.headroom.http_headers={"x-headroom-bypass"="true"}' "$FAKE_LOG"; then
  if ! grep -q '^\[model_providers\.headroom\]' "${CODEX_HOME:-$HOME/.codex}/config.toml" 2>/dev/null; then
    echo "Error loading config.toml: model_providers.headroom: provider name must not be empty"
    exit 1
  fi
fi
echo "model: fake-model"
echo "provider: headroom" >&2
echo "판정: APPROVE"
exit "${FAKE_RC:-0}"
EOF
chmod +x "$T/fakebin/codex"
export PATH="$T/fakebin:$PATH" FAKE_LOG="$T/args.log"
REAL_HOME="$HOME"
REAL_STAMP="$(stat -f '%m:%z' "$REAL_HOME/.codex/config.toml" 2>/dev/null || echo none)"
# 기본 설정 = 헤드룸 절 «있음» (r513 동작 유지) · HOME·CODEX_HOME 둘 다 임시($T) 안
export HOME="$T/home" CODEX_HOME="$T/codex"
mkdir -p "$HOME" "$CODEX_HOME"
printf '[model_providers.headroom]\nname = "headroom"\nurl = "http://127.0.0.1:8790/v1"\n' > "$CODEX_HOME/config.toml"
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
printf '질문 1: 이 설계가 맞는가\n' > "$T/p.txt"
HDR='model_providers.headroom.http_headers={"x-headroom-bypass"="true"}'

run() { bash "$TOOL" "$@" > "$T/stdout" 2> "$T/stderr"; echo $?; }
has_arg() { grep -qxF -- "$1" "$T/args.log"; }

# ⓐ 인자: bypass 헤더 · 모델 · effort · --skip-git-repo-check · -C · stdin /dev/null
if [ ! -f "$TOOL" ]; then
  bad "ⓐ 래퍼 없음: $TOOL — bypass 헤더 인자 0"
  echo "FAILED=$fail"; exit "$fail"
fi
rc="$(run --cwd "$T/cwd" --prompt-file "$T/p.txt" --out-dir "$T/d")"
[ "$rc" = 0 ] && ok "ⓐ rc0" || bad "ⓐ rc=$rc ($(cat "$T/stderr"))"
has_arg "$HDR" && ok "ⓐ bypass 헤더 인자" || bad "ⓐ bypass 헤더 인자 없음"
has_arg 'model="gpt-6.1-sol"' && ok "ⓐ 기본 모델 sol" || bad "ⓐ model=\"gpt-6.1-sol\" 없음"
has_arg 'model_reasoning_effort="high"' && ok "ⓐ 기본 effort high" || bad "ⓐ effort high 없음"
has_arg '--skip-git-repo-check' && ok "ⓐ --skip-git-repo-check" || bad "ⓐ --skip-git-repo-check 없음"
has_arg "$T/cwd" && ok "ⓐ -C <cwd>" || bad "ⓐ cwd 인자 없음"
grep -qx 'STDIN_BYTES=0' "$T/args.log" && ok "ⓐ stdin = /dev/null(0 바이트)" || bad "ⓐ stdin 이 비어 있지 않음: $(grep STDIN "$T/args.log")"
[ "$(head -1 "$T/args.log")" = exec ] \
  && ok "ⓐ 첫 인자 exec" || bad "ⓐ 첫 인자가 exec 아님"

# ⓑ 출력 = d/da-<시각>-<pid>.out 새 파일 · 끝줄 OUT <경로> rc=<n> · 두 번 = 다른 이름 · 헤더 두 줄 보존
out1="$(tail -1 "$T/stdout" | sed -n 's/^OUT \(.*\) rc=0$/\1/p')"
[ -n "$out1" ] && ok "ⓑ 끝줄 OUT <경로> rc=0" || bad "ⓑ 끝줄 형식: $(tail -1 "$T/stdout")"
case "$(basename "$out1")" in da-[0-9]*-[0-9]*-[0-9]*.out) ok "ⓑ 파일명 da-<시각>-<pid>.out";; *) bad "ⓑ 파일명: $out1";; esac
[ "$(dirname "$out1")" = "$T/d" ] && ok "ⓑ out-dir 안" || bad "ⓑ out-dir 밖: $out1"
grep -qx 'model: fake-model' "$out1" && grep -qx 'provider: headroom' "$out1" \
  && ok "ⓑ 실행 헤더 model:/provider: 두 줄 보존(stderr 포함)" || bad "ⓑ 헤더 두 줄 없음"
grep -qx '판정: APPROVE' "$out1" && ok "ⓑ 판정 본문 보존" || bad "ⓑ 판정 본문 없음"
rc="$(run --cwd "$T/cwd" --prompt-file "$T/p.txt" --out-dir "$T/d")"
out2="$(tail -1 "$T/stdout" | sed -n 's/^OUT \(.*\) rc=0$/\1/p')"
[ -n "$out2" ] && [ "$out2" != "$out1" ] && ok "ⓑ 두 번째 실행 = 다른 이름" || bad "ⓑ 같은 이름/없음: $out2"
[ "$(ls "$T/d" | wc -l | tr -d ' ')" = 2 ] && grep -qx '판정: APPROVE' "$out1" \
  && ok "ⓑ 첫 파일 덮어쓰기 0(파일 2개)" || bad "ⓑ 파일 수 $(ls "$T/d" | wc -l)"

# ⓒ 프롬프트 맨 앞 머리말 1줄 + 원문
prompt="$(cat "$FAKE_LOG.prompt")"
first="$(printf '%s\n' "$prompt" | head -1)"
printf '%s' "$first" | grep -qF '파일은 sed -n 으로 400줄 이하씩 나눠 읽는다' \
  && printf '%s' "$first" | grep -qF '본문을 못 봤으면 HOLD 대신 «검증 불가 — <파일:줄>» 로 적는다' \
  && ok "ⓒ 머리말 1줄(나눠 읽기 · 검증 불가 표기)" || bad "ⓒ 첫 줄이 머리말 아님: $first"
[ "$(printf '%s\n' "$prompt" | sed -n 2p)" = '질문 1: 이 설계가 맞는가' ] \
  && ok "ⓒ 둘째 줄 = 프롬프트 원문" || bad "ⓒ 원문 위치 어긋남"

# ⓓ --model·--effort 덮어쓰기 · 프롬프트 없음/빈 파일 = rc2 + 사유
rc="$(run --cwd "$T/cwd" --prompt-file "$T/p.txt" --out-dir "$T/d" --model gpt-5.5 --effort medium)"
[ "$rc" = 0 ] && has_arg 'model="gpt-5.5"' && has_arg 'model_reasoning_effort="medium"' && has_arg "$HDR" \
  && ok "ⓓ --model/--effort 덮어쓰기(헤더 유지)" || bad "ⓓ 덮어쓰기 실패 rc=$rc"
: > "$FAKE_LOG"; n_before="$(ls "$T/d" | wc -l)"
rc="$(run --cwd "$T/cwd" --prompt-file "$T/none.txt" --out-dir "$T/d")"
[ "$rc" = 2 ] && grep -q 'prompt' "$T/stderr" && [ ! -s "$FAKE_LOG" ] \
  && ok "ⓓ 프롬프트 없음 = rc2 + 사유 · codex 0" || bad "ⓓ 없음 rc=$rc $(cat "$T/stderr")"
: > "$T/empty.txt"
rc="$(run --cwd "$T/cwd" --prompt-file "$T/empty.txt" --out-dir "$T/d")"
[ "$rc" = 2 ] && grep -q 'prompt' "$T/stderr" && [ ! -s "$FAKE_LOG" ] \
  && ok "ⓓ 빈 프롬프트 = rc2 + 사유 · codex 0" || bad "ⓓ 빈 파일 rc=$rc"
[ "$(ls "$T/d" | wc -l)" = "$n_before" ] && ok "ⓓ rc2 = 출력 파일 0" || bad "ⓓ rc2 인데 파일 생김"
rc="$(run --prompt-file "$T/p.txt" --out-dir "$T/d")"
[ "$rc" = 2 ] && ok "ⓓ --cwd 없음 = rc2" || bad "ⓓ --cwd 없음 rc=$rc"

# ⓔ codex rc≠0 → 래퍼 rc 그대로 + 출력 파일 남김 · 전경 실행(래퍼 끝 = codex 끝)
rc="$(FAKE_RC=7 run --cwd "$T/cwd" --prompt-file "$T/p.txt" --out-dir "$T/d")"
oute="$(tail -1 "$T/stdout" | sed -n 's/^OUT \(.*\) rc=7$/\1/p')"
[ "$rc" = 7 ] && [ -s "$oute" ] && ok "ⓔ codex rc7 → 래퍼 rc7 · 출력 파일 남김" || bad "ⓔ rc=$rc out=$oute"
grep -nE '(^|[^&])&[[:space:]]*($|#)' "$TOOL" | grep -v '&&' | grep -q . \
  && bad "ⓔ 래퍼에 백그라운드 & 있음" || ok "ⓔ 백그라운드 & 0"
mkdir -p "$T/slowbin"
cat > "$T/slowbin/codex" <<'EOF'
#!/usr/bin/env bash
sleep 1; echo done > "$FAKE_LOG.slow"
EOF
chmod +x "$T/slowbin/codex"; rm -f "$FAKE_LOG.slow"
PATH="$T/slowbin:$PATH" bash "$TOOL" --cwd "$T/cwd" --prompt-file "$T/p.txt" --out-dir "$T/d" > "$T/stdout" 2> "$T/stderr"
[ -s "$FAKE_LOG.slow" ] && ok "ⓔ 래퍼 종료 시점에 codex 끝남(전경)" || bad "ⓔ 래퍼가 codex 보다 먼저 끝남"

# ── r782: 설정에 `[model_providers.headroom]` 절이 있을 때만 건너뛰기 머리 ─────────────────
cfg_absent()  { printf '[model_providers.cliproxy]\nname = "cliproxy"\n' > "$CODEX_HOME/config.toml"; }
cfg_present() { printf '[model_providers.headroom]\nname = "headroom"\n' > "$CODEX_HOME/config.toml"; }

# HR-ⓐ (빨강 먼저) 절 없는 설정 + 가짜 codex 흉내 → 지금 판(늘 실음)은 rc1
cfg_absent
rc="$(run --cwd "$T/cwd" --prompt-file "$T/p.txt" --out-dir "$T/hr")"
[ "$rc" = 0 ] && ok "HR-ⓐ 헤드룸 절 없는 설정 → rc0(설정 로드 거부 0)" || bad "HR-ⓐ rc=$rc ($(head -2 "$T/stderr"))"

# HR-ⓑ 절 없음 → 머리 인자 0 · INFO stderr 1줄 · 출력 파일엔 INFO 0
has_arg "$HDR" && bad "HR-ⓑ 절 없는데 머리 인자 있음" || ok "HR-ⓑ 절 없음 → 머리 인자 0"
grep -q '헤드룸 provider 없음' "$T/stderr" && ok "HR-ⓑ stderr INFO 1줄" || bad "HR-ⓑ INFO 없음: $(cat "$T/stderr")"
hb="$(tail -1 "$T/stdout" | sed -n 's/^OUT \(.*\) rc=0$/\1/p')"
[ -n "$hb" ] && ! grep -q 'INFO' "$hb" && ok "HR-ⓑ 출력 파일에 INFO 0" || bad "HR-ⓑ 출력 파일 INFO 섞임: $hb"
has_arg 'model="gpt-6.1-sol"' && ok "HR-ⓑ 절 없어도 기본 모델 유지" || bad "HR-ⓑ 모델 인자 없음"

# HR-ⓒ 절 있음 → 머리 인자 있음(지금과 같음 · r513 이유 유지) · INFO 0
cfg_present
rc="$(run --cwd "$T/cwd" --prompt-file "$T/p.txt" --out-dir "$T/hr")"
[ "$rc" = 0 ] && has_arg "$HDR" && ok "HR-ⓒ 절 있음 → 머리 인자 있음 rc0" || bad "HR-ⓒ rc=$rc 머리=$(has_arg "$HDR" && echo y || echo n)"
grep -q '헤드룸 provider 없음' "$T/stderr" && bad "HR-ⓒ 절 있는데 INFO 남" || ok "HR-ⓒ 절 있으면 INFO 0"

# HR-ⓓ CODEX_HOME 미설정 = $HOME/.codex/config.toml 을 봄 · 설정 파일 없음 = 머리 0
mkdir -p "$T/home2"
rc="$(CODEX_HOME= HOME="$T/home2" bash "$TOOL" --cwd "$T/cwd" --prompt-file "$T/p.txt" --out-dir "$T/hr" > "$T/stdout" 2> "$T/stderr"; echo $?)"
[ "$rc" = 0 ] && ! has_arg "$HDR" && ok "HR-ⓓ CODEX_HOME 미설정 · 설정 없음 → 머리 0 rc0" || bad "HR-ⓓ rc=$rc ($(head -2 "$T/stderr"))"
mkdir -p "$T/home2/.codex"
printf '[model_providers.headroom]\nname = "headroom"\n' > "$T/home2/.codex/config.toml"
rc="$(CODEX_HOME= HOME="$T/home2" bash "$TOOL" --cwd "$T/cwd" --prompt-file "$T/p.txt" --out-dir "$T/hr" > "$T/stdout" 2> "$T/stderr"; echo $?)"
[ "$rc" = 0 ] && has_arg "$HDR" && ok "HR-ⓓ \$HOME/.codex/config.toml 절 있음 → 머리 있음" || bad "HR-ⓓ home 설정 rc=$rc"

# HR-ⓔ 판정 = 줄 시작 `[model_providers.headroom]` 글자 일치만 (주석 줄·다른 provider 이름 안의 글자 0)
printf '# [model_providers.headroom]\n' > "$CODEX_HOME/config.toml"
run --cwd "$T/cwd" --prompt-file "$T/p.txt" --out-dir "$T/hr" > /dev/null
has_arg "$HDR" && bad "HR-ⓔ 주석 줄을 절로 읽음" || ok "HR-ⓔ 주석 줄 → 머리 0"
printf '[model_providers.headroom]\n' | sed 's/headroom/headroomx/' > "$CODEX_HOME/config.toml"
run --cwd "$T/cwd" --prompt-file "$T/p.txt" --out-dir "$T/hr" > /dev/null
has_arg "$HDR" && bad "HR-ⓔ headroomx 를 headroom 절로 읽음" || ok "HR-ⓔ [model_providers.headroomx] → 머리 0"
printf '[model_providers.other]\nname = "x"\n' > "$CODEX_HOME/config.toml"
run --cwd "$T/cwd" --prompt-file "$T/p.txt" --out-dir "$T/hr" > /dev/null
has_arg "$HDR" && bad "HR-ⓔ 다른 provider 에서 머리" || ok "HR-ⓔ 다른 provider 절 → 머리 0"
printf '[model_providers.headroom] # 헤드룸\n' > "$CODEX_HOME/config.toml"
run --cwd "$T/cwd" --prompt-file "$T/p.txt" --out-dir "$T/hr" > /dev/null
has_arg "$HDR" && ok "HR-ⓔ 줄 시작 절(주석 달림) → 머리 있음" || bad "HR-ⓔ 줄 시작 절을 놓침"

# HR-ⓕ 절 없어도 모델·effort·-C·stdin /dev/null·새 출력 파일명·끝줄 `OUT <경로> rc=<n>` 은 지금과 같음
cfg_absent
before_list="$(ls "$T/hr" 2>/dev/null | wc -l | tr -d ' ')"
rc="$(run --cwd "$T/cwd" --prompt-file "$T/p.txt" --out-dir "$T/hr" --model gpt-5.5 --effort medium)"
hf="$(tail -1 "$T/stdout" | sed -n 's/^OUT \(.*\) rc=0$/\1/p')"
[ "$rc" = 0 ] && has_arg 'model="gpt-5.5"' && has_arg 'model_reasoning_effort="medium"' \
  && has_arg '--skip-git-repo-check' && has_arg "$T/cwd" && grep -qx 'STDIN_BYTES=0' "$T/args.log" \
  && ok "HR-ⓕ 모델·effort·-C·--skip-git-repo-check·stdin 0 유지" || bad "HR-ⓕ 인자 어긋남 rc=$rc"
case "$(basename "$hf")" in da-[0-9]*-[0-9]*-[0-9]*.out) ok "HR-ⓕ 출력 파일 새 이름 da-<시각>-<pid>.out";; *) bad "HR-ⓕ 파일명: $hf";; esac
[ "$(ls "$T/hr" | wc -l | tr -d ' ')" = "$((before_list + 1))" ] && ok "HR-ⓕ 실행마다 새 파일(덮어쓰기 0)" || bad "HR-ⓕ 파일 수 $(ls "$T/hr" | wc -l)"

# HR-ⓗ 실 ~/.codex 읽기·쓰기 0 (CODEX_HOME·HOME = 임시)
case "$HOME" in "$T"/*) case "$CODEX_HOME" in "$T"/*) ok "HR-ⓗ HOME·CODEX_HOME 모두 임시";; *) bad "HR-ⓗ CODEX_HOME 실경로";; esac;; *) bad "HR-ⓗ HOME 실경로";; esac
grep -nE '(^|[^0-9])>>?[^&|]*config\.toml' "$TOOL" > /dev/null 2>&1 \
  && bad "HR-ⓗ 래퍼가 config.toml 에 쓰기" || ok "HR-ⓗ 래퍼 config.toml 쓰기 0"
[ "$(stat -f '%m:%z' "$REAL_HOME/.codex/config.toml" 2>/dev/null || echo none)" = "$REAL_STAMP" ] \
  && ok "HR-ⓗ 실 ~/.codex/config.toml 불변" || bad "HR-ⓗ 실 config 변경됨"

# HR-ⓖ 변이: 조건 삭제(늘 실음) → HR-ⓑ FAIL · 늘 뺌 → HR-ⓒ FAIL
if [ "${FT_DA_WRAPPER_MUTANT_CHECK:-1}" = 1 ]; then
  sed 's/^if \[ -f "\$cfg" \] && grep -q .*; then$/if true; then/' "$TOOL" > "$T/mut_always.sh"
  sed 's/^if \[ -f "\$cfg" \] && grep -q .*; then$/if false; then/' "$TOOL" > "$T/mut_never.sh"
  cmp -s "$TOOL" "$T/mut_always.sh" && bad "HR-ⓖ 변이 실음 생성 실패(조건 줄 미일치)" || ok "HR-ⓖ 변이 실음 생성"
  FT_DA_WRAPPER_MUTANT_CHECK=0 DA_CODEX_TOOL="$T/mut_always.sh" bash "${BASH_SOURCE[0]:-$0}" > "$T/mutA.log" 2>&1 \
    && bad "HR-ⓖ 변이(늘 실음)가 통과함" || ok "HR-ⓖ 변이(늘 실음) = 실패"
  grep -q 'FAIL HR-ⓑ' "$T/mutA.log" && ok "HR-ⓖ 변이(늘 실음) → HR-ⓑ FAIL" || bad "HR-ⓖ 변이(늘 실음)에 HR-ⓑ FAIL 없음"
  FT_DA_WRAPPER_MUTANT_CHECK=0 DA_CODEX_TOOL="$T/mut_never.sh" bash "${BASH_SOURCE[0]:-$0}" > "$T/mutB.log" 2>&1 \
    && bad "HR-ⓖ 변이(늘 뺌)가 통과함" || ok "HR-ⓖ 변이(늘 뺌) = 실패"
  grep -q 'FAIL HR-ⓒ' "$T/mutB.log" && ok "HR-ⓖ 변이(늘 뺌) → HR-ⓒ FAIL" || bad "HR-ⓖ 변이(늘 뺌)에 HR-ⓒ FAIL 없음"
fi

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILED=$fail"
exit "$fail"
