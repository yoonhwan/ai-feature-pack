#!/usr/bin/env bash
# test_tmuxc_opencode_model.sh — r476: opencode 좌석 모델 = 세션 env OPENCODE_CONFIG_CONTENT(--model 플래그 0).
#   opencode 2.0.32 TUI 최상위엔 --model 이 없다(run 서브명령 전용 → «Unrecognized flag: --model» 기동 실패).
#   픽스처 = 가짜 opencode(최상위 --model 이면 rc1 · env 를 파일로 떨굼) + 가짜 tmux(new-session -e 기록 · send-keys 로 받은 명령을 그 env 로 실행).
#   실 opencode·실 tmux·외부 호출 0 · GIT_* env 0.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
TMUXC="$HERE/../core/bin/tmuxc"
SPAWNS=("$HERE/../../fable-team/harness/bin/ft-nano-spawn.sh" "$HERE/../../fable-team/harness/kit/fable-team/bin/ft-nano-spawn.sh")
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
ID="opencode/deepseek-v4.1-flash-free"
mkdir -p "$T/bin" "$T/home" "$T/wt"

cat > "$T/bin/opencode" <<'SH'
#!/usr/bin/env bash
for a in "$@"; do [ "$a" = --model ] && { echo "Unrecognized flag: --model" >&2; exit 1; }; done
printf '%s' "${OPENCODE_CONFIG_CONTENT:-}" > "$FAKE_OUT/opencode.env"
python3 -c 'import json,os;c=os.environ.get("OPENCODE_CONFIG_CONTENT");print(json.loads(c)["model"] if c else "")' > "$FAKE_OUT/opencode.model"
SH
cat > "$T/bin/tmux" <<'SH'
#!/usr/bin/env bash
case "$1" in
  has-session) exit 1 ;;
  new-session) printf '%s\n' "$*" >> "$FAKE_OUT/tmux.log"; shift
    : > "$FAKE_OUT/seat.env"
    while [ $# -gt 0 ]; do [ "$1" = -e ] && { printf '%s\n' "$2" >> "$FAKE_OUT/seat.env"; shift; }; shift; done ;;
  send-keys) [ "${4:-}" = -l ] || exit 0
    case "$5" in opencode*) envs=(); while IFS= read -r kv; do envs+=("$kv"); done < "$FAKE_OUT/seat.env"
      env ${envs[@]+"${envs[@]}"} bash -c "$5"; echo "rc=$?" > "$FAKE_OUT/opencode.rc" ;; esac ;;
  display-message) echo test-orch ;;
  *) exit 0 ;;
esac
SH
chmod +x "$T/bin/opencode" "$T/bin/tmux"
run_open() { env -i PATH="$T/bin:$PATH" HOME="$T/home" FAKE_OUT="$T/out" bash "$TMUXC" open "$T/wt" --name R476 --agent opencode "$@"; }

# ⓐ dry-run — 명령 줄에 --model 0 · env 줄 1
out="$(run_open --model "$ID" --dry-run 2>&1)"
cmdl="$(printf '%s\n' "$out" | grep '^command=')"
[ "$cmdl" = "command=opencode --auto" ] && ok "ⓐ dry-run 명령 = opencode --auto(--model 0)" || bad "ⓐ 명령 줄: $cmdl"
n="$(printf '%s\n' "$out" | grep -cxF "env=OPENCODE_CONFIG_CONTENT={\"model\":\"$ID\"}")"
[ "$n" = 1 ] && ok "ⓐ env 줄 OPENCODE_CONFIG_CONTENT 1" || bad "ⓐ env 줄 $n개: $out"

# ⓑ 실행(가짜) — new-session -e FT_SEAT + -e OPENCODE_CONFIG_CONTENT · 가짜 opencode 가 env 로 모델을 읽는다
mkdir -p "$T/out"; run_open --model "$ID" >/dev/null 2>&1
grep -qF -- "-e FT_SEAT=R476 -e OPENCODE_CONFIG_CONTENT={\"model\":\"$ID\"}" "$T/out/tmux.log" \
  && ok "ⓑ new-session -e FT_SEAT · -e OPENCODE_CONFIG_CONTENT" || bad "ⓑ new-session 인자: $(cat "$T/out/tmux.log" 2>/dev/null)"
[ "$(cat "$T/out/opencode.rc" 2>/dev/null)" = rc=0 ] && [ "$(cat "$T/out/opencode.model" 2>/dev/null)" = "$ID" ] \
  && ok "ⓑ 가짜 opencode rc0 · model 칸 = $ID" || bad "ⓑ opencode $(cat "$T/out/opencode.rc" 2>/dev/null) model=$(cat "$T/out/opencode.model" 2>/dev/null)"

# ⓒ 모델 미지정 — env 0 · 명령 opencode --auto(기본값 박기 0)
out="$(run_open --dry-run 2>&1)"
printf '%s\n' "$out" | grep -q '^env=OPENCODE_CONFIG_CONTENT' && bad "ⓒ 모델 없음인데 env 줄: $out" || ok "ⓒ 모델 없음 → OPENCODE env 0(r610 GIT_* 3줄은 있음)"
printf '%s\n' "$out" | grep -qx 'command=opencode --auto' && ok "ⓒ 명령 opencode --auto 그대로" || bad "ⓒ 명령: $out"
rm -rf "$T/out"; mkdir -p "$T/out"; run_open >/dev/null 2>&1
grep -q OPENCODE_CONFIG_CONTENT "$T/out/tmux.log" && bad "ⓒ 실행에 env 심음" || ok "ⓒ 실행 new-session 에 OPENCODE env 0"

# ⓓ #variant 붙은 ID — JSON 그대로 통과(글자 검사만)
out="$(run_open --model "$ID#max" --dry-run 2>&1)"
printf '%s\n' "$out" | grep -qxF "env=OPENCODE_CONFIG_CONTENT={\"model\":\"$ID#max\"}" && ok "ⓓ #variant 그대로" || bad "ⓓ $out"
# 따옴표·역슬래시도 JSON 이스케이프(글자 깨짐 0)
out="$(run_open --model 'a/b"c\d' --dry-run 2>&1)"
printf '%s\n' "$out" | grep -qxF 'env=OPENCODE_CONFIG_CONTENT={"model":"a/b\"c\\d"}' && ok "ⓓ JSON 이스케이프" || bad "ⓓ 이스케이프 $out"

# fork 경로도 같은 처리(--model 플래그 0 · env 1)
mkdir -p "$T/ocs/proj"; echo '{}' > "$T/ocs/proj/ses_x.json"   # --source 실재 확인용 가짜 레거시 저장소
out="$(env -i PATH="$T/bin:$PATH" HOME="$T/home" TMUXC_OPENCODE_SESSIONS="$T/ocs" TMUXC_OPENCODE_DB="$T/none.db" \
  bash "$TMUXC" fork "$T/wt" --name R476F --source ses_x --agent opencode --model "$ID" --dry-run 2>&1)"
printf '%s\n' "$out" | grep -qx 'command=opencode --auto --session ses_x --fork' && ok "fork 명령 --model 0" || bad "fork 명령: $out"
printf '%s\n' "$out" | grep -qxF "env=OPENCODE_CONFIG_CONTENT={\"model\":\"$ID\"}" && ok "fork env 1" || bad "fork env: $out"

# 다른 agent 경로 — OPENCODE env 0(r610 부터 GIT_* 3줄은 모든 비 claude 좌석에 실린다)
out="$(env -i PATH="$T/bin:$PATH" HOME="$T/home" bash "$TMUXC" open "$T/wt" --name R476C --agent codex --model gpt-x --dry-run 2>&1)"
printf '%s\n' "$out" | grep -q '^env=OPENCODE' && bad "codex 에 OPENCODE env 줄: $out" || ok "codex OPENCODE env 0(다른 agent 불변)"

# ⓔ ft-nano-spawn PLAN 줄 — opencode = via=OPENCODE_CONFIG_CONTENT · claude = via 0 (PLAN 블록만 꺼내 돌린다)
for SP in "${SPAWNS[@]}"; do
  tag="$(basename "$(dirname "$(dirname "$SP")")")"
  { grep '^_VIA=""' "$SP"; grep '^echo "PLAN seat=' "$SP"; } > "$T/plan.sh"
  [ "$(wc -l < "$T/plan.sh")" -eq 2 ] || { bad "ⓔ $tag: PLAN 블록 추출 실패"; continue; }
  plan() { env -i PATH="$PATH" NAME=s AGENT="$1" MODEL="$2" WTDIR=w BRANCH=b BASE_BRANCH=origin/main IDX_REL=i bash "$T/plan.sh"; }
  r="$(plan opencode "$ID")"
  case "$r" in *"model=$ID via=OPENCODE_CONFIG_CONTENT"*) ok "ⓔ $tag: PLAN opencode via=OPENCODE_CONFIG_CONTENT";; *) bad "ⓔ $tag: $r";; esac
  r="$(plan claude m)"; case "$r" in *via=*) bad "ⓔ $tag: claude 에 via: $r";; *) ok "ⓔ $tag: claude PLAN via 0";; esac
  grep -q 'ft-opencode-reap.sh(r286) 미설치' "$SP" && ok "ⓔ $tag: R286 reap REJECT 줄 그대로" || bad "ⓔ $tag: reap REJECT 줄 없음"
done
cmp -s "${SPAWNS[0]}" "${SPAWNS[1]}" && ok "ft-nano-spawn 추적본 = 키트(cmp)" || bad "ft-nano-spawn 추적본 ≠ 키트"

# 600/300 초 상한 0(이 변경 범위)
grep -nE '\b(600|300)\b' "$TMUXC" | grep -qi 'opencode' && bad "opencode 경로에 600/300" || ok "600/300 0"
echo
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
