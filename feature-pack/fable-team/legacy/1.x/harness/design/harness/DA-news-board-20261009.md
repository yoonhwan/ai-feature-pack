# 판정 421 + 423(R34) 뉴스 보드·보고 누락 개선 — 사전검증 DA (1회)

## §0 요청 (byz-harness-arch-claude#13 → byz-harness-da-codex#0 · 2026-10-08)
- 대상 스냅샷(SHA-256): 설계 99406bcf184a088828855f22e258b9dcbbcbe50a61454b7c3e8a84357a1109fa — 이 sha 뒤 설계 수정 0.
- 설계: design/teams/harness/DESIGN-news-tree-workqueue-viz-20261009.md (실측 §1 · 안 §2 · 배분 §3) · 입력 감사 AUDIT-j410-console-vs-slack-20261008.md · AUDIT-r34-planner-relay-latency-20261008.md.
- 반박할 것 = 설계 §5 3항 + §2-4 의 훅 2개(report-coverage Stop · drain-before-interview PreToolUse)가 planner 를 막아 세우는 길(전역 아님 · planner 1좌석). 10+10분 · 2 HOLD 면 중단. 읽기 실측 자유 · 설치·발신·코드 0.
- 판정 §1 이하 + 결론 1줄 mbox.

## §1 범위·고정 증거

발주 #62643. 실제 설계 SHA-256 `99406bcf184a088828855f22e258b9dcbbcbe50a61454b7c3e8a84357a1109fa`가 §0과 일치합니다. 설계 §5 세 질문과 planner의 두 훅 막힘 경로만 검토했습니다. 두 감사 문서는 근거로 읽었지만 그 Slack/세션 수치를 재실측했다고 주장하지 않습니다. 설치·발신·코드/명부/원장 변경·실제 인터뷰·시험 실행은 없고 이 판정문만 추가합니다.

## §2 질문 1 — HOLD-N1: flock의 원장 권위/지원 범위 미확정

VERDICTS의 max+1 발급과 flock(:64)은 **같은 물리 파일과 같은 lock**을 공유할 때만 동시 번호 충돌을 막습니다. 두 planner가 서로 다른 워크트리/머신의 tracked VERDICTS 사본을 읽고 각각 잠그면 둘 다 max=N에서 N+1을 발급할 수 있습니다. 한 스크립트 이름이 단일 저장소/발급 권위를 뜻하지 않습니다. 설계가 질문에서 두 머신을 명시했지만 그 지원 경계를 정하지 않았습니다(:73).

최소 교정: 발급 원장/lock의 canonical 절대 위치와 발급 주체를 고정하고, 두 머신이 그 권위를 공유하지 않는 경우 두 번째 머신의 로컬 발급은 거부·단일 발급자에 전달하도록 정하세요. 분산 저장소를 새로 만들라는 요구는 아니며 현재 단위를 단일 머신/단일 원장으로 제한하는 것도 가능합니다. 승계 전후 같은 namespace를 사용하고 read-max·append·영속화는 lock 안에서 완료해야 합니다.

운영 전환(:67)에는 기존 판정 번호의 검증된 마지막 값/기존 기록 이관을 고정해야 합니다. 새 빈 파일의 max+1만으로 역사 번호와의 충돌 방지를 증명하지 못합니다. append-only done 사건도 같은 n의 상태 갱신과 신규 번호 발급을 구분해 조회에 fold해야 합니다. 시험은 동일 원장 두 process, 분리 사본 발급 거부/정한 namespace 정책, legacy 기준값 이후 첫 발급, 승계 중 중복 요청을 검사해야 합니다.

## §3 질문 2·planner 훅 — HOLD-N2: 유한 차단은 보고 완결성의 충분조건 아님

report-coverage의 stop_hook_active 통과 및 인터뷰의 같은 턴 두 번째 통과(:49,53)는 무한 차단을 피하려는 방향으로 수락합니다. 하지만 30건을 읽고 두 번째 답변에도 일부 번호가 없으면 통과+기록될 뿐, 그 미보고가 다음 턴/보드에 살아남는 계약은 없습니다. mailbox pending은 READ로 줄어들므로 ‘planner 미처리 0’이라고 보여도 읽고 미보고한 의무는 남을 수 있습니다(:52). 이번 감사가 지적한 READ와 보고의 차이를 다시 잃는 경로입니다.

최소 교정: seq별 보고 의무와 보고 확인 상태를 영속화하고, 한 번의 교정 뒤 미충족 항목은 planner를 계속 막지 말고 보드/다음 턴의 ‘미보고’로 남겨야 합니다. mailbox pending은 ‘수신 대기’와 구분해서 표시합니다. 최종 답변에 우연히 같은 판정 숫자가 나온 것을 해당 seq의 보고 완료로 오인하지 않도록 확인 단위/직접 참조 규칙을 고정하세요. 장황한 30문장 반복을 강제하기보다 번호를 보존한 묶음 보고를 허용할 수 있습니다.

판정/오빠라는 단어는 발주 골 원문·과거 인용에도 있으므로 kinds를 본문 문자열만으로 과대 분류하는 오탐을 구분해야 합니다. READ 수집은 이번 턴의 실제 수신 metadata/전문으로 하고 마지막 2MB 잘림(:61)이나 압축·relay 요약에 없는 본문을 ‘보고 의무 없음’으로 처리하지 않아야 합니다.

### 두 훅의 막힘 경로에 필요한 경계

- report 훅: 누락 30건·일부만 고친 재검·파싱/장부 오류에도 이번 턴의 추가 block은 0이며, 미보고 상태/오류가 보이게 남아야 합니다. 잘린 transcript를 전체 보고 성공으로 표시하지 않습니다.
- drain 훅: deny 상한은 세션+현재 사용자 턴 등 안정 키로 저장하고, pending 수나 tool-use id가 바뀌었다는 이유로 같은 턴의 첫 deny를 반복하지 않아야 합니다. 첫 deny→recv 후 쪽지가 다시 들어와도 두 번째 Ask는 진행할 수 있어야 합니다.
- pending 조회 실패·counter 저장 실패·recv 실패는 끝없는 deny나 정상 빈 함으로 바꾸지 말고 보이는 오류/잔여 의무를 기록한 제한적 통과 정책을 정해야 합니다. 두 훅이 각자 서로의 교정 상태를 초기화해도 안 됩니다.
- 인터뷰 동안 생긴 항목과 재개 뒤 첫 recv는 별도 턴의 의무로 들어가야 합니다. 현재 인터뷰를 자동 취소하거나 다른 질문으로 바꾸는 요구는 아닙니다.

가짜 시험은 30 READ, quote-only 번호, 2MB 밖의 READ, 같은 턴 계속 유입, 조회/기록 오류, Ask 대기 후 새 턴을 포함해 ‘유한 차단 + 의무 유실 0’을 검사해야 합니다. 현재 :66의 ‘시험 각 1’만으로 이 계약이 닫히지 않습니다.

## §4 질문 3 — HOLD-N3: 최신 화면과 변경 이력의 연결 증거 부족

chat.update의 현재 보드와 하루 한 뿌리 글은 읽기 개선 방향으로 수락합니다. 그러나 :44의 요약은 새 판정/오빠 손 증감만이라, 카드 A가 진행→완성하고 Issue 상태가 바뀐 갱신에서 이전 보드가 사라지면 그 변화가 무엇이었는지 복원할 값/버전 연결이 없습니다. 입력 hash가 달랐다는 사실(:46)만으로 과거 카드·명부·외부 Issue snapshot을 재구성할 수는 없습니다.

최소 교정: 갱신 전후의 불변 보드/입력 snapshot 또는 재생 가능한 원장 commit·외부 조회 snapshot을 hash/시각으로 묶어 보존하고, 한 줄 변화 요약에서 그 버전과 변경 단위/상태를 참조하도록 하세요. Slack에 모든 원문/이벤트를 다시 쌓으라는 요구가 아닙니다. 최신 보드 전용으로 이력을 보장하지 않는 선택을 한다면 그 한계를 명시하고 원래 사건/결과 스레드로 이어지는 경로는 유지해야 합니다.

시험은 판정/오빠 손 변화 없이 카드/Issue 상태만 바뀐 갱신에서도 변경 단위를 식별·원천 버전에 연결하는 경우, chat.update 성공 뒤 요약/버전 기록 실패의 복구, 날짜 전환의 최종 snapshot을 포함해야 합니다. 사용자에게 ‘본문 갱신=전체 역사 보존’으로 보여주면 안 됩니다.

## §5 통합 판정·이관

HOLD 1회. 세 원인은 판정 번호의 물리 권위/이관 기준, 보고 의무의 유실 없는 상태와 훅의 유한 차단, 최신 보드와 변경 원천 버전의 연결입니다. 손 트리 제거·명부 기반 현재 표시·✅ 오늘분 유지·판정 423의 보고/미러 개선 방향을 반대하는 것이 아닙니다. 채널/요약 문구·회신 상한 전체 우회·타 팀 hook 등 지정 범위 밖 사항은 재심사하지 않았습니다.

최초 요청 artifact 14:20:31부터 약 6분 이내로 초기 10분 안에 종료합니다. architect가 같은 세 계약/시험 범위를 고정하고 master/planner가 원장 운영 전환·가짜 hook/발행 회귀 및 설치/실제 갱신 증거를 확인해야 합니다. 같은 범위 교정 10분 1회, 두 번째 HOLD면 통합 이관 후 연속 리뷰 종료입니다.

HOLD

## §6 교정 요청 r2 (byz-harness-arch-claude#13 → byz-harness-da-codex#0 · 2026-10-08)
- 대상 스냅샷(SHA-256): 설계 r2 8a1f1a2423b3a4980c70e53c802cf83ffcbd12d09826917aebd5affbc057c640 — 이 sha 뒤 설계 수정 0.
- 반박할 것 = 설계 r2 §7 한 문항(N1·N2·N3 각 최소 교정 충족 · 새 원인만 · §6 인박스는 N2 저장소로 보고 새 원인 1개까지). 10분 1회 · 두 번째 HOLD 면 통합 이관 후 종료.
- 읽기 실측 자유 · 설치·발신·코드 0. 판정 §7 이하 + 결론 1줄 mbox.

## §7 교정 r2 검토 — #62689, 마지막 1회

실제 설계 SHA-256 `8a1f1a2423b3a4980c70e53c802cf83ffcbd12d09826917aebd5affbc057c640`가 §6과 일치합니다. 기존 N1/N2/N3 최소 교정과 N2 저장소로서의 인박스만 확인했습니다. 새 인박스 일반 기능/모델 선택을 심사하지 않았습니다. 설치·발신·코드/원장/큐 변경·실제 인터뷰·시험 실행은 없습니다.

### N1 — APPROVE(명시된 단일 머신/물리 원장 범위)

§2-1은 루트 런타임 파일과 lock을 하나로 고정하고 read-max/append/fsync를 lock 안에 둡니다. 호스트/루트가 권위와 다르면 발급을 거부하므로 분리 사본의 독립 max+1 문제를 지원 범위 밖으로 막습니다. 검증된 legacy seed가 없으면 발급 0이며 new와 done/todo를 fold해 상태 변경을 신규 번호와 구분합니다.

§3 나노 1은 두 process·불일치 거부·seed/첫 발급·done·승계 회귀를 명시해 기존 N1을 닫습니다. 실제 경로는 동일 물리 파일로 canonicalize하고, 운영 전환의 마지막 번호 cutoff/단일 실제 호스트 권위를 master/planner가 확인해야 합니다. 이 승인은 분산 발급이나 다른 파일/머신의 문자열 일치만으로 같은 권위가 된다는 보장이 아닙니다.

### N3 — APPROVE(보존된 최신 보드+별도 snapshot 이력)

§2-3은 렌더 dict 전체를 불변 snapshot으로 먼저 저장하고 이후 chat.update와 변경 단위 diff 답글을 냅니다. 카드/Issue만 바뀐 경우도 전후 snap ID와 함께 남기고, 저장 실패 발행 0·답글 누락 복구·날짜 최종 snapshot을 정의해 기존의 과거 상태/변경 근거 소실을 해소했습니다.

§3 나노 2의 직접 회귀도 수락합니다. snapshot ID/내용의 실제 불변성, 발행 중간 오류의 미완료 상태는 구현자가 검증해야 하며 누락 답글의 복구는 입력 hash가 그대로여도 차단되지 않아야 합니다. 30일 보존/명시 정리는 이력 한계이지 무한 영구 보존을 보장하지 않으며 이 DA가 정리/삭제를 실행·승인하지 않습니다.

### N2 — HOLD 유지: mark-only 닫힘·archive가 미보고 의무를 지울 수 있음

§2-4의 seq/group 직접 참조, reported:false 보존, 수신 대기/미보고 분리, 안정 턴 키·오류 통과/기록은 기존 N2의 유실/무한 차단 교정 방향으로 수락합니다. 그러나 §6-3의 연결 계약이 그 완결성을 깨뜨립니다.

- §2-4는 ①mark와 ②최종 답변의 #seq/group을 **둘 다** 요구합니다.
- §6-3:118은 mark를 닫는 사건으로, :120은 mark만 있는 줄을 archive로 옮길 수 있게 합니다.
- :121은 Stop 훅/보드 대조를 ‘mark 없는 것/미표시 수’로 다시 단순화하고 :126의 누락 지표도 mark만 봅니다.

직접 반례: cls=③ seq S를 master가 처리/위임/보류로 mark했지만 최종 답변에는 S를 적지 않았습니다(reported:false). mark-only filter는 S를 미보고 대상에서 제외하며, archive가 활성 큐에서 S를 옮기면 활성 큐만 읽는 Stop/보드에는 줄 자체가 없어집니다. pending도 이미 READ로 0일 수 있어 최초 N2의 ‘읽고 처리했는데 오빠께 안 올라온 10건’과 같은 누락입니다. 이는 기존 원인의 새 저장소 연결부를 검토한 직접 회귀이지 인박스 전체에 대한 새 질문이 아닙니다.

최소 교정은 cls①~④의 보고 의무 완료를 mark **and** reported로 한 곳에 정의해 Stop/show/board/지표/묶음/보관 모두가 같은 predicate를 쓰게 하는 것입니다. mark만 있는 미보고 줄은 활성 보고 의무에서 빠지면 안 됩니다. archive가 mark-only 자료를 이동시켜도 보고 reader가 의무를 계속 대조하도록 설계할 수 있지만, 더 단순한 방법은 보고 의무 대상에서 reported:false인 줄의 archive를 거부하는 것입니다. 그룹은 아직 보고되지 않은 구성 seq까지 같은 조건으로 유지해야 합니다.

가짜 직접 회귀는 ‘mark 성공·최종 #seq 없음·reported:false→Stop 미보고 유지/board 1/archival 후 유실 0’, 이후 직접 보고 확인으로 reported:true가 된 뒤만 닫힘/보관, 일부만 보고된 group을 포함해야 합니다. 이번 :72,133의 일반 mark/압축/기준표 시험은 이 predicate 충돌을 자동 해결하지 않습니다.

## §8 통합 이관 — 두 번째 HOLD, 연속 리뷰 종료

수락 항목은 N1 단일 물리 발급 권위/seed, N3 불변 snapshot/변경 이력, N2의 유한 hook 차단·오류 가시성·seq 식별 방향입니다. 잔여 단일 원인은 **처리 mark와 사용자 보고 완료를 별개 상태로 만들고도 mark-only 닫힘/보관을 유지하는 predicate 불일치**입니다. 인박스 자체의 새로운 원인은 추가하지 않았습니다.

최소 다음 과제: master가 canonical 보고-완료 predicate를 저장소/reader/archiver의 구현 계약으로 고정하고, 위 seq S의 가짜 상태 시험 하나에서 mark 이후에도 보고 의무가 남는지 확인합니다. 같은 턴 차단 1회라는 liveness 제한은 그대로 유지하며 실제 Slack/인터뷰를 막아 세우는 관찰이 필요하지 않습니다.

최초 발주 14:20:31부터 약 13분, 교정 요청 14:30:30부터 약 3분 이내 검토를 종료했습니다. 기존 예산을 초기화하지 않았고 두 번째 HOLD이므로 추가 r3 설계 리뷰/반복 탐색은 하지 않습니다. architect는 수락/잔여 원인/직접 상태 반례/최소 구현 시험을 master에게 통합 이관해야 합니다.

HOLD

## §9 구현 DA 재확인 요청 — 나노 4 인박스 (byz-harness-arch-claude#14 → byz-harness-da-codex#0 · 2026-10-08)
- 범위 고정(새 설계 반박 0 · 10분 1회 · bounded_da_review): §8 의 «N2 잔여 = 정본 술어 하나로 고정» 이 구현에서 지켜졌는가만.
- 고정 sha: nano/v425-master-inbox `d2ce4b6ff3` (워크트리 .worktrees/harness-v425-master-inbox). 파일: scripts/fable-team-bin/ft_inbox_core.py · ft-inbox.py · ft-inbox.sh · tests/harness/test_inbox.sh · tools/comm-canonical/mbox.sh(훅 1줄).
- 확인할 것 3: ①`obligation_closed`(ft_inbox_core.py:77) 가 유일한 닫힘 판정이고 show·archive·묶음·report 가 그것만 부르는가(다른 곳에 mark/reported 조건 재작성 0) ②cls ③ 줄 mark 후 report 없음 → archive 이동 거부 · 큐에 그대로 / 묶음 G={S1,S2} S1 만 report → G 미닫힘 ③미상 = 보고 의무 대상(MUST_REPORT) · Haiku 분류는 send 경로 밖(비동기 · 실패 시 미상 유지).
- arch 재현 출력(복붙): 「REFUSED seq=103 cls=③ reported=false — 술어 거짓(이동 거부)」 · 「PASS 술어: mark 후 report 없음 → archive 이동 거부」 · 「PASS 묶음: S2 대상 유지(archive 거부)」 · 「PASS 미상: mark 만 → archive 이동 거부(REFUSED)」 · 「PASS send 소요 1초 미만(Haiku sleep 8 대기 0)」 · test_inbox rc=0 PASS 48.
- 판정 형식: APPROVE / HOLD(반례 1개 · 파일:줄) — 이 파일 §10 에 append · 결론 1줄 mbox.

## §10 인박스 구현 재확인 — #62918

고정 SHA `d2ce4b6ff312dda92c9bdcc5aa7259beca5d0789`의 지정 세 확인사항만 검토했습니다. 종료된 설계 리뷰를 재개하거나 새로운 인박스 원인을 탐색하지 않았습니다. 나노 워크트리 HEAD와 관련 core/CLI/시험/comm 파일이 그 SHA와 같고 미커밋 변경이 없음을 확인했습니다. harness-ops Serena에는 새 파일이 없어 고정 SHA의 git show로 소스와 시험을 대조했습니다.

### ① 정본 술어 단일화 — APPROVE

ft_inbox_core.py:77–79가 유일한 닫힘 조건입니다. mark가 존재하고, 보고 의무 대상이면 reported가 정확히 True여야 닫힙니다. group_closed는 구성원 모두에 이 술어를 적용합니다(:82–83). show는 group_closed 및 obligation_closed로 조회 목록을 만들고(ft-inbox.py:69–79), archive의 move/stay도 group_closed만 사용합니다(:131–144).

report는 reported=True를 갱신하는 상태 변경(:127–128)이며 닫힘을 따로 계산하지 않습니다. archive의 mark 검사(:138)는 거부 사유 출력용일 뿐 이동 허용 조건의 재작성은 아닙니다. 이 범위에서 별도의 mark-only 닫힘/보관 조건은 찾지 못했습니다.

### ② 미보고·부분 묶음 보존 — APPROVE

실행에서 `REFUSED seq=103 cls=③ reported=false — 술어 거짓(이동 거부)`, mark 후 show 유지·archive 거부·큐 보존, report 후 닫힘/보관을 확인했습니다. 고정 test_inbox.sh:76–86이 그 직접 상태 회귀를 검사합니다.

G={401,402}를 mark한 뒤 401만 report하면 show에 G가 남고 archive는 402를 거부했습니다. 둘 다 report한 뒤에만 닫혔습니다(:97–107). 이로써 앞 설계의 mark-only archive에 따른 보고 의무 유실 반례를 지정 구현에서 차단합니다.

### ③ 미상·비동기 분류 — APPROVE

MUST_REPORT에 미상이 명시돼 있고(ft_inbox_core.py:15), 미상 mark만으로 archive가 거부되는 새 회귀도 통과했습니다(test_inbox.sh:91–95). ingest는 규칙표로 미상을 먼저 영속화한 뒤 별도 Popen으로 classify를 실행합니다(ft-inbox.py:38–46). 분류 실패는 미상 유지와 hook-errors.log를 남깁니다(:50–60).

가짜 Haiku 실패·미상 우선순위 유지 시험, sleep 8을 넣은 가짜 Haiku에서도 copied send가 1초 미만에 반환하고 이후 라벨만 갱신하는 시험(:135–146)이 통과했습니다. 실제 Claude/Haiku API를 호출한 성능 증거가 아니라 분리 실행 경계의 fixture 증거입니다.

### 실행 증거·최종 판정

명령: 고정 워크트리에서 `bash tests/harness/test_inbox.sh`. 결과: **48 PASS · RESULT fail=0 · exit 0**. test_kit_bin_sync도 suite 안에서 PASS했습니다. 실행 중 C.UTF-8 locale 경고는 관찰됐지만 위 단언/종료 코드 실패는 없었습니다.

시험은 mktemp FT_ROOT의 가짜 mailbox/body/queue, 가짜 Haiku와 임시 copied comm을 사용합니다. 실 Slack/LLM·운영 mailbox 발신·명부/설치/서비스 변경은 없습니다. 시험 프로세스가 생성한 fixture 쓰기/정리 외에는 요청한 판정문만 추가했습니다.

**지정 정본 술어 구현 재확인 APPROVE**입니다. 이는 §8 통합 이관 뒤 배정된 좁은 구현/관찰 과제의 종료이며 기존 설계 HOLD 횟수/예산을 초기화하는 새 설계 반복이 아닙니다. 인박스 전체·planner Stop/PreToolUse 연결·보드 및 사용자 최종 보고의 종단 누락 0을 인증하지 않습니다. master가 후속 hook/board의 같은 술어 소비 및 실제 운영 전환 검증을 이어받아야 합니다.

요청 artifact 15:01:50 KST부터 약 6분 이내로 이번 단발 10분 안에 재확인을 종료했습니다.

APPROVE
