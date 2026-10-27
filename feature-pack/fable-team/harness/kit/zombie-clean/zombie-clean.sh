#!/bin/bash
# zombie-clean.sh v2 — orphan-chain + pipe-peer 판정 기반 좀비 정리
#
# 판정 2단계:
#  ① 조상 체인: ppid 체인을 걸어 올라가 살아있는 세션 호스트(claude/codex/cursor/tmux/
#     데스크톱앱)나 tty 보유 조상을 만나면 = 사용중. pid 1까지 못 만나면 = 고아 후보.
#  ② 파이프 피어: 고아 후보라도 살아있는 세션·사용중 프로세스와 stdio 파이프가 연결돼
#     있으면 = 사용중(구제). stdio MCP 서버는 중간 래퍼(npm exec/uvx)가 먼저 죽으면
#     launchd(pid 1)로 재입양되지만 파이프는 살아있다 — 트리만 보면 오살한다(2026-08-02 실증).
#
# 불변 규칙:
#  · 세션 프로세스 자체(claude/codex)는 절대 죽이지 않는다 (tmux kill-session 절차로만)
#  · dev 서버·인프라(next-server/uvicorn/redis/postgres/headroom/hermes/ollama/IDE)는 항상 제외
#  · CDP :9333 크롬(byz-e2e 상시) + ESTABLISHED CDP 연결이 있는 테스트 크롬은 보호
#
# modes: scan | clean [--dry-run] | auto | status
#  auto = 훅 전용: 5분 스로틀 + 락 + 3초 유예 후 조용히 정리, 로그 ~/.claude/logs/zombie-clean.log
set -uo pipefail

CMD="${1:-scan}"
DRY=false; [[ "${2:-}" == "--dry-run" ]] && DRY=true
LOGDIR="$HOME/.claude/logs"; LOG="$LOGDIR/zombie-clean.log"
STAMP="/tmp/zombie-clean-$(id -u).last"
LOCK="/tmp/zombie-clean-$(id -u).lock"
WORK="$(mktemp -d /tmp/zc.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$LOGDIR"

PS="$WORK/ps.txt"; ZF="$WORK/zombies.txt"; TB="$WORK/table.txt"
LH="$WORK/livehosts.txt"; AWKF="$WORK/an.awk"

# 세션 호스트 패턴: 이 조상을 만나면 "사용중" (bash·awk 공용, ENVIRON로 전달)
# ★ft-*-tick.sh 류 디바운스 크론★ (2026-09-13 실증): nohup+disown 뒤 ppid=1(launchd)+tty없음으로
#   재입양되면, while 루프의 `sleep N` 자식이 "고아 sleep" 카테고리(:94)에 걸려 조상 체인에
#   HOSTRE 매치가 없으면 SIGTERM 오살당한다(pm-tick 30분+ 무음 사망, 로그 "Terminated: 15").
#   스크립트 자체 이름을 조상 매치 패턴에 넣어 alive() 판정에서 항상 "사용중"으로 구제한다.
export ZC_HOSTRE='(^|[/ ])claude([ ]|$)|--dangerously-skip-permissions|@openai/codex|(^|[/ ])codex([ ]|$)|cursor-agent|(^|[/ ])tmux([ ]|$)|Claude( Helper)?\.app|(^|[/ ])gemini([ ]|$)|opencode|ft-master-tick\.sh|ft-pm-tick\.sh|ft-goal-tick\.sh|ft-.*-tick\.sh'
# 항상 제외: 인프라·dev 서버·IDE·시스템 (좀비 후보로도 안 삼는다)
# streamable-http serena = serena-mcp.sh 관리의 프로젝트당 공유서버(ppid=1 상주가 정상) — 2026-09-01 제외
export ZC_EXCL='headroom|hermes|tailscale|[Oo]llama|uvicorn|next-server|next dev|redis-server|postgres|qdrant|mysqld|OpenClaw|openclaw|Google Chrome\.app|Google Chrome Helper|Visual Studio Code|Code Helper|Cursor\.app|Windsurf|JetBrains|IntelliJ|[Pp]y[Cc]harm|com\.apple\.|/System/|/usr/libexec|Docker|colima|zombie-clean|start-mcp-server --transport streamable-http'

snapshot() { ps -axwwo pid=,ppid=,tty=,rss=,command= > "$PS"; }

# 이 스크립트 자신의 부모 체인 (호출 세션 보호 방어선)
self_chain() {
    local p=$$ out=""
    while [[ -n "$p" && "$p" -gt 1 ]] 2>/dev/null; do
        out="$out $p"
        p=$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' ')
    done
    echo "$out"
}

# CDP 실사용 크롬 루트 pid (:9333은 무조건 보호, 그 외 포트는 ESTABLISHED만)
cdp_alive_chromes() {
    local out=""
    while read -r pid port; do
        [[ -z "$pid" ]] && continue
        if [[ "$port" == "9333" ]]; then out="$out $pid"; continue; fi
        if lsof -nP -iTCP:"$port" -sTCP:ESTABLISHED >/dev/null 2>&1; then out="$out $pid"; fi
    done < <(awk '{
        if (match($0, /--remote-debugging-port=[0-9]+/)) {
            s = substr($0, RSTART, RLENGTH); sub(/.*=/, "", s); print $1, s
        }
    }' "$PS")
    echo "$out"
}

# ── 구조적 보호선 2개 (v3, 2026-09-11) ────────────────────────────────────────
# ZC_EXCL 은 «열거식 패턴» 이라 목록에 없는 것은 전부 구멍이다. 아래 둘은 열거가 아니라
# «시스템에 물어보는» 판별이므로 목록 관리 없이 구조적으로 막힌다.
#
# ① launchd 등록 pid = 정의상 데몬. ppid=1 이라 «고아» 로 보이지만 부모가 launchd 인 게 정상.
#    실증(2026-09-11): xclaw 크루 16개(nanoclaw, 847MB)가 전부 ppid=1 + node.
#    ZC_EXCL 에 xclaw/nanoclaw 가 없으므로, 누가 «ppid=1 node» 를 카테고리에 넣는 순간 전멸한다.
#    launchd 관리 프로세스의 정지는 kill 이 아니라 `launchctl bootout` 이 옳은 경로다.
# ② tmux 서버 pid. tmux 서버는 «최초 실행 커맨드라인» 을 계속 유지한다 —
#    실측: pid 27942 의 argv 가 `tmux new-session -d -s ft-kakao-architect#9 ...` (경과 2h40m).
#    ppid=1 + argv 가 tmux + 장시간 → 「고아 tmux」로 보인다. 종료하면 kill-server 와 동일 효과
#    (전 좌석 동시 파괴 = HIL 대상). HOSTRE 의 tmux 패턴은 «argv 매칭» 이라 서버 자신은
#    커버되지만, pid 로 못 박아 두면 패턴이 바뀌어도 안전하다.
launchd_pids() { launchctl list 2>/dev/null | awk 'NR>1 && $1 ~ /^[0-9]+$/ {print $1}' | tr '\n' ' '; }
tmux_server_pid() { tmux display -p '#{pid}' 2>/dev/null | tr -d ' ' || true; }

# ③ agent-browser 데몬 pid (R178, 2026-10-14). 데몬은 ppid=1 로 떨어지고 크롬을 포트 0(무작위)으로 띄워
#    조상 체인 검사(alive)도 포트 검사(cdp_alive_chromes)도 못 잡는다 — 쓰는 중인 시험 크롬이 auto 회차마다 죽었다.
#    세션 파일(<세션>.pid/.sock/.target)에 «물어본다»: pid 숫자 · kill -0 살아 있음 · .sock 실재 ·
#    같은 세션 파일 중 가장 최근 mtime 이 ZC_AB_IDLE_MIN(기본 30분) 안 — 넷 다일 때만 그 데몬 pid 를 보호 pid 에 넣는다.
#    ★닫는 사건★: 세션 파일 없음 · 데몬 죽음 · 마지막 사용이 문턱 밖 중 하나면 넣지 않는다 = 기존대로 정리된다.
agent_browser_live_pids() {
    local dir="${ZC_AB_DIR:-$HOME/.agent-browser}" idle="${ZC_AB_IDLE_MIN:-30}" now pf base pid f m newest out=""
    [[ "$idle" =~ ^[0-9]+$ ]] || idle=30
    now=$(date +%s)
    for pf in "$dir"/*.pid; do
        [[ -f "$pf" ]] || continue
        base="${pf%.pid}"
        pid=$(tr -d ' \n' < "$pf" 2>/dev/null)
        [[ "$pid" =~ ^[0-9]+$ ]] && (( pid > 1 )) || continue
        kill -0 "$pid" 2>/dev/null || continue
        [[ -e "$base.sock" ]] || continue
        newest=0
        for f in "$base".*; do
            m=$(stat -f %m "$f" 2>/dev/null || echo 0)
            (( m > newest )) && newest=$m
        done
        (( now - newest <= idle * 60 )) || continue
        out="$out $pid"
    done
    echo "$out"
}

write_awk() {
cat > "$AWKF" << 'AWKEOF'
BEGIN {
    HOSTRE = ENVIRON["ZC_HOSTRE"]; EXCL = ENVIRON["ZC_EXCL"]
    n = split(hostpids, H, " ")
    for (i = 1; i <= n; i++) if (H[i] != "") HOST[H[i]] = 1
    NC = 0
    addcat("MCP(node)",    "@upstash|@modelcontextprotocol|sequential-thinking|task-master-ai|playwright-mcp|stitch-mcp|context7-mcp|mcp-server\\.cjs|excalidraw/dist|claude-mem|worker-service|chrome-devtools-mcp|omc.*bridge|[Pp]encil.*(mcp|server)|notebooklm-mcp")
    addcat("MCP(python)",  "serena|chroma-mcp")
    addcat("래퍼(npm·uv)", "npm exec |uv tool uvx|(^|/)uvx ")
    addcat("툴 헬퍼",      "\\.serena/|/_npx/|\\.cache/uv/|\\.omo/|codegraph|typescript-language-server|tsserver\\.js|typingsInstaller|pyright")
    addcat("E2E 크롬",     "agent-browser-chrome-|mcp-chrome-|Chrome for Testing|crashpad_handler")
    addcat("고아 tail",    "(^|/)tail -[fF] ")   # ^ 앵커는 /usr/bin/tail 형태를 놓친다
    addcat("고아 sleep",   "(^|/)sleep [0-9]")   # 2026-09-11 실증: `/bin/sleep 600` 이 ^sleep 에 안 걸렸다
}
function addcat(nm, re) { NC++; CN[NC] = nm; CR[NC] = re }
{
    pid = $1; ppid = $2; tty = $3; rss = $4
    cmd = $5; for (i = 6; i <= NF; i++) cmd = cmd " " $i
    PP[pid] = ppid; TT[pid] = tty; RS_[pid] = rss; CM[pid] = cmd
}
# 사용중 판정: 조상 체인에 보호 pid / 호스트 패턴 / tty 보유자가 있으면 1
function alive(pid,    p, hop) {
    if (pid in MEMO) return MEMO[pid]
    p = pid
    for (hop = 0; hop < 64; hop++) {
        if (p in HOST)                    { MEMO[pid] = 1; return 1 }
        if (CM[p] ~ HOSTRE)               { MEMO[pid] = 1; return 1 }
        if (TT[p] != "??" && TT[p] != "") { MEMO[pid] = 1; return 1 }
        p = PP[p]
        if (p == "" || p == 0 || p == 1) break
        if (!(p in CM)) break
    }
    MEMO[pid] = 0; return 0
}
# 바로 위 부모가 스냅샷에 살아 있고 launchd(1)가 아니면 1 — 관찰 루프(nohup·disown)의 sleep/tail 보호 (R178).
#   부모가 1 이거나 스냅샷에 없으면 0 = 기존대로 정리 (부모 루프가 죽으면 그 sleep 이 ppid=1 로 떨어져 닫힌다).
function parent_live(pid,    p) {
    p = PP[pid]
    return (p != "" && p != 0 && p != 1 && (p in CM)) ? 1 : 0
}
END {
    for (pid in CM) if (CM[pid] ~ HOSTRE) print pid > lhfile   # 세션 호스트 → 파이프 검사 소스
    for (pid in CM) {
        cmd = CM[pid]
        if (cmd ~ EXCL) continue
        cat = ""
        for (i = 1; i <= NC; i++) if (cmd ~ CR[i]) { cat = CN[i]; break }
        if (cat == "") continue
        if (alive(pid) || ((cat == "고아 sleep" || cat == "고아 tail") && parent_live(pid))) {
            LC[cat]++; LR[cat] += RS_[pid]
            print pid > lhfile                                  # 사용중 후보도 파이프 소스에 포함
        } else {
            ZC[cat]++; ZR[cat] += RS_[pid]
            printf "%s|%s|%d|%s\n", pid, cat, RS_[pid], substr(cmd, 1, 100) >> zfile
        }
    }
    printf "%-16s %6s %9s %6s %9s\n", "카테고리", "사용중", "메모리", "좀비", "메모리" > tbl
    for (i = 1; i <= NC; i++) {
        c = CN[i]
        if (LC[c] + 0 == 0 && ZC[c] + 0 == 0) continue
        printf "%-16s %6d %7.0fMB %6d %7.0fMB\n", c, LC[c]+0, LR[c]/1024, ZC[c]+0, ZR[c]/1024 > tbl
    }
}
AWKEOF
}

# lsof -F에서 PIPE·unix socket 레코드의 0x 커널주소 토큰 추출 (pid 붙임 여부는 인자)
# 주의: 이 환경의 Claude Code는 MCP stdio를 unix socketpair로 연결한다(PIPE 아님) — 둘 다 잡는다
pipe_tokens() {  # $1 = 콤마 pid 목록, $2 = "withpid"면 "pid tok" 형식
    local fmt="tdn"; [[ "${2:-}" == "withpid" ]] && fmt="ptdn"
    lsof -nP -S 2 -F "$fmt" -p "$1" 2>/dev/null | awk -v wp="${2:-}" '
        /^p/            { pid = substr($0, 2); next }
        /^t(PIPE|unix)/ { inp = 1; next }
        /^t/            { inp = 0; next }
        inp && match($0, /0x[0-9a-f]+/) {
            tok = substr($0, RSTART, RLENGTH)
            if (wp == "withpid") print pid, tok; else print tok
        }'
}

# 고아 후보 중 살아있는 쪽과 파이프로 연결된 프로세스 구제 (최대 3라운드 전이 확장)
pipe_rescue() {
    [[ -s "$ZF" && -s "$LH" ]] || return 0
    sort -u "$LH" > "$LH.u" && mv "$LH.u" "$LH"
    # 살아있는 쪽 / 후보 쪽 파이프 토큰 (50개씩 청크로 lsof)
    xargs -n 50 < "$LH" 2>/dev/null | tr ' ' ',' | while read -r chunk; do
        [[ -n "$chunk" ]] && pipe_tokens "$chunk"
    done > "$WORK/livepipes.txt"
    grep -v '|E2E 크롬|' "$ZF" | cut -d'|' -f1 | xargs -n 50 2>/dev/null | tr ' ' ',' | while read -r chunk; do
        [[ -n "$chunk" ]] && pipe_tokens "$chunk" withpid
    done > "$WORK/candtok.txt"
    [[ -s "$WORK/livepipes.txt" && -s "$WORK/candtok.txt" ]] || return 0
    sort -u "$WORK/livepipes.txt" > "$WORK/lp.txt"
    : > "$WORK/rescued.txt"
    local round prev=0 cur
    for round in 1 2 3; do
        awk 'NR==FNR { live[$1]=1; next } ($2 in live) { print $1 }' "$WORK/lp.txt" "$WORK/candtok.txt" \
            | sort -u > "$WORK/r.txt"
        cur=$(grep -c . "$WORK/r.txt" 2>/dev/null); cur=${cur:-0}
        [[ "$cur" -le "$prev" ]] && break
        prev=$cur; cp "$WORK/r.txt" "$WORK/rescued.txt"
        # 구제된 pid의 토큰을 live 집합에 편입 → 손자 파이프까지 전이
        awk 'NR==FNR { r[$1]=1; next } ($1 in r) { print $2 }' "$WORK/rescued.txt" "$WORK/candtok.txt" \
            >> "$WORK/lp.txt"
        sort -u "$WORK/lp.txt" > "$WORK/lp.u" && mv "$WORK/lp.u" "$WORK/lp.txt"
    done
    if [[ -s "$WORK/rescued.txt" ]]; then
        local rn; rn=$(grep -c . "$WORK/rescued.txt")
        awk -F'|' 'NR==FNR { r[$1]=1; next } !($1 in r)' "$WORK/rescued.txt" "$ZF" > "$ZF.n" && mv "$ZF.n" "$ZF"
        echo "파이프 연결 구제(사용중 재분류): ${rn}개" >> "$TB"
    fi
}

analyze() {
    : > "$ZF"; : > "$TB"; : > "$LH"
    snapshot; write_awk
    awk -v hostpids="$(self_chain) $(cdp_alive_chromes) $(launchd_pids) $(tmux_server_pid) $(agent_browser_live_pids)" \
        -v zfile="$ZF" -v tbl="$TB" -v lhfile="$LH" -f "$AWKF" "$PS"
    pipe_rescue
    awk -F'|' '{ n++; s += $3 } END { printf "확정 좀비 %d개 · ~%.0fMB\n", n+0, s/1024 }' "$ZF" >> "$TB"
}

# 과잉 인구조사: 좀비(orphan)가 아니어도 세션×MCP 곱셈으로 프로세스가 쌓이는 걸 가시화.
# Claude Code 알려진 이슈(#83689): idle 세션이 MCP 세트를 teardown 안 함 → 세션 수 × MCP 수로 폭증.
# 좀비 리포트가 "사용중"으로 정상 분류하는 프로세스라 clean으로 안 잡힌다 — 여기서 과잉만 진단·경고.
mcp_census() {
    [[ -s "$PS" ]] || snapshot
    local sess mcpn per flag dup
    # 세션 수: claude 바이너리 + codex(npm exec) 실행 인스턴스 (세션당 1개 루트)
    sess=$(grep -cE '(/|^)[^ ]*\.local/bin/claude( |$)|npm exec @openai/codex|@openai/codex ' "$PS")
    # 사용중 MCP 프로세스 수 = 표의 MCP(node)+MCP(python) 사용중 열 합
    mcpn=$(awk '$1=="MCP(node)"||$1=="MCP(python)"{s+=$2} END{print s+0}' "$TB")
    if [[ "$sess" -le 0 ]]; then echo "MCP 인구조사: 활성 세션 0"; return 0; fi
    per=$(( mcpn / sess ))
    flag=""; [[ "$per" -ge 15 ]] && flag=" ⚠️ 과잉 — idle 세션 정리(tmux-prune) + codex/claude MCP 로스터 축소 권고"
    echo "MCP 인구조사: 세션 ${sess}개 · MCP프로세스 ${mcpn}개 · 세션당 ~${per}개${flag}"
    # MCP 진입 인스턴스 수 vs 세션 수 대조로 고아 잔존(릭)을 잡는다.
    #   진입 시그니처만 센다: serena=uvx 래퍼(language_servers 자식 제외), 나머지=npm exec 라인.
    #   인스턴스 > 세션 = idle teardown 안 된 고아 잔존(CC 이슈 #83689) → clean으로 reap 권고.
    dup=$(awk -v sess="$sess" '
        /language_servers/ || /grep -|zombie-clean/ { next }
        /uv tool uvx/ && /serena/      { serena++ }
        /npm exec/ && /server-filesystem/     { fs++ }
        /npm exec/ && /sequential-thinking/   { think++ }
        /npm exec/ && /context7/              { ctx++ }
        /npm exec/ && /playwright/            { pw++ }
        END{
            d=0
            split("serena "serena" filesystem "fs" think "think" context7 "ctx" playwright "pw, a, " ")
            for(i=1;i<=length(a);i+=2){ nm=a[i]; c=a[i+1]+0
                if(c>sess){ printf "  ⚠️ %s 인스턴스 %d개 > 세션 %d개 → 고아 %d개 잔존(릭, clean으로 reap)\n", nm, c, sess, c-sess; d++ }
            }
            if(d==0) print "  MCP 진입 인스턴스 = 세션 수 이내 (고아 잔존 없음)"
        }
    ' "$PS")
    echo "$dup"
}

do_clean() {
    analyze
    local n; n=$(grep -c . "$ZF" 2>/dev/null || true)
    cat "$TB"
    if [[ "$n" -eq 0 ]]; then echo "좀비 없음"; return 0; fi
    if $DRY; then
        echo "-- dry-run: 종료하지 않음. 상위 15개 --"
        sort -t'|' -k3 -rn "$ZF" | head -15 | awk -F'|' '{printf "  %s [%s] %.0fMB %s\n", $1, $2, $3/1024, $4}'
        return 0
    fi
    local before; before=$(ps -axo rss= | awk '{s+=$1} END{printf "%.1f", s/1048576}')
    cut -d'|' -f1 "$ZF" | xargs -n 50 kill -TERM 2>/dev/null || true
    sleep 2
    # 생존자: command 앞 100자 재대조(pid 재사용 오살 방지) 후 강제 종료
    local surv=""
    while IFS='|' read -r pid cat rss cmd; do
        local cur; cur=$(ps -o command= -p "$pid" 2>/dev/null | cut -c1-100 || true)
        [[ -n "$cur" && "$cur" == "$cmd" ]] && surv="$surv $pid"
    done < "$ZF"
    if [[ -n "$surv" ]]; then echo $surv | xargs kill -9 2>/dev/null || true; fi
    local after; after=$(ps -axo rss= | awk '{s+=$1} END{printf "%.1f", s/1048576}')
    echo "정리 완료: ${n}개 종료 (전체 RSS ${before}GB → ${after}GB)"
    echo "$(date '+%F %T') mode=$CMD killed=$n rss=${before}GB->${after}GB" >> "$LOG"
}

# 로그 로테이션 — 반드시 append 블록 밖에서 호출(블록 안 mv는 fd를 끊어 이후 출력 유실)
rotate_log() { tail -n 400 "$LOG" > "$LOG.t" 2>/dev/null && mv "$LOG.t" "$LOG"; }

# ── 회수 대장 기반 복원 (v3, 2026-09-11) ──────────────────────────────────────
# ★tmm restore 는 회수분의 «일부만» 커버한다 — dead-scan 의 창·계보 필터 탓.
#   실측(2026-09-11): 37개 회수 후 `tmm dead --since 24` 는 25행만 보였고
#   ft-kakao-architect#9 · FB_VEC_IMPL#6 · loom_domain_impl#2 는 아예 미노출 → restore 거부.
#   대장에는 cwd + «전체 argv»(model·effort·resume uuid 포함)가 있으니 그것으로 직접 되살리는 게
#   보장 경로다. ft-kakao-architect#9 로 실증 복원 성공(이전 컨텍스트·모델·remote-control 그대로).
cmd_restore() {
    local name="" led="" dry=false a cwd argv
    for a in "$@"; do
        case "$a" in
            --dry-run) dry=true ;;
            *) if [[ -z "$name" ]]; then name="$a"; elif [[ -z "$led" ]]; then led="$a"; fi ;;
        esac
    done
    [[ -z "$name" ]] && { echo "사용법: zombie-clean.sh restore '<세션명>' [대장.tsv] [--dry-run]"; return 1; }
    if [[ -z "$led" ]]; then
        led=$(grep -lF "$(printf '\t%s\t' "$name")" "$LOGDIR"/zc-reclaim-*.tsv 2>/dev/null | tail -1)
    fi
    [[ -z "$led" || ! -f "$led" ]] && { echo "❌ 회수 대장에서 '$name' 을 못 찾음 ($LOGDIR/zc-reclaim-*.tsv)"; return 1; }
    cwd=$(awk -F'\t' -v n="$name" '$2==n{c=$6} END{print c}' "$led")
    argv=$(awk -F'\t' -v n="$name" '$2==n{x=$8} END{print x}' "$led")
    [[ -z "$argv" || "$argv" == "?" ]] && { echo "❌ 대장에 argv 가 없다: $name"; return 1; }
    if tmux has-session -t "=$name" 2>/dev/null; then echo "⚠️ 이미 살아있는 세션: $name — 복원 생략"; return 1; fi
    # R524: 첫 낱말이 claude(·…/claude) 면 그 낱말만 헤드룸 래퍼로 — 대장 argv 는 래퍼가 exec 한 본체라 그대로 보내면 프록시 미경유 직결
    local first="${argv%% *}" rest=""; [[ "$argv" == *" "* ]] && rest=" ${argv#* }"
    if [[ "$first" == claude || "$first" == */claude ]]; then
        hr_wrapper_ok || return 1
        argv="$(printf '%q' "$ZC_CLAUDE_HR")$rest"
    fi
    if $dry; then echo "[dry] session=$name"; echo "[dry] cwd=$cwd"; echo "[dry] argv=$argv"; return 0; fi
    tmux new-session -d -s "$name" -c "${cwd:-$HOME}" || { echo "❌ 세션 생성 실패: $name"; return 1; }
    tmux send-keys -t "=$name:" -l "$argv"; sleep 0.3; tmux send-keys -t "=$name:" Enter
    echo "✅ 복원: $name  (cwd=$cwd · 대장=$led)"
}

# 대장 한 장을 전부 복원. $1=대장파일(기본 최신) — 메모리 압력 확인하고 쓸 것(37개면 ~10GB).
cmd_restore_from() {
    local led="" dry="" a
    for a in "$@"; do case "$a" in --dry-run) dry="--dry-run" ;; *) [[ -z "$led" ]] && led="$a" ;; esac; done
    [[ -z "$led" ]] && led=$(ls -t "$LOGDIR"/zc-reclaim-*.tsv 2>/dev/null | head -1)
    [[ -z "$led" || ! -f "$led" ]] && { echo "❌ 대장 없음"; return 1; }
    echo "대장: $led ($(awk -F'\t' 'NR>1 && $1!~/^#/' "$led" | grep -c .) 행)"
    awk -F'\t' 'NR>1 && $1!~/^#/ && $2!=""{print $2}' "$led" | while IFS= read -r n; do
        cmd_restore "$n" "$led" $dry
    done
}

# ── 직전 세대 재개 기록 (판정 1344, 2026-10-13) ───────────────────────────────
# ft-seat-retire.sh 가 은퇴 때 쓰는 기록(대화 uuid·작업 폴더·모델) — 이게 «검증»되는 직전 세대(순번 2)만 tmux_prune 이 닫고,
# `resume` 이 같은 대화를 다시 연다. 기록이 없거나 어긋나면 지금처럼 보존한다(조용한 대체 0). 명부는 읽지 않는다.
#   `resume --from-live`(R163): 같은 검사·같은 명령인데 기록 경로만 «살아 있는 좌석 스냅샷»(ft-tick 이 계속 남김 · source=live) 폴더로.
ZC_FROM_LIVE=0
resume_record_file() {
    if [[ "$ZC_FROM_LIVE" == 1 ]]; then echo "${ZC_LIVE_DIR:-$HOME/.claude/state/seat-live}/$1.json"
    else echo "${ZC_RESUME_DIR:-$HOME/.claude/state/seat-resume}/$1.json"; fi
}
# $1=세션명 → rc 0 검증됨 · rc 2 기록 없음 · rc 1 불일치(사유 1단어 stdout: name|engine|uuid|jsonl|cwd|model|파일읽기)
resume_record_check() {
    local f; f=$(resume_record_file "$1"); [[ -f "$f" ]] || return 2
    python3 - "$f" "$1" <<'PY'
import json, os, sys
f, name = sys.argv[1:3]
try: d = json.load(open(f, encoding="utf-8"))
except (OSError, ValueError): print("파일읽기"); sys.exit(1)
if not isinstance(d, dict): print("파일읽기"); sys.exit(1)
uuid, jl, cwd, model = (d.get(k) for k in ("uuid", "jsonl", "cwd", "model"))
for why, ok in (("name", d.get("name") == name), ("engine", d.get("engine") == "claude"), ("uuid", isinstance(uuid, str) and bool(uuid)),
                ("jsonl", isinstance(jl, str) and os.path.isfile(jl) and os.path.basename(jl) == f"{uuid}.jsonl"),
                ("cwd", isinstance(cwd, str) and os.path.isdir(cwd)), ("model", isinstance(model, str) and bool(model))):
    if not ok: print(why); sys.exit(1)
PY
}

# $1=세션명 — 기록의 binding(세션·window·pane·pid·시작시각)이 «지금 그 좌석 pane 의 그 프로세스»와 같은가(닫기 전용 · DA⑥ 잔여 H1 · R364 판정기 하나).
#   은퇴 때 그 프로세스에서 만든 기록만 닫기 근거다 — pane 이 바뀌었거나(같은 이름 재생성)·pid 재사용(시작시각 불일치)·binding 없는 옛 기록은 닫지 않는다. 판정기 ft_seat_bind.py = 이 스크립트와 «같은 폴더» 고정 경로(리포 탐색 0) ·
#   없거나 조회 불가(rc 2)면 닫지 않는다(fail-closed · 옛 판정 후퇴 0). resume 경로는 세션이 죽은 뒤라 쓰지 않는다.
resume_record_pid_live() {
    local bind; bind="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)/ft_seat_bind.py"
    [[ -f "$bind" ]] || { echo "  ERROR 결속 판정기 없음: $bind" >&2; return 2; }
    python3 "$bind" "$1" --expect "$(resume_record_file "$1")" >/dev/null 2>&1
}

# resume '<세션명>' [--dry-run] — 검증된 재개 기록으로 같은 대화를 같은 폴더·모델로 다시 연다. 검증 실패·이미 살아 있음 = ❌ rc 1.
cmd_resume() {
    local name="" dry=false a why rc f cwd uuid model cmd
    for a in "$@"; do case "$a" in --dry-run) dry=true ;; --from-live) ZC_FROM_LIVE=1 ;; *) [[ -z "$name" ]] && name="$a" ;; esac; done
    [[ -z "$name" ]] && { echo "사용법: zombie-clean.sh resume '<세션명>' [--dry-run] [--from-live]"; return 1; }
    why=$(resume_record_check "$name"); rc=$?
    [[ $rc -eq 2 ]] && { echo "❌ 재개 기록 없음: $name ($(resume_record_file "$name"))"; return 1; }
    [[ $rc -ne 0 ]] && { echo "❌ 재개 기록 불일치(${why:-검사 실패}): $name"; return 1; }
    if tmux has-session -t "=$name" 2>/dev/null; then echo "⚠️ 이미 살아있는 세션: $name — 재개 생략"; return 1; fi
    f=$(resume_record_file "$name")
    IFS=$'\t' read -r uuid cwd model < <(python3 -c 'import json,sys;d=json.load(open(sys.argv[1]));print("\t".join(d[k] for k in ("uuid","cwd","model")))' "$f")
    [[ -n "$uuid" && -n "$cwd" && -n "$model" ]] || { echo "❌ 재개 기록 읽기 실패: $name"; return 1; }
    hr_wrapper_ok || return 1
    cmd="$(printf '%q' "$ZC_CLAUDE_HR") --dangerously-skip-permissions --resume $uuid --model '$model'"
    if $dry; then echo "[dry] session=$name"; echo "[dry] cwd=$cwd"; echo "[dry] cmd=$cmd"; return 0; fi
    tmux new-session -d -s "$name" -c "$cwd" || { echo "❌ 세션 생성 실패: $name"; return 1; }
    # 전송 실패를 성공으로 보고하지 않는다(DA⑥ H2) — 열린 세션은 자동으로 닫지 않고 사람이 확인한다.
    tmux send-keys -t "=$name:" -l "$cmd" || { echo "❌ 명령 전송 실패(-l): 세션 $name 열린 채 — 확인 뒤 닫기"; return 1; }
    sleep 0.3
    tmux send-keys -t "=$name:" Enter || { echo "❌ Enter 전송 실패: 세션 $name 열린 채 — 확인 뒤 닫기"; return 1; }
    echo "✅ 재개: $name  (uuid=$uuid · cwd=$cwd · 모델=$model)"
    resume_headroom_check "$name"
}

# ── 헤드룸 래퍼 (R524, 2026-10-20) ────────────────────────────────────────────
# 재개·복원은 claude 를 래퍼로만 연다 — 날 claude 는 프록시(8317)를 안 타 세션 한도에 걸린다(10-20 concierge master#6 실사건).
# 래퍼가 없으면 직결로 대신 열지 않고 실패한다. 전역 ANTHROPIC_BASE_URL export 0(프로젝트 레벨 래퍼로만).
ZC_CLAUDE_HR="${ZC_CLAUDE_HR:-$HOME/.headroom/claude-hr.sh}"
hr_wrapper_ok() { [[ -x "$ZC_CLAUDE_HR" ]] || { echo "❌ 헤드룸 래퍼 없음: $ZC_CLAUDE_HR"; return 1; }; }

# $1=세션명 — 열린 pane 의 claude 본체(래퍼가 exec 한 뒤) env 에서 ANTHROPIC_BASE_URL 확인 1줄. kill 0 · 항상 rc 0
#   (래퍼는 fail-open 이라 프록시 死 때 직결은 정상일 수 있다 — 경고만. 꼴 = tmuxc HEADROOM_BYPASS)
resume_headroom_check() {
    local name="$1" wait_s="${ZC_HR_WAIT_S:-7}" i pp pid="" url
    for ((i = 0; i < wait_s * 2; i++)); do
        pp=$(tmux list-panes -t "=$name:" -F '#{pane_pid}' 2>/dev/null | head -1)
        pid=$(pgrep -P "${pp:-0}" 2>/dev/null | head -1)
        [[ -n "$pid" && "$(basename -- "$(ps -o comm= -p "$pid" 2>/dev/null)")" == claude ]] && break
        pid=""; sleep 0.5
    done
    [[ -z "$pid" ]] && { echo "WARN HEADROOM 확인 불가(${wait_s}s) $name"; return 0; }
    url=$(ps eww "$pid" 2>/dev/null | tr ' ' '\n' | sed -n 's/^ANTHROPIC_BASE_URL=//p' | head -1)
    if [[ -n "$url" ]]; then echo "HEADROOM ok $name pid=$pid ANTHROPIC_BASE_URL=$url"
    else echo "WARN HEADROOM_BYPASS $name pid=$pid — 프록시 미경유 직결(kill 0 · 확인 뒤 래퍼로 다시)"; fi
}

# ── 메모리 압력 티어 (v3, 2026-09-11) ─────────────────────────────────────────
# 근거: 커널 패닉 2회(09-09 09:34 / 09-11 03:44) 실측. 두 번 다 동일 서명 —
#   "Compressor Info: 4x% of compressed pages limit (OK) and 100% of segments limit (BAD)
#    with 37~38 swapfiles" → 압축기 «세그먼트» 고갈로 커널 할당 경로가 막혀
#    watchdogd 90~94초 미체크인 → watchdog timeout 패닉.
# 압박 시작(첫 jetsam kill 09-10 21:44) → 패닉(03:44) 까지 리드타임 6시간.
# 세그먼트 수를 직접 노출하는 sysctl이 없어(vm.compressor_* 는 bytes 3종뿐) 3지표를 프록시로 쓴다.
#   swapfile 개수    : 패닉 시 37~38개 / 평시 1~4개   (7ms, 무료)
#   jetsam kill/10분 : 패닉 6시간 전부터 지속 발생     (~2.9s)
#   compressor bytes : 사용량 프록시                    (즉시)
# 티어는 tmux_prune 의 idle 임계를 조인다: GREEN 120분 / YELLOW 30분 / RED 10분
ZC_TIER=""; ZC_TIER_WHY=""
pressure_tier() {
    [[ -n "$ZC_TIER" ]] && return 0          # 호출당 1회만 측정 (캐시)
    local swapn compgb jets
    swapn=$(ls /System/Volumes/VM/swapfile* 2>/dev/null | wc -l | tr -d ' ')
    compgb=$(( $(sysctl -n vm.compressor_bytes_used 2>/dev/null || echo 0) / 1073741824 ))
    # 시험은 ZC_JETS_CMD 주입으로 실제 log show 호출 0 — 절대경로(/usr/bin/log)라 PATH 스텁이 안 먹는다(2026-10-27 부하 46~69 실사건).
    if [[ -n "${ZC_JETS_CMD:-}" ]]; then
        jets=$("$ZC_JETS_CMD" 2>/dev/null | grep -c killing_idle_process || true)
    else
        jets=$(/usr/bin/log show --last 10m --predicate 'eventMessage CONTAINS "killing_idle_process"' 2>/dev/null \
               | grep -c killing_idle_process || true)
    fi
    jets="${jets:-0}"
    if   [[ "$swapn" -ge "${ZC_P_SWAP_RED:-16}" || "$jets" -ge "${ZC_P_JETS_RED:-60}" || "$compgb" -ge "${ZC_P_COMP_RED:-26}" ]]; then
        ZC_TIER=RED
    elif [[ "$swapn" -ge "${ZC_P_SWAP_YEL:-8}"  || "$jets" -ge "${ZC_P_JETS_YEL:-20}" || "$compgb" -ge "${ZC_P_COMP_YEL:-20}" ]]; then
        ZC_TIER=YELLOW
    else
        ZC_TIER=GREEN
    fi
    ZC_TIER_WHY="swapfile=${swapn} jetsam/10m=${jets} compressor=${compgb}GB"
    return 0
}

# 티어 → tmux idle 임계(분). ZC_TMUX_IDLE_MIN 을 명시하면 그게 우선.
tier_idlemin() {
    pressure_tier
    case "$ZC_TIER" in
        RED)    echo "${ZC_IDLE_RED:-30}"     ;;   # 10분이었다 — 2026-09-15 사고: 밥 먹는 44분에 좌석 4개가 죽었다.
                                                   #   훅 경로(settings.json)는 plist 의 ZC_IDLE_RED 를 못 받아 «코드 기본값» 으로 돈다.
                                                   #   그래서 기본값 자체를 사람이 자리를 비우는 시간보다 크게 둔다.
        YELLOW) echo "${ZC_IDLE_YELLOW:-30}"  ;;
        *)      echo "${ZC_IDLE_GREEN:-120}"  ;;
    esac
}

# ── kill 전 복구점 확보 (v3, 2026-09-11) ──────────────────────────────────────
# "어차피 tmm/tmuxc 로 복구된다"가 성립하려면 «복구점이 남아 있어야» 한다.
#   tmuxc save 로 스냅샷을 갱신하면 tmm 이 SNAP 배지(= argv 완제품)로 복원한다.
#   스냅샷이 낡으면 트랜스크립트 model + effort high «추정» 복원으로 떨어진다(플래그·창 유실).
#   실증: 2026-09-11 패닉 직후 스냅샷이 09-06 자(5일 낡음)였다 — 40좌석이 추정 복원 대상이었다.
# save 는 ~7초라 «첫 kill 직전 1회만» 실행(dry-run 은 실행 안 함).
# 대장은 TSV 한 장. ★복귀는 `tmm dead --since 24 >/dev/null; tmm restore <NAME>` — tmm restore 는
#   dead 목록 «캐시»를 먼저 채워야 동작한다(tmm:618 주석). 앞의 tmm dead 를 빼면 «종료 목록에 없음» 으로 거부된다(2026-09-11 실증).
ZC_RECLAIM=""
reclaim_init() {
    [[ -n "$ZC_RECLAIM" ]] && return 0
    ZC_RECLAIM="$LOGDIR/zc-reclaim-$(date +%Y%m%dT%H%M%S).tsv"
    { printf '# zombie-clean 좌석 회수 대장 — restore 열을 그대로 붙여넣으면 복구된다.\n'
      printf '# tmm restore 는 dead-scan 창·계보 필터 탓에 회수분의 일부만 커버한다 — 대장 기반 restore 가 보장 경로.\n'
      printf 'ts\tsession\tlineage\tidle_min\ttier\tcwd\trestore\targv\n'
    } > "$ZC_RECLAIM"
    if command -v tmuxc >/dev/null 2>&1; then
        if tmuxc save >/dev/null 2>&1; then
            echo "  복구점: tmuxc save 완료(스냅샷 갱신) → SNAP 복원 가능"
        else
            echo "  ⚠️ tmuxc save 실패 — 추정 복원으로 떨어짐"
        fi
    else
        echo "  ⚠️ tmuxc 를 PATH 에서 못 찾음 — 스냅샷 갱신 생략, 추정 복원으로 떨어짐"
    fi
    echo "  복원 대장: $ZC_RECLAIM"
}

# $1=세션명 $2=lineage $3=idle분 $4=pane_pid — kill «전» 에 불러야 한다(cwd·argv 가 살아있을 때)
reclaim_record() {
    local cwd="" argv="" cpid=""
    cwd=$(tmux display -t "=$1:" -p '#{pane_current_path}' 2>/dev/null || true)
    # 실좌석 구조: pane_pid = 로그인셸(-zsh), 그 자식이 에이전트(claude/codex …).
    # ① 자식 중 «에이전트» 를 우선 채택(모델·플래그가 여기 있다) ② 없으면 첫 자식 ③ 그래도 없으면 pane 자신.
    if [[ -n "${4:-}" ]]; then
        local k
        for k in $(pgrep -P "$4" 2>/dev/null || true); do
            local ka; ka=$(ps -o args= -p "$k" 2>/dev/null || true)
            if [[ -n "$ka" ]] && printf '%s' "$ka" | grep -qE "$ZC_HOSTRE"; then cpid="$k"; break; fi
            [[ -z "$cpid" ]] && cpid="$k"
        done
        [[ -z "$cpid" ]] && cpid="$4"
        argv=$(ps -o args= -p "$cpid" 2>/dev/null | tr '\t' ' ' | cut -c1-300 || true)
    fi
    # restore 열: 검증된 재개 기록(판정 1344)이 있는 행은 같은 대화를 여는 resume, 없으면 기존 argv 재실행 restore.
    local rcmd="zombie-clean.sh restore $1"
    resume_record_check "$1" >/dev/null && rcmd="zombie-clean.sh resume '$1'"
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$(date '+%F %T')" "$1" "$2" "$3" "${ZC_TIER:-?}" "${cwd:-?}" "$rcmd" "${argv:-?}" >> "$ZC_RECLAIM"
}

# ── 명부 현역 역할 좌석 보호 (r1014, 2026-10-27) ────────────────────────────────
# 뿌리: 이 도구는 seats*.json 을 한 번도 읽지 않았다(`grep -c seats` = 0). 승계 직후에는 한 계보에 세 세대가
#   잠깐 같이 살고, 명부가 «지금 현역» 이라고 적은 좌석이 keep-last-2 밖 순번 3 에 놓인다. 자율 루프 좌석은
#   입력이 오래 없으니 그 좌석이 «idle» 로 지워진다 — 2026-10-27 arch 세 좌석(04:25·08:45)이 그렇게 사라졌다.
# 여기서 명부에 «물어본다»: 리포 루트의 .fable-team/seats*.json 전부에서 «_» 로 시작하는 역할 키
#   (_master·_arch·_da·_hil_route·_sets 안 arch/da 값 …)의 값이 세션명과 같으면 현역(`_closed` 있는 항목은 은퇴 = 현역 아님).
#   범위: 명부 «행»(이름 키의 role)은 보지 않는다 — 이 카드 계약은 «_» 역할 키다(카드 «알려진 한계» 1줄).
# rc: 0 현역 · 1 아님 · 2 판정 불가(명부 파일 없음 · JSON 깨짐 · 읽기 실패 · 7초 초과) — 부르는 쪽이 그 계보 kill 0(하드 룰 20).
ZC_ROSTER_READY=""; ZC_ROSTER_BADFILE=""
roster_root() {   # 명부 리포 루트 1개 — env(ZC_ROSTER_ROOT·FT_RES_ROOT) → cwd 위로 → BYZ 명부 정본 기본값
    local r
    [[ -n "${ZC_ROSTER_ROOT:-}" ]] && { echo "$ZC_ROSTER_ROOT"; return 0; }
    [[ -n "${FT_RES_ROOT:-}" ]] && { echo "$FT_RES_ROOT"; return 0; }
    r="$PWD"
    while [[ -n "$r" && "$r" != "/" ]]; do
        compgen -G "$r/.fable-team/seats*.json" >/dev/null 2>&1 && { echo "$r"; return 0; }
        r="$(dirname -- "$r")"
    done
    # launchd(plist)·훅 경로의 cwd 는 홈·/ 일 수 있다 — 그래도 현역 좌석은 지킨다(명부 정본 1곳)
    r="$HOME/Project/Agent/BYZ-Work/BYZ-Agents"
    compgen -G "$r/.fable-team/seats*.json" >/dev/null 2>&1 && { echo "$r"; return 0; }
    return 1
}
roster_scan() {   # 실행당 1회: $WORK/roster.names(현역 이름) · $WORK/roster.broken(판정 불가 파일)
    [[ -n "$ZC_ROSTER_READY" ]] && return 0
    ZC_ROSTER_READY=1
    : > "$WORK/roster.names"; : > "$WORK/roster.broken"; : > "$WORK/roster.broken.skip"; : > "$WORK/roster.noroot"
    local root; root="$(roster_root)" || {             # R3: 루트 못 찾음 = 판정 불가(하드 룰 20) — launchd 는 env 없이 돈다
        echo "명부 루트 없음" > "$WORK/roster.noroot"
        return 0
    }
    python3 - "$root" "$WORK/roster.names" "$WORK/roster.broken" <<'PY' 2>/dev/null \
        || echo "$root/.fable-team/seats.json" >> "$WORK/roster.broken"
import glob, json, os, signal, sys

def _on_alarm(*_a):
    raise SystemExit(3)

signal.signal(signal.SIGALRM, _on_alarm)
signal.alarm(7)                      # 7초 상한(외부 호출 7초 룰) — 넘으면 판정 불가로 떨어진다
root, nout, bout = sys.argv[1:4]
sout = bout + ".skip"
files = sorted(glob.glob(os.path.join(root, ".fable-team", "seats*.json")))
names, broken, skip = set(), [], set()
if not files:
    broken.append(os.path.join(root, ".fable-team", "seats.json"))
for f in files:
    try:
        with open(f, encoding="utf-8") as fh:
            d = json.load(fh)
        if not isinstance(d, dict):
            raise ValueError("not a mapping")
    except Exception:
        broken.append(f)
        continue

    # r4(오빠 결정 17:3x «명부가 엇갈려도 지킨다»): 은퇴 집합은 «명부마다» 따로 모은다 —
    #   A 명부가 현역이라고 적은 좌석을 B 명부의 은퇴 행이 지우지 못한다(reclaim 과 같은 판정 · 두 경로 한 집합).
    fnames, fskip, fretired = set(), set(), set()

    def walk(v, closing):
        # closing = 닫힌 세트(_closed) 안 — 그 안 이름은 현역이 아니라 «jsonl 판정 건너뛸 이름»(r3 R7)
        if isinstance(v, str):
            x = v.strip()
            if x:
                (fskip if closing else fnames).add(x)
        elif isinstance(v, dict):
            cl = closing or ("_closed" in v)
            for x in v.values():
                walk(x, cl)
        elif isinstance(v, list):
            for x in v:
                walk(x, closing)

    for k, v in d.items():
        if isinstance(k, str) and k.startswith("_"):
            walk(v, False)
        elif isinstance(k, str) and isinstance(v, dict):
            # 행(이름 키) — role=stop-ready 또는 _closed = «일하는 좌석» 판정을 건너뛸 이름(r1014 r2).
            #   정지 레디 좌석은 크론 틱이 jsonl 을 계속 써서 영원히 못 지운다(2026-10-13 세션 122개 꼴).
            role = v.get("role") if isinstance(v.get("role"), str) else ""
            if role == "stop-ready" or "_closed" in v:
                fskip.add(k)
            if "_closed" in v:
                fretired.add(k)           # r3 R4: 역할 칸이 «은퇴 행» 을 가리키면 현역 아님
    # 명부마다: 이 명부의 은퇴 행만 이 명부의 현역에서 뺀다(다른 명부의 은퇴 행은 보호를 지우지 못한다 — r4)
    names |= (fnames - fretired)
    skip |= fskip
with open(nout, "w", encoding="utf-8") as fh:
    for n in sorted(names):
        fh.write(n + "\n")
with open(sout, "w", encoding="utf-8") as fh:
    for n in sorted(skip):
        fh.write(n + "\n")
with open(bout, "w", encoding="utf-8") as fh:
    for f in broken:
        fh.write(f + "\n")
PY
}
roster_file_covers() {   # $1=세션명 $2=명부파일 → rc0 = 이 이름이 그 명부에 등록될 수 있다(기본 명부 · seats-<팀>.json)
    local b="${2##*/}" t
    case "$b" in
        seats.json) return 0 ;;
        seats-*.json)
            t="${b#seats-}"; t="${t%.json}"
            [[ -n "$t" ]] || return 0
            case "$1" in *"$t"*) return 0 ;; esac ;;
    esac
    return 1
}
roster_active() {   # $1=세션명 → rc0 현역 · rc1 아님 · rc2 판정 불가. 판정 불가 사유는 ZC_ROSTER_BADFILE
    local name="$1" f
    ZC_ROSTER_BADFILE=""
    roster_scan
    if [[ -s "$WORK/roster.noroot" ]]; then
        ZC_ROSTER_BADFILE="명부 루트 없음"
        return 2
    fi
    grep -Fxq -- "$name" "$WORK/roster.names" 2>/dev/null && return 0
    [[ -s "$WORK/roster.broken" ]] || return 1
    # 깨진 명부는 «이 이름이 등록될 수 있는 명부» 일 때만 판정 불가로 친다 — 남의 팀 명부가 깨졌다고 남의 계보를 멈추지 않는다(계약 ③)
    while IFS= read -r f; do
        [[ -n "$f" ]] || continue
        roster_file_covers "$name" "$f" || continue
        ZC_ROSTER_BADFILE="${f##*/}" || true
        echo "판정 불가 $f" >> "$WORK/roster.why"
        return 2
    done < "$WORK/roster.broken"
    return 1
}

roster_jsonl_skip() {   # $1=세션명 → rc0 = 그 명부 행이 stop-ready 이거나 _closed (jsonl 판정 건너뛰기)
    roster_scan
    grep -Fxq -- "$1" "$WORK/roster.broken.skip" 2>/dev/null
}
# ── «일하는 좌석» 판정: jsonl 활동 (r1014 r2 · 2026-10-27) ────────────────────────
# 입력(tmux session_activity)은 «사람이 친 시각» 만 센다. 발주 뒤 출력만 내는 좌석은 6시간 idle 로 보인다 —
#   13:39 kill 때 #160 의 jsonl 마지막 레코드는 kill 56초 전, #161 은 kill 그 순간이었다(둘 다 일하는 중).
# jsonl mtime 은 «그 좌석이 대화를 진행 중» 의 직접 증거다(출력 idle 은 10-13 «크론 출력으로 영원히 keep» 재발 — 쓰지 않는다).
# rc 0 = 활동(분 stdout) · 2 = 판정 불가(폴더·jsonl 못 찾음·읽기 실패·7초 초과 · 하드 룰 20).
seat_jsonl_idle() {   # $1=세션명
    local name="$1" cwd slug dir
    command -v tmux >/dev/null 2>&1 || return 2
    cwd=$(tmux display -t "=$name:" -p '#{pane_current_path}' 2>/dev/null || true)
    [[ -n "$cwd" ]] || return 2
    slug="${cwd//\//-}"; slug="${slug//./-}"          # /Users/x/proj → -Users-x-proj (claude projects 폴더 슬러그)
    dir="${ZC_CLAUDE_PROJECTS:-$HOME/.claude/projects}/$slug"
    [[ -d "$dir" ]] || return 2
    local out rc
    out=$(python3 - "$dir" "$name" "${ZC_JSONL_SCAN_MAX:-200}" "${ZC_JSONL_HEAD_BYTES:-262144}" <<'PY' 2>/dev/null
import glob, os, re, signal, sys, time

def _on_alarm(*_a):
    raise SystemExit(3)

signal.signal(signal.SIGALRM, _on_alarm)
signal.alarm(7)
d, name, cap, head = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4])
now = time.time()
pat = re.compile(r'"(?:agentName|customTitle)":"' + re.escape(name) + '"')
files = []
for f in glob.glob(os.path.join(d, "*.jsonl")):
    try:
        files.append((os.stat(f).st_mtime, f))
    except OSError:
        continue
files.sort(reverse=True)                 # 최신 먼저 — 살아 있는 좌석일수록 앞에서 끝난다
for mt, f in files[:cap]:
    try:
        with open(f, "rb") as fh:
            blob = fh.read(head).decode("utf-8", "replace")
    except OSError:
        continue
    if pat.search(blob):
        print(int((now - mt) // 60))
        raise SystemExit(0)
raise SystemExit(4)                       # 못 찾음 = 판정 불가(부르는 쪽이 그 좌석 kill 0)
PY
    ); rc=$?
    [[ "$rc" -eq 0 && -n "$out" ]] || return 2      # 0 만 «활동(분)» — 그 밖(못 찾음·시간 초과·읽기 실패)은 판정 불가
    echo "$out"
    return 0
}

# tmuxc 정책 정리: lineage(베이스명 #N 계열)당 최근 KEEP개 보존, 초과 유령만 kill-session.
# 표준승인(2026-07-11 CLAUDE.md): kill-session은 메모리 relief용 상시 자율 정리 허용,
#   lineage당 최근 KEEP개 보존(기본·하한 2 — 2026-09-15 복귀, R75 판정 807 로 하한 고정), kill-server는 HIL(여기서 안 함).
#   «최근»은 세대 번호(#N) 기준 · attached·active V65 task 도 순번을 차지한다.
# 가드: idle < IDLE_MIN분 = 활성으로 보호(호스트 세션도 이걸로 커버) / pane에 라이브 서버 있으면 보호 /
#   멤버가 keep 이하인 lineage는 손대지 않음.
tmux_prune() {
    command -v tmux >/dev/null 2>&1 || return 0
    pressure_tier   # 부모 셸에서 먼저 측정 — $(tier_idlemin) 서브셸은 캐시만 읽는다
    # keep 기본 2 (2026-09-15 오빠 지시로 1→2 복귀). 2026-09-11 에 1 로 내렸다가 이번 사고를 키웠다.
    #   CLAUDE.md 의 손 정리 하한이 keep-last-2 인 이유와 같다 — 증류 직후 구세션에 물어볼 일이 잦다.
    #   ★plist 의 env 는 훅 경로(settings.json SessionStart/End)에 안 닿는다★ — 그래서 «코드 기본값»을 올린다.
    local keep="${ZC_TMUX_KEEP:-2}" idlemin="${ZC_TMUX_IDLE_MIN:-$(tier_idlemin)}"
    # ★keep-last-2 는 하한이다 — 어떤 티어·설정에서도 2 밑으로 내리지 않는다(R75 · 판정 807). 올릴 때는 소리 없이 하지 않고 출력한다(#0 RULE).
    if ! [[ "$keep" =~ ^[0-9]+$ ]] || (( keep < 2 )); then echo "  keep 하한 2 적용 (요청 ZC_TMUX_KEEP=$keep)"; keep=2; fi
    local now; now=$(date +%s)
    local sess; sess=$(tmux list-sessions -F '#{session_name}|#{session_activity}|#{session_attached}' 2>/dev/null) || return 0
    [[ -z "$sess" ]] && return 0
    local SRVRE='server\.sh|uvicorn|next-server|next dev|caddy|redis-server|postgres|cli-proxy|headroom|hermes|[Oo]llama|node .*(dev|start|watch)'
    local bases; bases=$(printf '%s\n' "$sess" | sed -E 's/#[0-9]+\|/|/' | cut -d'|' -f1 | sort -u)
    local killed=0 total idx gen activity name idle pp srvhit why rcr rostbad=0 rrc jidle jrc
    while IFS= read -r base; do
        [[ -z "$base" ]] && continue
        # 이 lineage 멤버를 세대 번호(#N) 내림차순 정렬(최신 세대가 위) — 같은 번호(번호 없음=0)끼리는 입력 시각 내림차순.
        #   승계 계보의 «최신»은 번호가 큰 쪽이다. 입력 시각으로만 세우면 옛 세대에 질문한 순간 최신 세대가 3번째로 밀려 정리된다(R75 B2).
        local members; members=$(printf '%s\n' "$sess" | awk -F'|' -v b="$base" '{n=$1; sub(/#[0-9]+$/,"",n); g=0; if(match($1,/#[0-9]+$/)) g=substr($1,RSTART+1); if(n==b) print g"|"$2"|"$1"|"$3}' | sort -t'|' -k1,1rn -k2,2rn)
        total=$(printf '%s\n' "$members" | grep -c .)
        # 멤버가 keep 이하인 lineage 는 ★티어 무관 보호★ — 유일한 세대는 죽이지 않는다.
        #   2026-09-11 에는 「RED 면 우회」였다. 좌석=역할이라 대부분의 lineage 가 멤버 1개라서
        #   그 우회는 사실상 «RED 면 전부 죽인다»와 같았고, 2026-09-15 에 그대로 터졌다
        #   (jetsam 103건 → RED → idle 10분 → arch-fable#42·da-claude#2·tester-check#3·tmm 4개 몰살).
        #   ★메모리를 되찾겠다고 살아있는 유일한 세대를 죽이면 복구 비용이 절약분보다 크다.★
        #   R75(판정 807): 그래서 RED 에서도 유일 세대·최신 keep 세대는 지킨다. RED 의 회수력은 «keep 밖 세대 + RED idle 임계» 경로로만 남는다.
        #   판정 1344: 멤버 1개 계보만 무조건 건너뛴다. 2개 이상은 멤버 판정으로 들어가 — 순번 2(직전 세대)는 «검증된 재개 기록»이 있을 때만 풀린다(아래).
        [[ "$total" -le 1 ]] && continue
        idx=0; rostbad=0
        while IFS='|' read -r gen activity name att; do
            [[ -z "$name" ]] && continue
            idx=$((idx+1))   # 순번은 가드 앞에서 센다 — attached·preserve 도 «최신 순번»을 차지한다 (R75 · 판정 807)
            # Explicit active-task protection is independent of terminal input idle time.
            idle=$(( (now - activity) / 60 ))   # ★r2: 닫는 사건(MAJOR) 계산을 preserve 검사 앞으로 이동
            # ★session_activity 는 «입력»만 센다 — 발주 뒤 출력만 내는 작업 좌석(codex DA)이 일하는 중에도 6시간 idle 로 잡혀
            #   ABANDON 으로 회수됐다(2026-10-01 da-codex#11 · win_idle 1분 vs sess_idle 380분). 출력(window_activity)도 활동으로 본다.
            wact=$(tmux list-windows -t "=$name" -F '#{window_activity}' 2>/dev/null | sort -n | tail -1)
            [[ -n "$wact" && "$wact" -gt "$activity" ]] && idle=$(( (now - wact) / 60 ))
            if [[ "$(tmux show-options -qv -t "=$name:" @zc_v65_active 2>/dev/null)" == "1" ]] \
                && [[ "$idle" -lt "${ZC_TMUX_ABANDON_MIN:-360}" ]]; then
                echo "  tmux preserve $name (active V65 task, idle=${idle}분)"
                continue
            fi
            # ★attached = 사람이 보고 있는 화면. 어떤 티어에서도 죽이지 않는다.
            #   현행은 idle 임계에만 의존했는데, RED 로 임계가 10분이 되면 «보고 있지만 조용한»
            #   좌석까지 대상이 된다(2026-09-11 설계 구멍). 티어 무관 최우선 보호선.
            [[ "${att:-0}" -gt 0 ]] && continue
            # ★명부 현역 역할 좌석 = attached 와 같은 급 보호 (r1014). 순번·idle 무관.
            #   판정 불가(rc2)면 «그 계보» kill 0 + 1줄 — 깨진 명부를 «현역 아님» 으로 읽지 않는다(하드 룰 20).
            roster_active "$name"; rrc=$?
            if [[ "$rrc" -eq 0 ]]; then echo "  tmux keep $name (명부 현역 역할)"; continue; fi
            if [[ "$rrc" -eq 2 ]]; then
                [[ "$rostbad" -eq 1 ]] || echo "  tmux keep $base 계보 전체 (명부 판정 불가: ${ZC_ROSTER_BADFILE:-?} — kill 0)"
                rostbad=1; break
            fi
            # ★최신 keep 세대는 어떤 티어에서도 보존한다(R75 B1). 옛 «RED 에서 6시간 방치면 keep 안도 회수»는 하한 2 를 깼다.
            #   자리를 비운 좌석(밥·회의)과 버려진 좌석을 가르는 선은 keep 밖 세대의 idle 임계가 맡는다.
            #   단 순번 2(직전 세대, 판정 1344)는 «검증된 재개 기록»(ft-seat-retire.sh 가 은퇴 때 씀)이 있으면 보존하지 않고 아래 가드(idle 임계·라이브 서버)로 계속한다.
            #   기록이 없거나 어긋나면 지금처럼 보존하고 그 사실을 출력한다(#0 RULE). 순번 1·3~keep 보존과 위 attached·active V65 가드는 불변.
            if [[ "$idx" -le "$keep" ]]; then
                [[ "$idx" -ne 2 ]] && continue
                why=$(resume_record_check "$name"); rcr=$?
                if [[ $rcr -eq 2 ]]; then echo "  tmux keep $name (재개 기록 없음 — 직전 세대 보존)"; continue
                elif [[ $rcr -ne 0 ]]; then echo "  tmux keep $name (재개 기록 불일치: ${why:-검사 실패})"; continue; fi
                resume_record_pid_live "$name" || { echo "  tmux keep $name (재개 기록 불일치: pid)"; continue; }
            fi
            # ★keep 밖 세대는 «입력» 유휴만 본다 — 승계로 밀려난 옛 좌석의 10분 체크 크론이 화면에 계속 출력해 출력 유휴가 0~28분에 묶이면 영원히 못 지운다(2026-10-13 세션 122개·claude 16 GB).
            #   출력 포함 idle 은 위 preserve(active V65 task · ABANDON) 판정에만 쓴다 — 10-01 codex DA 오살 방지 그대로.
            idle=$(( (now - activity) / 60 ))
            [[ "$idle" -lt "$idlemin" ]] && continue       # 활성(호스트 포함) 보호
            # ★«일하는 좌석» 판정(r1014 r2): 입력 idle 이 커도 그 좌석 jsonl 이 최근에 쓰였으면 keep.
            #   정지 레디(stop-ready)·은퇴(_closed) 좌석은 건너뛴다 — 크론 틱이 jsonl 을 계속 써서 영원히 못 지우는 2026-10-13 꼴.
            #   jsonl 못 찾음 = 판정 불가 1줄 · 그 좌석 kill 0(하드 룰 20 · 슬러그가 cwd 와 다른 좌석 포함).
            if ! roster_jsonl_skip "$name"; then
                jidle=$(seat_jsonl_idle "$name"); jrc=$?
                if [[ "$jrc" -eq 0 && -n "$jidle" ]]; then
                    [[ "$jidle" -lt "$idlemin" ]] && { echo "  tmux keep $name (jsonl 활동 ${jidle}분 전)"; continue; }
                elif [[ "$jrc" -eq 2 ]]; then
                    echo "  tmux keep $name (판정 불가: jsonl 못 찾음 — $name)"; continue
                fi
            fi
            pp=$(tmux list-panes -t "$name" -F '#{pane_pid}' 2>/dev/null | head -1)
            srvhit=""
            [[ -n "$pp" ]] && srvhit=$(pgrep -P "$pp" 2>/dev/null | while read -r k; do ps -o command= -p "$k" 2>/dev/null; done | grep -aoE "$SRVRE" | head -1)
            [[ -n "$srvhit" ]] && continue                 # 라이브 서버 보호
            if $DRY; then
                echo "  [dry] tmux kill $name (lineage=$base idle=${idle}분)"; killed=$((killed+1)); continue
            fi
            reclaim_init                                  # 첫 kill 직전 1회: tmuxc save + 대장 생성
            reclaim_record "$name" "$base" "$idle" "$pp"   # kill 전에 cwd·argv 확보
            tmux kill-session -t "$name" 2>/dev/null && { echo "  tmux kill $name (lineage=$base idle=${idle}분)"; killed=$((killed+1)); }
        done <<< "$members"
    done <<< "$bases"
    echo "tmux 정책 정리: ${killed}개 (압력=${ZC_TIER:-?}, keep-last-${keep}, idle≥${idlemin}분, 라이브서버·attached·유일세대·최신 keep 세대 보호 · 순번 2(직전 세대)는 검증된 재개 기록이 있을 때만 해제 / active V65 task 보호 해제 ${ZC_TMUX_ABANDON_MIN:-360}분)"
    [[ -n "$ZC_RECLAIM" ]] && echo "  복원: zombie-clean.sh restore '<NAME>' (전량=restore-from) · 대장 $ZC_RECLAIM"
    [[ "$killed" -gt 0 && "$DRY" == false ]] && echo "$(date '+%F %T') tmux-prune killed=$killed keep=$keep idlemin=$idlemin tier=${ZC_TIER:-?} reclaim=${ZC_RECLAIM:-none}" >> "$LOG"
    return 0
}

# 디스크 임계 점검(R128) — 후보 목록만, 삭제 0. 크기 조회가 느려(uv 캐시 du 110초) ZC_DISK_REPORT_MIN(기본 60분)에 1회만 돈다.
#   목록은 로그에 남기고, ZC_DISK_NOTIFY_CMD 가 있으면 그 명령의 stdin 으로 넘긴다(슬랙/쪽지 연결은 설치 쪽 env).
disk_report() {
    local st="${ZC_DISK_STAMP:-/tmp/zombie-clean-disk-$(id -u).last}" out rc
    if [[ -f "$st" ]] && (( $(date +%s) - $(stat -f %m "$st" 2>/dev/null || echo 0) < ${ZC_DISK_REPORT_MIN:-60} * 60 )); then return 0; fi
    touch "$st"
    out=$(bash "$(dirname "${BASH_SOURCE[0]}")/zombie-clean-disk.sh" 2>&1); rc=$?
    [[ -z "$out" ]] && return 0
    echo "$out"
    if [[ -n "${ZC_DISK_NOTIFY_CMD:-}" ]] && printf '%s\n' "$out" | bash -c "$ZC_DISK_NOTIFY_CMD"; then return 0; fi
    echo "  ⚠️ 디스크 알림 못 보냄(ZC_DISK_NOTIFY_CMD 미설정/실패, rc=$rc) — 로그에만 기록"
}

auto_mode() {
    # 5분 스로틀 (ZC_FORCE=1이면 무시 — 테스트용)
    if [[ "${ZC_FORCE:-0}" != "1" && -f "$STAMP" ]]; then
        local age=$(( $(date +%s) - $(stat -f %m "$STAMP" 2>/dev/null || echo 0) ))
        [[ "$age" -lt "${ZC_THROTTLE:-240}" ]] && exit 0
    fi
    # 동시 실행 락 (180초 넘은 낡은 락은 스틸)
    if ! mkdir "$LOCK" 2>/dev/null; then
        local lage=$(( $(date +%s) - $(stat -f %m "$LOCK" 2>/dev/null || echo 0) ))
        [[ "$lage" -lt 180 ]] && exit 0
        rm -rf "$LOCK"; mkdir "$LOCK" 2>/dev/null || exit 0
    fi
    trap 'rm -rf "$LOCK" "$WORK"' EXIT
    touch "$STAMP"
    sleep 3   # SessionEnd 직후 호스트 종료를 기다렸다가 고아를 정확히 판정
    DRY=false
    {
        pressure_tier
        echo "$(date '+%F %T') auto sweep 시작 [압력=$ZC_TIER $ZC_TIER_WHY]"
        do_clean
        [[ "${ZC_TMUX:-1}" == "1" ]] && tmux_prune   # tmuxc 정책 정리 동반 (ZC_TMUX=0으로 끔)
        [[ "${ZC_DISK:-1}" == "1" ]] && disk_report  # 디스크 임계 점검 동반 (ZC_DISK=0으로 끔 · 후보 목록만)
    } >> "$LOG" 2>&1 || true
    rotate_log   # 블록 종료 후 로테이션 (블록 안에서 하면 fd 끊김)
}

case "$CMD" in
    scan)
        analyze
        cat "$TB"
        mcp_census
        pressure_tier; echo "메모리 압력: $ZC_TIER ($ZC_TIER_WHY) → tmux idle 임계 $(tier_idlemin)분"
        if [[ -s "$ZF" ]]; then
            echo "-- 좀비 상위 10개 --"
            sort -t'|' -k3 -rn "$ZF" | head -10 | awk -F'|' '{printf "  %s [%s] %.0fMB %s\n", $1, $2, $3/1024, $4}'
        fi
        ;;
    clean)  do_clean ;;
    auto)   auto_mode ;;
    tmux-prune) tmux_prune ;;
    disk)         shift; exec bash "$(dirname "${BASH_SOURCE[0]}")/zombie-clean-disk.sh" "$@" ;;
    restore)      shift; cmd_restore "$@" ;;
    restore-from) shift; cmd_restore_from "$@" ;;
    resume)       shift; cmd_resume "$@" ;;
    status)
        analyze
        cat "$TB"
        mcp_census
        pressure_tier; echo "메모리 압력: $ZC_TIER ($ZC_TIER_WHY) → tmux idle 임계 $(tier_idlemin)분"
        top -l 1 | grep PhysMem
        ;;
    *) echo "사용법: zombie-clean.sh [scan|clean|tmux-prune|auto|status|disk [--apply-approved]|restore '<세션명>'|restore-from [대장.tsv]|resume '<세션명>'] [--dry-run]"; exit 1 ;;
esac
