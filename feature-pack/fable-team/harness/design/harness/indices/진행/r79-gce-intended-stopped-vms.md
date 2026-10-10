# 인덱스: GCE 가드 ⑥ — «의도된 정지» VM 등록으로 CCU VM 2대 A1P 경보 해제 (R79 · 판정 830)
<!-- ledger: design/harness/GOAL-harness.md -->
- Issue: 없음 → R79(판정 830 · master#25 발주 #71578)
- 상태: 대기
- 선행: 없음
- 제안서: 없음 — 오빠 판정 830 직접 지시(CCU VM 2대 보존 + 의도된 정지 등록)
- 시험 입력: 기존 `tests/scripts/test_gce_guard_coverage.py` 의 `guard` 픽스처(가짜 gcloud · 임시 `GCE_GUARD_OUT`·`GCE_GUARD_MODE_FILE`) — 실 gcloud·VM 조작 0
- 기준값: `state/gce-op-model/BREACH.md` = A1P:ccu-stress-stt-tts · A1P:ccu-stress-vllm escalated 134h(2026-10-10 00:44Z) · `.runkeys` 에 그 2키만

## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
골의 축: C 「업그레이드하고 레포에 커밋 푸시 … 배포 발행(슬랙) 수신해 반영」 + B 「메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의」. 판정 830 · GCE 감시 경보 정상화.

## 배경 (한 단락 — 나노워커가 이 파일만 읽고 착수 가능해야 함)
GCE 가드(`scripts/ops/gce-guard-check.sh` · launchd 1시간마다 · `.worktrees/ops-guard` 에서 실행)의 점검⑥은 GPU 인스턴스를 모두 열거한다. 약정 등록 VM(`ops-mode.env` `CUD_VMS`)이 아닌 GPU 인스턴스가 RUNNING 이면 `A1` FAIL, 그 밖 상태면 `A1P` FAIL 을 낸다. CCU 시험용 VM 2대(`ccu-stress-stt-tts` · `ccu-stress-vllm`)는 TERMINATED 로 보존 중이라 10-04 부터 A1P 가 escalated 로 남아 있다. 오빠가 이 2대를 «보존 + 의도된 정지»로 정했다(판정 830). 그래서 `ops-mode.env` 에 `INTENDED_STOPPED_VMS` 를 두고, ⑥ 분기에서 «등록된 이름 ∧ TERMINATED» 만 PASS(의도된 정지 표기)로 바꾼다. RUNNING 은 등록 여부와 상관없이 지금처럼 `A1` FAIL 이다(누가 켜면 바로 다시 경보). TERMINATED 가 아닌 다른 상태(STOPPING·SUSPENDED·STAGING 등)는 지금처럼 `A1P` FAIL 이다. ★옛 설계 rev.5(D-1)는 «해소는 삭제 또는 봉투 편입이지 목록 등재가 아니다»라고 적었다 — 판정 830 이 그 원칙을 이 2대에 한해 바꾸므로, 그 주석을 판정 830 근거로 고친다.★

## 사전검증
- 소환: 아니오
- 면제: 설정 1줄 + ⑥ 분기 1곳(등록명 ∧ TERMINATED 만 PASS · RUNNING·기타 상태 판정 무변화) · 뮤테이션 시험으로 닫음 — arch 서명 byz-harness-arch-claude#26

## 조사 근거
- `scripts/ops/gce-guard-check.sh:449`~`:457` ⑥ 미등록 분기(`:451` RUNNING → A1 · `:455` 그 밖 → A1P · 바로 위 주석이 D-1 원칙) · `:230` `EXP_6` 분모(열거 1 + 등록 VM 수 · 발견마다 floor 위로 늘어남 — PASS 도 `obs` 를 부르니 분모 영향 0) · `:118`~`:128` `render_breach`(미해소 0이면 BREACH.md 삭제) · `:201`~`:206` 모드 파일 로딩.
- `infrastructure/gpu/gce/ops-mode.env` `CUD_VMS` 줄(새 변수는 그 아래).
- launchd `com.byz.gce-guard-check.plist`: 스크립트·`WorkingDirectory` = `.worktrees/ops-guard`(detached origin/main 2387870fb8) · `GCE_GUARD_OUT` = 루트 `state/gce-op-model/` → 모드 파일과 스크립트는 ops-guard 작업 트리에서 읽힌다.

## 구현 범위 (닫힌 목록 · 나노 브랜치는 origin/main 기준)
1. `infrastructure/gpu/gce/ops-mode.env`: `INTENDED_STOPPED_VMS="ccu-stress-stt-tts ccu-stress-vllm"` + 주석 1줄(판정 830 · 보존 · TERMINATED 만 PASS · 켜면 A1).
2. `scripts/ops/gce-guard-check.sh` ⑥ 미등록 분기의 `else`(RUNNING 아님) 안: `case " ${INTENDED_STOPPED_VMS:-} " in *" $n "*)` ∧ `[ "$st" = "TERMINATED" ]` 이면 `pass 6 "⑥ $n 의도된 정지(판정 830 · TERMINATED · 켜지면 A1 FAIL)"`. 그 밖은 지금 `fail 6 "A1P:$n" …` 그대로. 이름 비교는 지금처럼 공백 구분 정확 일치(하위 이름 오탐 0). D-1 주석은 판정 830 근거로 고친다.
3. 시험 `tests/scripts/test_gce_guard_coverage.py` 에 4건 추가(기존 `guard` 픽스처 재사용):
   - ①등록 + TERMINATED → PASS 줄 · `A1P` 키 0.
   - ②등록 + RUNNING → `A1:<이름>` FAIL(등록이 RUNNING 을 덮지 않음).
   - ③등록 + SUSPENDED(또는 STOPPING) → `A1P` FAIL 그대로.
   - ④미등록 + TERMINATED → `A1P` FAIL 그대로 · 하위 이름 오탐 0(`ccu-stress-vllm-2` 는 등록 아님).
   - 뮤테이션: 2번 분기를 지우면 ①이 빨개지고, TERMINATED 조건을 지우면 ③이 빨개져야 한다.

커밋은 자기 브랜치, **push 금지**. **금지**: VM·디스크 조작(gcloud stop/start/delete 0) · `CUD_VMS` 변경 · ops-guard 워크트리 직접 수정 · 라이브 plist 수정.

## 완료 조건 (닫힘 판정 기준 — ops 수락 판정문)
- `python3 -m pytest tests/scripts/test_gce_guard_coverage.py -q` rc=0(기존 + 4건) · `bash -n scripts/ops/gce-guard-check.sh`.
- 카드 증거 줄 형식(필수 · 시험 칸은 명령 1개 · 없으면 반송): `세트: <40hex> · 시험: python3 -m pytest tests/scripts/test_gce_guard_coverage.py -q rc=0 · 이슈: 0`.
- 랜딩·적용(master 집행 · 카드 밖) — 아래 두 길 중 하나:
  - **ⓑ 로컬 우선(추천 · push 0 · 되돌릴 수 있음)**: 나노 시험 PASS 뒤 master 가 나노 브랜치의 두 파일을 `.worktrees/ops-guard` 작업 트리에 `cp` → `cmp`(나노 커밋 바이트와 같음) → 가드 1회 수동 실행(plist 와 같은 env `GCE_GUARD_OUT=<루트>/state/gce-op-model/gce-guard-check.last.log`). 되돌림 = `git -C .worktrees/ops-guard checkout -- <두 파일>`. main 랜딩 뒤 `checkout -- <두 파일>` → `checkout --detach origin/main`(바이트 같아 충돌 0).
  - **ⓐ main 랜딩**: 판정 739 묶음 push 에 포함(push 는 오빠 승인값 필요) → `git -C .worktrees/ops-guard fetch origin && git -C .worktrees/ops-guard checkout --detach origin/main` → 다음 1시간 실행.
- 해제 확인(둘 다): ①`state/gce-op-model/gce-guard-check.last.log` 에 `PASS ⑥ ccu-stress-stt-tts 의도된 정지` · `PASS ⑥ ccu-stress-vllm 의도된 정지` 2줄 ②`BREACH.ledger` 의 두 키 state = `resolved` ③`test ! -e state/gce-op-model/BREACH.md`(미해소 0이면 가드가 지운다 · 다른 건이 생기면 그 건만 남음 — 그때는 ②로 판정).
- 진행→완성 이동은 `ft-index-move.sh <파일> 완성 --da <판정문#§N>`.

## 상태
대기 — master spawn 대기

## 결과
(닫을 때 증거 줄)
