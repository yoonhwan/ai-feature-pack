#!/usr/bin/env bash
# ft-docker-test-reap.sh — 주인(pytest pid)이 죽은 «시험 라벨» 컨테이너를 익명 볼륨째 거둔다 (R352).
#   대상 = 라벨 byz.test=1 컨테이너 중 byz.owner_pid 의 프로세스가 «확실히 없거나» 시작 시각(byz.owner_start)이 다른 것(pid 재사용).
#   라벨 없는 컨테이너·볼륨은 보지도 않는다 — 이미 쌓인 라벨 없는 익명 볼륨은 이 도구 범위 밖(사람 몫).
#   사용: ft-docker-test-reap.sh [--kill]   (기본 = 목록만 · --kill 이 `docker rm -f -v` · ft-disk-alarm 이 하루 1회 --kill)
#   안전(DA⑥ r1): 목록 때 잡은 «불변 컨테이너 ID» 로만 inspect·rm · 삭제 직전 그 ID 의 라벨을 목록 때와 다시 대조(다르면 skip) ·
#     그 사이 사라진 ID 는 정상 skip(오류 0) · 같은 이름의 새 컨테이너는 손대지 않는다.
#     주인 판정 = ps 전체 목록 «조회 성공 + 그 pid 없음» 일 때만 죽음 · ps 실패/빈 출력 = 조회 불가 → 제거 0 · rc20.
#     주인 시작 시각 라벨이 비었으면 보수적으로 skip + WARN · 시각 비교는 양쪽 LC_ALL=C TZ=UTC 고정.
#     inspect 실패(없음 아님)·rm 실패 = 그 컨테이너 skip + 마지막에 rc20(조용한 0 없음).
#   7초 룰(판정 666): docker·ps 호출마다 7초(FT_DOCKER_REAP_CALL_S 는 1~7 정수만 · 아니면 7 + WARN) · 전체 70초.
#   env(시험용): FT_DOCKER · FT_PS · FT_DOCKER_REAP_CALL_S
set -uo pipefail
export LC_ALL=C TZ=UTC
KILL=0
case "${1:-}" in "") ;; --kill) KILL=1;; *) echo "usage: ft-docker-test-reap.sh [--kill]" >&2; exit 2;; esac
DOCKER="${FT_DOCKER:-docker}"; PSBIN="${FT_PS:-ps}"; CALL_S="${FT_DOCKER_REAP_CALL_S:-7}"; TOTAL_S=70
T0=$(date +%s)
warn() { echo "WARN docker-test-reap: $1" >&2; }
fail() { echo "ERROR docker-test-reap: $1" >&2; exit 20; }
norm() { tr -s ' ' | sed 's/^ //;s/ $//'; }
case "$CALL_S" in ''|*[!0-9]*) CALL_S=0;; esac
if [ "$CALL_S" -lt 1 ] || [ "$CALL_S" -gt 7 ]; then warn "FT_DOCKER_REAP_CALL_S='${FT_DOCKER_REAP_CALL_S:-}' 는 1~7 정수가 아니다 — 7 사용"; CALL_S=7; fi
call() { # 남은 전체 마감 안에서 호출마다 CALL_S 초 — perl alarm 으로 끊는다(macOS 에 timeout 이 없을 수 있다)
  local left=$((TOTAL_S-($(date +%s)-T0)))
  [ "$left" -gt 0 ] || return 124
  [ "$left" -le "$CALL_S" ] || left="$CALL_S"
  perl -e 'alarm shift; exec @ARGV or exit 127' "$left" "$@"
}
gone() { case "$1" in *[Nn]o\ such*) return 0;; *) return 1;; esac; }   # docker 의 «대상 없음» 응답 = 그 사이 사라짐

rows="$(call "$DOCKER" ps -a --no-trunc --filter label=byz.test=1 --format '{{.ID}}|{{.Names}}|{{.Label "byz.owner_pid"}}|{{.Label "byz.owner_start"}}|{{.Label "byz.sid"}}')"; rc=$?
[ "$rc" = 0 ] || fail "docker ps 실패/시간 초과(rc=$rc) — 시험 컨테이너 조사 불가"
n_label=0; cands=()
while IFS='|' read -r id name pid start _sid; do
  [ -n "$id" ] || continue; n_label=$((n_label+1))
  case "$pid" in ''|*[!0-9]*) warn "$name: byz.owner_pid 라벨 없음/비숫자 — skip"; continue;; esac
  [ -n "$start" ] || { warn "$name: byz.owner_start 라벨이 비어 있음(주인 시작 시각 판정 불가) — skip"; continue; }
  cands+=("$id|$name|$pid|$start")
done <<< "$rows"
if [ "${#cands[@]}" = 0 ]; then echo "OK 후보 0 — 시험 라벨 컨테이너 ${n_label} 중 판정 가능한 주인 죽은 것 없음"; exit 0; fi

procs="$(call "$PSBIN" -A -o pid=,lstart=)"; rc=$?   # 성공 + 목록에 그 pid 없음 = 확실한 부재 · 실패/빈 출력 = 조회 불가
{ [ "$rc" = 0 ] && [ -n "$procs" ]; } || fail "ps 조회 실패/빈 출력(rc=$rc) — 주인 생존 판정 불가 · 제거 0"
dead=()
for c in "${cands[@]}"; do
  IFS='|' read -r id name pid start <<< "$c"
  now="$(printf '%s\n' "$procs" | awk -v p="$pid" '$1==p{$1="";print;exit}' | norm)"
  if [ -z "$now" ]; then dead+=("$c")
  elif [ "$now" != "$(printf '%s' "$start" | norm)" ]; then dead+=("$c"); fi   # pid 재사용
done
if [ "${#dead[@]}" = 0 ]; then echo "OK 후보 0 — 시험 라벨 컨테이너 ${n_label} 중 주인 죽은 것 없음"; exit 0; fi
if [ "$KILL" = 0 ]; then
  names=""; for c in "${dead[@]}"; do IFS='|' read -r id name _r <<< "$c"; names="$names $name"; done
  echo "DRY 주인 죽은 시험 컨테이너 ${#dead[@]}:${names} (--kill 로 제거)"; exit 0
fi

removed=0; vols=0; bad=(); unknown=0
for c in "${dead[@]}"; do
  IFS='|' read -r id name pid start <<< "$c"
  # 삭제 직전 «그 ID» 의 라벨·마운트를 한 번에 다시 읽는다 — 이름이 아니라 불변 ID 로
  out="$(call "$DOCKER" inspect --format '{{index .Config.Labels "byz.test"}}|{{index .Config.Labels "byz.owner_pid"}}|{{index .Config.Labels "byz.owner_start"}}|{{range .Mounts}}{{.Name}} {{end}}' "$id" 2>&1)"; rc=$?
  if [ "$rc" != 0 ]; then
    gone "$out" && continue   # 그 사이 사라짐 = 정상 skip
    warn "$name ($id): inspect 실패 rc=$rc — 불명 · skip"; unknown=$((unknown+1)); continue
  fi
  IFS='|' read -r l_test l_pid l_start mounts <<< "$out"
  if [ "$l_test" != 1 ] || [ "$l_pid" != "$pid" ] || [ "$l_start" != "$start" ]; then
    warn "$name ($id): 삭제 직전 라벨이 목록 때와 다름 — skip"; continue
  fi
  v=$(printf '%s\n' $mounts | grep -cE '^[0-9a-f]{64}$')
  rout="$(call "$DOCKER" rm -f -v "$id" 2>&1)"; rc=$?
  if [ "$rc" = 0 ]; then removed=$((removed+1)); vols=$((vols+v))
  else gone "$rout" || bad+=("$name"); fi
done
echo "주인 죽은 시험 컨테이너 ${removed} 제거 · 익명(추정) 볼륨 ${vols} 제거"
[ "${#bad[@]}" = 0 ] && [ "$unknown" = 0 ] || fail "rm -f -v 실패: ${bad[*]:-없음} · inspect 불명 ${unknown} (제거 ${removed})"
