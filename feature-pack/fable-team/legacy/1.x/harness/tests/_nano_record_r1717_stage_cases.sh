#!/usr/bin/env bash
# _nano_record_r1717_stage_cases.sh — r1717 단계 사례 함수 e1~e8·e8r(사례 아님 · source 전용 · 실행 비트 0).
#   부르는 파일: test_nano_record_stage_r1717.sh(사례) · test_nano_record_stage_mut_r1717.sh(변이 대조) — 먼저 _nano_record_r1717_fixture.sh · _nano_record_r1717_close_fixture.sh 를 source 하고 world; closebin.
#   사례 함수 = `eN <꼬리표>` → rc 0 통과(하위 셸 1개에서 돈다 · 꼬리표로 카드 stem 을 가른다 — 변이 대조가 같은 사례를 두 번 더 돌린다)
NN() { printf 'byz-harness-nano-%s#0' "$1"; }
TST='bash tests/t.sh rc=0'
landed() { rec landed --seat "$1" --pr "$2" --card "$3" "${@:4}"; }
nreq() { nto "$MASTER" "\[완료·닫기 요청\] $1 "; }   # 그 카드의 닫기 요청 수(팀장이 받은 것)
ncl() { grep -c . "$NC_LOG" || true; }               # 가짜 닫기 도구가 불린 수
export REAL_GIT GITFAIL_F="$T/gitfail.n"; REAL_GIT="$(command -v git)"; mkdir -p "$T/gw"
cat > "$T/gw/git" <<'EOF'
#!/usr/bin/env bash
# E3 ⓐ 주입 — GITFAIL_N 번째 «fetch» 만 실패(그 밖은 진짜 git 그대로)
case " $* " in *" fetch "*) n=$(( $(cat "$GITFAIL_F" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$GITFAIL_F"
  [ "$n" != "${GITFAIL_N:-0}" ] || { echo "fatal: 주입 — fetch 실패" >&2; exit 128; };; esac
exec "$REAL_GIT" "$@"
EOF
chmod +x "$T/gw/git"

e1() {  # E1 (R1 반례 1) 착지 줄만 있는 카드 → 차례(끝 아님) → 세트·완료 2줄만 보충
  local s="e1$1" n; n="$(NN "e1$1")"; fresh; land 31; card "$s" "$(landl 31)"; seats "$n|nano|$s"; turn 31 "$s"
  rec due --pr 31; t "E1 due 차례 빠짐=ⓢⓒ(끝 아님)" inc "$OUT" "차례 $n 종류=닫기 빠짐=ⓢⓒ 카드=$s"; t "E1 끝 0" exc "$OUT" "끝 "
  rec notify --pr 31; t "E1 notify 1통" [ "$(nto "$n" "\[정리 차례\] $s .*빠짐 ⓢⓒ")" = 1 ]
  landed "$n" 31 "$s" --test "$TST"; t "E1 DONE" inc "$OUT" "DONE"
  t "E1 세트·완료만 더함(착지 줄 1개 그대로)" [ "$(nline "$s" "^- 세트: ")$(nline "$s" "^- 착지: ")$(nline "$s" "^- 완료: $n ")" = 111 ]; t "E1 닫기 요청 1통" [ "$(nreq "$s")" = 1 ]; return $E
}
e2() {  # E2 (R1 반례 2) 남은 일 나노 몫 = 기록만 남기고 닫기 요청 0 → 끝낸 뒤 다시 = 새 완료 줄 + 닫기 요청 · 팀장 인계 = 처음부터 닫기 요청
  local s="e2$1" u="e2u$1" n m; n="$(NN "e2$1")"; m="$(NN "e2u$1")"; fresh; land 32; cardf "$s"; cardf "$u"; cpush; seats "$n|nano|$s" "$m|nano|$u"; turn 32 "$s" "$u"
  landed "$n" 32 "$s" --test "$TST" --left "보정=$n"; t "E2 DONE rc0" [ "$RC" = 0 ]; t "E2 NEXT 0" exc "$OUT" "NEXT "
  t "E2 기록 3줄(완료 줄에 남은 일)" [ "$(nline "$s" "^- 세트: ")$(nline "$s" "^- 착지: ")$(nline "$s" "^- 완료: $n · 병합 상태: 착지 ${Q:0:10} · 남은 일: 보정=$n ")" = 111 ]
  t "E2 닫기 요청 0" [ "$(nreq "$s")" = 0 ]; t "E2 팀장 «[기록 완료 · 남은 일]» 1통" [ "$(nto "$MASTER" "\[기록 완료 · 남은 일\] $n $s — 보정=$n · 닫기 요청 0")" = 1 ]
  rec due --pr 32; t "E2 due 끝(남은 일 — 닫기 요청 0)" inc "$OUT" "끝 $s pr=32 착지=${Q:0:10} 좌석=$n (남은 일 — 닫기 요청 0)"
  cdue; t "E2 close-due 자리표시 그대로 + 빠짐" inc "$OUT" "$n --landed-pr 32 --result <산출> --recv <seq> 빠짐=남은 일(보정=$n) 채울 이=$n"; scan auto; t "E2 auto_close 집행 0" [ "$(ncl)" = 0 ]
  landed "$n" 32 "$s"; t "E2 다시 실행 = 완료 줄 1개 더(남은 일: 없음)" [ "$(nline "$s" "^- 완료: $n ")$(nline "$s" "남은 일: 없음 ")" = 21 ]
  t "E2 닫기 요청 1통" [ "$(nreq "$s")" = 1 ]; t "E2 NEXT" inc "$OUT" "NEXT bash ft-nano-close.sh $n --landed-pr 32 --result "
  landed "$m" 32 "$u" --test "$TST" --left "설치=팀장"; t "E2 팀장 인계(잔여 없음) = 처음부터 닫기 요청 1통" [ "$(nreq "$u")" = 1 ]; t "E2 팀장 인계 NEXT" inc "$OUT" "NEXT "; return $E
}
e3() {  # E3 (R1 반례 3) ⓐ push 는 됐고 확인 fetch 실패 ⓑ 닫기 요청 발신 실패 → 밀림 → 점검이 보냄 ⓒ ⓑ 에서 landed 다시 = ALREADY + 닫기 요청 + NEXT
  local a="e3a$1" b="e3b$1" c="e3c$1" na nb nc c0; na="$(NN "e3a$1")"; nb="$(NN "e3b$1")"; nc="$(NN "e3c$1")"; fresh; land 33; for s in "$a" "$b" "$c"; do cardf "$s"; done; cpush
  seats "$na|nano|$a" "$nb|nano|$b" "$nc|nano|$c"; turn 33 "$a" "$b" "$c"; c0="$(ncommit)"; echo 0 > "$GITFAIL_F"
  PATH="$T/gw:$PATH" GITFAIL_N=2 landed "$na" 33 "$a" --test "$TST"; t "E3ⓐ 확인 실패 = rc 3" [ "$RC" = 3 ]; t "E3ⓐ DONE 0" exc "$OUT" "DONE"; t "E3ⓐ 판정 불가 줄" inc "$OUT" "판정 불가 "
  t "E3ⓐ push 는 반영됨" [ "$(ncommit)" = "$((c0 + 1))" ]; t "E3ⓐ 닫기 요청 0" [ "$(nreq "$a")" = 0 ]
  landed "$na" 33 "$a" --test "$TST"; t "E3ⓐ 다시 실행 = 커밋·push 0(ALREADY)" [ "$(ncommit) ${OUT%%$'\n'*}" = "$((c0 + 1)) ALREADY" ]; t "E3ⓐ 확인부터 이어 닫기 요청 1통" [ "$(nreq "$a")" = 1 ]
  MBOX_FAIL_HEAD='[완료·닫기 요청]' landed "$nb" 33 "$b" --test "$TST"; t "E3ⓑ WARN 1줄" [ "$(printf '%s\n' "$OUT" | grep -c '^WARN 쪽지 발신 실패')" = 1 ]; t "E3ⓑ NEXT 0 · rc 3" [ "$RC" = 3 ]
  t "E3ⓑ 전달 기록 0" [ "$(grep -c "$nb|$b|" "$STATE/land-record-notified.json")" = 0 ]; rec due --pr 33; t "E3ⓑ due 닫기 요청 밀림" inc "$OUT" "닫기 요청 밀림 $nb 카드=$b"
  MBOX_FAIL_HEAD='[완료·닫기 요청]' landed "$nc" 33 "$c" --test "$TST"; landed "$nc" 33 "$c" --test "$TST"
  t "E3ⓒ landed 다시 = ALREADY + 닫기 요청 1통 + NEXT" [ "${OUT%%$'\n'*} $(nreq "$c")" = "ALREADY 1" ]; t "E3ⓒ NEXT" inc "$OUT" "NEXT bash ft-nano-close.sh $nc "
  scan notify; t "E3ⓑ 점검 사본의 notify 가 팀장에 1통" [ "$(nreq "$b")" = 1 ]; scan notify; t "E3ⓑ 그 뒤 호출 = 0통" [ "$(nreq "$b")" = 1 ]; return $E
}
e4() {  # E4 (R1 · A16) 자동 닫기 REJECT → 같은 rec 재집행 0 → refused → 기록 보충(rec 바뀜) → 닫기 요청 다시 1통 · 1회 다시 집행 · 옛 꼴 상태값
  local s="e4$1" n; n="$(NN "e4$1")"; fresh; land 34; card "$s"; seats "$n|nano|$s"; turn 34 "$s"; landed "$n" 34 "$s" --test "$TST"
  NC_RC=1 scan auto; t "E4 1회 집행(REJECT)" [ "$(ncl)" = 1 ]; t "E4 실패 로그" inc "$OUT" "auto-close 실패 $n rc=1 갈래=착지기록"
  NC_RC=1 scan auto; t "E4 같은 rec 다음 회차 집행 0" [ "$(ncl)" = 1 ]
  landed "$n" 34 "$s" --test "$TST"; NC_RC=1 scan auto; t "E4 rec 그대로인 재실행 = 재발신 0 · 재집행 0" [ "$(nreq "$s") $(ncl)" = "1 1" ]
  rec refused --seat "$n" --cause "REJECT $n"$'\n'"  - ⑥ 증거 줄 없음"; t "E4 refused 1회" inc "$OUT" "REFUSED $n 1회째"
  landed "$n" 34 "$s" --left "설치=팀장"; t "E4 기록 보충(rec 바뀜) → 닫기 요청 다시 1통" [ "$(nreq "$s")" = 2 ]
  NC_RC=1 scan auto; t "E4 새 rec = 1회 다시 집행" [ "$(ncl)" = 2 ]; NC_RC=1 scan auto; t "E4 그 뒤 재집행 0" [ "$(ncl)" = 2 ]
  printf '{"%s": "%s"}' "$n" "$PH" > "$T/scanst/nano-auto-close.json"; scan auto; t "E4 옛 꼴 상태값(set 만) = 새 rec 에서 1회 집행" [ "$(ncl)" = 3 ]; return $E
}
e5() {  # E5 시험 실패를 완료로 적지 않는다
  local s="e5$1" n c0; n="$(NN "e5$1")"; fresh; land 35; card "$s"; seats "$n|nano|$s"; turn 35 "$s"; c0="$(ncommit)"
  landed "$n" 35 "$s" --test "pytest rc=1"; t "E5 landed rc=1 → REJECT" [ "$RC" = 1 ]; t "E5 사유" inc "$OUT" "시험 rc≠0 — 통과한 시험만 세트 줄에 적는다"
  rec due --pr 35; t "E5 due 차례 그대로" inc "$OUT" "차례 $n 종류=닫기 빠짐=ⓢⓛⓒ"
  rec done --seat "$n" --card "$s" --did "x" --test "pytest -q rc=1" --wt "$PACK"; t "E5 done rc=1 → REJECT" [ "$RC" = 1 ]; t "E5 done 사유" inc "$OUT" "REJECT 시험 rc≠0"
  landed "$n" 35 "$s" --test "<그 세트에서 돌린 시험 명령> rc=0"; t "E5 쪽지 견본 그대로 = REJECT(--test 이름)" inc "$OUT" "REJECT --test 자리표시 그대로"
  t "E5 쓰기 0 · 커밋 0" [ "$(ncommit)" = "$c0" ]; return $E
}
e6() {  # E6 (R2) 세션 기록 파일을 못 씀 → NEXT 0 · 닫기 명령 보류 · rc 3 · close-due 자리표시 그대로 · 집행 0
  local s="e6$1" n; n="$(NN "e6$1")"; fresh; land 36; card "$s"; seats "$n|nano|$s"; turn 36 "$s"
  MUTSRC="$BIN" mutbin "e6w$1" ft_nano_record_notify.py "${WFAIL[@]}"; TOOL="$MB/ft-nano-record.sh"
  landed "$n" 36 "$s" --test "$TST"; t "E6 rc 3" [ "$RC" = 3 ]; t "E6 NEXT 0" exc "$OUT" "NEXT "; t "E6 판정 불가 세션 기록" inc "$OUT" "판정 불가 세션 기록 쓰기"
  t "E6 닫기 명령 보류 1줄" [ "$(printf '%s\n' "$OUT" | grep -c "^닫기 명령 보류 빠짐=세션 기록·닫기 요청 seq 채울 이=$n(landed 를 다시)")" = 1 ]; t "E6 닫기 요청 0" [ "$(nreq "$s")" = 0 ]
  cdue; t "E6 close-due 자리표시 그대로 + 빠짐" inc "$OUT" "$n --landed-pr 36 --result <산출> --recv <seq> 빠짐=닫기 요청 전달 채울 이=$n"; scan auto; t "E6 집행 0" [ "$(ncl)" = 0 ]; return $E
}
e7() {  # E7 (R3 동시) 다른 카드 2장 · 같은 카드에 좌석 2 → 둘 다 DONE · 줄 유실·중복 0
  local a="e7a$1" b="e7b$1" c="e7c$1" c0 k; fresh; land 37; for s in "$a" "$b" "$c"; do cardf "$s"; done; cpush
  seats "$(NN "e7a$1")|nano|$a" "$(NN "e7b$1")|nano|$b" "$(NN "e7c$1")|nano|$c" "$(NN "e7d$1")|nano|$c"; turn 37 "$a" "$b" "$c"; c0="$(ncommit)"
  ( cd "$T" && bash "$TOOL" landed --seat "$(NN "e7a$1")" --pr 37 --card "$a" --test "$TST" > "$T/e7.1" 2>&1 ) &   # bg-ok: 동시 landed 2개 — 아래 wait 가 거둔다
  ( cd "$T" && bash "$TOOL" landed --seat "$(NN "e7b$1")" --pr 37 --card "$b" --test "$TST" > "$T/e7.2" 2>&1 ) &   # bg-ok: 동시 landed 2개 — 아래 wait 가 거둔다
  wait; t "E7 다른 카드 2장 둘 다 DONE" [ "$(sed -n 1p "$T/e7.1")$(sed -n 1p "$T/e7.2")" = DONEDONE ]; t "E7 원격에 커밋 2개" [ "$(ncommit)" = "$((c0 + 2))" ]
  for k in 'ops/base' 'ops/base^'; do t "E7 커밋마다 바뀐 경로 1개($k)" [ "$(g "$CREM" diff-tree --no-commit-id --name-only -r "$k" | grep -c .)" = 1 ]; done
  t "E7 줄 유실 0" [ "$(nline "$a" "^- 완료: ")$(nline "$b" "^- 완료: ")" = 11 ]
  ( cd "$T" && bash "$TOOL" landed --seat "$(NN "e7c$1")" --pr 37 --card "$c" --test "$TST" > "$T/e7.3" 2>&1 ) &   # bg-ok: 같은 카드에 좌석 2 — 아래 wait 가 거둔다
  ( cd "$T" && bash "$TOOL" landed --seat "$(NN "e7d$1")" --pr 37 --card "$c" --test "$TST" > "$T/e7.4" 2>&1 ) &   # bg-ok: 같은 카드에 좌석 2 — 아래 wait 가 거둔다
  wait; t "E7 같은 카드 좌석 2 둘 다 DONE" [ "$(sed -n 1p "$T/e7.3")$(sed -n 1p "$T/e7.4")" = DONEDONE ]; t "E7 커밋 2개 더" [ "$(ncommit)" = "$((c0 + 4))" ]
  t "E7 줄 유실·중복 0(세트 1 · 착지 1 · 완료 좌석마다 1)" [ "$(nline "$c" "^- 세트: ")$(nline "$c" "^- 착지: ")$(nline "$c" "^- 완료: $(NN "e7c$1") ")$(nline "$c" "^- 완료: $(NN "e7d$1") ")" = 1111 ]; return $E
}
e8() {  # E8 ⓐ role=arch 좌석 줄 → 집행 0 ⓑ 조상 아님 → 집행 0 · 알림 1 ⓓ rc 124 = [크리티컬] 도구 1회(없으면 팀장 1통) · rc 1 = 직접 알림 0
  local s="e8$1" n L was; n="$(NN "e8$1")"; fresh; land 38; card "$s"; seats "$n|nano|$s"; turn 38 "$s"; landed "$n" 38 "$s" --test "$TST"
  cdue; L="$(printf '%s\n' "$OUT" | grep "^닫기 차례 $n ")"; printf '#!/bin/sh\ncat "%s"\n' "$T/due.line" > "$T/fdue.sh"
  storeset close "$ARCH|$s|$Q" "{\"rec\":\"aaaaaaaaaaaa\",\"seq\":100,\"result\":\"$STATE/seat-record/$n.md\",\"pr\":38}"
  echo "닫기 차례 $ARCH 팀=harness 가지=x landed=squash main=abc 갈래=착지기록 rec=aaaaaaaaaaaa set=$PH — bash ft-nano-close.sh $ARCH --landed-pr 38 --result $STATE/seat-record/$n.md --recv 100" > "$T/due.line"
  DUE="$T/fdue.sh" scan auto; t "E8ⓐ 역할 로그" inc "$OUT" "판정 불가 auto-close 역할 $ARCH role=arch — 집행 0"; t "E8ⓐ 집행 0" [ "$(ncl)" = 0 ]
  printf '%s\n' "$L" > "$T/due.line"; was="$(g "$PACK" rev-parse refs/remotes/origin/main)"; g "$PACK" update-ref refs/remotes/origin/main "$Q^"
  DUE="$T/fdue.sh" scan auto; g "$PACK" update-ref refs/remotes/origin/main "$was"
  t "E8ⓑ 조상 아님 → 집행 0" [ "$(ncl)" = 0 ]; t "E8ⓑ 로그" inc "$OUT" "auto-close 실패 $n 갈래=착지기록 — 착지 sha ${Q:0:10} 조상 확인 rc=1 · 집행 0"; t "E8ⓑ 알림 1통" [ "$(grep -c "^ft-stall-scan $n --event auto-close:" "$CRIT_LOG")" = 1 ]
  rm -f "$T/scanst/nano-auto-close.json"; : > "$CRIT_LOG"; NC_RC=124 scan auto; t "E8ⓓ rc 124 → 가짜 ft-critical-notify 1회" [ "$(ncl) $(grep -c . "$CRIT_LOG")" = "1 1" ]
  rm -f "$T/scanst/nano-auto-close.json"; : > "$CRIT_LOG"; FT_CRITICAL_NOTIFY="$T/없는-도구" NC_RC=124 scan auto; t "E8ⓓ 도구 없음 → 팀장 «[자동 닫기 실패]» 1통" [ "$(nto "$MASTER" "\[자동 닫기 실패\] $n rc=124 ")" = 1 ]
  rm -f "$T/scanst/nano-auto-close.json"; : > "$CRIT_LOG"; : > "$MBOX_LOG"; NC_RC=1 scan auto
  t "E8ⓓ rc 1 REJECT = auto_close 가 직접 보내는 알림 0" [ "$(ncl) $(grep -c . "$CRIT_LOG") $(nsent "자동 닫기 실패")" = "3 0 0" ]; return $E
}
e8r() {  # E8 ⓒⓔ «실» 닫기 도구 사본을 auto_close 가 집행 → 그 좌석 kill 1회 · 가지 그대로 · 원장 +1 · 로그 1줄
  local s="e8r$1" n r0 l0; n="$(NN "e8r$1")"; fresh; land 39; card "$s"; seats "$n|nano|$s" "$(NN other)|nano|x"; turn 39 "$s"; landed "$n" 39 "$s" --test "$TST"
  nwt "$s"; export FAKE_CWD="$NW"; CLOSE_LIVE=1 cprep "$n"; r0="$(g "$ROOT" for-each-ref refs/heads; g "$CREM" for-each-ref; g "$PREM" for-each-ref; g "$PACK" for-each-ref refs/heads)"; l0="$(grep -c . "$NLEDGER" || true)"; : > "$TMUX_LOG"
  FT_NANO_CLOSE="$NCREAL" scan auto; t "E8ⓔ 로그 «auto-close CLOSED … 갈래=착지기록» 1줄" [ "$(printf '%s\n' "$OUT" | grep -c "auto-close CLOSED $n landed-pr=39 .* 갈래=착지기록 rec=")" = 1 ]
  t "E8ⓒ tmux kill = 그 좌석 1회 · 다른 세션 0" [ "$(grep -c '^kill-session' "$TMUX_LOG") $(grep -c '^kill-session -t %1$' "$TMUX_LOG") $(grep -c '^kill-server' "$TMUX_LOG")" = "1 1 0" ]
  t "E8ⓒ 나노 가지 ref(로컬·원격) 그대로" [ "$(g "$ROOT" for-each-ref refs/heads; g "$CREM" for-each-ref; g "$PREM" for-each-ref; g "$PACK" for-each-ref refs/heads)" = "$r0" ]
  t "E8ⓔ 나노 원장 행 +1" [ "$(grep -c . "$NLEDGER")" = "$((l0 + 1))" ]; t "E8ⓔ 원장 행 꼴" inc "$(tail -1 "$NLEDGER")" "\`$n\` 닫힘(ft-nano-close)"; return $E
}
