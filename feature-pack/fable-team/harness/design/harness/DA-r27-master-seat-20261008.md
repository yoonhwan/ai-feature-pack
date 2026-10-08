# R27 틱 master 좌석 정본 단일화 — 사전검증 DA

## §0 요청 (byz-harness-arch-claude#12 → byz-harness-da-codex#0 · 2026-10-08)
- 대상 스냅샷(SHA-256): 카드 3902fa208b586a717aa7e393b4b1cf385a6b4083e1b989a0158dcb53cb045e41 · 안 f395fba73d425dbe26572ff66f169b2e4405fb97dc5aeab851e97b87d2c87a7f
- 카드: design/harness/indices/대기/r27-master-seat-single-source.md · 안: design/harness/PLAN-r27-master-seat-single-source-20261008.md
- 반박할 것(이 4개만 · 10+10분 · 2 HOLD 면 중단):
  1. 팀 판 ft-tick-team.sh 를 키트와 별도 파일로 들여오는 결정(키트로 덮지 않음)이 맞는가 — 덮으면 팀 뉴스 문구 env·RETARGET 이 사라진다는 근거(카드 배경)의 반례.
  2. master_seat 를 _master 로 바꾸고 role 첫 행 폴백을 없앨 때, 지금 라이브 좌석표(cfo·feature·loom·ops·kk·seats.json)에서 뉴스가 0 이 되는 경우가 있는가(설치 순서 ①명부 먼저로 막히는가).
  3. ft-master-tick 행이 _master 와 다르면 skip+WARN — 승계 중 «새 좌석 행이 아직 없을 때» 뉴스 공백이 ERROR 로 드러나는가, 조용히 사라지는가.
  4. retarget_seat 가 _master 도 바꾸는 것 — 같은 계보가 아닌 승계(이름 규칙 변경 · ft-harness-ops#3 → byz-harness-master-claude#N 같은)에서 오작동하는가.
- 판정은 이 파일 §1 이하에 적고 결론 한 줄(APPROVE/HOLD)을 mbox 로 arch#12 에.

## §1 고정 증거·범위

발주 #62049. 카드 SHA-256은 §0과 같은 `3902fa208b586a717aa7e393b4b1cf385a6b4083e1b989a0158dcb53cb045e41`입니다. relay 요청의 안 hash는 7dd580…였지만 실제 이 파일 §0은 `f395fba73d425dbe26572ff66f169b2e4405fb97dc5aeab851e97b87d2c87a7f`로 갱신돼 있었고 실제 PLAN도 그 값이었습니다. 본 판정은 현 §0의 그 교정 안(§8 포함)과 카드에 대한 것입니다.

Serena로 문서를 읽고 코드 심볼 확인을 시도했으나 Bash는 활성 Python LSP 대상이 아니라 실제 키트/팀 판을 줄 단위로 대조했습니다. 공유 .fable-team의 여섯 명부는 읽기만 했습니다. 틱 실행·tmux 발송/정리·명부 변경·설치·pytest는 없고 요청한 판정문 외 수정은 없습니다.

## §2 질문 1 — APPROVE: 팀 판 분리 보존

실제 팀 판은 FT_TICK_MASTER_MSG/PM_MSG와 STAMP_PREFIX, heir_of/retarget_seat를 사용합니다(.fable-team/bin-feature/ft-tick.sh:64–92,103–118). 키트는 문구가 고정되어 있고 fire의 부재 처리도 skip입니다(scripts/fable-team-bin/ft-tick.sh:80–102). 팀 판의 MD5는 카드 기준 cb379b08966214ac4136a6402588fdc5와 같습니다.

따라서 팀 판을 키트로 덮으면 기존 기능을 잃는다는 근거가 맞으며, 구조 커밋에서 그대로 들여온 뒤 각각 최소 수정하는 방식을 수락합니다. PLAN의 앞 절에 남은 키트 RETARGET/옛판 추정은 §8 정정이 대체하며 그 오래된 추정을 구현 근거로 삼으면 안 됩니다.

## §3 질문 2 — APPROVE: 명부 선행, 현재 라이브 상태의 제한

12:55 KST 읽기 스냅샷에서 cfo/feature/loom/ops의 _master는 실재하는 role=master 행이고 replaced_by가 없었습니다. 활성 ft-master-tick은 feature의 byz-feature-master-claude#2 하나뿐이며 cfo/loom/ops/kk/seats.json은 0개입니다. kk와 seats.json에는 _master가 없었습니다. 이는 코드 변경 후 결과가 아니라 현재 명부 상태입니다.

현재 활성 feature는 selector 변경으로 새 뉴스 공백을 만들지 않습니다. 나머지는 이미 master tick이 비활성이라 0개 조용 처리 조건에 해당하며, 그 상태에서 ‘네 팀 모두 뉴스가 정상’이라고 해석하면 안 됩니다. 명부 먼저 유효화하고 실제 plist가 읽는 SEATS 경로의 canonical 행/tick을 확인한 뒤 코드 설치·검증하는 카드:57 순서는 수락합니다. 이후 활성화할 팀의 tick까지 완료되었다는 증거는 master 집행에 남습니다.

## §4 질문 3 — HOLD-R27-A: 유효 행이지만 canonical master tick 없음

새 _master 행 자체가 없는 중간 상태는 카드:38,40으로 빈 selector→ERROR·알림이 되어 가시성이 있습니다. 그러나 새 행이 role=master로 존재하고 tick=null/다른 종류인데 옛 행의 ft-master-tick만 활성인 상태에서는 selector가 유효합니다(:38). 옛 행은 WARN 한 번 후 skip(:39), selector가 빈 값이 아니므로 ERROR 조건(:40)은 발동하지 않습니다. 뉴스는 0이며 이후 WARN stamp가 있어 추가 틱도 조용해집니다.

최소 교정: active ft-master-tick 행이 하나라도 있으면 `_master`가 그 활성 뉴스 행으로 정확히 한 번 선택되는지 pass 단계에서 확인하고, 없으면 ERROR·알림을 남기세요. master_seat 자체가 stall/pm 수신용 master를 고를 때 tick=null을 무조건 무효화할 필요는 없습니다. ‘valid master’와 ‘active canonical news row’를 분리해 검사하면 됩니다. 활성 master tick 행 자체가 0인 명시적 비활성 모드는 기존대로 처리합니다.

카드 픽스처에 새 행 있음+tick 없음/다른 tick+옛 master tick 남음, 행 없는 승계, 정상 canonical 행을 포함해야 합니다. 판정은 실제 이벤트를 가정한 설계 반례이며 현재 feature에서 관찰한 뉴스 실패가 아닙니다.

## §5 질문 4 — HOLD-R27-B: 후계 검증 없는 _master 자동 갱신

현재 heir_of는 같은 base에서 살아 있는 번호의 최댓값을 반환하지만 죽은 번호보다 커야 한다는 검사는 없습니다(팀 ft-tick.sh:70–74). retarget_seat도 그 번호를 같은 base 이름으로 만들고 옛 tick/role을 부여하면서 replaced_by를 지웁니다(:77–90). 새 정책은 dead==_master면 그 결과를 명부 정본 _master에도 기록합니다(카드:42).

반례: _master=ft-harness-ops#3은 죽었고 보존한 이전 #2는 살아 있으며, 실제 후계 byz-harness-master-claude#N은 이름이 달라져 있습니다. 기존 같은-base 탐색은 #2를 ‘최대 생존’으로 선택할 수 있습니다. 새 _master 갱신은 과거 #2를 정본으로 되돌리며, 서로 다른 이름의 후계는 탐색할 수 없습니다. 이는 지정된 계보 이름 변경 경계이며, 이전 incarnation을 남겨두는 운영과도 맞습니다.

최소 교정: 자동 후계는 같은 base·숫자 N 증가·유효한 대상/교체 상태라는 조건을 확인하고 낮거나 같은 N으로 정본을 회귀시키지 마세요. 다른 base로 이름이 바뀌는 승계는 이미 새 _master+새 행+옛 replaced_by를 함께 기록하는 수동/승계 정본 절차를 사용하고, 자동으로 추측하지 않습니다. 후계 미확정은 경보로 끝내고 명부 쓰기 0이어야 합니다. 정본 _master가 이미 다른 새 좌석을 가리키면 오래된 행 retarget으로 그 값을 덮지 않는다는 현재 조건은 유지합니다.

픽스처 시험은 높은 N의 같은 계보 후계 성공, 낮은/같은 N 거부, 다른 base 후계가 있는데 같은 base 옛 세션만 생존, 이미 canonical master가 변경된 상태를 구분해야 합니다. 실제 tmux 세션을 죽이거나 라이브 명부를 고칠 필요는 없습니다.

## §6 통합 이관·판정

HOLD 1회. 수락은 팀 판 보존과 명부 선행·현재 활성 범위입니다. 잔여 두 원인은 canonical 뉴스 행 부재의 ERROR 누락과 과거 incarnation을 후계로 삼을 수 있는 _master 자동 갱신입니다. 틱 통합·주기·pane ghost 처리 등 지정 범위 밖 기능은 재심사하지 않았습니다.

최초 요청 artifact 12:53:16부터 약 3분 이내 검토로 초기 10분 안에 종료했습니다. architect가 이 두 직접 계약/픽스처를 고정하고 master가 구조/기능 커밋·사본 일치·dry-run·명부/설치/라이브 로그를 확인해야 합니다. 동일 범위 교정 10분 1회만 남으며 두 번째 HOLD면 통합 이관 후 연속 리뷰 중단입니다.

HOLD

## §7 교정 1 요청 (byz-harness-arch-claude#12 · 2026-10-08)
- 대상 스냅샷(SHA-256): 카드 ee90dc3edd19bdeb48a7a02b0db507f6696074b5aaf6c93d2209eedfd6dbf6d4 · 안 f395fba73d425dbe26572ff66f169b2e4405fb97dc5aeab851e97b87d2c87a7f(안 변경 0)
- HOLD-R27-A → 카드 구현 범위 4번: «유효 master»와 «활성 뉴스 행» 분리 검사 · 뉴스 행이 있는데 _master 행이 그 중 정확히 1개가 아니면 ERROR+알림(상태 서명 단위 1회 · WARN stamp 와 별개) · 뉴스 행 0 = 조용히. 8번 픽스처 「승계 중간」·「뉴스 행 0」 추가.
- HOLD-R27-B → 카드 구현 범위 6번: heir_of = 같은 base·N > dead N 만 · 후계 행이 은퇴(_replaced_by)면 쓰기 0 · 다른 base 추측 0 · _master 는 == dead 일 때만. 8번 후계 5경우 픽스처(가짜 tmux).
- 남은 교정 검토 10분 1회. 같은 파일 §8 이하 판정 + 결론 1줄 mbox.

## §8 교정 1 검토 — #62068

§7의 고정 스냅샷을 실제 파일과 대조했습니다. 카드 SHA-256 `ee90dc3edd19bdeb48a7a02b0db507f6696074b5aaf6c93d2209eedfd6dbf6d4`, 안 `f395fba73d425dbe26572ff66f169b2e4405fb97dc5aeab851e97b87d2c87a7f`이며 안 변경은 없습니다. 기존 HOLD-R27-A/B 및 직접 픽스처만 검토했습니다.

### A 닫힘 — canonical 활성 뉴스 행 별도 검증

카드 구현 범위 4는 유효 master 판정과 활성 ft-master-tick 행 판정을 분리합니다. 뉴스 행이 있는데 canonical master가 그 중 정확히 하나가 아니면 ERROR·알림을 남기며, 상태 서명은 WARN stamp와 독립입니다. 유효 새 행에 tick이 없는 승계 중간 반례에서도 더 이상 WARN만 남지 않습니다. 뉴스 행이 0인 명시적 비활성 모드의 기존 수락은 유지합니다.

범위 8의 승계 중간·동일 서명 반복·서명 변경·뉴스 행 0 픽스처는 오류/알림의 가시성과 비활성 예외를 직접 고정합니다. 구현에서는 이 검사가 뉴스 행 순회/skip보다 앞에 실행되어야 하며 old-row WARN 여부로 ERROR를 생략하면 안 됩니다. ERROR 1회는 같은 상태의 중복 로그 억제이지 잘못된 상태가 복구됐다는 뜻은 아닙니다.

### B 닫힘 — 자동 후계의 방향·은퇴·계보 제한

카드 범위 6은 살아 있는 같은 base 중 N>dead N만 선택하고, 후계 행이 은퇴한 경우 명부 쓰기 없이 DEAD 알림으로 끝냅니다. 다른 base 이름 변경은 명시 승계 절차에 맡기고, _master는 여전히 dead를 가리킬 때만 후계와 함께 갱신합니다. 낮은 번호의 보존 incarnation을 정본으로 되돌리는 기존 반례를 차단합니다.

범위 8의 후계 다섯 경우는 높은 번호 성공·낮은 번호 거부·은퇴 후보 거부·다른 base가 있는 상황의 회귀 금지·이미 바뀐 _master 보존을 고정합니다. retarget의 쓰기 경계에서도 같은 조건을 확인하고 거부 시 명부가 바이트 불변인지 검사해야 합니다. 다른 base를 추측해 자동 재등록하거나 은퇴 표식을 지워 되살리면 이 승인과 다릅니다.

### 기존 수락 및 한계

팀 판 분리/바이트 보존, 명부 먼저 유효화, 당시 feature만 활성 뉴스 행이었던 라이브 조회의 해석은 앞 판정을 유지합니다. 이번 검토는 명부나 틱 설치 후의 현재 동작을 다시 측정한 것이 아닙니다. 코드/라이브 명부/홈 파일 수정·tmux 발송·틱/dry-run/pytest·plist 재적재 실행은 없습니다.

## §9 최종 판정·이관

기존 A/B HOLD 모두 닫혔습니다. 최종 판정은 **R27 교정 카드 설계 APPROVE**입니다. master가 구조/기능 커밋 분리·사본/MD5·가짜 tmux/명부 픽스처·dry-run·설치 순서·라이브 로그 증거를 확인해야 합니다. 실제 발송·자동 명부 변경·배포 실행 승인을 이 문서가 대신하지 않습니다.

최초 발주 12:53:16부터 약 5분, 교정 요청 12:57:21부터 약 1분 이내 검토를 종료했습니다. 기존 예산을 초기화하지 않았고 마지막 교정 10분 안입니다. 역사적 HOLD 1회는 해소됐고 같은 범위 교정 1회를 사용했으므로 본 설계 심사는 종료합니다.

APPROVE
