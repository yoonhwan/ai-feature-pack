#!/bin/bash
# mbox.sh 가 source 하는 쪽지 가드 — send/relay 앞단의 문 두 개(단독 실행 0 · DIR 은 mbox.sh 가 정한다) · 200줄 규칙 분리.
#   ①수신자 판정(D3): 은퇴·닫힌 좌석·명부 충돌·명부 깨짐은 REJECT rc 3 — 옛 이름 쪽지가 죽은 큐에 쌓이지 않게(R97).
#   ②planner 앞 허용 머리(D4): 진행·참고 쪽지는 상태판이 나른다 — 모드 warn(기본: 로그+전송) | reject.
#   ★안전 보고 우선★: 머리 [HIL]·[긴급] 은 어떤 명부 상태에서도 REJECT 하지 않는다(은퇴가 읽히면 후계로 전달 · 못 읽으면 명시 이름 그대로 + WARN + 로그).
#   설계 정본 = PLAN-harness-networking-20261011 §2 D3·D4. 명부 경로 = _seats_json(FT_SEATS_JSON) 의 폴더. 외부 호출 0(json·큐 파일만).
GUARD_STATE="$DIR/../state"; US=$'\037'

guard_log() { mkdir -p "$GUARD_STATE" 2>/dev/null; printf '%s %s\n' "$(date -u +%FT%TZ)" "$2" >> "$GUARD_STATE/$1" 2>/dev/null || true; }

# warn | reject — env FT_PLANNER_HEAD_MODE > queues.conf 의 planner_head_mode= > warn. 모르는 값은 warn.
guard_mode() {
  local m="${FT_PLANNER_HEAD_MODE:-}" conf="${FT_MBOX_QUEUES_CONF:-$DIR/queues.conf}"
  if [ -z "$m" ] && [ -f "$conf" ]; then m="$(sed -n 's/^planner_head_mode=//p' "$conf" | tail -1 | tr -d '[:space:]')"; fi
  case "$m" in reject) echo reject;; *) echo warn;; esac
}

# 출력 줄 = `<동사>␟<새 수신자>␟<문장>`(구분자 U+001F — 탭은 read 가 연속 구분자를 합친다) : OK · WARN · REJECT · FORWARD(후계로 전달) · EXPLICIT(명시 이름 그대로 + 로그)
_guard_py_recipient() {
  python3 - "$(_seats_json)" "$1" "$2" <<'PY'
import json, glob, os, re, sys
sj, to, safe = sys.argv[1], sys.argv[2], sys.argv[3] == "1"
d = os.path.dirname(sj) or "."
def out(verb, new="", msg=""): print(f"{verb}\x1f{new}\x1f{msg}")
def stop(msg, forward=""):  # 안전 보고면 막지 않는다
    if forward and safe: out("FORWARD", forward, msg)
    elif safe: out("EXPLICIT", "", "명부 미확인 — 명시 이름으로 전송 (" + msg + ")")
    else: out("REJECT", "", msg)
    sys.exit(0)
docs, bad = {}, []
for f in sorted(glob.glob(d + "/seats*.json")):
    try: v = json.load(open(f, encoding="utf-8"))
    except Exception: v = None
    if isinstance(v, dict): docs[f] = v
    else: bad.append(f)
def tfile(n):  # 이름의 팀 글자 → authoritative 명부 파일(없으면 "")
    m = re.match(r"^(?:byz|ft)-([a-z0-9]+)-", n)
    return (d + ("/seats.json" if m.group(1) == "v65" else "/seats-" + m.group(1) + ".json")) if m else ""
auth = tfile(to); team = os.path.basename(auth)[6:-5] if auth else ""
for f in bad:
    if f != auth: out("WARN", "", "명부 " + os.path.basename(f) + " 읽기 실패 · 이 판정에는 미사용")
if auth in bad: stop("명부 읽기 실패 " + os.path.basename(auth) + " — 다시 보내라")
hold = [f for f, v in docs.items() if isinstance(v.get(to), dict)]   # 전역 검색 = 충돌 검사 전용
if len(hold) > 1: stop("명부 충돌 " + " ".join(os.path.basename(f) for f in hold))
row = docs.get(auth, {}).get(to)                                    # 상태는 authoritative 파일에서만
if not isinstance(row, dict):
    other = " (다른 명부 " + os.path.basename(hold[0]) + " 에만 있음 · 판정에 안 씀)" if hold else ""
    out("WARN", "", "미등록 " + to + " — 전송" + other); out("OK"); sys.exit(0)
cur, seen, crow, cfile = to, {to}, row, auth
while crow.get("_replaced_by"):
    cur = crow["_replaced_by"]
    if cur in seen: stop("명부 순환 " + to)
    seen.add(cur); cfile = tfile(cur)
    if cfile in bad: stop("명부 읽기 실패 " + os.path.basename(cfile) + " — 다시 보내라")
    nxt = docs.get(cfile, {}).get(cur)
    if not isinstance(nxt, dict): break
    crow = nxt
closed = crow.get("role") in ("closed", "stopped")
def why(f, r): return "_closed=" + str(docs.get(f, {}).get("_closed") or r.get("_closed") or "?")
if cur != to and closed: stop("은퇴한 좌석 " + to + " → 후계 " + cur + " 도 닫힘(" + why(cfile, crow) + ")")
if cur != to: stop("은퇴한 좌석 " + to + " → 현역 " + cur + " — 후계 이름으로 다시 보내라", forward=cur)
if closed: stop("닫힌 좌석(" + team + " " + why(auth, row) + ")")
if row.get("role") == "stop-ready": out("WARN", "", "정지 레디 좌석 " + to + " — 전송")
out("OK")
PY
}

# planner 앞 머리 판정 — 본문은 argv[4](heredoc 이 stdin 을 쓴다). 출력 줄: WARN · LOGH(planner-head.log) · ALIAS(머리 치환) · REJECT
_guard_py_head() {
  python3 - "$(dirname "$(_seats_json)")/seats-planner.json" "$1" "$2" "$3" <<'PY'
import json, re, sys
pj, to, mode, body = sys.argv[1:5]
try: master = json.load(open(pj, encoding="utf-8")).get("_master")
except Exception: sys.exit(0)
if master != to: sys.exit(0)
lines = body.strip().split("\n") if body.strip() else [""]
m = re.match(r"\[[^\]]*\]", lines[0].strip()); head = m.group(0) if m else ""
def emit(k, t): print(k + "\x1f\x1f" + t)
def has(p): return any(re.match(p, l.strip()) for l in lines)
viol = ""
if head == "[HIL·merge]": emit("ALIAS", "[합치기]"); emit("LOGH", "별칭 [HIL·merge]→[합치기] to=" + to); head = "[합치기]"
if head == "[결정]":
    miss = [k for k in ("비가역", "선례", "선택지") if not has(k + r"\s*:")]
    if miss: viol = "[결정] 필수 줄 없음: " + ",".join(miss) + " (비가역:·선례:·선택지: 3줄)"
elif head == "[HIL]" or head.startswith("[HIL·"):
    miss = [n for n, p in (("①막힌 명령", "①|막힌 명령"), ("②막은 훅·사유", "②|훅|사유"), ("④선택지", "④|선택지")) if not re.search(p, body)]
    if miss: emit("WARN", "[HIL] 본문에 " + ",".join(miss) + " 줄 없음 — 전송은 한다")
elif head in ("[완료]", "[정지 레디]") or head.startswith("[완료·"):
    if not re.search(r"(세트|시험)\s*:", body): emit("WARN", head + " 증거 줄(세트:·시험:) 없음 — 전송은 한다")
elif head not in ("[긴급]", "[합치기]", "[부팅 보고]"):
    viol = "planner 앞 쪽지는 " + "[결정]·[HIL]·[긴급]·[합치기]·[정지 레디]·[완료]·[부팅 보고]" + " 만 — 진행·참고·마일스톤은 상태판(ft-board)이 나른다. 되돌릴 수 있고 사람 손도 안 필요한 것은 팀 master 가 선례(ft-precedent)로 결정한다(R-E). 머리=" + (head or "없음")
if viol and mode == "reject": emit("REJECT", viol)
elif viol: emit("WARN", "planner 머리 규칙 위반(warn 모드 · 전송) — " + viol); emit("LOGH", "to=" + to + " " + viol)
PY
}

# [부팅 보고] 본문 검사(P4) — 승계 좌석 retire=<구>-><후계> rc=0 · master/arch cron=<id>. 발신자 = mbox.sh 의 $from. lint 부재·명부 불명 = WARN + 전송.
_guard_boot_lint() {
  local first lint="" f res rc; first="${1%%$'\n'*}"; first="${first#"${first%%[![:space:]]*}"}"
  case "$first" in '[부팅 보고]'*) ;; *) return 0;; esac
  for f in "$DIR/ft-boot-report-lint.py" "$DIR/../../.claude/fable-team/bin/ft-boot-report-lint.py"; do [ -f "$f" ] && { lint="$f"; break; }; done
  [ -n "$lint" ] || { echo "WARN 부팅 보고 lint 파일 없음 — 검사 없이 전송 (설치 순서)" >&2; return 0; }
  res="$(printf '%s' "$1" | python3 "$lint" --from "${from:-}" --seats-dir "$(dirname "$(_seats_json)")")"; rc=$?
  case "$rc" in
    0) return 0;;
    1) echo "REJECT ${res#REJECT }" >&2; return 3;;
    *) echo "WARN 부팅 보고 lint 실행 실패 rc=$rc — 검사 없이 전송" >&2; return 0;;
  esac
}

# guard_check <to> <body> — GUARD_TO·GUARD_BODY 를 정한다. rc 3 = REJECT(큐 적재 0).
guard_check() {
  GUARD_TO="$1"; GUARD_BODY="$2"
  local first safe=0 out verb new msg rej=""
  first="${2%%$'\n'*}"; first="${first#"${first%%[![:space:]]*}"}"
  case "$first" in '[HIL]'*|'[HIL·'*|'[긴급]'*) safe=1;; esac
  out="$(_guard_py_recipient "$1" "$safe" 2>/dev/null)" || out="REJECT$US${US}가드 실행 실패 — 다시 보내라"
  [ "$safe" = 1 ] && case "$out" in REJECT*) out="EXPLICIT$US${US}명부 미확인 — 명시 이름으로 전송 (가드 실행 실패)";; esac
  while IFS=$'\037' read -r verb new msg; do
    case "$verb" in
      WARN)     echo "WARN $msg" >&2;;
      REJECT)   rej="$msg";;
      FORWARD)  GUARD_TO="$new"; echo "WARN $msg — 후계 $new 로 전달" >&2; guard_log mbox-guard.log "forward $1 -> $new ($msg)";;
      EXPLICIT) echo "WARN $msg" >&2; guard_log mbox-guard.log "explicit to=$1 ($msg)";;
    esac
  done <<< "$out"
  [ -z "$rej" ] || { echo "REJECT $rej" >&2; return 3; }
  out="$(_guard_py_head "$GUARD_TO" "$(guard_mode)" "$2" 2>/dev/null)" || out=""
  while IFS=$'\037' read -r verb new msg; do
    case "$verb" in
      WARN)  echo "WARN $msg" >&2;;
      LOGH)  guard_log planner-head.log "$msg";;
      ALIAS) GUARD_BODY="$new${GUARD_BODY#\[HIL·merge\]}";;
      REJECT) rej="$msg";;
    esac
  done <<< "$out"
  [ -z "$rej" ] || { echo "REJECT $rej" >&2; return 3; }
  _guard_boot_lint "$2" || return $?
  return 0
}
