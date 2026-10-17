#!/usr/bin/env bash
# serena-guard — serena MCP 서버가 부풀면 재기동해 메모리를 돌려받는다.
#
# 왜 (2026-09-15 사고):
#   serena(9493) 가 5.5GB 까지 부풀어 시스템이 jetsam 으로 cfprefsd·trustd 를 초당 단위로 죽였고,
#   그 jetsam 카운트(103건/10분)가 zombie-clean 의 RED 판정을 띄웠다. RED 는 keep-last-1 과
#   「멤버≤keep lineage」 보호를 «우회» 하므로, 좌석이 역할당 하나뿐인 이 환경에서는
#   idle 10분 넘은 좌석이 전부 kill 됐다(실측 4개: arch-fable#42·da-claude#2·tester-check#3·tmm).
#   즉 «serena 메모리» 가 «좌석 몰살» 로 번지는 경로가 있었다. 그 경로의 출발점을 여기서 끊는다.
#
# 원칙:
#   - 매 틱 재기동하지 않는다. 기동은 캐시를 다시 읽는 비용이라 그 자체가 스파이크다.
#     임계를 넘었을 때만 재기동한다(기본 3GB).
#   - 재기동은 «실행 중인 argv 그대로» 한다 — --project 가 빠지면 다른 프로젝트로 뜬다.
#   - 오염 캐시(node_modules 가 섞인 document_symbols.pkl)는 재기동으로 안 낫는다. 크기만 경고한다.
set -uo pipefail

LOG="${SERENA_GUARD_LOG:-$HOME/.claude/logs/serena-guard.log}"
MAX_MB="${SERENA_MAX_MB:-3000}"          # 이 값을 넘으면 재기동
CACHE_WARN_MB="${SERENA_CACHE_WARN_MB:-400}"   # 심볼 캐시 파일 하나가 이보다 크면 경고
DRY="${SERENA_GUARD_DRY:-0}"
mkdir -p "$(dirname "$LOG")"

log() { printf '%s %s\n' "$(date '+%F %T')" "$*" >> "$LOG"; }

# streamable-http 로 뜬 serena 인스턴스만 다룬다.
# stdio 인스턴스는 부모(codex·claude)가 수명을 쥐고 있어 밖에서 죽이면 그 세션이 깨진다.
PIDS=()
while IFS= read -r _p; do [ -n "$_p" ] && PIDS+=("$_p"); done \
    < <(pgrep -f 'serena start-mcp-server.*--transport streamable-http' 2>/dev/null)   # mapfile 은 bash 4+ — launchd 의 /bin/bash(3.2) 호환
[ "${#PIDS[@]}" -eq 0 ] && exit 0

restarted=0
for pid in "${PIDS[@]}"; do
    # uv 래퍼(수십 MB)가 아니라 실제 서버(python)만 본다
    cmd="$(ps -o command= -p "$pid" 2>/dev/null)" || continue
    case "$cmd" in */uv\ tool*|*"/uv "*) continue ;; esac

    rss_mb=$(( $(ps -o rss= -p "$pid" 2>/dev/null || echo 0) / 1024 ))
    [ "$rss_mb" -eq 0 ] && continue

    port="$(printf '%s' "$cmd" | sed -n 's/.*--port \([0-9]*\).*/\1/p')"
    proj="$(printf '%s' "$cmd" | sed -n 's/.*--project \(.*\)$/\1/p')"

    # 캐시 오염 감시 — 재기동으로 안 낫는 축이라 «경고만» 한다.
    if [ -n "$proj" ] && [ -d "$proj/.serena/cache" ]; then
        while IFS= read -r f; do
            fmb=$(( $(stat -f %z "$f" 2>/dev/null || echo 0) / 1048576 ))
            [ "$fmb" -ge "$CACHE_WARN_MB" ] && \
                log "WARN 심볼캐시 ${fmb}MB — node_modules 유입 의심: $f (project.yml ignored_paths 확인)"
        done < <(find "$proj/.serena/cache" -name '*.pkl' -type f 2>/dev/null)
    fi

    if [ "$rss_mb" -lt "$MAX_MB" ]; then
        continue
    fi

    if [ "$DRY" = 1 ]; then
        log "[dry] restart pid=$pid port=${port:-?} rss=${rss_mb}MB (임계 ${MAX_MB}MB)"
        restarted=$((restarted+1)); continue
    fi

    # 부모 uv 래퍼도 같이 정리한다(남으면 다음 틱에 유령으로 잡힌다)
    ppid="$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')"
    kill "$pid" 2>/dev/null
    [ -n "$ppid" ] && [ "$ppid" != 1 ] && kill "$ppid" 2>/dev/null
    sleep 3

    # 원래 커맨드 그대로 다시 띄운다
    ( cd "${proj:-$HOME}" && nohup /opt/homebrew/bin/uv tool uvx \
        --from git+https://github.com/oraios/serena serena start-mcp-server \
        --transport streamable-http --host 127.0.0.1 --port "$port" \
        --open-web-dashboard False --project "$proj" \
        >>"${LOG%.log}-$port.out" 2>&1 & disown ) 2>/dev/null

    # 기동 확인 (최대 40초)
    ok=0
    for _ in $(seq 1 20); do
        sleep 2
        if lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1; then ok=1; break; fi
    done
    newpid="$(pgrep -f "serena start-mcp-server.*--port $port" 2>/dev/null | tail -1)"
    newrss=$(( $(ps -o rss= -p "${newpid:-0}" 2>/dev/null || echo 0) / 1024 ))
    if [ "$ok" = 1 ]; then
        log "restart ok port=$port ${rss_mb}MB -> ${newrss}MB (임계 ${MAX_MB}MB) pid=$pid -> ${newpid:-?}"
    else
        log "restart FAILED port=$port — LISTEN 안 뜸. 수동 확인 필요: $cmd"
    fi
    restarted=$((restarted+1))
done

[ "$restarted" -gt 0 ] && exit 0
exit 0
