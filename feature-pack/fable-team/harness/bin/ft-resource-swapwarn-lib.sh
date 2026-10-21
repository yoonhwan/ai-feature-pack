#!/usr/bin/env bash
# ft-resource-swapwarn-lib.sh — r633: swap>FT_RES_SWAP_MAX ∧ level>=FT_SWAP_LEVEL_MIN 은 동결·REJECT 하지 않고 «닫아도 되는 유휴 좌석» 목록을 팀장에게 쪽지로(감시자 본문 줄 수 상한 ≤245 때문에 lib).
#   FT_RES_SWAP_FREEZE=1 = swap 축만 옛 동작(swap∧level2 동결·REJECT · 쪽지 0) — level 4·disk·memfree 동결은 env 와 무관하게 그대로.
#   계기: 동결 10회 중 8회가 swap∧level 2(그때 memfree 30~36% · 3~5분 뒤 저절로 해제) — 그 사이 네 팀 spawn·교대가 막힘(골 6 «메모리 세션 제한으로 안 멈춰 있게» 충돌 · 10-19·10-21 · arch 115).
#   감시자는 hard 동결(disk·memfree·level 4) 판정·생성을 «먼저» 하고, hard 조건이 참인 틱엔 이 함수를 부르지 않는다(DA⑥ r1 ① · 쪽지가 동결을 늦추지 않게).
#   목록 = ft-resource-reclaim.sh --dry-run --preventive 출력의 WOULD-CLOSE 행만(승인 두 행 안 · HIL·SKIP 행 0 · 이 lib 는 닫기 0 — 닫기는 팀장).
#     요약 줄 `PREVENTIVE reclaimed=N …` 이 없거나 N ≠ WOULD-CLOSE 행 수(dry-run 은 reclaimed = WOULD-CLOSE 수) = «회수 출력 형식 깨짐» ERROR · rc3 · 쪽지 0 — «후보 0»(WARN) 과 다른 글.
#   수신자 = 그 좌석의 현역 명부 행(_replaced_by·_closed 없음 · role 이 stop-ready·closed 아님)이 있는 seats*.json 의 _master · 교대된 옛 세대는 `_replaced_by` 사슬 끝 좌석의 명부 _master
#     (ft_stall_detect.load_teams·_lineage_master 와 같은 규칙 — launchd python3 = 3.9 라 그 모듈(3.10 문법)을 import 못 해 여기 다시 적는다).
#     _master 가 둘 이상으로 갈림 · 사슬이 명부에 없는 이름으로 끊김 · 명부에 없음 = ORPHAN(로그 ERROR + 하네스 명부 _master 앞 묶음 1통) · 옛 _master 로 되돌아가 보내기 0. 후보 0 팀엔 안 보냄.
#   중복 = 팀장별 서명(swap FT_RES_SWAPWARN_BAND_MIB(4096) 구간 · 좌석 목록)이 같으면 FT_RES_SWAPWARN_REPEAT_SEC(1800) 안에 다시 안 보냄(후보 0 WARN·ORPHAN 묶음도 같은 규칙) · 상태 .fable-team/state/swap-warn.json
#     없음 = 첫 실행 · 있는데 깨짐·읽기 오류 = ERROR · 그 틱 발신 0 · 파일 덮어쓰기 0(사람이 보게 남김).
#   쪽지 1통 = 상한 FT_RES_SWAPWARN_SEND_CAP_SEC(7초 · 하드 룰 12) + 재시도 1 · 실패·상한 초과 = ERROR 1줄 · 서명 기록 0 → 다음 틱 재시도. 회수 도구 상한 = FT_RES_CLOSELIST_CAP_SEC(30초).
#   실패는 전부 감시 로그 ERROR 1줄 + rc≠0 · 동결 0(막기로 폴백 0).
_SWAPWARN_PY="$(cat <<'PY'
import json, re, sys
from pathlib import Path
mode, root, state = sys.argv[1], Path(sys.argv[2]), Path(sys.argv[3])
st = {}
if state.exists():
    try:
        st = json.loads(state.read_text(encoding="utf-8"))
    except (OSError, ValueError) as e:
        print("STATEBAD\t%s 읽기·파싱 실패: %s" % (state, str(e)[:80])); sys.exit(4)
    if not isinstance(st, dict) or not all(isinstance(v, dict) for v in st.values()):
        print("STATEBAD\t%s 형식 아님(객체의 객체)" % state); sys.exit(4)
if mode == "mark":
    st[sys.argv[4]] = {"sig": sys.argv[5], "ts": int(sys.argv[6])}
    tmp = state.with_name(state.name + ".tmp")
    tmp.write_text(json.dumps(st, ensure_ascii=False), encoding="utf-8")
    tmp.replace(state)
    sys.exit(0)
band, now, rep = int(sys.argv[4]), int(sys.argv[5]), int(sys.argv[6])
lines = sys.stdin.read().splitlines()
would = [c[0].strip() for c in (ln.split(" | ") for ln in lines) if len(c) == 4 and c[3].startswith("WOULD-CLOSE")]
summ = [m for m in (re.match(r"^PREVENTIVE reclaimed=(\d+) candidates=(\d+)", ln) for ln in lines) if m]
if not summ:
    print("BADOUT\t요약 줄(PREVENTIVE reclaimed=… candidates=…) 없음"); sys.exit(3)
if int(summ[-1].group(1)) != len(would):
    print("BADOUT\t요약 reclaimed=%s ≠ WOULD-CLOSE 행 %d" % (summ[-1].group(1), len(would))); sys.exit(3)
rows, harness_master = {}, None
for f in sorted((root / ".fable-team").glob("seats*.json")):
    try:
        d = json.loads(f.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        continue
    if not isinstance(d, dict):
        continue
    if f.name == "seats-harness.json":
        harness_master = d.get("_master")
    for k, v in d.items():
        if not k.startswith("_") and isinstance(v, dict):
            rows.setdefault(k, []).append((d, v))
def live(v):
    return v.get("role") not in ("stop-ready", "closed") and not v.get("_replaced_by") and not v.get("_closed")
def master_of(s):
    if s not in rows:
        return None, "명부에 없음"
    lm = {d.get("_master") for d, v in rows[s] if live(v) and d.get("_master")}
    if len(lm) > 1:
        return None, "_master 갈림(%s)" % ",".join(sorted(lm))
    if lm:
        m = lm.pop()
        return (m, "") if m != s else (None, "자기 자신이 _master")
    end = s
    for _ in range(10):
        nxt = {v.get("_replaced_by") for d, v in rows[end] if v.get("_replaced_by")}
        if not nxt:
            break
        if len(nxt) > 1:
            return None, "_replaced_by 갈림(%s)" % ",".join(sorted(nxt))
        nxt = nxt.pop()
        if nxt not in rows:
            return None, "_replaced_by 사슬 끊김(%s → %s 명부에 없음)" % (end, nxt)
        end = nxt
    em = {d.get("_master") for d, v in rows[end] if d.get("_master")}
    if len(em) != 1:
        return None, "사슬 끝 %s 의 _master %s" % (end, "갈림(" + ",".join(sorted(em)) + ")" if em else "없음")
    m = em.pop()
    return (m, "") if m != s else (None, "자기 자신이 _master")
def due(key, sig):
    old = st.get(key) or {}
    return not (old.get("sig") == sig and now - int(old.get("ts", 0)) < rep)
by, orph = {}, []
for s in sorted(set(would)):
    m, why = master_of(s)
    if m:
        by.setdefault(m, []).append(s)
    else:
        orph.append((s, why))
if not would and due("_none", "%d|" % band):
    print("NONE\t_none\t-\t%d|" % band)
if orph:
    sig = "%d|%s" % (band, " ".join(s for s, _ in orph))
    if due("_orphan", sig):
        for s, why in orph:
            print("ORPHAN\t%s\t%s\t-" % (s, why))
        print("ORPHANS\t%s\t%s\t%s" % (harness_master or "", " · ".join("%s(%s)" % o for o in orph), sig))
for m, ss in sorted(by.items()):
    sig = "%d|%s" % (band, " ".join(ss))
    if due(m, sig):
        print("SEND\t%s\t%s\t%s" % (m, " ".join(ss), sig))
PY
)"

_swapwarn_mail() { # $1=수신 $2=본문 → 7초 상한 + 재시도 1 · 성공 rc0 · 실패 = 마지막 rc
  local i rc=1
  for i in 1 2; do
    DU_CAP="${FT_RES_SWAPWARN_SEND_CAP_SEC:-7}" run_capped bash "$_SW_MBOX" send "$1" ft-resource-watch "$2" >/dev/null; rc=$?
    [ "$rc" != 0 ] || return 0
  done
  return "$rc"
}

_swapwarn_mark() { python3 -c "$_SWAPWARN_PY" mark "$RES_ROOT" "$_SW_STATE" "$1" "$2" "$3" >/dev/null || logline "ERROR swap 닫기 목록 서명 기록 실패 key=$1 — 다음 틱 재발신"; }

swapwarn_send() { # $1=swap MiB $2=level — 감시자 tick 에서 swap 경고 ∧ hard 동결 조건 0 ∧ FT_RES_SWAP_FREEZE≠1 일 때만 호출 · 실패 = ERROR 1줄 + rc≠0 (동결 판정에 영향 0)
  local swap="$1" level="$2" out rc plan now band kind m ss sig cm sent=0 err=0
  _SW_STATE="$STATE/swap-warn.json"
  out="$(DU_CAP="${FT_RES_CLOSELIST_CAP_SEC:-30}" run_capped bash "${FT_RECLAIM_SH:-$HERE/ft-resource-reclaim.sh}" --dry-run --preventive)"; rc=$?
  [ "$rc" = 0 ] || { logline "ERROR swap 닫기 목록 회수 도구 rc=$rc$([ "$rc" = 124 ] && echo ' (상한 초과)') — 동결 0 · 쪽지 0"; return 3; }
  now="$(now_epoch)"; band=$((swap / ${FT_RES_SWAPWARN_BAND_MIB:-4096}))
  plan="$(printf '%s\n' "$out" | python3 -c "$_SWAPWARN_PY" plan "$RES_ROOT" "$_SW_STATE" "$band" "$now" "${FT_RES_SWAPWARN_REPEAT_SEC:-1800}")"; rc=$?
  if [ "$rc" != 0 ]; then
    case "$plan" in
      BADOUT*) logline "ERROR swap 닫기 목록 회수 출력 형식 깨짐 — ${plan#BADOUT	} · 동결 0 · 쪽지 0";;
      STATEBAD*) logline "ERROR swap 닫기 목록 상태 파일 깨짐 — ${plan#STATEBAD	} · 발신 0 · 파일 그대로(사람 확인)";;
      *) logline "ERROR swap 닫기 목록 계산 실패 rc=$rc $(printf '%s' "$plan" | head -1 | cut -c1-120) — 동결 0 · 쪽지 0";;
    esac
    return 3
  fi
  [ -n "$plan" ] || return 0
  _SW_MBOX="${FT_MBOX_SH:-}"; [ -n "$_SW_MBOX" ] || { . "$HERE/ft-harness-root.sh" && cm="$(ft_comm_dir "$HERE")" && _SW_MBOX="$cm/mbox.sh"; } || { logline "ERROR swap 닫기 목록 우편함 못 풂 — 동결 0"; return 3; }
  while IFS="$(printf '\t')" read -r kind m ss sig; do
    case "$kind" in
      NONE) logline "WARN swap=${swap}M level=${level} close-list 후보 0(닫아도 되는 유휴 좌석 없음) — 동결 0"; _swapwarn_mark _none "$sig" "$now";;
      ORPHAN) logline "ERROR swap 닫기 목록 수신자 없음 $m — $ss · 옛 _master 로 보내기 0"; err=1;;
      ORPHANS)
        if [ -z "$m" ]; then logline "ERROR swap 닫기 목록 명부 이상 묶음 수신자 없음(seats-harness.json _master)"; err=1
        elif _swapwarn_mail "$m" "[자원 경고·명부 이상] swap ${swap}MiB level ${level} — 닫아도 되는 유휴 좌석인데 팀장을 못 정함: $ss · 명부 확인"; then _swapwarn_mark _orphan "$sig" "$now"
        else rc=$?; logline "ERROR swap 닫기 목록 명부 이상 묶음 발신 실패 to=$m rc=$rc$([ "$rc" = 124 ] && echo " (상한 ${FT_RES_SWAPWARN_SEND_CAP_SEC:-7}초 초과)") (재시도 1 포함)"; err=1; fi;;
      SEND)
        if _swapwarn_mail "$m" "[자원 경고] swap ${swap}MiB level ${level} — 닫아도 되는 유휴 좌석: $ss · 팀장이 닫기(nano-close 경로) · 새 spawn 은 막지 않음"; then
          _swapwarn_mark "$m" "$sig" "$now"; sent=$((sent + $(printf '%s\n' "$ss" | wc -w)))
        else rc=$?; logline "ERROR swap 닫기 목록 쪽지 발신 실패 to=$m rc=$rc$([ "$rc" = 124 ] && echo " (상한 ${FT_RES_SWAPWARN_SEND_CAP_SEC:-7}초 초과)") (재시도 1 포함)"; err=1; fi;;
    esac
  done <<<"$plan"
  [ "$sent" = 0 ] || logline "WARN swap=${swap}M level=${level} close-list sent n=${sent} — 동결 0(r633 · swap 축 옛 동작 FT_RES_SWAP_FREEZE=1)"
  [ "$err" = 0 ] || return 3
  return 0
}
