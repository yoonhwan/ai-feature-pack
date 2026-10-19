#!/usr/bin/env bash
# test_da_codex_wrapper.sh — r513 시험: DA 용 codex 래퍼 ft-da-codex.sh 가 헤드룸 «건너뛰기» 헤더·모델·effort·
# 머리말을 싣고, 실행마다 새 출력 파일을 만들고, 실패를 그대로 돌려준다.
# 픽스처 = PATH 앞 가짜 codex(받은 인자·stdin 을 파일에 적고 고정 판정 출력) · 외부 호출 0 · 헤드룸 0 · GIT_* env 0.
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
echo "model: fake-model"
echo "provider: headroom" >&2
echo "판정: APPROVE"
exit "${FAKE_RC:-0}"
EOF
chmod +x "$T/fakebin/codex"
export PATH="$T/fakebin:$PATH" FAKE_LOG="$T/args.log"
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
cat > "$T/fakebin/codex" <<'EOF'
#!/usr/bin/env bash
sleep 1; echo done > "$FAKE_LOG.slow"
EOF
chmod +x "$T/fakebin/codex"; rm -f "$FAKE_LOG.slow"
run --cwd "$T/cwd" --prompt-file "$T/p.txt" --out-dir "$T/d" >/dev/null
[ -s "$FAKE_LOG.slow" ] && ok "ⓔ 래퍼 종료 시점에 codex 끝남(전경)" || bad "ⓔ 래퍼가 codex 보다 먼저 끝남"

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILED=$fail"
exit "$fail"
