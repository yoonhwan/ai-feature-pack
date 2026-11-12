#!/usr/bin/env bash
# test_nano_record_r1717.sh — r1717 묶음 1: ft-nano-record.sh 도구 사례 ③~⑧·⑪~⑳ + 변이 M2·M3·M4·M5·M6·M8·M9·M16(변이마다 원본 대조) + 기준판 ⑭.
#   착지 꼬리 사례 ①②⑧(꼬리)⑨⑩ + M1 + 기준판 ① = test_nano_record_land_r1717.sh · 단계 E1~E8 = test_nano_record_stage_r1717.sh · 묶음 2 D1~D5 = test_nano_record_done_r1717.sh
#   세계 = _nano_record_r1717_fixture.sh(임시 bare remote 2 · 사본 리포 2 · 가짜 명부·mbox·tmux) · ⑭·⑲ 의 닫기 = «실» ft-nano-close.sh 사본(_nano_record_r1717_close_fixture.sh)
#   실 명부·실 우편함·실 tmux·네트워크 0 · sleep 0 · 자기 파일 재호출 0 · 사례 = 하위 셸 1개(사례마다 새 카드 stem)
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$HERE/_nano_record_r1717_fixture.sh"; . "$HERE/_nano_record_r1717_close_fixture.sh"
NN() { printf 'byz-harness-nano-%s#0' "$1"; }   # 좌석 이름(카드 stem 과 같은 key)
TST='bash tests/t.sh rc=0'
landed() { rec landed --seat "$1" --pr "$2" --card "$3" "${@:4}"; }

step "사전: 문법 · 짝 사본 · 줄 수"
for f in ft-nano-record.sh ft_nano_record.py ft_nano_record_due.py ft_nano_record_notify.py ft_nano_record_write.py ft_nano_record_done.py ft_nano_record_auto.py ft-nano-close-due.sh ft_stall_scan.py; do
  cmp -s "$SRC/$f" "$KIT/$f" && ok "짝 사본 bin·kit cmp0 $f" || bad "짝 사본 다름 $f"
  case "$f" in ft_nano_record*|ft-nano-record.sh) [ "$(wc -l < "$SRC/$f")" -le 200 ] && ok "≤200줄 $f" || bad "200줄 넘음 $f";; esac
done
bash -n "$SRC/ft-nano-record.sh" && /bin/bash -n "$SRC/ft-nano-record.sh" && bash -n "$SRC/ft-nano-close-due.sh" && ok "bash -n(/bin/bash 3.2 포함)" || bad "bash -n"
world; closebin

c3() {  # ③ 나노 없음(tmux 세션 없음 · stop-ready 행) → 주인 없음 · cards:[] → 카드 없음 · settle
  local s="c3$1" n; n="$(NN "c3$1")"; fresh; land 3; card "$s"; seats "$n|nano|$s"; dead "$n"; turn 3 "$s"
  rec due --pr 3; t "③ due 주인 없음(끝 아님)" inc "$OUT" "주인 없음 $s 담당=$MASTER 빠짐=ⓢⓛ"; t "③ due rc0" [ "$RC" = 0 ]
  rec notify --pr 3; t "③ 팀장 1통" [ "$(nto "$MASTER" "\[정리 차례 · 주인 없음\] $s ")" = 1 ]; t "③ 나노 발신 0" [ "$(nto "$n")" = 0 ]
  rec notify --pr 3; t "③ notify 한 번 더 = 0통" [ "$(nto "$MASTER")" = 1 ]
  seats "$n|stop-ready|$s"; rec due --pr 3; t "③ stop-ready 행도 주인 없음" inc "$OUT" "주인 없음 $s "
  cardf "$s" "$(setl)" "$(landl 3)"; cpush; rec due --pr 3; t "③ 세트·착지 두 줄 뒤 끝(주인 기록)" inc "$OUT" "끝 $s pr=3"; t "③ (주인 기록)" inc "$OUT" "(주인 기록)"
  land 4; TURN_BY="$n" turn 4; rec due --pr 4; t "③ cards:[] → 카드 없음" inc "$OUT" "카드 없음 PR #4 담당=$MASTER"
  rec notify --pr 4; t "③ 카드 없음 팀장 1통" [ "$(nto "$MASTER" "\[정리 차례 · 카드 없음\] PR #4 ")" = 1 ]
  local l0; l0="$(wc -l < "$STATE/land-record-turn.jsonl")"; seats "$n|nano|$s"
  rec settle --seat "$n" --pr 4 --no-card x; t "③ role=nano settle = REJECT" [ "$RC" = 1 ]; t "③ settle REJECT 쓰기 0" [ "$(wc -l < "$STATE/land-record-turn.jsonl")" = "$l0" ]
  rec settle --seat "$MASTER" --pr 4 --no-card "코드만"; rec due --pr 4; t "③ settle --no-card 뒤 끝(카드 없음 확정)" inc "$OUT" "(카드 없음 확정 · 코드만)"
  land 5; TURN_BY="$n" turn 5; rec settle --seat "$ARCH" --pr 5 --card "$s"; rec due --pr 5; t "③ settle --card 뒤 그 카드의 차례 판정" inc "$OUT" "차례 $n 종류=닫기 빠짐=ⓛⓒ 카드=$s"
  return $E
}
c4() {  # ④ 카드 2장 → 카드마다 따로
  local a="c4a$1" b="c4b$1" na nb; na="$(NN "c4a$1")"; nb="$(NN "c4b$1")"; fresh; land 6; cardf "$a"; cardf "$b"; cpush; seats "$na|nano|$a" "$nb|nano|$b"; turn 6 "$a" "$b"
  rec due --pr 6; t "④ 카드마다 차례" [ "$(printf '%s\n' "$OUT" | grep -c '^차례 ')" = 2 ]
  landed "$na" 6 "$a" --test "$TST"; rec due --pr 6; t "④ 기록한 장 = 끝" inc "$OUT" "끝 $a "; t "④ 다른 장 = 차례 그대로" inc "$OUT" "차례 $nb 종류=닫기 빠짐=ⓢⓛⓒ 카드=$b"
  return $E
}
c5() {  # ⑤ 재사용 좌석 → 종류=기록만
  local s="c5$1" n; n="$(NN "c5x$1")"; fresh; land 7; card "$s" "- 2026-11-12 12:28 — 대기→진행 · 좌석 $n"; seats "$n|nano|other$1"; turn 7 "$s"
  rec due --pr 7; t "⑤ due 종류=기록만" inc "$OUT" "차례 $n 종류=기록만 "
  rec notify --pr 7; t "⑤ 쪽지 본문도 기록만" [ "$(nto "$n" "종류 기록만")" = 1 ]
  return $E
}
c6() {  # ⑥ 같은 notify 두 번 · ⑦ 1800초 뒤 재촉 1 + 무응답 1 · ⑧ mbox 실패 = 보낸 기록 0
  local s="c6$1" n; n="$(NN "c6$1")"; fresh; land 8; card "$s"; seats "$n|nano|$s"; turn 8 "$s"
  MBOX_FAIL=5 rec notify --pr 8; t "⑧ 발신 실패 WARN 1줄" [ "$(printf '%s\n' "$OUT" | grep -c '^WARN 쪽지 발신 실패')" = 1 ]; t "⑧ 보낸 기록 0" [ ! -s "$STATE/land-record-notified.json" ]
  FT_LAND_RECORD_NOW=1000 rec notify --pr 8; t "⑧ 다음 호출이 다시 보냄 · ① 본문에 landed 명령" [ "$(nto "$n" "\[정리 차례\] $s .*ft-nano-record.sh landed --seat $n --pr 8 --card $s --test ")" = 1 ]
  FT_LAND_RECORD_NOW=1500 rec notify --pr 8; t "⑥ 2회째 발신 0" [ "$(nto "$n")" = 1 ]
  FT_LAND_RECORD_NOW=2801 rec notify --pr 8; t "⑦ 1800초 뒤 재발신 1" [ "$(nto "$n")" = 2 ]; t "⑦ 팀장 무응답 1통" [ "$(nto "$MASTER" "\[정리 차례 무응답\] $n $s ")" = 1 ]
  FT_LAND_RECORD_NOW=9999 rec notify --pr 8; t "⑦ 그 뒤 발신 0" [ "$(nsent .)" = 3 ]
  return $E
}
c11() {  # ⑪ landed REJECT 2종 → 쓰기 0
  local s="c11$1" n m c0; n="$(NN "c11$1")"; m="$(NN "c11o$1")"; fresh; land 11; cardf "$s"; cardf "o$s"; cpush; seats "$n|nano|$s" "$m|nano|o$s"; turn 11 "$s"; c0="$(ncommit)"
  landed "$m" 11 "$s" --test "$TST"; t "⑪ 차례 좌석 아님 = REJECT" [ "$RC" = 1 ]; t "⑪ 사유" inc "$OUT" "차례 좌석이 아님"
  landed "$n" 99 "$s" --test "$TST"; t "⑪ 장부에 없는 (PR·카드) = REJECT" [ "$RC" = 1 ]; t "⑪ 사유 2" inc "$OUT" "장부에 (PR #99 · $s) 줄 없음"
  t "⑪ 커밋 0" [ "$(ncommit)" = "$c0" ]; return $E
}
c12() {  # ⑫ 조상 아님 = REJECT · git 실패 = 판정 불가
  local s="c12$1" n c0; n="$(NN "c12$1")"; fresh; land 12; card "$s"; seats "$n|nano|$s"; c0="$(ncommit)"
  Q="$PH" turn 12 "$s"; landed "$n" 12 "$s" --test "$TST"; t "⑫ 조상 아님 = REJECT" [ "$RC" = 1 ]; t "⑫ 사유" inc "$OUT" "조상 아님"
  : > "$STATE/land-record-turn.jsonl"; PACK=/nonexistent/r1717 turn 12 "$s"; landed "$n" 12 "$s" --test "$TST"; t "⑫ 리포 없음 = 판정 불가 rc 3" [ "$RC" = 3 ]; t "⑫ 판정 불가 줄" inc "$OUT" "판정 불가 git merge-base"
  t "⑫ 쓰기 0" [ "$(ncommit)" = "$c0" ]; return $E
}
c13() {  # ⑬ 세트 줄 있는 카드 → 착지·완료 2줄 · 절 밖 바이트 같음
  local s="c13$1" n b a; n="$(NN "c13$1")"; fresh; land 13; CARD_TAIL='\n## 참고\n- 절 밖 줄\n' card "$s" "$(setl)"; seats "$n|nano|$s"; turn 13 "$s"; b="$(ctext "$s")"
  landed "$n" 13 "$s"; t "⑬ DONE" inc "$OUT" "DONE"; a="$(ctext "$s")"
  t "⑬ 더한 줄 = 착지·완료 2줄뿐(나머지 바이트 같음)" [ "$(printf '%s\n' "$a" | grep -vF -e "- 착지: $Q " -e "- 완료: $n ")" = "$b" ]
  t "⑬ 줄 수 +2" [ "$(printf '%s\n' "$a" | grep -c .)" = "$(( $(printf '%s\n' "$b" | grep -c .) + 2 ))" ]
  t "⑬ 상태 절 안(«## 참고» 앞)" inc "$(printf '%s\n' "$a" | grep -e '^- 완료: ' -e '^## 참고' | head -1)" "- 완료: $n "
  return $E
}
c14() {  # ⑭ 세트 줄 없는 카드: --test 없음 REJECT → --test 있음 3줄 → 실 ft-nano-close --landed-pr 사본 = LANDED-PR-OK
  local s="c14$1" n c0 nx; n="$(NN "c14$1")"; fresh; land 14; card "$s"; seats "$n|nano|$s"; turn 14 "$s"; c0="$(ncommit)"
  landed "$n" 14 "$s"; t "⑭ --test 없음 = REJECT" [ "$RC" = 1 ]; t "⑭ 사유" inc "$OUT" "세트 줄 없음 — --test 필요"; t "⑭ 쓰기 0" [ "$(ncommit)" = "$c0" ]
  landed "$n" 14 "$s" --test "$TST"; t "⑭ DONE" inc "$OUT" "DONE"
  t "⑭ 세트·착지·완료 3줄" [ "$(nline "$s" "^- 세트: $PH · 시험: $TST · 이슈: 0")$(nline "$s" "^- 착지: $Q ")$(nline "$s" "^- 완료: $n · 병합 상태: 착지 ${Q:0:10} · 남은 일: 없음")" = 111 ]
  nx="$(printf '%s\n' "$OUT" | sed -n 's/^NEXT bash ft-nano-close.sh //p')"; set -f; nclose $nx; set +f
  t "⑭ 닫기 도구가 그 카드 ref 로 LANDED-PR-OK" inc "$OUT" "LANDED-PR-OK #14"; return $E
}
c15() {  # ⑮ 상태 절 «뒤» 절에만 세트·착지 → 없는 것
  local s="c15$1" n; n="$(NN "c15$1")"; fresh; land 15; CARD_TAIL="\n## 참고\n$(setl)\n$(landl 15)\n" card "$s"; seats "$n|nano|$s"; turn 15 "$s"
  rec due --pr 15; t "⑮ 절 밖 줄은 없는 것" inc "$OUT" "차례 $n 종류=닫기 빠짐=ⓢⓛⓒ"; return $E
}
c16() {  # ⑯ (R3) 더러운 공유 작업 트리 → 자기 줄만 1커밋
  local s="c16$1" n d st0 t0 t1; n="$(NN "c16$1")"; fresh; land 16; card "$s" "$(setl)"; seats "$n|nano|$s"; turn 16 "$s"
  echo l > "$OPS/local.txt"; g "$OPS" add local.txt; g "$OPS" commit -qm "ⓓ 미발행"; d="$(g "$OPS" rev-parse HEAD)"
  echo "- 남이 쓰던 줄" >> "$OPS/$IDX/진행/$s.md"; echo x > "$OPS/other.txt"; echo y > "$OPS/staged.txt"; g "$OPS" add staged.txt
  st0="$(g "$OPS" status --porcelain=v2 --branch)"; t0="$(g "$CREM" rev-parse ops/base)"
  landed "$n" 16 "$s"; t "⑯ DONE" inc "$OUT" "DONE"; t1="$(g "$CREM" rev-parse ops/base)"
  t "⑯ 커밋 정확히 1개 · 부모 = 실행 전 원격 끝" [ "$(g "$CREM" rev-parse "$t1^")" = "$t0" ]
  t "⑯ 바뀐 경로 = 그 카드 1개" [ "$(g "$CREM" -c core.quotepath=false diff-tree --no-commit-id --name-only -r "$t1")" = "$IDX/진행/$s.md" ]
  t "⑯ 더한 줄 = 이번 2줄뿐" [ "$(g "$CREM" diff-tree --no-commit-id --numstat -r "$t1" | cut -f1,2)" = "2	0" ]
  t "⑯ ⓐ 남의 미커밋 줄 0" [ "$(nline "$s" "남이 쓰던 줄")" = 0 ]; t "⑯ ⓓ 미발행 커밋 0" [ -z "$(g "$CREM" branch --contains "$d" 2>/dev/null)" ]
  t "⑯ 작업 트리 status 바이트 같음" [ "$(g "$OPS" status --porcelain=v2 --branch)" = "$st0" ]; return $E
}
c17() {  # ⑰ push 거절 1회 = 재시도 DONE · 2회 = 판정 불가 push → 다시 실행 DONE · 잠금 = 판정 불가 lock
  local a="c17a$1" b="c17b$1" c="c17c$1" n c0; n="$(NN "c17$1")"; fresh; land 17; for s in "$a" "$b" "$c"; do cardf "$s" "$(setl)"; done; cpush
  seats "$n|nano|$a" "$(NN "c17b$1")|nano|$b" "$(NN "c17c$1")|nano|$c"; turn 17 "$a" "$b" "$c"; c0="$(ncommit)"
  echo 1 > "$RACE_F"; landed "$n" 17 "$a"; t "⑰ 1회 앞섬 → DONE" inc "$OUT" "DONE"; t "⑰ 커밋 1개(+끼어든 1)" [ "$(ncommit)" = "$((c0 + 2))" ]; t "⑰ 부모 = 새 끝" [ "$(g "$CREM" log -1 --format=%s 'ops/base^')" = race ]
  echo 2 > "$RACE_F"; landed "$(NN "c17b$1")" 17 "$b"; t "⑰ 두 번 연속 → 판정 불가 push rc 3" [ "$RC" = 3 ]; t "⑰ push 줄" inc "$OUT" "판정 불가 push"; t "⑰ DONE 0" exc "$OUT" "DONE"
  t "⑰ 닫기 요청 0" [ "$(nsent "닫기 요청\] $b ")" = 0 ]; rec due --pr 17; t "⑰ due 열린 줄 그대로" inc "$OUT" "차례 $(NN "c17b$1") "
  landed "$(NN "c17b$1")" 17 "$b"; t "⑰ 다시 실행 DONE" inc "$OUT" "DONE"; t "⑰ 줄 중복 0" [ "$(nline "$b" "^- 착지: ")$(nline "$b" "^- 완료: ")" = 11 ]
  c0="$(ncommit)"; OUT="$(cd "$T" && FT_LAND_RECORD_LOCK_S=0.3 python3 -c 'import fcntl,subprocess,sys
f=open(sys.argv[1],"a"); fcntl.flock(f,fcntl.LOCK_EX); sys.exit(subprocess.run(sys.argv[2:]).returncode)' "$STATE/land-record.lock" bash "$TOOL" landed --seat "$(NN "c17c$1")" --pr 17 --card "$c" 2>&1)"; RC=$?
  t "⑰ 잠금을 남이 쥠 → 판정 불가 lock rc 3" [ "$RC" = 3 ]; t "⑰ lock 줄" inc "$OUT" "판정 불가 lock"; t "⑰ 쓰기 0" [ "$(ncommit)" = "$c0" ]; return $E
}
c18() {  # ⑱ landed 두 번 → ALREADY
  local s="c18$1" n c0 l0; n="$(NN "c18$1")"; fresh; land 18; card "$s"; seats "$n|nano|$s"; turn 18 "$s"
  landed "$n" 18 "$s" --test "$TST"; c0="$(ncommit)"; l0="$(ctext "$s" | grep -c .)"
  landed "$n" 18 "$s" --test "$TST"; t "⑱ 2회째 ALREADY rc0" [ "$RC" = 0 ]; t "⑱ ALREADY 줄" inc "$OUT" "ALREADY"; t "⑱ DONE 0" exc "$OUT" "DONE"
  t "⑱ 줄 수·커밋 수 그대로" [ "$(ncommit) $(ctext "$s" | grep -c .)" = "$c0 $l0" ]; t "⑱ 닫기 요청 재발신 0" [ "$(nsent "\[완료·닫기 요청\]")" = 1 ]; return $E
}
c19() {  # ⑲ (R2) NEXT 인자 = 실재 파일 + 실제 seq → 실 닫기 사본에 그대로 · 기록만 = NEXT 0
  local s="c19$1" r="c19r$1" n m nx; n="$(NN "c19$1")"; m="$(NN "c19m$1")"; fresh; land 19; cardf "$s"; cardf "$r" "- 2026-11-12 — 대기→진행 · 좌석 $m"; cpush
  seats "$n|nano|$s" "$m|nano|x$s"; turn 19 "$s" "$r"
  landed "$n" 19 "$s" --test "$TST"; nx="$(printf '%s\n' "$OUT" | sed -n 's/^NEXT bash ft-nano-close.sh //p')"; set -f; set -- $nx; set +f
  t "⑲ 팀장 닫기 요청 1통" [ "$(nto "$MASTER" "\[완료·닫기 요청\] $s 착지 ${Q:0:10} · 좌석 $n · 세션 기록 ")" = 1 ]
  t "⑲ NEXT 꼴" [ "$1 $2 $3 $4 $6" = "$n --landed-pr 19 --result --recv" ]; t "⑲ --result = 실재 파일" [ -s "${5:-/nonexistent}" ]
  t "⑲ --recv = 그 쪽지의 실제 seq" [ "${7:-x}" = "$(awk -F'\t' '/완료·닫기 요청/{print $1}' "$MBOX_LOG")" ]
  nwt "$s"; CLOSE_LIVE=1 nclose "$n" --landed-pr 19 --result "$s 착지 ${Q:0:10}" --recv -; t "⑲ 옛 꼴 인자 = ① 거절" inc "$OUT" "①결과 경로 없음"
  CLOSE_LIVE=1 nclose "$@"; t "⑲ NEXT 인자 그대로 → ①·② 사유 0" exc "$OUT" "①결과"; t "⑲ ② 0" exc "$OUT" "  - ②"; t "⑲ 실 닫기 CLOSED" inc "$OUT" "CLOSED $n landed-pr=19"
  : > "$MBOX_LOG"; landed "$m" 19 "$r" --test "$TST"; t "⑲ 기록만 DONE" inc "$OUT" "DONE"; t "⑲ 기록만 NEXT 0" exc "$OUT" "NEXT "; t "⑲ 기록만 팀장 발신 0" [ "$(nto "$MASTER")" = 0 ]
  t "⑲ 완료 줄에 좌석 계속" [ "$(nline "$r" "^- 완료: $m · 병합 상태: 착지 ${Q:0:10} · 좌석 계속(지금 카드 x$s)")" = 1 ]; return $E
}
c20() {  # ⑳ (A11) 다 선 좌석 = 자리표시 0 + 갈래=착지기록 + 1회 집행 · 넷 중 하나 빠짐 = 그대로 + 빠짐= · 집행 0
  local k na nb nc nd ne L; for k in a b c d e; do eval "n$k=\"\$(NN \"c20$k$1\")\""; done; fresh; land 20
  cardf "c20a$1"; cardf "c20b$1" "$(setl)" "$(landl 20)" "$(donel "$nb" "좌석 계속(지금 카드 x)")"; cardf "c20c$1" "$(setl)" "$(landl 20)"
  cardf "c20d$1" "$(setl)" "$(landl 20)" "$(donel "$nd" "남은 일: 보정=$nd")"; cardf "c20e$1" "$(setl)" "$(landl 20)" "$(donel "$ne")"; cpush
  seats "$na|nano|c20a$1" "$nb|nano|c20b$1" "$nc|nano|c20c$1" "$nd|nano|c20d$1" "$ne|nano|c20e$1"; turn 20 "c20a$1" "c20b$1" "c20c$1" "c20d$1" "c20e$1"
  landed "$na" 20 "c20a$1" --test "$TST"; echo x > "$STATE/seat-record/$nd.md"
  storeset close "$nd|c20d$1|$Q" "{\"rec\":\"$(recof "c20d$1" "$nd")\",\"seq\":100,\"result\":\"$STATE/seat-record/$nd.md\",\"pr\":20}"
  cdue; L="$(printf '%s\n' "$OUT" | grep "^닫기 차례 $na ")"
  t "⑳ 갈래=착지기록 rec=" inc "$L" " 갈래=착지기록 rec="; t "⑳ 자리표시 0" exc "$L" "<"; t "⑳ 실제 인자" inc "$L" "--landed-pr 20 --result '$STATE/seat-record/$na.md' --recv "
  t "⑳ 좌석 계속 = 그대로 + 빠짐" inc "$OUT" "$nb --landed-pr 20 --result <산출> --recv <seq> 빠짐=닫을 좌석 아님(좌석 계속) 채울 이=팀장"
  t "⑳ 완료 줄 없음" inc "$OUT" "$nc --landed-pr 20 --result <산출> --recv <seq> 빠짐=착지 뒤 완료 줄 채울 이=$nc"
  t "⑳ 남은 일 나노 몫" inc "$OUT" "$nd --landed-pr 20 --result <산출> --recv <seq> 빠짐=남은 일(보정=$nd) 채울 이=$nd"
  t "⑳ 전달 기록 없음" inc "$OUT" "$ne --landed-pr 20 --result <산출> --recv <seq> 빠짐=닫기 요청 전달 채울 이=$ne"
  AUTO=0 scan auto; t "⑳ FT_NANO_AUTO_CLOSE≠1 → 집행 0" [ ! -s "$NC_LOG" ]
  scan auto; t "⑳ 1회 집행(그 좌석만)" [ "$(grep -c . "$NC_LOG") $(cut -d' ' -f1 "$NC_LOG")" = "1 $na" ]; t "⑳ 로그 CLOSED 갈래=착지기록" inc "$OUT" "auto-close CLOSED $na landed-pr 갈래=착지기록 rec="
  return $E
}
export RACE_F="$T/race" CREM_D="$CREM"; echo 0 > "$RACE_F"; mkdir -p "$ROOT/.git/hooks"
cat > "$ROOT/.git/hooks/pre-push" <<'EOF'
#!/usr/bin/env bash
# ⑰ 주입 — RACE_F 의 수만큼, push 직전에 다른 writer 가 카드 ref 를 1커밋 앞세운다(non-FF 거절)
n="$(cat "$RACE_F" 2>/dev/null || echo 0)"; [ "$n" -gt 0 ] || exit 0; echo $((n - 1)) > "$RACE_F"
G() { env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE git -C "$CREM_D" "$@"; }
G update-ref refs/heads/ops/base "$(G commit-tree 'ops/base^{tree}' -p ops/base -m race)"
EOF
chmod +x "$ROOT/.git/hooks/pre-push"

step "사례 ③~⑧"; run "③ 주인 없음·카드 없음·settle" c3; run "④ 카드 2장" c4; run "⑤ 재사용 좌석 = 기록만" c5; run "⑥⑦⑧ notify 1회·재촉 1회·발신 실패" c6
step "사례 ⑪~⑮"; run "⑪ landed REJECT 2종" c11; run "⑫ 조상 아님·git 실패" c12; run "⑬ 착지·완료 2줄" c13; run "⑭ 세트 줄 없는 카드 → LANDED-PR-OK" c14; run "⑮ 상태 절 경계" c15
step "사례 ⑯~⑳"; run "⑯ 자기 기록만 1커밋(R3)" c16; run "⑰ push 거절·잠금" c17; run "⑱ 멱등 ALREADY" c18; run "⑲ NEXT 실제 인자(R2)" c19; run "⑳ 착지 갈래 집행(A11)" c20
step "변이 M2·M3·M4·M5·M6·M8·M9·M16 (+원본 대조)"
mutbin m2 ft_nano_record_due.py 'if idx_stem(v) == stem and k in ctx.live()]' 'if k in ctx.live()]'; mutcase M2 c5 2
mutbin m3 ft_nano_record_notify.py '    if ent and not (ent.get("n") == 1 and now - float(ent.get("ts") or 0) >= gap):   # r1717-mut:sent' '    if False:'; mutcase M3 c6 3
mutbin m4 ft_nano_record_write.py '        if a.seat not in own:   # r1717-mut:turnseat' '        if False:'; mutcase M4 c11 4
mutbin m5 ft_nano_record_write.py '    rc, _o, _e = run(["git", "-C", repo, "merge-base", "--is-ancestor", q, f"refs/remotes/origin/{target}"])   # r1717-mut:ancestor' '    rc = 0'; mutcase M5 c12 5
mutbin m6 ft_nano_record_due.py '        sec = lines[st + 1:en] if st is not None else []   # r1717-mut:section' '        sec = lines'; mutcase M6 c15 6
mutbin m8 ft_nano_record_write.py '    if not m["l"]:   # r1717-mut:sameq' '    if True:'; mutcase M8 c18 8
mutbin m9 ft_nano_record_auto.py '    if not left_free(left_of(done[-1]), master):   # r1717-mut:autoleft' '    if False:'; mutcase M9 c20 9
mutbin m16 ft_nano_record_write.py '    path, raw = ctx.card(team, iroot, stem)
    lines, st, en = section(raw.decode("utf-8"))' '    path, raw = ctx.card(team, iroot, stem)
    raw = open(os.path.join(str(ctx.root), ".worktrees", "ops", path), "rb").read()
    lines, st, en = section(raw.decode("utf-8"))'; mutcase M16 c16 16
step "기준판 ⑭ (팩 103be13029 — 도구 없음 · 닫기 도구는 «세트: 40-hex 줄이 없다» REJECT)"
BASE="$T/base"; mkdir -p "$BASE"
if git -C "$H" archive 103be13029fc16eb35fb0a305defcbad6c46ce10 -- bin/ft-nano-close.sh bin/ft-team-lib.sh 2>/dev/null | tar -x -C "$BASE" 2>/dev/null && [ -f "$BASE/bin/ft-nano-close.sh" ]; then
  [ ! -e "$BASE/bin/ft-nano-record.sh" ] && ok "기준판에 도구 없음" || bad "기준판에 도구가 있다"
  ( BIN="$BASE/bin"; TOOL="$BIN/ft-nano-record.sh"; c14 base ) >/dev/null 2>&1 && bad "기준판에서 ⑭ 가 통과함" || ok "기준판 ⑭ FAIL(기대)"
  ( fresh; land 21; card c14base2; seats "$(NN c14base2)|nano|c14base2"; nclose "$(NN c14base2)" --landed-pr 21 --result "$T/gh.json" --recv 100; inc "$OUT" "«세트:» 40-hex 줄이 없다" ) \
    && ok "기준판 닫기 = «세트: 40-hex 줄이 없다» REJECT" || bad "기준판 닫기 사유가 다름"
else bad "기준판(103be13029) 꺼내기 실패 — 팩 리포 밖이거나 얕은 사본"; fi
finish
