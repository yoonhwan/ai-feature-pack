#!/bin/bash
# mbox.sh 가 source 하는 «깨움 예산» (r1476 · mbox_wakegate.sh 와 짝). 단독 실행 0 — DIR 은 mbox.sh 가 정한다.
#   시각 창 = epoch/3600 «고정»(달력 시각) · 좌석 6/창 · 팀 30/창 · mkdir 원자 잠금(죽은 pid 해제 · 10초 상한)
#   wake_budget_reserve <좌석> [출처] : 예약 1회 = 차감 1회 → `reserved n=<k> team=<m>` rc0 | `exhausted seat|team n=…` rc3 | `ERROR …` rc1
#   wake_budget_refund  <좌석> [출처] : 차감 되돌림(0 미만 0) — 원장 행 0(원장은 «예약» 만 적는다)
# ★fail-closed★ — 장부가 깨졌거나 잠금이 10초를 넘으면 «울리지 않는다». 소진 우회 0 · 못 깨운 쪽지는 held 로 남아 sweep 이 잡는다.
# ★왜 파일인가★ — 프로세스 로컬 카운터는 send 마다 새 프로세스라 0 으로 돌아간다. 좌석·팀 합은 «공유 상태» 라야 상한이 성립한다.

_wg_now() { if [ -n "${FT_MBOX_NOW:-}" ]; then printf '%s' "$FT_MBOX_NOW"; else date +%s; fi; }
_wg_state() { printf '%s' "${FT_MBOX_STATE_DIR:-$DIR/../state}"; }
_wg_key() { printf '%s' "$1" | tr -c 'A-Za-z0-9._#-' '_'; }
_wg_hhmm() { local n="$1"; printf '%s' "$(date -r "$n" +%H:%M 2>/dev/null || date -d "@$n" +%H:%M 2>/dev/null || printf '?')"; }
_wg_errlog() { local f; f="$(_wg_state)/wake-budget/_errors.log"; mkdir -p "$(dirname "$f")" 2>/dev/null; printf '%s %s\n' "$(_wg_hhmm "$(_wg_now)")" "$1" >> "$f" 2>/dev/null || true; }
# 외부 조회 상한(하드 룰 12 · 7초) — timeout 없으면 그대로 실행(로컬 판정기는 보통 ms 단위 · 침몰은 위험)
_wg_timeout() { local n="$1"; shift; if command -v timeout >/dev/null 2>&1; then timeout "$n" "$@"; elif command -v gtimeout >/dev/null 2>&1; then gtimeout "$n" "$@"; else "$@"; fi; }
# 억제 파일 첫 줄의 «key=값» 하나(공백으로 나뉜 토큰) — 파일 없으면 빈 값.
_wg_kv() { awk -v k="$2" 'NR==1{ for (i=1;i<=NF;i++) if (substr($i,1,length(k)+1)==k"=") { print substr($i, length(k)+2); exit } }' "$1" 2>/dev/null; }

# 좌석의 팀(예산 합산 단위) — 명부 entry.team · 없으면 default(한 팀으로 묶는다 · 상한을 안 걸면 팀 상한이 사라진다).
_wg_team() {
  local sj t=""
  sj="$(_seats_json 2>/dev/null)" || sj=""
  if [ -z "$sj" ] || [ ! -f "$sj" ]; then printf 'default'; return 0; fi
  t="$(python3 - "$sj" "$1" <<'PY' 2>/dev/null
import json, sys
try:
    d = json.load(open(sys.argv[1], encoding="utf-8"))
except Exception:
    sys.exit(0)
e = d.get(sys.argv[2])
print(e.get("team") if isinstance(e, dict) and e.get("team") else "default")
PY
)"
  printf '%s' "${t:-default}"
}

# ── 예산 잠금(mkdir · macOS flock 없음) — 죽은 pid 해제 · 10초(기본 100×0.1s) 상한 = ft-verdict-lock.sh 꼴 ──
_wg_lock() {  # <wake-budget 폴더> → rc0 획득 · rc1 상한 초과
  local d="$1/.lock" i=0 pid tries="${FT_MBOX_WAKE_LOCK_TRIES:-100}"
  until mkdir "$d" 2>/dev/null; do
    pid="$(cat "$d/pid" 2>/dev/null || printf '')"
    case "$pid" in
      ''|*[!0-9]*) ;;
      *) if ! kill -0 "$pid" 2>/dev/null; then
           rm -rf "$d" 2>/dev/null || true
           echo "WARN 예산 잠금 죽은 보유 pid $pid 해제 — $d" >&2
           continue
         fi ;;
    esac
    i=$((i + 1))
    # 상한 초과 = fail-closed(부르는 쪽이 budget 으로 떨어진다). 소진 우회 0.
    if [ "$i" -gt "$tries" ]; then return 1; fi
    sleep 0.1
  done
  printf '%s' "$$" > "$d/pid" 2>/dev/null || true
  return 0
}
_wg_unlock() { local d="$1/.lock"; [ "$(cat "$d/pid" 2>/dev/null)" = "$$" ] && rm -rf "$d" 2>/dev/null; return 0; }

# 예약 → stdout `reserved n=<k> team=<m>` rc0 | `exhausted seat|team n=…` rc3 | `ERROR …` rc1(fail-closed)
wake_budget_reserve() {
  local seat="$1" src="${2:-send}" sd win smax tmax out rc=0 msg
  sd="$(_wg_state)/wake-budget"
  mkdir -p "$sd" 2>/dev/null || {
    printf 'ERROR state 폴더 생성 실패 %s\n' "$sd"
    printf 'ERROR state 폴더 생성 실패 %s\n' "$sd" >&2
    _wg_errlog "mkdir-fail $sd"; return 1; }
  win=$(( $(_wg_now) / 3600 ))
  smax="${FT_MBOX_WAKE_SEAT_MAX:-6}"; tmax="${FT_MBOX_WAKE_TEAM_MAX:-30}"
  if ! _wg_lock "$sd"; then
    printf 'ERROR 예산 잠금 10초 초과 — %s/.lock\n' "$sd"
    printf 'ERROR 예산 잠금 10초 초과 — %s/.lock\n' "$sd" >&2   # ★사유는 stderr 로도★ — 게이트가 stdout 을 삼켜도 «왜 안 울렸는지» 는 남는다
    _wg_errlog "lock-timeout seat=$seat src=$src"
    return 1
  fi
  out="$(python3 - "$sd" "$(_wg_key "$seat")" "$(_wg_team "$seat")" "$win" "$smax" "$tmax" "$src" "$(_wg_now)" <<'PY'
import json, os, sys, time
sd, seat, team, win, smax, tmax, src, now = sys.argv[1:9]
win, smax, tmax = int(win), int(smax), int(tmax)
led = os.path.join(sd, "_ledger.log")
seatsf = os.path.join(sd, seat + ".json")
teamf = os.path.join(sd, "_team-%s.json" % team)


def read(p):
    """(window, n) | None(없음) | ValueError(깨짐·형식 아님)."""
    try:
        with open(p, encoding="utf-8") as f:
            d = json.load(f)
    except FileNotFoundError:
        return None
    except (ValueError, OSError) as e:
        raise ValueError(str(e))
    if not isinstance(d, dict) or not isinstance(d.get("window"), int) or not isinstance(d.get("n"), int):
        raise ValueError("형식 아님")
    return d["window"], d["n"]


def write(p, w, n):
    tmp = "%s.tmp.%d" % (p, os.getpid())
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump({"window": w, "n": n}, f)
    os.replace(tmp, p)


try:
    s = read(seatsf)
    t = read(teamf)
except ValueError as e:
    for p in (seatsf, teamf):
        if os.path.exists(p):
            try:
                os.replace(p, "%s.bad-%d" % (p, int(now)))
            except OSError:
                pass
    with open(os.path.join(sd, "_errors.log"), "a", encoding="utf-8") as f:
        f.write("%s corrupt seat=%s src=%s (%s)\n" % (time.strftime("%Y-%m-%dT%H:%M:%S", time.localtime(int(now))), seat, src, e))
    print("ERROR 예산 장부 손상 — 격리했고 이 호출은 budget")
    sys.exit(3)
sn = s[1] if s and s[0] == win else 0     # 새 시각 창 = 그 창 첫 예약부터 다시 센다(닫는 사건)
tn = t[1] if t and t[0] == win else 0
if sn >= smax:
    print("exhausted seat n=%d" % sn)
    sys.exit(3)
if tn >= tmax:
    print("exhausted team n=%d" % tn)
    sys.exit(3)
sn += 1
tn += 1
write(seatsf, win, sn)
write(teamf, win, tn)
with open(led, "a", encoding="utf-8") as f:
    f.write("%s seat=%s src=%s n=%d team=%s/%d win=%d\n"
            % (time.strftime("%Y-%m-%dT%H:%M:%S", time.localtime(int(now))), seat, src, sn, team, tn, win))
print("reserved n=%d team=%d" % (sn, tn))
PY
)" || rc=$?
  _wg_unlock "$sd"
  # 잠금은 «항상» 놓는다 — py 가 죽어도 다음 송신이 10초를 기다리지 않는다.
  # ★오류는 stdout(CLI 계약) + stderr(게이트가 stdout 을 잡아도 사유가 남는다) 두 곳에★ — 조용한 fail-closed 0.
  msg="${out:-ERROR 예산 판정 실패}"
  printf '%s\n' "$msg"
  case "$msg" in ERROR*) printf '%s\n' "$msg" >&2 ;; esac
  return "$rc"
}

wake_budget_refund() {
  local seat="$1" sd win out rc=0
  sd="$(_wg_state)/wake-budget"
  [ -d "$sd" ] || return 0
  win=$(( $(_wg_now) / 3600 ))
  if ! _wg_lock "$sd"; then
    _wg_errlog "lock-timeout refund seat=$seat"
    printf 'ERROR 예산 잠금 10초 초과(refund) — %s/.lock\n' "$sd" >&2
    return 1
  fi
  out="$(python3 - "$sd" "$(_wg_key "$seat")" "$(_wg_team "$seat")" "$win" <<'PY' 2>/dev/null
import json, os, sys
sd, seat, team, win = sys.argv[1:5]
win = int(win)


def bump(p):
    try:
        with open(p, encoding="utf-8") as f:
            d = json.load(f)
        w, n = d.get("window"), d.get("n")
    except Exception:
        return None
    if not isinstance(w, int) or not isinstance(n, int) or w != win or n <= 0:
        return None
    tmp = "%s.tmp.%d" % (p, os.getpid())
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump({"window": w, "n": n - 1}, f)
    os.replace(tmp, p)
    return n - 1


a = bump(os.path.join(sd, seat + ".json"))
b = bump(os.path.join(sd, "_team-%s.json" % team))
print("refunded n=%s team=%s" % (a, b))
PY
)" || rc=$?
  _wg_unlock "$sd"
  printf '%s\n' "${out:-refunded n=? team=?}"
  return "$rc"
}
