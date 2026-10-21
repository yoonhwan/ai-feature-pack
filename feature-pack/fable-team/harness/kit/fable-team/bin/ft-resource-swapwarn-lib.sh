#!/usr/bin/env bash
# ft-resource-swapwarn-lib.sh — r633: swap>FT_RES_SWAP_MAX ∧ level>=FT_SWAP_LEVEL_MIN 은 동결·REJECT 하지 않고(옛 동작 = FT_RES_SWAP_FREEZE=1) «닫아도 되는 유휴 좌석» 목록을 팀장에게 쪽지로(감시자 본문 줄 수 상한 ≤245 때문에 lib).
#   계기: 동결 10회 중 8회가 swap∧level 2(그때 memfree 30~36% · 3~5분 뒤 저절로 해제) — 그 사이 네 팀 spawn·교대가 막힘(골 6 «메모리 세션 제한으로 안 멈춰 있게» 충돌 · 10-19·10-21 · arch 115).
#   목록 = ft-resource-reclaim.sh --dry-run --preventive 출력의 WOULD-CLOSE 행만(승인 두 행 안 · HIL·SKIP 행 0 · 이 lib 는 닫기 0 — 닫기는 팀장).
#   수신자 = 그 좌석의 현역 명부 행이 있는 seats*.json 의 _master · 교대된 옛 세대는 `_replaced_by` 사슬 끝 명부의 _master(ft_stall_detect.load_teams·_lineage_master 와 같은 규칙 —
#     launchd python3 = 3.9 라 그 모듈(3.10 문법)을 import 하지 못해 여기 다시 적는다). 후보 0 팀엔 안 보냄.
#   중복 = 팀장별 서명(swap FT_RES_SWAPWARN_BAND_MIB(4096) 구간 · 좌석 목록)이 같으면 FT_RES_SWAPWARN_REPEAT_SEC(1800) 안에 다시 안 보냄 · 상태 .fable-team/state/swap-warn.json.
#   실패(회수 도구 rc≠0·상한 FT_RES_CLOSELIST_CAP_SEC(30) 초과 · 수신자 없음 · 쪽지 실패) = 감시 로그 ERROR 1줄 · 동결 0(막기로 폴백 0) · 쪽지 실패 팀은 서명 기록 0 → 다음 틱 재시도.
_SWAPWARN_PY="$(cat <<'PY'
import json, sys
from pathlib import Path
mode, root, state = sys.argv[1], Path(sys.argv[2]), Path(sys.argv[3])
try:
    st = json.loads(state.read_text(encoding="utf-8"))
except (OSError, ValueError):
    st = {}
if mode == "mark":
    st[sys.argv[4]] = {"sig": sys.argv[5], "ts": int(sys.argv[6])}
    tmp = state.with_name(state.name + ".tmp")
    tmp.write_text(json.dumps(st, ensure_ascii=False), encoding="utf-8")
    tmp.replace(state)
    sys.exit(0)
band, now, rep = int(sys.argv[4]), int(sys.argv[5]), int(sys.argv[6])
seats = sorted({c[0] for c in (ln.rstrip("\n").split(" | ") for ln in sys.stdin) if len(c) == 4 and c[3].startswith("WOULD-CLOSE")})
rows, live = {}, {}
for f in sorted((root / ".fable-team").glob("seats*.json")):
    try:
        d = json.loads(f.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        continue
    for k, v in d.items():
        if k.startswith("_") or not isinstance(v, dict):
            continue
        rows[k] = (d, v)
        if d.get("_master") and v.get("role") not in ("stop-ready", "closed") and not v.get("_replaced_by") and not v.get("_closed"):
            live.setdefault(k, d["_master"])
def master_of(s):
    if s in live:
        return live[s]
    end = s
    for _ in range(10):
        nxt = rows.get(end, ({}, {}))[1].get("_replaced_by")
        if not nxt or nxt not in rows:
            break
        end = nxt
    m = rows.get(end, rows.get(s, ({}, {})))[0].get("_master")
    return m if m and m != s else None
by = {}
for s in seats:
    m = master_of(s)
    if m:
        by.setdefault(m, []).append(s)
    else:
        print("ORPHAN\t" + s)
for m, ss in sorted(by.items()):
    sig = "%d|%s" % (band, " ".join(ss))
    old = st.get(m) or {}
    if old.get("sig") == sig and now - int(old.get("ts", 0)) < rep:
        continue
    print("SEND\t%s\t%s\t%s" % (m, " ".join(ss), sig))
PY
)"

swapwarn_send() { # $1=swap MiB $2=level — 감시자 tick 에서 swap 경고(그리고 FT_RES_SWAP_FREEZE≠1)일 때만 호출 · 언제나 rc0(동결 판정에 영향 0)
  local swap="$1" level="$2" out rc plan now band kind m ss sig mbox cm sent=0 wstate="$STATE/swap-warn.json"
  out="$(DU_CAP="${FT_RES_CLOSELIST_CAP_SEC:-30}" run_capped bash "${FT_RECLAIM_SH:-$HERE/ft-resource-reclaim.sh}" --dry-run --preventive)"; rc=$?
  [ "$rc" = 0 ] || { logline "ERROR swap 닫기 목록 회수 도구 rc=$rc$([ "$rc" = 124 ] && echo ' (상한 초과)') — 동결 0 · 쪽지 0"; return 0; }
  now="$(now_epoch)"; band=$((swap / ${FT_RES_SWAPWARN_BAND_MIB:-4096}))
  plan="$(printf '%s\n' "$out" | python3 -c "$_SWAPWARN_PY" plan "$RES_ROOT" "$wstate" "$band" "$now" "${FT_RES_SWAPWARN_REPEAT_SEC:-1800}")" || { logline "ERROR swap 닫기 목록 계산 실패 rc=$? — 동결 0 · 쪽지 0"; return 0; }
  [ -n "$plan" ] || return 0
  mbox="${FT_MBOX_SH:-}"; [ -n "$mbox" ] || { . "$HERE/ft-harness-root.sh" && cm="$(ft_comm_dir "$HERE")" && mbox="$cm/mbox.sh"; } || { logline "ERROR swap 닫기 목록 우편함 못 풂 — 동결 0"; return 0; }
  while IFS="$(printf '\t')" read -r kind m ss sig; do
    case "$kind" in
      ORPHAN) logline "ERROR swap 닫기 목록 수신자 없음 $m (명부 _master 못 찾음)";;
      SEND)
        if bash "$mbox" send "$m" ft-resource-watch "[자원 경고] swap ${swap}MiB level ${level} — 닫아도 되는 유휴 좌석: $ss · 팀장이 닫기(nano-close 경로) · 새 spawn 은 막지 않음" >/dev/null 2>>"$LOG"; then
          python3 -c "$_SWAPWARN_PY" mark "$RES_ROOT" "$wstate" "$m" "$sig" "$now" || logline "ERROR swap 닫기 목록 서명 기록 실패 to=$m"
          sent=$((sent + $(printf '%s\n' "$ss" | wc -w)))
        else logline "ERROR swap 닫기 목록 쪽지 발신 실패 to=$m"; fi;;
    esac
  done <<<"$plan"
  [ "$sent" = 0 ] || logline "WARN swap=${swap}M level=${level} close-list sent n=${sent} — 동결 0(r633 · 옛 동작 FT_RES_SWAP_FREEZE=1)"
  return 0
}
