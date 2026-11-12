# r1718 A6 — ft-nano-close.sh 거절 사유 분류표

ft-nano-close.sh 의 `bad+=(…)` 전부를 ft-critical-notify.sh 의 표(`PROG` · `CLOSE_NEXT`)로 나눈 결과다.
«진행» 만 알리지 않는다. 나머지 셋은 desk 에 [크리티컬] 1통을 보낸다. 표에 없는 새 사유는 «환경» 으로 떨어져 알린다.
사유 글이 다른 도구 출력(`$_ev_out` · `$_gate_out` 등)을 그대로 싣는 곳은 실행 때 글로 분류된다. 이 표는 소스에 적힌 글만 본다.

합계 78곳: 진행 4 · 기록 없음 4 · 낡음·갈라짐 0 · 환경 70
`bad` 배열 밖 출구(echo 로 바로 거절): 원장 WT 낡음·갈라짐 2곳(줄 313, 316) = 낡음·갈라짐 → ⓑ

| 줄 | 분류 | 다음 손 | 사유 글(앞 110자) |
|---|---|---|---|
| 1179 | 환경 | ⓒ REJECT 원문대로 | ①결과 경로 없음: ${RESULT:-<미지정>} |
| 1180 | 환경 | ⓒ REJECT 원문대로 | ①결과 파일이 비어 있음(0바이트): $RESULT — 리서치 좌석의 산출 = 조사 결과(r888 r2) |
| 1182 | 환경 | ⓒ REJECT 원문대로 | ②--recv <seq> 미지정 |
| 1184 | 환경 | ⓒ REJECT 원문대로 | ②seq $RECV 가 우편함 기록에 없다 |
| 1201 | 환경 | ⓒ REJECT 원문대로 | ③pgrep 실패(rc=$prc: ${op:0:60}) |
| 1204 | 환경 | ⓒ REJECT 원문대로 | ③pgrep 실패(rc=$prc2: ${op2:0:60}) |
| 1207 | 환경 | ⓒ REJECT 원문대로 | ③고아 tmux 서버(pgrep ${n} · 소켓 부재) |
| 1211 | 환경 | ⓒ REJECT 원문대로 | ③tmux 조회 실패(rc=$tmux_rc: ${tmux_out:0:60}) |
| 1219 | 환경 | ⓒ REJECT 원문대로 | ③pane 경로 조회 실패(rc=$dm_rc) |
| 1248 | 환경 | ⓒ REJECT 원문대로 | ⓐ좌석 전용 워크트리가 있다(${SEAT_WT:-$SEAT_WT_ERR} |
| 1249 | 환경 | ⓒ REJECT 원문대로 | ⓑpane cwd 를 알 수 없다 — 공유 워크트리 확인 불가(세션이 살아 있어야 한다) |
| 1255 | 환경 | ⓒ REJECT 원문대로 | ⓑpane cwd($cwd)의 toplevel 이 등록된 워크트리가 아니다 |
| 1256 | 환경 | ⓒ REJECT 원문대로 | ⓑ공유 워크트리 $SH_TOP 의 브랜치를 알 수 없다(detached |
| 1257 | 환경 | ⓒ REJECT 원문대로 | ⓑ공유 워크트리 $SH_TOP 가 나노 브랜치($SH_BR |
| 1299 | 환경 | ⓒ REJECT 원문대로 | ⓐ--wt 경로가 없다: $NWT |
| 1301 | 환경 | ⓒ REJECT 원문대로 | ⓐ--wt($_nw)가 이 리포($ROOT)에 등록된 .worktrees/ 아래 워크트리가 아니다 · 팩 경로는 하네스 카드(첫 5줄 원장 줄 GOAL-harness)만$(_pack_move_hin |
| 1304 | 환경 | ⓒ REJECT 원문대로 | ⓑ--wt($_nw)에 체크아웃된 브랜치(${_nb:-detached})가 --branch($NBR)와 다르다 |
| 1307 | 환경 | ⓒ REJECT 원문대로 | ⓑ--branch($NBR)는 정본 줄기(base)다 — 좌석 브랜치가 아니라 닫지 않는다 |
| 1309 | 환경 | ⓒ REJECT 원문대로 | ⓐ표준 전용 워크트리($_std_wt)가 따로 있다 — --wt($_nw)와 다르다, 추측 금지(인자 없이 닫거나 인자를 고쳐라) |
| 1315 | 환경 | ⓒ REJECT 원문대로 | ⓒpane cwd($cwd)의 toplevel(${_ctop:-없음})이 --wt($_nw)와 다르다 |
| 1321 | 환경 | ⓒ REJECT 원문대로 | ⓓtmux pane 조회 실패(rc=$_prc: ${_pp:0:60}) |
| 1328 | 환경 | ⓒ REJECT 원문대로 | ⓓ다른 pane(${_oth# })의 cwd 가 --wt($_nw |
| 1333 | 환경 | ⓒ REJECT 원문대로 | ⓔgit status 실패(rc=$_drc: ${_dirty:0:60}) |
| 1334 | 진행 | — (발신 0) | ⓔ--wt 미커밋 변경 $(printf '%s\n' "$_dirty" ¦ grep -c .)건 — 커밋하거나 되돌린 뒤 닫는다(WIP 자동 커밋 0 · .serena/project.yml 만이면 g |
| 1337 | 환경 | ⓒ REJECT 원문대로 | ③$SEAT_WT_ERR |
| 1350 | 환경 | ⓒ REJECT 원문대로 | base 가 «HEAD»(detached spawn)인데 base_sha(${_HSHA:-없음})를 $SEAT_REPO 에서 못 푼다 — 판정 불가 |
| 1379 | 환경 | ⓒ REJECT 원문대로 | ⑤ origin/main fetch 실패($feat |
| 1410 | 환경 | ⓒ REJECT 원문대로 | $_DOCS_BASE_ERR |
| 1412 | 환경 | ⓒ REJECT 원문대로 | base 가 sha ${_BASE_SHA:0:9} 이고 $_FEAT 의 조상이 아니다 — FT_NANO_FEAT=<랜딩 브랜치> 로 다시 |
| 1420 | 환경 | ⓒ REJECT 원문대로 | ③세션 없음: $SEAT |
| 1433 | 진행 | — (발신 0) | ③워크트리에 ${IDLE_MIN}분 내 편집: $last |
| 1436 | 환경 | ⓒ REJECT 원문대로 | ③jsonl 기록 시각 없음: ${_lt%%$'\n'*} |
| 1438 | 진행 | — (발신 0) | ③jsonl 마지막 기록(${_lt#* } |
| 1601 | 환경 | ⓒ REJECT 원문대로 | ⓐ--wt($_nw)가 이 리포($ROOT)에 등록된 .worktrees/ 아래 워크트리가 아니다 · 팩 경로는 하네스 카드(원장 GOAL-harness)만 (카드 ${CARD_READ:-못 찾음} |
| 1612 | 환경 | ⓒ REJECT 원문대로 | ④press/시험 카드인데 checkpoint 실행 기록 없음: ft-checkpoint.sh <증거폴더> --seat $SEAT |
| 1615 | 환경 | ⓒ REJECT 원문대로 | ④checkpoint 표 없음: ${cp_tab:-<빈 경로>} |
| 1616 | 환경 | ⓒ REJECT 원문대로 | ④마지막 checkpoint alarm=$cp_al exit=$cp_ex — 경보면 4축 정리 → arch(+DA |
| 1638 | 환경 | ⓒ REJECT 원문대로 | ⑥나노 워크트리 ${SEAT_WT_ERR:-없음: $ROOT/.worktrees/${WT_PREFIX}<key>[-rN]} — «한 일 0» 을 셀 워크트리가 없다 |
| 1639 | 환경 | ⓒ REJECT 원문대로 | ⑥한 일 0 검사 스크립트 없음: $HERE/ft-nano-never-started-check.sh (런타임 bin 에 같이 복사) |
| 1648 | 환경 | ⓒ REJECT 원문대로 | ⑥$(printf '%s' "$_ns_out" ¦ grep -vE '^(SUCCESSOR¦LANDED |
| 1652 | 환경 | ⓒ REJECT 원문대로 | ⑥카드 못 찾음: seats.json index=${IDX:-<빈 값>} — 대체됨 줄을 대조할 카드가 없다${_sibn:+ · 형제 ${_sibn}개} |
| 1653 | 환경 | ⓒ REJECT 원문대로 | ⑥대체됨 검사 스크립트 없음: $HERE/ft-nano-superseded-check.sh (런타임 bin 에 같이 복사) |
| 1656 | 환경 | ⓒ REJECT 원문대로 | ⑥$(printf '%s' "$_sp_out" ¦ sed -e 's/^REJECT //' -e '2,$s/^/    /') |
| 1660 | 환경 | ⓒ REJECT 원문대로 | ⑥카드 못 찾음: seats.json index=${IDX:-<빈 값>} — 중단 줄을 남길 카드가 없다${_sibn:+ · 형제 ${_sibn}개} |
| 1661 | 환경 | ⓒ REJECT 원문대로 | ⑥나노 워크트리 ${SEAT_WT_ERR:-없음: $ROOT/.worktrees/${WT_PREFIX}<key>[-rN]} — 중단 세트(HEAD)를 정할 수 없다 |
| 1662 | 환경 | ⓒ REJECT 원문대로 | ⑥중단 검사 스크립트 없음: $HERE/ft-nano-suspended-check.sh (런타임 bin 에 같이 복사) |
| 1672 | 환경 | ⓒ REJECT 원문대로 | ⑥나노 워크트리 ${SEAT_WT_ERR:-없음: $ROOT/.worktrees/${WT_PREFIX}<key>[-rN]} — 리서치 «코드 0» 을 셀 워크트리가 없다 |
| 1678 | 환경 | ⓒ REJECT 원문대로 | ⑥리서치 기준 판 없음(reflog |
| 1690 | 환경 | ⓒ REJECT 원문대로 | ⑥리서치 origin/main fetch 실패 — 옛 ref 대조 0(R22 |
| 1715 | 환경 | ⓒ REJECT 원문대로 | ⑥리서치 검사 실패(rev-list rc=$_rs_nrc·$_rs_mrc · 경로목록 rc=$_rs_src·$_rs_prc: ${_rs_n:0:60} |
| 1717 | 환경 | ⓒ REJECT 원문대로 | ⑥리서치 아님 — 기준 판 ${_rs_base:0:9}($_rs_bsrc |
| 1726 | 환경 | ⓒ REJECT 원문대로 | ⑥승인 갈래 판정기 없음: $HERE/ft-nano-close-due.sh (런타임 bin 에 같이 복사) |
| 1727 | 환경 | ⓒ REJECT 원문대로 | ⑥--approved 판정문 없음: $APPROVED — 없는 판정문으로 닫지 않는다 |
| 1733 | 환경 | ⓒ REJECT 원문대로 | ⑥승인 갈래 판정 시간 초과(${_ap_cap}초 상한 · 하드 룰 12 |
| 1734 | 환경 | ⓒ REJECT 원문대로 | ⑥$(printf '%s' "$_ap_out" ¦ sed -e 's/^APPROVE-REJECT //' -e 's/^REJECT //' -e '2,$s/^/    /') |
| 1740 | 환경 | ⓒ REJECT 원문대로 | $_lp_pr_err |
| 1743 | 기록 없음 | ⓐ 그 나노에 정리 기록 차례 | ⑥카드 못 찾음: seats.json index=${IDX:-<빈 값>} — 착지 대조(«세트:» sha·«- 착지:» 줄)를 할 카드가 없다 |
| 1744 | 환경 | ⓒ REJECT 원문대로 | $_lp_pr_err |
| 1748 | 기록 없음 | ⓐ 그 나노에 정리 기록 차례 | ⑥--landed-pr 카드 «## 상태» 절에 «세트:» 40-hex 줄이 없다: $CARD_READ — 대조할 세트가 없으면 닫지 않는다 |
| 1749 | 기록 없음 | ⓐ 그 나노에 정리 기록 차례 | ⑥--landed-pr 카드에 «- 착지:» 줄이 없다: $CARD_READ — 착지 기록 없는 좌석은 이 경로로 닫지 않는다 |
| 1757 | 환경 | ⓒ REJECT 원문대로 | $_lp_sx_err |
| 1762 | 환경 | ⓒ REJECT 원문대로 | $_lp_equiv_err |
| 1767 | 환경 | ⓒ REJECT 원문대로 | ⑥카드 못 찾음: seats.json index=${IDX:-<빈 값>} (후보 $WT/·$ROOT/·$LEDGER_WT/ 아래 어디에도 없음 |
| 1769 | 환경 | ⓒ REJECT 원문대로 | ⑥증거 검사 스크립트 없음: $HERE/ft-nano-evidence-check.sh (런타임 bin 에 같이 복사) |
| 1776 | 환경 | ⓒ REJECT 원문대로 | ⓔ$(nf_again "증거 검사" "$(( $(nf_now |
| 1777 | 환경 | ⓒ REJECT 원문대로 | ⓔ$(printf '%s' "$_ev_out" ¦ sed -e 's/^REJECT //' -e '2,$s/^/    /') |
| 1779 | 기록 없음 | ⓐ 그 나노에 정리 기록 차례 | ⑥나노 워크트리 ${SEAT_WT_ERR:-없음: $ROOT/.worktrees/${WT_PREFIX}<key>[-rN]} — 증거 줄의 HEAD 를 대조할 수 없다 |
| 1788 | 환경 | ⓒ REJECT 원문대로 | ⑥$(nf_again "증거 검사" "$(( $(nf_now |
| 1790 | 환경 | ⓒ REJECT 원문대로 | ⑥$(printf '%s' "$_ev_out" ¦ sed -e 's/^REJECT //' -e '2,$s/^/    /') |
| 1815 | 환경 | ⓒ REJECT 원문대로 | ⓓ--result($RESULT)가 공유 워크트리($SH_TOP |
| 1816 | 환경 | ⓒ REJECT 원문대로 | ⓓ--result($_rel)가 공유 워크트리에서 추적 중이 아니다(미추적) |
| 1817 | 진행 | — (발신 0) | ⓓ--result($_rel)에 미커밋 변경이 있다 — 커밋한 뒤 닫는다 |
| 1835 | 환경 | ⓒ REJECT 원문대로 | ⑤$(nf_again "cherry 게이트" "$(( $(nf_now |
| 1846 | 환경 | ⓒ REJECT 원문대로 | ⑤$(nf_again "cherry 게이트(origin/main)" "$(( $(nf_now |
| 1851 | 환경 | ⓒ REJECT 원문대로 | ⑤$(printf '%s' "$_gate_out" ¦ sed '2,$s/^/    /') |
| 1859 | 환경 | ⓒ REJECT 원문대로 | ⑤-생애 $(nf_again "freshness" "$(( $(nf_now |
| 1862 | 환경 | ⓒ REJECT 원문대로 | ⑤-생애 $(printf '%s' "$_fresh_out" ¦ sed '2,$s/^/    /') |
| 1868 | 환경 | ⓒ REJECT 원문대로 | ⑤cherry 게이트 스크립트 없음: $HERE/ft-nano-cherry-gate.sh (런타임 bin 에 같이 복사) |
