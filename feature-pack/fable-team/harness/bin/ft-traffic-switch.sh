#!/usr/bin/env bash
# ft-traffic-switch.sh — Cloud Run 트래픽 전환 공용 도구(r1133 · 사건 h244 10-29: 옛 리비전 Ready 만 보고 전환 → RT STT 503 11분 · 손 원복).
#   트래픽 전환 h 계획은 이 도구로만 한다 — ft-hil --add 가 날 `gcloud run services update-traffic` 줄·--health-url 없는 호출을 REJECT(ft_traffic_plan_judge.py).
#   ft-traffic-switch.sh --service S --region G --to <리비전|LATEST>=<퍼센트>[,…] --health-url <URL> [--allow-env-drift "<이유>"] [--project P]
# ① 지금 트래픽 표 읽기 = 직전 표 보관 ② 대상 리비전 Ready ③ 의존 대조: 지금 최대 비율 리비전에만 있는 env·secret 이름 = REJECT rc 1 · 전환 0
#    (--allow-env-drift 이유 = 통과 + 이유 1줄) ④ update-traffic ⑤ health: 창 60 s · 간격 5 s · 건마다 7 s — HTTP 200 ∧ consumer_ready == true = 성공
# ⑥ 실패면 직전 표로 자동 원복 → 원복 뒤 health 1회 → rc 3 · 원복도 실패 = rc 4 + 손 원복 명령 1줄(그대로 칠 수 있게)
# ⑦ 마지막 줄 `=== 결과 === <서비스> → <대상> · health=<코드> consumer_ready=<값> · <성공|원복 rc=3|원복 실패 rc=4|전환 0 rc=1|판정 불가 rc=5>`
# r1137(사건 h254): LATEST = latestCreatedRevisionName(움직이는 이름 · latestReady 아님) · 그 리비전이 Ready 아니면 판정 불가 rc 5(전환 0)
#   ④ 뒤 services describe 1회 → 켜진 리비전(percent>0) ⊄ 대조한 리비전 ∪ 지금 리비전 이면 자동 원복 rc 3 · 그 조회 실패도 원복(전환 뒤라 원복 쪽)
# rc: 0 성공 · 1 전환 전 거절(의존 어긋남·Ready 아님) · 2 사용법 · 3 원복함 · 4 원복 실패 · 5 판정 불가(gcloud 조회 실패 — 전환 0 · 하드 룰 20)
# 상한(하드 룰 12): gcloud 조회 7 s + 재시도 1 · update-traffic 60 s(쪼갤 수 없는 배치) · curl 7 s.
#   도구 1회 계산 상한 ≈ 조회 14×3 + 전환 60 + 전환 뒤 조회 14 + health 67 + 원복 60 + 7 ≈ 250 s → h 계획 쪽 timeout 은 260 s 이상(그 안에서 끊으면 원복 전에 죽는다).
# 시험 대역: TS_GCLOUD·TS_CURL(명령) · TS_HEALTH_WINDOW·TS_HEALTH_INTERVAL·TS_HEALTH_TRIES(초·초·회 — 시험은 간격 0) · 출력은 전부 stdout(h .out 에 남게)
set -uo pipefail
GC="${TS_GCLOUD:-gcloud}"; CU="${TS_CURL:-curl}"
WIN="${TS_HEALTH_WINDOW:-60}"; IV="${TS_HEALTH_INTERVAL:-5}"; TRIES="${TS_HEALTH_TRIES:-12}"
S=""; G=""; TO=""; URL=""; DRIFT=""; DRIFT_SET=0; PROJ=""; HC="-"; HR="-"
usage() { echo "usage: ft-traffic-switch.sh --service S --region G --to <리비전|LATEST>=<퍼센트>[,…] --health-url <URL> [--allow-env-drift \"<이유>\"] [--project P]" >&2; exit 2; }
while [ $# -gt 0 ]; do
  [ -n "${2:-}" ] || usage
  case "$1" in
    --service) S="$2" ;; --region) G="$2" ;; --to) TO="$2" ;; --health-url) URL="$2" ;; --project) PROJ="$2" ;;
    --allow-env-drift) DRIFT="$2"; DRIFT_SET=1 ;;
    *) usage ;;
  esac
  shift 2
done
[ -n "$S" ] && [ -n "$G" ] && [ -n "$TO" ] && [ -n "$URL" ] || usage
[[ "$TO" =~ ^[A-Za-z0-9._-]+=[0-9]+(,[A-Za-z0-9._-]+=[0-9]+)*$ ]] || { echo "REJECT --to 꼴이 아니다(<리비전>=<퍼센트>[,…]): $TO" >&2; exit 2; }
[[ "$URL" =~ ^https?:// ]] || { echo "REJECT --health-url 은 http(s) 주소다: $URL" >&2; exit 2; }
GA=(--region="$G"); [ -z "$PROJ" ] || GA+=(--project="$PROJ")
TD="$(mktemp -d)"; trap 'rm -rf "$TD"' EXIT

lim() { local s="$1"; shift; perl -e 'alarm shift; exec @ARGV' -- "$s" "$@"; }   # 상한 초 뒤 SIGALRM(rc 142)
fin() {  # <health> <consumer_ready> <끝 글> <rc> [앞 줄] — 결과 줄은 언제나 마지막 줄
  [ -z "${5:-}" ] || echo "$5"
  echo "=== 결과 === $S → $TO · health=$1 consumer_ready=$2 · $3"
  exit "$4"
}
gtry() {  # <저장 파일> <gcloud 인자…> — 조회 1회 7 s + 재시도 1 · 둘 다 실패 = rc 1
  local f="$1" i; shift
  for i in 1 2; do lim 7 "$GC" "$@" "${GA[@]}" --format=json > "$f" 2> "$f.err" && return 0; done
  return 1
}
gq() {  # gtry 실패 = 판정 불가 rc 5 로 끝(전환 0)
  gtry "$@" && return 0
  local f="$1"; shift
  fin "-" "-" "판정 불가 rc=5" 5 "판정 불가 — gcloud $* 실패: $(head -c 300 "$f.err")"
}
py() {  # <모드> <파일…> — gcloud JSON·health 본문 읽기(문자열만 · 실행 0)
  python3 - "$@" <<'PY'
import json, sys
mode, files = sys.argv[1], sys.argv[2:]
def load(p):
    with open(p) as f:
        return json.load(f)
def deps(p):  # env 이름 + secret 참조 이름(env secretKeyRef · volume secret)
    spec, out = load(p).get("spec") or {}, set()
    for c in spec.get("containers") or []:
        for e in c.get("env") or []:
            out.add("env:" + e.get("name", "?"))
            ref = ((e.get("valueFrom") or {}).get("secretKeyRef") or {}).get("name")
            if ref:
                out.add("secret:" + ref)
    for v in spec.get("volumes") or []:
        ref = (v.get("secret") or {}).get("secretName")
        if ref:
            out.add("secret:" + ref)
    return out
if mode == "table":  # 1줄 직전 표(rev=pct,… · latest 추종 = LATEST) · 2줄 최대 비율 리비전 · 3줄 latestReady · 4줄 latestCreated
    st = load(files[0]).get("status") or {}
    rows = [t for t in st.get("traffic") or [] if (t.get("percent") or 0) > 0]
    print(",".join("%s=%d" % ("LATEST" if t.get("latestRevision") else t.get("revisionName", "?"), t["percent"]) for t in rows))
    print(max(rows, key=lambda t: t["percent"]).get("revisionName", "") if rows else "")
    print(st.get("latestReadyRevisionName", ""))
    print(st.get("latestCreatedRevisionName", ""))
elif mode == "on":  # 켜진 리비전 이름(percent>0 · LATEST 행도 revisionName · 이름 없음 = ?)
    rows = ((load(files[0]).get("status") or {}).get("traffic")) or []
    print(" ".join(sorted({t.get("revisionName") or "?" for t in rows if (t.get("percent") or 0) > 0})))
elif mode == "ready":
    cs = (load(files[0]).get("status") or {}).get("conditions") or []
    print(next((c.get("status", "") for c in cs if c.get("type") == "Ready"), "없음"))
elif mode == "miss":  # 지금(files[0])에만 있는 이름
    print(" ".join(sorted(deps(files[0]) - deps(files[1]))))
elif mode == "cr":  # health 본문의 consumer_ready → true|false|-
    try:
        v = load(files[0]).get("consumer_ready")
        print("true" if v is True else "false" if v is False else "-")
    except Exception:
        print("-")
PY
}
health_once() { : > "$TD/h.body"; HC="$("$CU" -sS -m 7 -o "$TD/h.body" -w '%{http_code}' "$URL" 2>/dev/null)"; [ -n "$HC" ] || HC=000; HR="$(py cr "$TD/h.body")"; }
watch_health() {  # 창(WIN 초) 안 TRIES 회까지 — 200 ∧ consumer_ready=true 면 rc 0
  local i=0 t0=$SECONDS
  while :; do
    i=$((i + 1)); health_once; echo "health $i: $HC consumer_ready=$HR"
    [ "$HC" = 200 ] && [ "$HR" = true ] && return 0
    [ "$i" -lt "$TRIES" ] && [ $((SECONDS - t0)) -lt "$WIN" ] || return 1
    sleep "$IV"
  done
}
upd() { lim 60 "$GC" run services update-traffic "$S" "${GA[@]}" --to-revisions="$1" > "$TD/u.out" 2>&1; local r=$?; tail -3 "$TD/u.out"; return "$r"; }
restore() {  # $1=왜 — 직전 표로 되돌림 → health 1회 → rc 3 · 되돌림 실패 = rc 4 + 손 원복 명령
  echo "원복 — $1 → 직전 표 $PREV"
  upd "$PREV" || fin "$HC" "$HR" "원복 실패 rc=4" 4 "원복 실패 — 손 원복: gcloud run services update-traffic $S ${GA[*]} --to-revisions=$PREV"
  health_once; echo "원복 뒤 health: $HC consumer_ready=$HR"
  fin "$HC" "$HR" "원복 rc=3" 3
}

gq "$TD/svc.json" run services describe "$S"
{ read -r PREV; read -r CUR; read -r LREADY; read -r LCREATED; } < <(py table "$TD/svc.json")
[ -n "${PREV:-}" ] && [ -n "${CUR:-}" ] || fin "-" "-" "판정 불가 rc=5" 5 "판정 불가 — 지금 트래픽 표가 비었다($S)"
echo "직전 표: $PREV (원복은 이 표로) · 지금 최대 비율 리비전: $CUR"
CUR_JSON=""; CHK=""
for x in ${TO//,/ }; do
  n="${x%%=*}"; [ "${x#*=}" -gt 0 ] || continue
  lt=""; [ "$n" != LATEST ] || { n="${LCREATED:-}"; lt="LATEST = $n(latestCreated)"; }
  [ -n "$n" ] || fin "-" "-" "판정 불가 rc=5" 5 "판정 불가 — latestCreatedRevisionName 이 비었다($S)"
  gq "$TD/t.json" run revisions describe "$n"
  rd="$(py ready "$TD/t.json")"
  [ "$rd" = True ] || [ -z "$lt" ] || fin "-" "-" "판정 불가 rc=5" 5 "판정 불가 — 최신 리비전 준비 안 됨(created $n Ready=$rd · ready ${LREADY:-?}) · 준비 뒤 다시"
  [ "$rd" = True ] || fin "-" "-" "전환 0 rc=1" 1 "REJECT 대상 $n 준비 안 됨(Ready=$rd)"
  CHK="$CHK $n"
  [ "$n" != "$CUR" ] || { echo "${lt:-의존 대조 — 대상 $n} = 지금 리비전(대조 생략)"; continue; }
  [ -z "$lt" ] || echo "$lt"
  [ -n "$CUR_JSON" ] || { CUR_JSON="$TD/cur.json"; gq "$CUR_JSON" run revisions describe "$CUR"; }
  miss="$(py miss "$CUR_JSON" "$TD/t.json")"
  if [ -z "$miss" ]; then echo "의존 대조 — 대상 $n ↔ 지금 $CUR: 어긋남 0"
  elif [ "$DRIFT_SET" = 1 ]; then echo "의존 어긋남 허용(--allow-env-drift): $DRIFT — 대상 $n 에 없는 키: $miss"
  else fin "-" "-" "전환 0 rc=1" 1 "REJECT 의존 어긋남 — 대상 $n 에 없는 키: $miss (지금 $CUR · 알고 넘기려면 --allow-env-drift \"<이유>\")"
  fi
done
echo "전환 — $S → $TO"
upd "$TO" || restore "전환 명령 실패 rc=$?"
gtry "$TD/after.json" run services describe "$S" && ON="$(py on "$TD/after.json")" && [ -n "$ON" ] \
  || restore "전환 뒤 켜진 리비전 조회 실패(판정 불가 — 전환 뒤라 원복 쪽)"
echo "켜진 리비전 = $ON (대조한 리비전:$CHK · 지금 $CUR)"
for r in $ON; do case " $CHK $CUR " in *" $r "*) ;; *) restore "켜진 리비전 $r 가 대조 안 한 리비전" ;; esac; done
watch_health || restore "health ${WIN}s 창 실패(마지막 $HC consumer_ready=$HR)"
fin "$HC" "$HR" "성공" 0
