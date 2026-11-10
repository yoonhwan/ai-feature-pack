#!/usr/bin/env bash
# ft-resource-selflink-lib.sh — r589: 루트 clients/web/node_modules 안 «자기 자신을 가리키는 링크» 감시(감시자 본문 줄 수 상한 ≤245 때문에 lib 로 분리).
#   계기: 2026-10-21 루트 clients/web/node_modules/node_modules → 그 폴더 자신 심링크가 두 번(23:35 · 00:45) 생겨 루트 FE 를 쓰는 좌석이 500.
#   원리: `ln -s A B` 는 B 가 이미 폴더(또는 폴더로 가는 링크 · -n 없음)면 «B 안에» A 이름으로 링크를 만든다 → 손 명령 한 번이면 루트 안에 자기 링크.
#   ★지우기·자동 고침 0★ — 생기면 로그 1줄 + 서명(경로·대상)이 바뀔 때만 planner 명부 _master 에 쪽지 1통(«지우기: unlink …» 한 줄). 지우는 것은 사람.
selflink_watch() { # 감시자 tick 에서 호출 · 경로 = FT_RES_SELFLINK_PATH(시험용) 또는 <루트>/clients/web/node_modules/node_modules
  local p tgt sig sigf="$STATE/.selflink-node-modules.sig" seats route mbox cm
  p="${FT_RES_SELFLINK_PATH:-$RES_ROOT/clients/web/node_modules/node_modules}"
  [ -L "$p" ] || { rm -f "$sigf"; return 0; }   # 링크 없음 = 서명을 지운다 — 다음 발생은 새 사건(쪽지 다시 1통)
  tgt="$(readlink "$p" 2>/dev/null)"
  sig="$p|$tgt"; [ "$sig" != "$(cat "$sigf" 2>/dev/null)" ] || return 0
  logline "WARN node_modules 자기 링크 $p → $tgt"
  seats="${FT_SEATS_JSON:-$RES_ROOT/.fable-team/seats-planner.json}"
  route="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("_master",""))' "$seats" 2>/dev/null)"
  [ -n "$route" ] || { logline "ERROR 자기 링크 쪽지 수신자 없음(planner _master · $seats) — $p"; return 0; }
  mbox="${FT_MBOX_SH:-}"; [ -n "$mbox" ] || { . "$HERE/ft-harness-root.sh" && cm="$(ft_comm_dir "$HERE")" && mbox="$cm/mbox.sh"; } || { logline "ERROR 자기 링크 쪽지 우편함 못 풂"; return 0; }
  if bash "$mbox" send "$route" ft-resource-watch "[장비 정리] 루트 clients/web/node_modules 안 자기 링크 $p → $tgt · 루트 FE 500 원인 · 지우기: unlink $p" >/dev/null 2>>"$LOG"; then printf '%s\n' "$sig" > "$sigf"
  else logline "ERROR 자기 링크 쪽지 발신 실패 to=$route"; fi
}
