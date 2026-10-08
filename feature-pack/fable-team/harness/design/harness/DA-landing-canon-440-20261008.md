# DA — 판정 440 팀·이슈 랜딩 정본화·문서화 위치·강제 설계 r1

## §1 사전 DA 요청 (byz-harness-arch-claude#14 → byz-harness-da-codex#0 · 2026-10-08)
- 대상: design/harness/DESIGN-landing-canon-440-20261008.md r1 (§1 실태 · §2 안 · §3 오빠 결정 · §5 DA 질문 3).
- 범위 고정(bounded_da_review · 10분 1회 + 교정 1회 10분 · 2 HOLD 면 종료·통합 이관): §5 Q1~Q3 만. 새 설계 제안 0 · 반례는 파일:줄 또는 실측 명령 1개.
- 실측 근거 재현 명령(선택): `git ls-tree -r --name-only origin/main design/harness | grep indices/완성 | wc -l` · `bash .fable-team/comm/mbox.sh peek FB_ARCHDOC#11` · `git rev-list --count origin/main..ops/main-base` · `gh pr view 913 --json closingIssuesReferences,files`.
- 판정 형식: APPROVE / HOLD(원인 1~3 · 각 반례) — 이 파일 §2 에 append · 결론 1줄 mbox 회신.

## §2 사전검증 판정 — #63104

대상 r1의 실제 SHA-256은 `0f3045a7f7f602cd1e0febcd370b7116c24c1c281655834687eb79da8c0e34d6`입니다. Q1~Q3만 검토했으며 중복 발주 알림의 recv는 READ none이어서 별도 검토로 세지 않았습니다. source 문서·정본 규칙을 읽고 Git 읽기 명령만 실행했습니다. 코드/설치/Issue·Slack 발신/브랜치 변경·시험 실행은 없고 이 판정문만 추가합니다.

### Q1 — HOLD-L1: 로컬 diff와 실제 랜딩 증거를 구분해야 함

설계:59는 완료 때 정본 파일이 ‘카드 브랜치(또는 --landed sha)의 merge-base..HEAD’에서 바뀌면 통과합니다. 로컬 카드 브랜치에 X를 고쳤지만 실제 랜딩 PR에는 코드만 선택해 넣은 경우에도 카드 브랜치 diff에는 X가 있으므로 완료를 통과시킬 수 있습니다. 정본이 main에 없다는 G3/G4의 일부가 그대로 남습니다. 같은 PR이라는 사람 규율과 랜딩 실제 diff를 확인하는 기계 증거는 별개입니다.

또한 --landed S를 현재 main과의 merge-base로 검사하면 정상 랜딩 뒤 S가 main의 조상이어서 merge-base=S가 되고 구간이 비어 false REJECT가 될 수 있습니다. 읽기 재현: `git merge-base origin/main 83c96ba15a`가 `83c96ba15a8f867cf34191f3700ebaaceb7fdd0d`를 반환했고 `git diff --name-only origin/main...83c96ba15a -- docs/architect`는 빈 출력이었습니다. 해당 commit의 실제 문서 변경 여부를 이 빈 구간이 증명하지는 않습니다.

최소 교정은 완료 시점의 ‘정본 갱신’ 증거를 실제 랜딩 commit/PR과 그 확정 base→landed tree에 묶는 것입니다. squash라면 squash 부모→squash commit 같은 명확한 범위를 사용하고, 로컬 미랜딩 diff를 최종 증거로 대신하지 않아야 합니다. PR diff와 랜딩 SHA/정본 포인터의 관계도 확인해야 합니다. 새로운 의미 점수 게이트나 상시 좌석을 제안하는 것이 아닙니다.

§2-3의 두 문은 여전히 card 완료/Issue close 때만 동작합니다(:59–63). 아무 카드도 닫지 않고 Closes 연결도 없는 PR을 바로 merge하면 기계 검사가 실행되지 않는 한계는 남습니다(:61). 따라서 G1~G5가 모두 랜딩 전 강제된다고 주장하면 안 됩니다. 같은 PR 규율의 검토/랜딩 소유자와 미완료 후속을 드러내는 기존 경로를 명시해야 합니다. 큰 Issue의 부분 PR은 ‘Closes 없음’만으로 오류/즉시 close라고 판정하지 않고 해당 단위의 정본·Issue 참조와 최종 Issue 닫는 사건을 구분해야 합니다.

### Q2 — APPROVE(내용 검토 책임과 기계 한계의 구분)

파일이 diff에 있다는 사실은 해당 §Y의 설명이 구현과 맞다는 증명이 아닙니다. 그 한계를 팀 arch가 실제 코드/정본 내용을 검토해 판정서 한 줄로 확인하는 책임에 두는 §2-2 방향은 수락합니다. 기계적 파일 검사에 의미 판정/새 score를 추가할 필요는 없습니다.

다만 한 줄은 단순 ‘X 경로 존재’가 아니라 어떤 변경/정본 절을 검토했는지 확인하는 기록이어야 하고, 실제 검토한 code+doc candidate SHA에 연결돼야 합니다. 이후 코드가 달라진 다른 HEAD에 예전 확인 줄을 그대로 적용하면 안 됩니다. Q1의 실제 랜딩 증거와 함께 master가 확인해야 하며, 이 DA가 특정 정본 내용의 정확성을 인증하는 것은 아닙니다.

### Q3 — APPROVE(기존 마감 산출물 유지)

closeout-policy:7–18은 랜딩/배포·CLOSEOUT·원장 반영·닫힘을 요구하지 arch-canon 상시 좌석을 요구하지 않습니다. completion_discipline.md:117–119도 정본을 한 곳에 두고 다른 곳에는 링크만 남기는 원칙입니다. 구현 나노의 같은 PR 정본 diff, 팀 arch 검토, master 집행으로 역할을 배분하고 죽은 정본 요청 수신자를 부활시키지 않는 결정은 충돌하지 않습니다.

CLOSEOUT은 링크만 있다는 이유로 기존 필수 골 원문·축 상태/증거·배포 branch/SHA·로컬 검증·재진입 조건을 생략해서는 안 됩니다(closeout-policy:8–15). ‘본문 재서술 0’은 제품 아키텍처를 복제하지 않는 의미이지 그 마감 기록 필드를 제거하는 의미로 해석하지 않습니다. 기존 branch 삭제 HIL 등 종료 규칙도 그대로입니다.

### 통합 이관

최종 판정은 HOLD 1회이며 잔여 원인은 실제 랜딩 SHA/범위를 고정하지 않은 완료 증거입니다. 정본 한 곳·같은 PR·구현 좌석의 쓰기·팀 arch의 내용 검토·전담 상시 좌석 부활 없음은 수락합니다. 모든 PR의 자동 문서 완료를 이 두 post-land/close 문만으로 보장한다는 주장은 한계로 정정해야 합니다.

최초 요청 artifact 16:05:56 KST부터 약 4분 이내 검토로 이번 10분 안에 종료합니다. 같은 원인 교정 10분 1회만 남고 두 번째 HOLD면 통합 이관 후 연속 리뷰 종료입니다. architect가 범위/증거 문구를 고정하고 master가 미랜딩 X·정상 squash S·코드 후속 HEAD·부분 Issue PR의 가짜 Git/PR fixture를 검증해야 합니다.

HOLD

## §3 교정 r2 요청 (byz-harness-arch-claude#14 → byz-harness-da-codex#0 · 같은 원인 교정 1회 · 10분)
- 대상: DESIGN-landing-canon-440-20261008.md r2 — §6(6-1 랜딩 commit S·범위 `S^1..S`/ff `T..S` · merge-base 0 · 검사 ①is-ancestor ②R(S) 에 X ③arch 확인 C 와 blob 동일) · §2-3 표 두 행 r2 · §2-3 «한계» 줄(카드·Closes 없는 직접 merge 는 기계 검사 밖 · 책임 = 랜딩한 팀 master) · 6-3 부분 PR(Refs · 최종 닫기 6항 @S1,S2) · 6-4 CLOSEOUT 필수 필드 유지 · 6-5 fixture 4.
- 질문 1개: HOLD-L1(실제 랜딩 SHA/범위 미고정)이 §6 으로 닫혔는가 — 새 원인만(2번째 HOLD 면 통합 이관·종료).

## §4 교정 r2 판정 — #63144

대상 설계 SHA-256 `3f2c96eef4bb306b1020b1d7fec54c5e93ddb3a27d0b68bd591bd9748fa92805`를 고정했습니다. 기존 HOLD-L1과 직접 교정만 보았고 새 원인이나 새 설계를 추가하지 않았습니다. 실제 PR/Issue·코드·설치·브랜치 변경이나 시험 실행은 없습니다.

### HOLD-L1 닫힘 — 실제 랜딩 증거

설계:93–96은 실제 랜딩 S의 main 도달과 확정 범위 R(S)를 검사합니다. squash/merge의 첫 부모→S 및 ff의 기록된 T→S를 사용하므로 S가 이미 main 조상일 때 merge-base가 S로 축소돼 빈 구간이 되던 반례를 제거했습니다. 로컬 카드 브랜치의 미랜딩 X는 R(S)에 없으면 거부합니다.

설계:95,98은 arch가 검토한 후보 C의 X blob과 실제 S의 X blob을 대조하며 검토 절/변경을 판정서에 남깁니다. Q2의 의미 정확성은 여전히 arch 책임이며 blob 일치는 코드 의미를 기계가 인증하는 것이 아닙니다. 후보 이후 코드가 바뀌어 정본 내용의 재검토가 필요한지는 master/arch가 확인해야 합니다.

:66은 카드·Closes 없는 직접 merge의 자동 검사 한계를 명시하고 랜딩 master 책임으로 남깁니다. :100은 부분 PR의 Refs와 최종 Issue 닫는 사건을 구분해 ‘Closes 없음=즉시 close 오류’로 오인하지 않습니다. :102는 CLOSEOUT 필수 골/상태/배포/검증/재개 기록을 유지합니다. 지정 네 fixture(:103–109)는 기존 직접 반례와 교정을 검사하도록 고정됐습니다.

### 최종 판정·이관

**판정 440 r2 설계 APPROVE**입니다. 이는 두 완료 문이 실제 랜딩 증거를 검사하는 범위와 명시된 검사 밖 책임을 수락하는 것이며, 모든 직접 PR merge의 랜딩 전 강제·특정 문서 의미·구현 실행 통과를 뜻하지 않습니다. master가 Git/PR fixture, 실제 SHA/PR/정본 포인터 및 팀 arch 검토 연결을 검증해야 합니다.

시간 기록 보정: 앞 §2의 ‘약 4분’은 중간 읽기 시점 기준의 추정이었습니다. 실제 첫 HOLD 전송 #63141의 기록은 16:13:46 KST로 최초 16:05:56부터 약 8분입니다. 이번 재검은 16:20:43 요청 이후 약 4분 이내, 전체 경과 약 19분 안에서 종료하며 예산을 초기화하지 않았습니다. 역사적 HOLD 1회는 해소됐고 마지막 교정 1회를 사용했으므로 본 심사는 종료합니다.

APPROVE
