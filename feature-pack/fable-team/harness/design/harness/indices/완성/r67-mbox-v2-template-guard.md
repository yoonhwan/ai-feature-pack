# 인덱스: 추적 사본 mbox-v2.sh 를 제자리에서 부르면 «설치용 사본» 안내 1줄로 멈춘다 (R67 · 판정 698 ③ · arch#25)
<!-- ledger: design/harness/GOAL-harness.md -->
- Issue: 없음 → 요청 원장 `design/harness/REQUEST-LEDGER.md` R67(harness da-claude#0 부팅 보고 #67708)
- 상태: 대기
- 선행: 판정 698 ② R66 카드 닫힘(한 번에 한 단위)
- 시험 입력: 스크래치 임시 폴더에 사본만 복사(옆에 mbox.py 없음) · 임시 폴더에 가짜 mbox.py 스텁 — 루트 우편함·tmux 0
- 기준값(arch#25 실측 · origin/main 2026-10-09 14시대 팁 · ops HEAD 동일 바이트): 추적 사본 두 개 `scripts/fable-team-bin/mbox-v2.sh` · `scripts/harness-install/fable-team/bin/mbox-v2.sh` 는 바이트 동일(sha256 앞12 `40fa21885d92`) · 8행 `MBOXPY="$DIR/mbox.py"` · 두 폴더 모두 mbox.py 없음(git 이력상 한 번도 없었음) → 제자리 실행 시 `python3: can't open file '…/mbox.py'` · 설치본 `.worktrees/v6-realtime-live/.fable-team/{comm,bin}/mbox-v2.sh` 도 같은 바이트(`40fa21885d92`)이고 `comm/` 에는 mbox.py 심링크가 있어 정상(`peek` 실측 `pending=0`).

## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
하네스 GOAL 표 B / 닫는 증거(정본 복붙): 「REQUEST-LEDGER.md 행 + Issue 「채택/보류 + 오빠 값」 코멘트 + 반영 sha」 — 행 = R67 · 오빠 값 = 판정 698 ③(Issue 없음 → 판정서) · 반영 sha = 이 카드 랜딩 sha.
골의 축: B(개선요청 접수·협의) + C(도구 업그레이드).

## 배경 (한 단락 — 나노워커가 이 파일만 읽고 착수 가능해야 함)
`mbox-v2.sh` 는 큐 브리지(`ft-mbox-bridge.sh` 146행 기본값 `$HERE/../comm/mbox-v2.sh`)가 쓰는 «설치용 사본»이다 — 브리지 머리 주석 23행이 「mbox.py 와 같은 디렉토리에 둬야 한다」고 적어 두었다. 그런데 리포 안 추적 사본 두 곳 옆에는 mbox.py 가 없어서, 좌석이 워크트리에서 이 사본을 우편함 명령으로 착각해 부르면 파이썬 오류 한 줄만 나오고 무엇을 써야 하는지 안 알려 준다(R67 원장 기재 «판정 592 mbox.py 분리 뒤 빠짐» 은 실측과 다름 — 그 폴더엔 원래 없었다). 사본 머리에 «옆에 mbox.py 가 없으면 안내 1줄 + exit 2» 를 넣어, 잘못 부른 좌석이 바로 루트 `.fable-team/comm/mbox.sh` 로 가게 한다. 설치된 자리(옆에 mbox.py 있음)의 동작은 바이트 이외 무변경.

## 사전검증
- 소환: 아니오 · 면제: 안내 1줄 + 종료코드만 바꾸는 가드(전송·저장 경로 무변경 · 값 노출 0) — arch 서명 byz-harness-arch-claude#25
- 조사 근거: `scripts/fable-team-bin/mbox-v2.sh:8` · `scripts/harness-install/fable-team/bin/ft-mbox-bridge.sh:23` · `scripts/harness-install/fable-team/bin/ft-mbox-bridge.sh:146`
- 7초 룰 점검(판정 666): 외부 호출 0 — 해당 없음.

## 설계 (닫힌 목록)
1. 두 추적 사본 8행 `MBOXPY=…` 바로 뒤에 가드 1블록: `[ -f "$MBOXPY" ] || { echo "REJECT mbox-v2.sh 는 설치용 사본 — 옆에 mbox.py 없음($MBOXPY). 좌석 우편함은 <루트>/.fable-team/comm/mbox.sh 를 쓴다" >&2; exit 2; }`.
2. 두 사본은 계속 바이트 동일(한 파일 고치고 cp).
3. 그 밖의 줄(전송·doorbell·SELF) 변경 0 — 정본 `tools/comm-canonical/mbox.sh` 와의 오래된 차이(도어벨 분리 전 판)는 이 카드 범위 밖(별 후보로만 기록).

## 구현 범위 (닫힌 목록 · 나노)
기존 파일(수정): `scripts/fable-team-bin/mbox-v2.sh` · `scripts/harness-install/fable-team/bin/mbox-v2.sh`.
새 시험: tests/harness/test_mbox_v2_guard.sh — ①두 사본 `bash -n` ②두 사본 `cmp` 동일 ③임시 폴더(옆에 mbox.py 없음)에서 `peek x` → exit 2 · stderr 에 `설치용 사본` · `.fable-team/comm/mbox.sh` 두 문자열 · 파이썬 트레이스백 0 ④임시 폴더에 가짜 mbox.py(인자를 그대로 echo 하는 스텁) 두면 `peek x` 가 스텁 출력 그대로 · exit 0 ⑤루트 `.fable-team/`·홈·tmux 쓰기 0.
커밋은 자기 브랜치, **push 금지**. **금지**: 루트 `.fable-team/`·`.worktrees/v6-realtime-live/.fable-team/` 쓰기 · 실 우편함 send.

## 완료 조건 (닫힘 판정 기준 — ops 수락 판정문)
- 위 시험 rc=0 · arch 독립 재현.
- 카드 증거 줄: 세트: <40hex> · 시험: bash tests/harness/test_mbox_v2_guard.sh rc=0 · 이슈: 0.
- 루트 지침: 완료 그 턴에 증거 줄 + arch#25 에 `[완료·휴식]` 1통.
- ★랜딩 뒤 master 집행(앞 단계 값이 다르면 멈추고 보고)★: PR → CI 확인 → 병합(별 명령) → 설치본 두 곳(`.worktrees/v6-realtime-live/.fable-team/comm/mbox-v2.sh`·`…/bin/mbox-v2.sh`)은 cp 전 sha256 앞12 `40fa21885d92` 확인 뒤 새 사본 cp + cmp(다르면 cp 0 · arch 반송) → 설치 자리에서 `peek <master 이름>` 1회 정상 → 요청 원장 R67 닫힘 표기.

## 상태
- base_sha: 1c46f335a4a698b5f6e3b66121617086bcbe9368 (spawn 2026-10-09)
- 2026-10-09 — 대기/ 생성 (byz-harness-arch-claude#25 · 판정 698 ③ · R67 원인 실측).
- 정본 영향: 하네스 키트 사본 2 + 설치본 2(같은 바이트) · 홈 정본 0.
- 별 후보(착수 0): 추적 사본 `mbox-v2.sh`(226줄 · 도어벨 분리 전)와 정본 `tools/comm-canonical/mbox.sh` 의 계보 차이 정리 — 브리지 v2 큐를 실제로 쓰는 좌석이 있는지부터 실측.
- 2026-10-09 14:26 — 대기→진행 · 좌석 byz-harness-nano-r67-mbox-v2-template-guard#0

## 결과
- 세트: 9e251d64053649bd0aeeb8181c2fecb329f43adf · 시험: bash tests/harness/test_mbox_v2_guard.sh rc=0 · 이슈: 0
정본 영향 없음: 제품 정본 변경 없음 — 추적 사본 mbox-v2.sh 가드 1블록·시험만 (arch 재현 #69069 · 판정서 §113).
- 2026-10-09 14:31 — 진행→완성 · DA design/harness/OPS-VERDICTS-20261006.md#§113
