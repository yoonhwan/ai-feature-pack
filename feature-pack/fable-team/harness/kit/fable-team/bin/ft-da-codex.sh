#!/usr/bin/env bash
# ft-da-codex.sh — DA(적대검증) 용 codex exec 호출 1곳 (r513).
# r990: 머리말 둘째 줄 [DA 전수] — DA 는 1회차에 기준 «전체» 를 훑어 반례를 한 묶음으로 낸다(한 건 왕복 금지).
# 사용: ft-da-codex.sh --cwd <폴더> --prompt-file <파일> --out-dir <폴더> [--model gpt-6.1-sol] [--effort low|high · 기본 low]
# 헤드룸 «건너뛰기» 헤더(x-headroom-bypass)를 provider 요청 머리에 싣는다 — 경로(8790→8317)·계정 회전·모델은 그대로,
# 본문 접힘(캐시 참조)만 0. DA 는 승인 정책 never 라 headroom_retrieve 로 원문을 다시 못 받기 때문.
# ★조건(r782)★ 설정(${CODEX_HOME:-$HOME/.codex}/config.toml)에 `[model_providers.headroom]` 절이 «있을 때만» 싣는다 —
# 헤드룸 경로가 꺼진 설정에서 그 머리만 남으면 codex 가 «provider name must not be empty» 로 설정 로드 거부(rc1).
# 절이 없으면 머리 0 + stderr INFO 1줄(출력 파일엔 안 섞임).
# 출력 = <out-dir>/da-<YYYYmmdd-HHMMSS>-<pid>.out (실행마다 새 이름 · 덮어쓰기 0) · 끝줄 `OUT <경로> rc=<n>` · rc = codex rc.
# r947: 출력 옆 `<out>.meta` 1줄 `head=<40hex|none> model=<M> effort=<E> rc=<n> start=<epoch> end=<epoch>` — head = codex «전» git -C <cwd> rev-parse HEAD(실패 = none · 상시 승인이 거절)
set -uo pipefail

PREAMBLE='[DA 머리말] 파일은 sed -n 으로 400줄 이하씩 나눠 읽는다 · 본문을 못 봤으면 HOLD 대신 «검증 불가 — <파일:줄>» 로 적는다.
[DA 전수] 1회차에 질문지의 결과 계약·기준 «전체» 를 훑어 반례를 한 묶음으로 낸다 · 한 건을 찾았다고 멈추지 않는다 · 이미 처리된 지난 반례는 다시 내지 않는다 · 기준 밖 지적은 범위 밖 메모로만 적는다.'
BYPASS='model_providers.headroom.http_headers={"x-headroom-bypass"="true"}'
usage() { echo "usage: ft-da-codex.sh --cwd <폴더> --prompt-file <파일> --out-dir <폴더> [--model M] [--effort E]" >&2; exit 2; }

cwd="" prompt_file="" out_dir="" model="gpt-6.1-sol" effort="low"   # r1066: 기본 low — 어려운 판정에서만 부르는 쪽이 --effort high 를 적는다
while [ $# -gt 0 ]; do
  [ $# -ge 2 ] || usage
  case "$1" in
    --cwd) cwd="$2" ;;
    --prompt-file) prompt_file="$2" ;;
    --out-dir) out_dir="$2" ;;
    --model) model="$2" ;;
    --effort) effort="$2" ;;
    *) usage ;;
  esac
  shift 2
done
[ -n "$cwd" ] && [ -n "$out_dir" ] && [ -n "$prompt_file" ] || usage
[ -d "$cwd" ] || { echo "ERROR cwd 폴더 없음: $cwd" >&2; exit 2; }
[ -s "$prompt_file" ] || { echo "ERROR prompt 파일 없음 또는 빈 파일: $prompt_file" >&2; exit 2; }
mkdir -p "$out_dir" || { echo "ERROR out-dir 만들기 실패: $out_dir" >&2; exit 2; }

out="$out_dir/da-$(date +%Y%m%d-%H%M%S)-$$.out"
n=0
while [ -e "$out" ]; do n=$((n+1)); out="$out_dir/da-$(date +%Y%m%d-%H%M%S)-$$-$n.out"; done
# r939 H1: «곧 끝나는 일» 자기 등록 — 승계(retire)가 이 DA 를 죽이지 않고 후계에게 넘긴다(장부 state/bg-finite.tsv · 상한 70분)
HERE0="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
bash "$HERE0/ft-bg-finite.sh" register "${FT_SEAT:--}" "${FT_BG_FINITE_DA_SEC:-4200}" "$$" "ft-da-codex.sh cwd=$cwd" >/dev/null 2>&1 || true   # 등록 실패 = 넘김 대상 아님(오늘과 같은 reap) — 도구 stdout 계약을 흔들지 않는다
trap 'bash "$HERE0/ft-bg-finite.sh" unregister $$ >/dev/null 2>&1 || true' EXIT

cfg="${CODEX_HOME:-$HOME/.codex}/config.toml"
bypass=()
if [ -f "$cfg" ] && grep -q '^\[model_providers\.headroom\]' "$cfg" 2>/dev/null; then
  bypass=(-c "$BYPASS")
else
  echo "INFO 헤드룸 provider 없음($cfg) → 건너뛰기 머리 0" >&2
fi

head="$(git -C "$cwd" rev-parse --verify -q HEAD 2>/dev/null)"; [[ "$head" =~ ^[0-9a-f]{40}$ ]] || head=none   # DA 가 «본» sha — codex 가 cwd 에 커밋해도 바뀌지 않게 먼저 잰다
start="$(date +%s)"
prompt="$PREAMBLE
$(cat "$prompt_file")"
codex exec --skip-git-repo-check -C "$cwd" \
  -c "model=\"$model\"" -c "model_reasoning_effort=\"$effort\"" ${bypass[@]+"${bypass[@]}"} \
  "$prompt" < /dev/null > "$out" 2>&1
rc=$?
printf 'head=%s model=%s effort=%s rc=%s start=%s end=%s\n' "$head" "${model//[[:space:]]/_}" "${effort//[[:space:]]/_}" "$rc" "$start" "$(date +%s)" > "$out.meta" || echo "WARN .meta 쓰기 실패: $out.meta" >&2
echo "OUT $out rc=$rc"
exit "$rc"
