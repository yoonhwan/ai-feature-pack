#!/usr/bin/env bash
# ft-resource-proc-lib.sh — r1041: 사용자 프로세스 수 경보 + 같은 명령줄 프로세스만 SIGSTOP (ft-resource-watch.sh tick 이 proc_watch 1회로 부른다).
#   계기: 2026-10-28 10:4x 나노 r1038 시험이 자기 파일을 가드 없이 다시 불러 fork 폭주 → kern.maxprocperuid(6000) 도달,
#         전 좌석 셸이 fork 실패(planner rc1 · arch #168 · 그 이름 프로세스 4750개). 감시자는 CPU(r522)만 보고 있었고 «프로세스 수» 칸이 없었다.
#   판정 2축(서로 독립):
#     ⓐ 사용자 프로세스 수 ≥ FT_RES_PROC_MAX(4000) → planner 명부 _master 에 [프로세스 폭주] 쪽지 1통(r522 와 같은 서명 규칙 · 같은 사건이면 다시 안 보냄 · 끝나면 서명 지움)
#     ⓑ 같은 명령줄이 ≥ FT_RES_PROC_DUP(200) 개 → 그 명령줄 프로세스만 SIGSTOP(다른 프로세스 0 · kill 0 · 풀기 = SIGCONT · 정리 kill 은 쪽지에 «HIL» 로 적는다)
#   ps 는 1회(ps -axo user=,pid=,command=) — 사용자 행만 센다. 시험용 env: FT_RES_PROC_PS(ps 표본 파일 — 실 프로세스 증가 0) ·
#     FT_RES_PROC_USER(사용자 이름) · FT_RES_KILL_CMD(정지 명령 · 기본 kill) · FT_RES_PROC_QUIET_SEC(쪽지 억제 창 · 기본 600)
#   R8: ps 조회 실패 = 쪽지 0 · 정지 0 · 로그 ERROR 1줄(«판정 불가») — 조용한 통과 0(하드 룰 20).
proc_ps_out() {   # 표본 1회 — 시험은 파일 한 장으로 갈음한다
  if [ -n "${FT_RES_PROC_PS:-}" ]; then cat -- "$FT_RES_PROC_PS" 2>/dev/null; return $?; fi
  ps -axo user=,pid=,command= 2>/dev/null
}

# 사용자 행만 «명령줄 개수» 로 접는다 — 출력 1줄: <개수>\t<명령줄>
proc_group() {    # <표본> <사용자>
  printf '%s\n' "$1" | awk -v me="$2" '
    $1==me { c=""; for(i=3;i<=NF;i++) c=c (i>3?" ":"") $i; if(c=="") c="?"; n[c]++ }
    END { for(k in n) printf "%d\t%s\n", n[k], k }' | sort -rn | head -1
}

# 그 명령줄의 pid 만 — 정지 대상(다른 명령줄 0)
proc_pids() {     # <표본> <사용자> <명령줄>
  printf '%s\n' "$1" | awk -v me="$2" -v want="$3" '
    $1==me { c=""; for(i=3;i<=NF;i++) c=c (i>3?" ":"") $i; if(c=="") c="?"; if(c==want) print $2 }'
}

proc_watch() {
  local out rc me max dup quiet sigf lastf killc grp tn tc sig k p sent stops body route seats mbox cm
  max="${FT_RES_PROC_MAX:-4000}"; dup="${FT_RES_PROC_DUP:-200}"; quiet="${FT_RES_PROC_QUIET_SEC:-600}"
  case "$max" in ''|*[!0-9]*) logline "WARN FT_RES_PROC_MAX=$max 무효 — 기본 4000"; max=4000;; esac
  case "$dup" in ''|*[!0-9]*) logline "WARN FT_RES_PROC_DUP=$dup 무효 — 기본 200"; dup=200;; esac
  case "$quiet" in ''|*[!0-9]*) quiet=600;; esac
  me="${FT_RES_PROC_USER:-$(id -un)}"
  out="$(proc_ps_out)"; rc=$?
  [ "$rc" = 0 ] && [ -n "$out" ] || { logline "ERROR 프로세스 수 판정 불가(ps rc=$rc) — 쪽지 0 · 정지 0"; return 0; }
  sigf="$STATE/.proc-flood.sig"; lastf="$STATE/.proc-flood.last"
  k="$(printf '%s\n' "$out" | awk -v me="$me" '$1==me{c++} END{print c+0}')"
  grp="$(proc_group "$out" "$me")"; tn="${grp%%	*}"; tc="${grp#*	}"
  case "$tn" in ''|*[!0-9]*) tn=0; tc="";; esac
  sig=""
  [ "$k" -ge "$max" ] && sig="total=${max}"
  [ "$tn" -ge "$dup" ] && sig="${sig:+$sig/}cmd=${tc}:${tn}"
  [ -n "$sig" ] || { rm -f "$sigf"; return 0; }             # 폭주가 끝나면 서명을 지운다 — 다음 폭주는 새 사건
  [ "$sig" != "$(cat "$sigf" 2>/dev/null)" ] || return 0    # 같은 서명 = 같은 사건(쪽지 0 · 정지 0)
  printf '%s\n' "$sig" > "$sigf"
  body="프로세스 ${k} 개(임계 ${max})"
  stops=""
  if [ "$tn" -ge "$dup" ]; then
    killc="${FT_RES_KILL_CMD:-kill}"; sent=0
    for p in $(proc_pids "$out" "$me" "$tc"); do
      $killc -STOP "$p" 2>/dev/null && sent=$((sent+1)) || true
    done
    stops="같은 명령줄 «${tc}» ×${tn} → 그 프로세스만 SIGSTOP ${sent}개(다른 프로세스 0) · 풀기 = SIGCONT <pid>"
    printf '%s\t%s\t%s\n' "$(now_utc)" "$tn" "$tc" >> "$STATE/proc-flood.log"
  fi
  body="$body${stops:+ · $stops}"
  route=""; seats="${FT_SEATS_JSON:-$RES_ROOT/.fable-team/seats-planner.json}"
  route="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("_master",""))' "$seats" 2>/dev/null)"
  [ -n "$route" ] || { logline "ERROR [프로세스 폭주] 쪽지 수신자 없음(planner _master · $seats) — $body"; return 0; }
  mbox="${FT_MBOX_SH:-}"; [ -n "$mbox" ] || { . "$HERE/ft-harness-root.sh" && cm="$(ft_comm_dir "$HERE")" && mbox="$cm/mbox.sh"; } || { logline "ERROR [프로세스 폭주] 쪽지 우편함 못 풂"; return 0; }
  local now; now="$(now_epoch)"; local last=0; [ -f "$lastf" ] && last="$(cat "$lastf" 2>/dev/null)"
  case "$last" in ''|*[!0-9]*) last=0;; esac
  if [ $((now-last)) -lt "$quiet" ]; then logline "[프로세스 폭주] 쪽지 억제(최근 $((now-last))s 내 1통 · 서명 $sig) — $body"; return 0; fi
  if bash "$mbox" send "$route" ft-resource-watch "[프로세스 폭주] $body · 정리 kill 은 HIL · 끄기는 사람 판단" >/dev/null 2>>"$LOG"; then
    printf '%s\n' "$now" > "$lastf"
  else logline "ERROR [프로세스 폭주] 쪽지 발신 실패 to=$route"; fi
}
