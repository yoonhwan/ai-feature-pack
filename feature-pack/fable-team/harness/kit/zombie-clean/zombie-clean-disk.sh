#!/bin/bash
# zombie-clean-disk.sh — 디스크 임계 점검 + 후보 목록 (R128 · R246). zombie-clean.sh `disk` 가 부른다.
#
# 사용: zombie-clean-disk.sh [--dry-run] [--apply-approved]
#  · 사용률 < 임계(ZC_DISK_THRESHOLD, 기본 90%) = 출력 0 · rc 0
#  · 이상 = 후보 목록 1통(삭제 0). 목록은 HF 캐시·Docker 미사용 볼륨·uv·ollama.
#  · --apply-approved 일 때만 승인 범주 삭제: HF `models--*`·`datasets--*` + `docker volume prune -f`(익명만 · -a 금지).
#    uv·ollama·이름 있는 docker 볼륨은 어떤 경우에도 목록만(삭제 = HIL).
#  · docker 호출은 7초 룰: 시도당 ZC_DISK_CALL_TIMEOUT_S(기본 7) + 재시도 1. 두 번 다 실패 = ERROR(stderr) + rc 1 (조용한 통과 0).
set -uo pipefail

DRY=false; APPLY=false
for a in "$@"; do case "$a" in --dry-run) DRY=true ;; --apply-approved) APPLY=true ;; esac; done

THRESHOLD="${ZC_DISK_THRESHOLD:-90}"
CALL_TIMEOUT="${ZC_DISK_CALL_TIMEOUT_S:-7}"
HF_HUB="${ZC_HF_HUB:-$HOME/.cache/huggingface/hub}"
UV_DIR="${ZC_UV_DIR:-$HOME/.cache/uv}"
OLLAMA_DIR="${ZC_OLLAMA_DIR:-$HOME/.ollama}"
RC=0

# 시도당 상한 + 재시도 1. stdout 은 성공한 시도의 것만 낸다.
run7() {
    local try out pid i
    for try in $(seq 1 "${RUN7_TRIES:-2}"); do
        out=$(mktemp "${TMPDIR:-/tmp}/zcdisk.XXXXXX")
        "$@" > "$out" 2>/dev/null & pid=$!
        i=0
        while kill -0 "$pid" 2>/dev/null && (( i < CALL_TIMEOUT * 10 )); do sleep 0.1; i=$((i+1)); done
        if kill -0 "$pid" 2>/dev/null; then
            pkill -TERM -P "$pid" 2>/dev/null; kill -TERM "$pid" 2>/dev/null; wait "$pid" 2>/dev/null
            rm -f "$out"; continue
        fi
        if wait "$pid"; then cat "$out"; rm -f "$out"; return 0; fi
        rm -f "$out"
    done
    return 1
}

# 크기 조회도 7초 상한(시도 1회) — uv 캐시 58GB 는 du 110초·uv cache size 46초라 못 쪼개므로 «크기 미확인» 으로 보고한다(목록만 범주라 삭제 판단에 영향 0).
fmt_kb() {
    [[ "${1:-}" =~ ^[0-9]+$ ]] || { echo "크기 미확인(${CALL_TIMEOUT}초 초과)"; return; }
    awk -v k="$1" 'BEGIN { if (k >= 1048576) printf "%.1fGB", k/1048576; else printf "%dMB", k/1024 }'
}
dirs_kb() {  # $@=경로들 → 합계 KB, 없으면 0, 시간 초과/실패면 빈 문자열
    local d existing=()
    for d in "$@"; do [[ -d "$d" ]] && existing+=("$d"); done
    (( ${#existing[@]} )) || { echo 0; return; }
    local out
    out=$(RUN7_TRIES=1 run7 du -sk "${existing[@]}") || return 0   # 시간 초과 = 빈 값(0 으로 둔갑시키지 않는다)
    printf '%s\n' "$out" | awk '{s += $1} END {print s+0}'
}

pct=$(df -Pk "${ZC_DISK_PATH:-$HOME}" 2>/dev/null | awk 'NR==2 { gsub("%", "", $5); print $5 }')
[[ "$pct" =~ ^[0-9]+$ ]] || { echo "ERROR disk: df 사용률을 읽지 못함 (${ZC_DISK_PATH:-$HOME})" >&2; exit 1; }
(( pct < THRESHOLD )) && exit 0

hf_dirs=()
if [[ -n "$HF_HUB" && -d "$HF_HUB" ]]; then
    for d in "$HF_HUB"/models--* "$HF_HUB"/datasets--*; do [[ -d "$d" ]] && hf_dirs+=("$d"); done
fi
hf_models=0; hf_datasets=0
for d in "${hf_dirs[@]+"${hf_dirs[@]}"}"; do
    case "$(basename "$d")" in models--*) hf_models=$((hf_models+1)) ;; *) hf_datasets=$((hf_datasets+1)) ;; esac
done
hf_kb=$(dirs_kb "${hf_dirs[@]+"${hf_dirs[@]}"}")

anon=0; named=0; vol_reclaim="?"
if vols=$(run7 docker volume ls -q -f dangling=true); then
    anon=$(printf '%s\n' "$vols" | grep -cE '^[0-9a-f]{64}$')
    named=$(printf '%s\n' "$vols" | grep -cvE '^([0-9a-f]{64})?$')
    # docker system df 는 실측 7.2초(볼륨 크기 계산) — 상한에 걸리면 크기만 «미확인» 으로 쓰고 개수 목록은 유지한다.
    vol_reclaim=$(RUN7_TRIES=1 run7 docker system df --format '{{.Type}}|{{.Reclaimable}}' | awk -F'|' '$1=="Local Volumes" {print $2}')
    vol_reclaim="${vol_reclaim:-크기 미확인(${CALL_TIMEOUT}초 초과)}"
else
    echo "ERROR docker: volume ls ${CALL_TIMEOUT}초 안에 응답 없음/실패 (재시도 1회 후) — Docker 후보 확인 못 함" >&2; RC=1
fi

echo "디스크 사용률 ${pct}% (임계 ${THRESHOLD}%) — 정리 후보 목록$($APPLY && ! $DRY || echo ' (삭제 0)')"
echo "  HF 캐시 $(fmt_kb "$hf_kb") (models-- ${hf_models}개 · datasets-- ${hf_datasets}개) · 승인 범주"
if (( RC == 0 )); then
    echo "  Docker 미사용 볼륨 ${anon}개 (익명) 회수 가능 ${vol_reclaim} · 승인 범주 · 이름 있는 볼륨 ${named}개는 목록만"
fi
echo "  uv 캐시 $(fmt_kb "$(dirs_kb "$UV_DIR")") · 목록만"
echo "  ollama $(fmt_kb "$(dirs_kb "$OLLAMA_DIR")") · 목록만"

$APPLY || exit "$RC"
if $DRY; then echo "  [dry] --apply-approved: HF ${#hf_dirs[@]}개 삭제 · docker volume prune -f 실행 예정 (실행 안 함)"; exit "$RC"; fi
for d in "${hf_dirs[@]+"${hf_dirs[@]}"}"; do rm -rf -- "$d"; done
echo "  삭제: HF ${#hf_dirs[@]}개"

# Docker API < 1.42 는 prune 에 all=true 가 자동 적용돼 이름 있는 볼륨(byz-agents_postgres_data 등)까지 지운다(moby v23 volume_routes.go) — 하네스는 여러 머신에 배포되므로 prune 직전 서버 API 를 확인한다.
# 1.42 이상일 때만 prune. 미달·파싱 실패·호출 실패 = ERROR + RC=1 + prune 건너뜀 (HF 삭제는 위에서 이미 끝남).
docker_api_ok() {
    local v major minor
    v=$(run7 docker version --format '{{.Server.APIVersion}}') || { echo "ERROR docker: 서버 API 버전 조회 실패/${CALL_TIMEOUT}초 초과 — volume prune 건너뜀" >&2; return 1; }
    v=$(printf '%s' "$v" | tr -d '[:space:]')
    [[ "$v" =~ ^([0-9]+)\.([0-9]+)$ ]] || { echo "ERROR docker: 서버 API 버전 파싱 실패('$v') — volume prune 건너뜀" >&2; return 1; }
    major=${BASH_REMATCH[1]}; minor=${BASH_REMATCH[2]}
    (( major > 1 || (major == 1 && minor >= 42) )) || { echo "ERROR docker: 서버 API ${v} < 1.42 — prune 이 이름 있는 볼륨까지 지우므로 volume prune 건너뜀" >&2; return 1; }
}
if (( RC == 0 )); then
    if ! docker_api_ok; then RC=1
    elif run7 docker volume prune -f >/dev/null; then echo "  삭제: docker volume prune -f 실행"
    else echo "ERROR docker: volume prune -f 실패/${CALL_TIMEOUT}초 초과" >&2; RC=1; fi
fi
exit "$RC"
