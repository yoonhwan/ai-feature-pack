#!/usr/bin/env bash
# h-mini-byz-server.sh — BYZ 서버(redis·gateway·worker·web)를 mini(ssh 별칭 `mini`)에서 띄우고 필요량(RSS)을 잰다.
#   초안 v2(2026-10-22 · pi 초안 → aifp-multihost-master-claude#1 검수·재작성) · 실행은 오빠가 `! bash /tmp/h<N>` 로만.
#   근거: docs/multihost/measured-byz-server-env-20261022.md (최소 키 «이름» 목록) · PLAN-mini-e2e-round1 §2·§3·§4
# 호출: SHA=<커밋 sha> KEY_SRC=dotenv|op [ACTION=up|stop] bash /tmp/h<N>      (SHA·KEY_SRC 기본값 없음)
# 원칙: 원본 BYZ repo 는 읽기만(git archive) · 키는 «디스크·명령줄에 안 남기고» ssh stdin 으로만 · 값 출력 0
#       외부 호출 단건 70초 천장(긴 설치·빌드는 mini 백그라운드 작업 + 짧은 폴링) · stale-port 정리 스크립트·Makefile 타깃 사용 0
#       포트는 38301~38399 만 · mini 원격은 전부 PATH 접두(비대화형 ssh PATH 함정 — 실측)
# 검수에서 pi 초안 대비 고친 것: ①키 값이 `env K=V …` 명령줄에 박혀 ps 에 보이던 것 → stdin 으로 eval(명령줄 0)
#   ②`cd … && cmd & echo $! > .h-pids` 가 cd 를 백그라운드 서브셸에 가둬 pid 파일이 $HOME 에 써지던 결함 → 단일 원격 스크립트
#   ③worker 에 키가 안 가던 것 ④`uv run`/`npx` 래퍼 pid 를 기록하던 것 → venv python·next 바이너리 직접 ⑤web 빌드(수 분)가 70초 천장에서
#   매번 죽던 것 → 백그라운드 설치 작업 + 재실행 이어가기 ⑥얕은 clone 의 임의 sha 체크아웃 → `git archive <sha>`(.env 는 애초에 미추적)
#   ⑦rsync 완료 판정이 du 비교(mini 쪽 venv·node_modules 로 항상 통과)였던 것 → rsync 종료코드로
# rc: 0 성공 · 2 사전점검/인자 · 3 반입·설치 실패/진행 중(같은 인자로 재실행하면 이어감) · 4 기동 실패 · 5 사후 점검 실패
set -uo pipefail

MINI="${MINI:-mini}"                          # ★고정 규칙: ssh 별칭만★
SRC="${SRC:-/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents}"
SHA="${SHA:-}"
ACTION="${ACTION:-up}"                        # up | stop | fwd(포워딩만 재개설)
KEY_SRC="${KEY_SRC:-}"                        # dotenv | op
MAX_GB="${MAX_GB:-2}"
P_REDIS="${P_REDIS:-38311}"; P_GATEWAY="${P_GATEWAY:-38312}"; P_WEB="${P_WEB:-38314}"
PORTS=("$P_REDIS" "$P_GATEWAY" "$P_WEB")
WORK="${TMPDIR:-/tmp}/h-byz-$$"               # 이 맥 임시 작업 폴더(끝에 지움)
TUN_PORT="${LOOM_PG_TUNNEL_PORT:-38309}"       # 이 맥 loom 터널(launchd 상주 · 127.0.0.1) 포트 — 정본 server.sh 와 같은 값
FWD_EXTRA="${FWD_EXTRA-8000 8001}"           # 이 맥 상주 터널 중 mini 에 더 빌려줄 포트: 8000=LLM vLLM(LOCAL_VLLM_BASE_URL) · 8001=GPU STT/TTS(GPU_STT_TTS_URL) — 이 맥 로컬 기동과 같은 세트
FWD_PORTS=("$TUN_PORT" $FWD_EXTRA)               # 38309(DB) + 8000 + 8001
# mini 쪽 포트 → 이 맥 쪽 포트. 8000(LLM)은 이 맥에서 launchd 상주 터널 18703 이 소유한다(수동 8000 터널은 재부팅으로 사라짐 · 상위 #3202). 나머지는 같은 번호.
LLM_LOCAL_PORT="${LLM_LOCAL_PORT:-18703}"
lport() { case "$1" in 8000) printf '%s' "$LLM_LOCAL_PORT";; *) printf '%s' "$1";; esac; }
TUN_PIDF="$HOME/.h-byz-tunnel.pid"            # 이 맥에서 이 h 가 연 «역방향 포워딩 ssh» pid(이 pid 만 정리)
PYBIN="${PYBIN:-$SRC/.venv/bin/python}"        # psycopg 있는 python(DSN 해석 스크립트용 — 이 맥 BYZ .venv)
SO=(-o BatchMode=yes -o ConnectTimeout=6 -o ServerAliveInterval=10 -o ServerAliveCountMax=3)
# 값은 «이름» 으로만 안다 — measured-byz-server-env-20261022.md §최소 세트 + 조건부(번역·TTS)
KEYS=(BYZ_LLM_SOURCING LOCAL_VLLM_BASE_URL LOCAL_VLLM_API_KEY GPU_STT_MODEL STT_PROVIDER GEMINI_API_KEY GOOGLE_API_KEY GOOGLE_PROJECT_ID
      CORPUS_RETENTION_DAYS SUPABASE_DB_URL LOOM_INTERIM_DB_URL LOOM_INTERIM_PG_DSN LOOM_INGEST_PG_DSN GCS_DATA_BUCKET GCS_DATA_PREFIX
      PAYMENT_MODE APP_ENV V6_AUTHORITATIVE_STT_MODE V6_AUTHORITATIVE_STT_PROVIDER BYZ_E2E_JWT_SECRET
      V5_BACKEND_ENABLED   # 2026-10-24 러너 1회차: 없으면 gateway 가 /v5 라우터를 안 붙여 POST /v5/audio_event·/v5/sessions/init 404 → 오디오 조각 전송 실패(chunk_post_failed) → host_empty (shared/config/v5_config.py: 이 이름이 true 계열이어야 backend_enabled)
      FIREWORKS_API_KEY GROQ_API_KEY DEEPGRAM_API_KEY ELEVENLABS_API_KEY SONIOX_API_KEY
      RETURNZERO_ID RETURNZERO_SECRET CLOVA_API_SECRET GOOGLE_API_KEY
      LLM_PROVIDER BRAIN_LLM_PROVIDER TTS_PROVIDER CARTESIA_API_KEY TYPECAST_API_KEY SUPERTONE_API_KEY OPENAI_API_KEY)
say() { printf '[h-byz] %s\n' "$*"; }
die() { printf '[h-byz] REJECT rc=%s %s\n' "$1" "$2" >&2; exit "$1"; }
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT
# ★mini 원격은 항상 PATH 접두★ — 명령줄에는 비밀이 없다(비밀은 stdin 으로만 간다)
ms() { local t="$1"; shift; timeout "$t" ssh "${SO[@]}" "$MINI" "export PATH=/opt/homebrew/bin:\$HOME/.local/bin:\$PATH; $*"; }

# ── ACTION=stop — 이 h 가 기록한 pid 만 ────────────────────────────────────
if [ "$ACTION" = "stop" ]; then
  say "STOP — ~/Project/BYZ-Agents/.h-pids 의 pid 만 종료"
  ms 40 'f=$HOME/Project/BYZ-Agents/.h-pids; [ -f "$f" ] || { echo pids=none; exit 0; }; n=0; while read -r pid; do [ -n "$pid" ] || continue; if kill -0 "$pid" 2>/dev/null; then kill "$pid" 2>/dev/null && n=$((n+1)); fi; done < "$f"; : > "$f"; echo stopped=$n' 2>&1 | sed 's/^/        /'
  # 이 h 의 포트(${PORTS[*]})를 듣는 프로세스 중 작업 폴더가 ~/Project/BYZ-Agents 아래인 것만(next start 자식 next-server 처럼 pid 파일 밖에 남는 것)
  ms 20 "sleep 1; n=0; for p in ${PORTS[*]}; do for pid in \$(lsof -ti tcp:\$p -sTCP:LISTEN 2>/dev/null); do cwd=\$(lsof -a -p \$pid -d cwd -Fn 2>/dev/null | sed -n 's/^n//p'); case \"\$cwd\" in \"\$HOME/Project/BYZ-Agents\"*) kill \$pid 2>/dev/null && n=\$((n+1));; esac; done; done; echo stopped_port_listeners=\$n" 2>&1 | sed 's/^/        /'
  if [ -f "$TUN_PIDF" ]; then
    tp="$(cat "$TUN_PIDF" 2>/dev/null)"
    if [ -n "$tp" ] && kill -0 "$tp" 2>/dev/null && ps -o args= -p "$tp" 2>/dev/null | grep -q -- "-R 127.0.0.1:"; then kill "$tp" 2>/dev/null; say "        이 맥 역방향 포워딩 ssh 종료(pid $tp)"; fi
    rm -f "$TUN_PIDF"
  fi
  say "남의 프로세스·Chrome·기본 포트 Redis·이 맥 loom 터널 본체는 건드리지 않았다(위 pid 만)"
  exit 0
fi

# ── ACTION=fwd — 역방향 포워딩만 다시 (서버는 건드리지 않는다) ───────────────────
#   포워딩 ssh 가 죽으면(2026-10-22 19:2x 실측: 이 맥 ssh 0 · mini 38309·8000·8001 LISTEN 0 인데 서버는 health 200) 서버가 DB·LLM·STT 를 잃는다.
if [ "$ACTION" = "fwd" ]; then
  say "FWD — 역방향 포워딩만 재개설(서버 프로세스 불변)"
  tp="$(cat "$TUN_PIDF" 2>/dev/null)"
  if [ -n "$tp" ] && kill -0 "$tp" 2>/dev/null && ps -o args= -p "$tp" 2>/dev/null | grep -q -- "-R 127.0.0.1:"; then
    OKN=0; for fp in "${FWD_PORTS[@]}"; do n="$(ms 15 "lsof -nP -iTCP:$fp -sTCP:LISTEN 2>/dev/null | wc -l | tr -d ' '")" || n=0; [ "${n:-0}" -ge 1 ] 2>/dev/null && OKN=$((OKN+1)); done
    [ "$OKN" = "${#FWD_PORTS[@]}" ] && { say "        이미 살아 있음(ssh pid $tp · mini 포트 ${FWD_PORTS[*]} 전부 LISTEN) — 할 일 없음"; exit 0; }
    kill "$tp" 2>/dev/null; say "        ssh 는 살아 있으나 포트 일부 없음($OKN/${#FWD_PORTS[@]}) — 그 ssh 만 종료 후 재개설"; sleep 1
  fi
  for fp in "${FWD_PORTS[@]}"; do
    lsof -nP -iTCP:"$(lport "$fp")" -sTCP:LISTEN -t >/dev/null 2>&1 || die 2 "이 맥 127.0.0.1:$(lport "$fp") 상주 터널이 없다(mini 포트 $fp 용)"
    TB="$(ms 15 "lsof -nP -iTCP:$fp -sTCP:LISTEN 2>/dev/null | wc -l | tr -d ' '")" || TB=0
    [ "${TB:-0}" = 0 ] || die 2 "mini 에서 포트 $fp 가 이미 사용 중이다 — 남은 포워딩이면 mini 의 그 sshd 자식이 정리될 때까지(수십 초) 기다렸다 다시"
  done
  RARGS=(); for fp in "${FWD_PORTS[@]}"; do RARGS+=(-R "127.0.0.1:$fp:127.0.0.1:$(lport "$fp")"); done
  FL="$(mktemp "${TMPDIR:-/tmp}/h-byz-fwd.XXXXXX")"
  nohup ssh "${SO[@]}" -o ExitOnForwardFailure=yes -N "${RARGS[@]}" "$MINI" </dev/null >"$FL" 2>&1 &
  echo $! > "$TUN_PIDF"; disown 2>/dev/null || true; sleep 3
  kill -0 "$(cat "$TUN_PIDF")" 2>/dev/null || { tail -2 "$FL" | sed 's/^/        /'; rm -f "$TUN_PIDF" "$FL"; die 4 "역방향 포워딩이 서지 않았다"; }
  for fp in "${FWD_PORTS[@]}"; do
    n="$(ms 15 "lsof -nP -iTCP:$fp -sTCP:LISTEN 2>/dev/null | wc -l | tr -d ' '")" || n=0
    [ "${n:-0}" -ge 1 ] 2>/dev/null || { kill "$(cat "$TUN_PIDF")" 2>/dev/null; rm -f "$TUN_PIDF" "$FL"; die 4 "mini 에서 127.0.0.1:$fp 가 LISTEN 이 아니다"; }
  done
  rm -f "$FL"
  say "        포워딩 OK(${FWD_PORTS[*]}) · ssh pid $(cat "$TUN_PIDF") — 정지는 ACTION=stop (서버 포함 정지)"
  exit 0
fi

# ── 0) 인자·로컬 사전점검 ─────────────────────────────────────────────────
say "0/7 사전점검"
[ -n "$SHA" ] || die 2 "SHA=<커밋 sha> 가 필요하다(기본값 없음 — 어떤 코드를 시험하는지 확정해야 한다)"
case "$SHA" in *[!0-9a-fA-F]*) die 2 "SHA 형식 오류: '$SHA'";; esac
[ "${#SHA}" -ge 7 ] || die 2 "SHA 가 너무 짧다: '$SHA'"
case "$KEY_SRC" in dotenv|op) ;; *) die 2 "KEY_SRC=dotenv|op 가 필요하다(기본값 없음)";; esac
[ -d "$SRC/.git" ] || die 2 "BYZ 저장소가 아니다: $SRC"
FULL="$(git -C "$SRC" rev-parse --verify -q "$SHA^{commit}")" || die 2 "원본 저장소에 그 sha 가 없다: $SHA"
for p in "${PORTS[@]}"; do [[ "$p" =~ ^383[0-9][0-9]$ ]] || die 2 "포트 $p 가 38301~38399 밖이다"; done
say "        sha=${FULL:0:12} · KEY_SRC=$KEY_SRC · redis=$P_REDIS gateway=$P_GATEWAY web=$P_WEB"

# ── 1) mini 사전점검 ─────────────────────────────────────────────────────
say "1/7 mini 사전점검 (ssh $MINI)"
PRE="$(ms 25 'echo user=$(id -un); echo disk=$(df -h ~ | awk "NR==2{print \$4}"); memory_pressure 2>/dev/null | tail -1; for c in redis-server uv node npm; do printf "%s=%s\n" $c "$(command -v $c || echo absent)"; done')" || die 2 "mini 접속 실패"
printf '%s\n' "$PRE" | sed 's/^/        /'
printf '%s\n' "$PRE" | grep -q '^user=byz' || die 2 "원격 사용자가 byz 가 아니다"
for c in redis-server uv node npm; do printf '%s\n' "$PRE" | grep -q "^$c=/" || die 2 "$c 없음(이 h 는 설치하지 않는다)"; done
LIVE="$(ms 15 'f=$HOME/Project/BYZ-Agents/.h-pids; n=0; [ -f "$f" ] && while read -r pid; do [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null && n=$((n+1)); done < "$f"; echo $n')" || LIVE=0
[ "${LIVE:-0}" = "0" ] || die 2 "이 h 가 띄운 프로세스가 아직 $LIVE 개 살아 있다 — 먼저 ACTION=stop"
for p in "${PORTS[@]}"; do
  BUSY="$(ms 15 "lsof -nP -iTCP:$p -sTCP:LISTEN 2>/dev/null | wc -l | tr -d ' '")" || BUSY=0
  [ "$BUSY" = "0" ] || die 2 "포트 $p 이 mini 에서 이미 사용 중이다 — P_REDIS/P_GATEWAY/P_WEB 로 다른 383xx 를 주라"
done
say "        포트 3개 비어 있음"
# loom 터널(사설 dev DB 로 가는 길)은 이 맥 launchd 가 상주 소유한다 — 이 h 는 그 로컬 포트를 mini 로 «빌려줄» 뿐 만들지 않는다(판정 909)
for fp in "${FWD_PORTS[@]}"; do
  lp="$(lport "$fp")"
  lsof -nP -iTCP:"$lp" -sTCP:LISTEN -t >/dev/null 2>&1 || die 2 "이 맥 127.0.0.1:$lp 에 상주 터널이 없다 — 이 h 는 터널을 열지 않는다(mini 포트 $fp ← 이 맥 $lp: 38309=DB · 8000←18703=LLM vLLM · 8001=GPU STT/TTS)"
done
[ -x "$PYBIN" ] || die 2 "psycopg 있는 python 이 없다: $PYBIN (PYBIN= 로 지정)"
command -v gcloud >/dev/null 2>&1 || die 2 "이 맥에 gcloud 가 없다 — dev DSN 을 Secret Manager 에서 못 꺼낸다"
for fp in "${FWD_PORTS[@]}"; do
  TBUSY="$(ms 15 "lsof -nP -iTCP:$fp -sTCP:LISTEN 2>/dev/null | wc -l | tr -d ' '")" || TBUSY=0
  [ "$TBUSY" = "0" ] || die 2 "mini 에서 포트 $fp 이 이미 사용 중이다(이전 포워딩이 남았나 — ACTION=stop 먼저)"
done
say "        이 맥 상주 터널(mini 포트 ${FWD_PORTS[*]} ← 이 맥 $(for q in "${FWD_PORTS[@]}"; do printf "%s " "$(lport "$q")"; done)) LISTEN 확인 · mini 에서 모두 비어 있음"

# ── 2) 코드 반입 — git archive(.env 는 미추적이라 애초에 안 들어옴) ───────
say "2/7 코드 반입"
mkdir -p "$WORK/repo"
# design/ 은 증거 산출물 1.1GB 라 서버·러너에 불필요 → 제외
git -C "$SRC" archive "$FULL" -- . ':(exclude)design' | tar -x -C "$WORK/repo" || die 3 "git archive 실패"
printf '%s\n' "$FULL" > "$WORK/repo/GIT_SHA"
if find "$WORK/repo" -maxdepth 3 -name '.env*' -type f ! -name '*.example' | grep -q .; then die 3 "아카이브에 실제 .env 파일이 있다(.example 제외) — 비밀 반입 금지, 중단"; fi
SZ_MB=$(( $(du -sk "$WORK/repo" | awk '{print $1}') / 1024 ))
say "        아카이브 ${SZ_MB}MB"
[ "$SZ_MB" -le $(( MAX_GB * 1024 )) ] || die 2 "아카이브 ${SZ_MB}MB 가 상한 ${MAX_GB}GB 초과"
ms 20 'mkdir -p $HOME/Project/BYZ-Agents' >/dev/null || die 3 "원격 디렉터리 생성 실패"
SENT=0
for try in 1 2 3; do
  if timeout 70 rsync -a --partial --timeout=60 -e "ssh ${SO[*]}" "$WORK/repo/" "$MINI:Project/BYZ-Agents/" 2>"$WORK/rsync.err"; then SENT=1; break; fi
  tail -2 "$WORK/rsync.err" | sed 's/^/        /'; say "        rsync 70초 초과/실패 — 이어받기 $try/3"
done
[ "$SENT" = 1 ] || die 3 "전송 미완 — 같은 인자로 재실행하면 이어받는다"
say "        전송 완료(rsync rc=0)"

# ── 3) 설치·빌드 — mini 백그라운드 작업 + 짧은 폴링 ───────────────────────
say "3/7 설치·빌드(uv sync → npm ci → next build) — 파이썬은 3.13 고정(BYZ 에 .python-version 이 없고 mini 최신은 3.15.0 사전판 → 고정 안 하면 uv 가 3.15 를 고름 · 이 맥 .venv 는 3.13.12)"
BUILD_ENV="NEXT_PUBLIC_API_URL=http://127.0.0.1:$P_GATEWAY/api/v1 NEXT_PUBLIC_SSE_URL=http://127.0.0.1:$P_GATEWAY/sse/v1 NEXT_PUBLIC_WS_URL=ws://127.0.0.1:$P_GATEWAY/ws/v1 NEXT_PUBLIC_BASE_URL=http://127.0.0.1:$P_WEB"
MARK="$FULL|$P_GATEWAY|$P_WEB|extras=gateway,worker"   # 설치 방식이 바뀌면 표식도 바뀌어 재설치된다(h381 1회차: extra 없이 깔려 python-multipart·onnxruntime 누락)
STATE="$(ms 15 "cd \$HOME/Project/BYZ-Agents; if [ \"\$(cat .h-installed 2>/dev/null)\" = '$MARK' ]; then echo done; elif [ -f .h-install.pid ] && kill -0 \$(cat .h-install.pid) 2>/dev/null; then echo running; elif [ -f .h-install.rc ]; then echo rc=\$(cat .h-install.rc); else echo none; fi")" || STATE=none
case "$STATE" in
  done) say "        이미 설치·빌드됨(같은 sha·포트)";;
  running) say "        설치 작업이 아직 진행 중(.h-install.log)"; ms 10 'tail -2 $HOME/Project/BYZ-Agents/.h-install.log' | sed 's/^/        /'; die 3 "진행 중 — 몇 분 뒤 같은 인자로 재실행";;
  *)
    case "$STATE" in rc=0) ;; rc=*) say "        직전 설치 작업이 실패($STATE) — 로그 끝 3줄:"; ms 10 'tail -3 $HOME/Project/BYZ-Agents/.h-install.log' | sed 's/^/        /';; esac
    ms 20 "cd \$HOME/Project/BYZ-Agents; rm -f .h-install.rc .h-installed; nohup bash -c 'set -e; uv sync --frozen --python /opt/homebrew/bin/python3.13 --extra gateway --extra worker; cd clients/web; npm ci --no-audit --no-fund; $BUILD_ENV npm run build; cd ../..; echo \"$MARK\" > .h-installed' > .h-install.log 2>&1 < /dev/null & echo \$! > .h-install.pid; echo started" >/dev/null || die 3 "설치 작업 시작 실패"
    for i in 1 2 3 4 5 6 7 8 9 10; do
      sleep 5
      S="$(ms 10 'cd $HOME/Project/BYZ-Agents; if [ -f .h-installed ]; then echo done; elif kill -0 $(cat .h-install.pid) 2>/dev/null; then echo running; else echo failed; fi' 2>/dev/null)" || S=running
      [ "$S" = "running" ] || break
    done
    case "$S" in
      done) say "        설치·빌드 완료";;
      failed) ms 10 'tail -5 $HOME/Project/BYZ-Agents/.h-install.log' | sed 's/^/        /'; die 3 "설치/빌드 실패(.h-install.log)";;
      *) die 3 "설치·빌드가 50초 안에 안 끝났다 — mini 에서 계속 진행 중. 몇 분 뒤 같은 인자로 재실행(이어서 확인)";;
    esac;;
esac

# ── 4) 기동 — 키는 stdin 으로만(명령줄·디스크 0) ──────────────────────────
say "4/7 기동 (redis → web → gateway → worker)"
ENVF="$WORK/env.sh"; : > "$ENVF"; chmod 600 "$ENVF"; N=0
if [ "$KEY_SRC" = dotenv ]; then
  [ -f "$SRC/.env" ] || die 2 "KEY_SRC=dotenv 인데 $SRC/.env 가 없다"
  for k in "${KEYS[@]}"; do
    v="$(grep -m1 -E "^${k}=" "$SRC/.env" 2>/dev/null | sed "s/^${k}=//; s/^[\"']//; s/[\"']\$//" | tr -d '\r')"
    [ -n "$v" ] && { printf 'export %s=%q\n' "$k" "$v" >> "$ENVF"; N=$((N+1)); }
  done
else
  [ -n "${OP_SERVICE_ACCOUNT_TOKEN_DEVELOP:-}" ] || die 2 "OP_SERVICE_ACCOUNT_TOKEN_DEVELOP 미설정(kskill 기본 토큰 금지)"
  for k in "${KEYS[@]}"; do v="${!k:-}"; [ -n "$v" ] && { printf 'export %s=%q\n' "$k" "$v" >> "$ENVF"; N=$((N+1)); }; done
fi
[ "$N" -gt 0 ] || die 2 "넘길 키가 0개다(KEY_SRC=$KEY_SRC)"
# 비밀이 아닌 고정값(출처: 33335c7a tests/gateway/conftest.py 가 30 을 고정 · supabase/migrations 20261021000001 주석 «30일») — .env 에 없어도 gateway 기동(lifespan)이 요구한다
grep -q '^export CORPUS_RETENTION_DAYS=' "$ENVF" || { printf 'export CORPUS_RETENTION_DAYS=30\n' >> "$ENVF"; N=$((N+1)); say "        CORPUS_RETENTION_DAYS 는 .env 에 없어 고정값 30 으로 둔다(비밀 아님)"; }
# dev DB DSN 2개 — ★정본 경로 그대로★(scripts/server/loom_dsn.sh · supabase_dsn.sh: Secret Manager → 사설 host 를 127.0.0.1:$TUN_PORT 로 재작성 → 실효 검증).
#   mini 에는 GCP 자격이 없다(gcloud 는 이 맥에서만 부른다). 결과 DSN 은 127.0.0.1:$TUN_PORT 라서 아래 역방향 포워딩이 mini 의 같은 이름 포트로 받는다.
say "        dev DSN 2개를 정본 스크립트로 꺼낸다(값 출력 0 — 스크립트가 찍는 건 source·포트뿐)"
DSN_OUT="$( cd "$WORK/repo" && APP_ENV=local LOOM_PG_TUNNEL_PORT="$TUN_PORT" PYTHON="$PYBIN" bash -c '
  source scripts/server/loom_dsn.sh; source scripts/server/supabase_dsn.sh
  resolve_loom_interim_dsn all >&2 && resolve_supabase_dsn >&2 || exit 1
  printf "export LOOM_INTERIM_DB_URL=%q\nexport SUPABASE_DB_URL=%q\n" "$LOOM_INTERIM_DB_URL" "$SUPABASE_DB_URL"
' 2>"$WORK/dsn.err" )" || { sed 's/^/        /' "$WORK/dsn.err" | tail -4; die 2 "dev DSN 을 못 꺼냈다(gcloud 로그인·터널·위 오류 — 값은 출력하지 않는다)"; }
grep -E '^\[(LOOM|SUPABASE)-DSN\]' "$WORK/dsn.err" | head -3 | sed 's/^/        /'
printf '%s\n' "$DSN_OUT" >> "$ENVF"; unset DSN_OUT; N=$((N+2))
# 정본 worker 기동 세트 — scripts/server/ready-check.sh 의 WORKER_ENV_SPEC(단일 소스 · 비밀 아님: 포트·모델명·스위치). .env 에 이미 있는 이름은 건드리지 않고, 없는 것만 채운다. PORT 는 mini 에서 쓰지 않는다.
SPEC_N=0
while IFS= read -r spec; do
  nm="${spec%%=*}"; vl="${spec#*=}"
  [ "$nm" = "PORT" ] && continue
  grep -q "^export $nm=" "$ENVF" || { printf 'export %s=%q\n' "$nm" "$vl" >> "$ENVF"; SPEC_N=$((SPEC_N+1)); N=$((N+1)); }
done < <(sed -n '/^WORKER_ENV_SPEC=(/,/^)/p' "$WORK/repo/scripts/server/ready-check.sh" | grep -E '^[[:space:]]*"[A-Z0-9_]+=' | sed -E 's/^[[:space:]]*"//; s/"[[:space:]]*$//')
say "        정본 WORKER_ENV_SPEC 에서 .env 에 없던 고정값 ${SPEC_N}개를 채웠다(값 출력 0)"
for req in PAYMENT_MODE APP_ENV V6_AUTHORITATIVE_STT_MODE V6_AUTHORITATIVE_STT_PROVIDER BYZ_E2E_JWT_SECRET V5_BACKEND_ENABLED; do   # 이름만 검사
  grep -q "^export $req=" "$ENVF" || say "        ⚠ 필수 이름 누락: $req (gateway/worker 가 기동 중 raise 할 수 있다)"
done
say "        키 ${N}개 이름을 stdin 으로 넘긴다(값 출력 0)"
# 역방향 포워딩 — mini 의 127.0.0.1:$TUN_PORT 로 오는 접속을 이 맥의 loom 터널(127.0.0.1:$TUN_PORT)로 되돌린다.
#   mini 가 사설 DB 에 닿는 길 = 이 맥 상주 터널을 빌림. ExitOnForwardFailure: 포워딩이 안 서면 ssh 가 즉시 실패. 이 h 가 연 ssh pid 만 TUN_PIDF 에 기록.
RARGS=(); for fp in "${FWD_PORTS[@]}"; do RARGS+=(-R "127.0.0.1:$fp:127.0.0.1:$(lport "$fp")"); done
say "        역방향 포워딩 개설(mini ← 이 맥): ${FWD_PORTS[*]}"
nohup ssh "${SO[@]}" -o ExitOnForwardFailure=yes -N "${RARGS[@]}" "$MINI" </dev/null >"$WORK/fwd.log" 2>&1 &
echo $! > "$TUN_PIDF"; disown 2>/dev/null || true; sleep 3   # h 가 끝나도 포워딩은 남는다(서버가 쓰는 동안) — 정지는 ACTION=stop
kill -0 "$(cat "$TUN_PIDF")" 2>/dev/null || { tail -2 "$WORK/fwd.log" | sed 's/^/        /'; rm -f "$TUN_PIDF"; die 4 "역방향 포워딩이 서지 않았다(mini sshd 의 원격 포워딩 허용·포트 충돌 확인)"; }
for fp in "${FWD_PORTS[@]}"; do
  FWD_OK="$(ms 15 "lsof -nP -iTCP:$fp -sTCP:LISTEN 2>/dev/null | wc -l | tr -d ' '")" || FWD_OK=0
  [ "$FWD_OK" -ge 1 ] 2>/dev/null || { kill "$(cat "$TUN_PIDF")" 2>/dev/null; rm -f "$TUN_PIDF"; die 4 "mini 에서 127.0.0.1:$fp 가 LISTEN 이 아니다"; }
done
say "        포워딩 OK(${FWD_PORTS[*]}) · ssh pid $(cat "$TUN_PIDF") — 정지는 ACTION=stop"
# 원격 스크립트 = [env 블록] + [기동 명령]. 전부 stdin 으로 가서 `bash -s` 가 읽는다 → 명령줄에 비밀이 없다.
{
  cat <<EOS
cd "\$HOME/Project/BYZ-Agents" || exit 1
: > .h-pids; chmod 600 .h-pids
nohup redis-server --port $P_REDIS --save '' --appendonly no >/tmp/h-byz-redis.log 2>&1 </dev/null &
echo \$! >> .h-pids
(cd clients/web && { PORT=$P_WEB nohup ./node_modules/.bin/next start -p $P_WEB >/tmp/h-byz-web.log 2>&1 </dev/null & echo \$! >> ../../.h-pids; })   # 2026-10-22 h381 실측: 중괄호 없으면 & 가 «cd && nohup» 전체를 감싸 subshell 이 ssh 출력을 쥔 채 남고(60초 timeout → rc=4) pid 는 ~/.h-pids 로 샌다
EOS
  cat "$ENVF"
  cat <<EOS
export REDIS_HOST=127.0.0.1 REDIS_PORT=$P_REDIS REDIS_URL=redis://127.0.0.1:$P_REDIS/0   # REDIS_URL 이 우선(settings.py:104 · heartbeat 는 REDIS_URL 만 봄) — mini 기본 6379(기존 redis 가동 중)에 붙지 않게 고정
nohup .venv/bin/python -m uvicorn gateway.main:app --host 127.0.0.1 --port $P_GATEWAY >/tmp/h-byz-gateway.log 2>&1 </dev/null &
echo \$! >> .h-pids
nohup .venv/bin/python -m worker.main >/tmp/h-byz-worker.log 2>&1 </dev/null &
echo \$! >> .h-pids
sleep 1
echo started=\$(wc -l < .h-pids)
EOS
} | timeout 60 ssh "${SO[@]}" "$MINI" "export PATH=/opt/homebrew/bin:\$HOME/.local/bin:\$PATH; bash -s" 2>&1 | sed 's/^/        /' || die 4 "기동 실패"
rm -f "$ENVF"

# ── 5) 필요량 실측(기동 60초 뒤) ──────────────────────────────────────────
say "5/7 60초 뒤 프로세스별 RSS·memory_pressure"
sleep 55
ms 40 'cd $HOME/Project/BYZ-Agents; tot=0; while read -r pid; do r=$(ps -o rss= -p "$pid" 2>/dev/null | tr -d " "); [ -n "$r" ] || { echo "pid=$pid (종료됨)"; continue; }; mb=$((r/1024)); tot=$((tot+mb)); printf "pid=%s rss=%sMB %s\n" "$pid" "$mb" "$(ps -o comm= -p "$pid" | xargs basename)"; done < .h-pids; echo total_rss=${tot}MB; memory_pressure 2>/dev/null | tail -1' 2>&1 | sed 's/^/        /'
for u in "127.0.0.1:$P_GATEWAY/health" "127.0.0.1:$P_WEB/"; do
  CODE="$(ms 15 "curl -s -L -o /dev/null -w '%{http_code}' -m 5 http://$u || true")" || CODE="?"
  say "        http://$u → $CODE"
done
say "        로그 끝 줄(오류 확인용 · 값 없음):"
for f in gateway worker web; do printf '          %s: ' "$f"; ms 10 "tail -1 /tmp/h-byz-$f.log 2>/dev/null | cut -c1-120" 2>/dev/null; echo; done

# ── 6~7) 끝 ──────────────────────────────────────────────────────────────
GW_OK="$(ms 15 "curl -s -L -o /dev/null -w '%{http_code}' -m 5 http://127.0.0.1:$P_GATEWAY/health || true")"; WEB_OK="$(ms 15 "curl -s -o /dev/null -w '%{http_code}' -m 5 http://127.0.0.1:$P_WEB/ || true")"
if [ "$GW_OK" != "200" ] || [ "$WEB_OK" != "200" ]; then
  say "        ✗ health 실패 gateway=$GW_OK web=$WEB_OK — 로그 끝(값 없음):"
  for f in gateway worker web; do printf '          %s: ' "$f"; ms 10 "tail -2 /tmp/h-byz-$f.log 2>/dev/null | tr '\n' ' ' | cut -c1-240" 2>/dev/null; echo; done
  die 5 "서버가 안 떴다(health gateway=$GW_OK web=$WEB_OK) — 위 로그의 RuntimeError 가 빠진 env 이름. 정지: ACTION=stop"
fi
say "6/7 끝"
cat <<EOF
        닫는 증거 4줄(보고에 그대로):
          · sha=${FULL:0:12} 반입(아카이브 ${SZ_MB}MB) · 포트 3개 비었음
          · 설치·빌드 완료(.h-installed)
          · pid 개수 + total_rss=…MB + memory_pressure free %  ← ★필요량 실측★
          · health 코드(gateway / web)
        정지: SHA=… KEY_SRC=… ACTION=stop bash /tmp/h<N>   (.h-pids 의 pid 만)
        다음 회차에 필요: ① 기존 Chrome 정리·CDP 9333 재기동·마이크 허용·출력장치 BlackHole(오빠 손, mini 앞) ② h-mini-tts-say(h379) ③ 러너 실행 h — BYZ_E2E_JWT_SECRET 은 이 h 처럼 stdin 으로만
        이 h 가 하지 않은 것: 설치(brew·uv·npm 자체) 0 · stale-port 정리/Makefile 타깃 0 · 기본 포트(6379·8080·3001·3015) 0 · 원본 repo 수정 0 · 값 출력 0 · 디스크 기록 0
EOF
exit 0
