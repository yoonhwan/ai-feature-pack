# 인덱스: codex 좌석 Serena 부팅 경로 — session_id 없는 고정판 + headroom 압축(CCR) 대응 문장 (R66 · 판정 698 ② · arch#25)
<!-- ledger: design/teams/harness/GOAL-harness.md -->
- Issue: 없음 → 요청 원장 `design/teams/harness/REQUEST-LEDGER.md` R66(v65 arch#184 관찰 #67273 · 좌석 보고 #67271)
- 상태: 대기
- 선행: 없음(판정 698 순서상 ① op675b 닫힘 뒤 첫 단위)
- 시험 입력: 스테이징 사본과 홈 BOOT 의 diff · 기존 codex 세션 기록(읽기만) — 실 codex 좌석 기동 0
- 기준값(arch#25 실측): ①codex 설정 `~/.codex/config.toml` 1533–1536행 Serena = 고정 커밋 `cd04838be9a9…`(`get_current_config` 출력 «Serena version: 1.6.2.dev0») — `initial_instructions` 응답에 session_id 가 «없다», `activate_project(project=<절대경로>)` 만으로 활성화됨(좌석 proposal#0 세션 `rollout-2026-10-08T16-44-25-…` 에서 activate → get_current_config 정상) ②실패 좌석 product#0 세션 `rollout-2026-10-08T23-55-33-…` = `get_current_config` 먼저(→ «No active project») · `initial_instructions` 3회 · ★activate_project 0회★ — BOOT 1 문장(「session_id 를 받은 뒤 activate_project(…, session_id=…)」)을 따라 session_id 를 찾다 멈춤 ③codex `model_provider = "headroom"`(config 15·19행 · 8790) — 큰 도구 출력(initial_instructions 원문 14.8 KB)이 헤드룸 압축으로 CCR 참조로 바뀌어 보임 · 좌석은 `headroom_retrieve` 도구를 찾아보다 멈춤 ④홈 BOOT sha256 앞16 `329582414d727dd5`.

## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
하네스 GOAL 표 B / 닫는 증거(정본 복붙): 「REQUEST-LEDGER.md 행 + Issue 「채택/보류 + 오빠 값」 코멘트 + 반영 sha」 — 행 = R66 · 오빠 값 = 판정 698 ②(Issue 없음 → 판정서) · 반영 sha = 이 카드 랜딩 sha.
골의 축: B(개선요청 접수·협의) + C(정본 업그레이드·설치).

## 배경 (한 단락 — 나노워커가 이 파일만 읽고 착수 가능해야 함)
BOOT 1 은 Claude 좌석의 Serena(새 판 · session_id 필수)에 맞춰 「`initial_instructions` 로 session_id 를 받은 뒤 `activate_project(project=…, session_id=…)`」라고 적는다. 그런데 codex 좌석의 Serena 는 고정된 옛 판이라 session_id 가 아예 없고, `activate_project(project=<워크트리 절대경로>)` 만 부르면 된다. 게다가 codex 는 헤드룸 프록시를 거쳐 긴 도구 출력이 «CCR 참조»로 접혀 보인다 — `initial_instructions` 원문이 그렇게 접히자 좌석은 session_id 를 못 찾았다고 판단하고 grep 으로 물러났다(2건). 고칠 것은 문장 하나다: BOOT 1 에 «codex 좌석 = session_id 없이 activate_project 만 · CCR 참조가 보이면 `headroom_retrieve` 로 원문» 을 덧붙이고, 프로젝트 Serena 지침에도 같은 줄을 둔다. 헤드룸·Serena 설치·버전은 건드리지 않는다.

## 사전검증
- 소환: 아니오 · 면제: 문장 2곳 추가(동작·설정 변경 0 · 기존 Claude 경로 문장 무변경) — arch 서명 byz-harness-arch-claude#25
- 조사 근거: `docs/rules/serena-mcp-usage.md:1` · `design/teams/harness/REQUEST-LEDGER.md:70` · `design/teams/harness/staged-514/COMM-GUIDE-BOOT.md:7`
- 7초 룰 점검(판정 666): 외부 호출 0 — 해당 없음.

## 설계 (닫힌 목록)
1. 스테이징 design/teams/harness/staged-r66/COMM-GUIDE-BOOT.md = ★현 홈 BOOT(sha256 앞16 `329582414d727dd5`) 바이트 복사★ 뒤 1번 항목 끝에 한 문장만 덧붙임: 「★codex 좌석(`--agent codex`)은 Serena 고정 옛 판이라 session_id 가 없다 — `initial_instructions`·`get_current_config` 없이 `activate_project(project="<워크트리 절대경로>")` 만 부른다. 도구 출력이 CCR 참조로 접혀 보이면 `headroom_retrieve` 로 원문을 받는다(헤드룸 압축 · 2026-10-09 R66)★」. 그 밖의 줄 변경 0(diff = 1번 항목 1줄 바뀜뿐).
2. `docs/rules/serena-mcp-usage.md` 활성화 절에 같은 뜻 1~2줄(codex 좌석 경로) 추가.
3. 헤드룸 설정·codex 설정·Serena 버전 변경 0(별 후보로만 — 아래 상태 절).

## 구현 범위 (닫힌 목록 · 나노)
기존 파일(수정): `docs/rules/serena-mcp-usage.md`. 새 파일: design/teams/harness/staged-r66/COMM-GUIDE-BOOT.md · tests/harness/test_r66_codex_serena_boot.sh.
시험: ①스테이징 BOOT 와 홈 BOOT 의 `diff` = 바뀐 줄 1개(1번 항목)뿐 · 추가 0 · 삭제 0 — ★홈이 이미 스테이징과 같으면 SKIP(설치 뒤 재실행)★ · 홈이 `329582414d727dd5` 도 스테이징도 아니면 FAIL ②스테이징 1번 줄에 `activate_project(project=` · `session_id 가 없다` · `headroom_retrieve` 세 문자열 ③기존 Claude 문장(`session_id=…`) 그대로 남음 ④`docs/rules/serena-mcp-usage.md` 에 `codex` · `activate_project` 줄 1개 이상 ⑤홈·루트·`~/.codex` 쓰기 0.
커밋은 자기 브랜치, **push 금지**. **금지**: 홈 `~/.claude/skills/tmuxc/COMM-GUIDE-BOOT.md` 직접 수정 · `~/.codex/config.toml` 수정 · 헤드룸 재시작.

## 완료 조건 (닫힘 판정 기준 — ops 수락 판정문)
- 위 시험 rc=0 · arch 독립 재현.
- 카드 증거 줄: 세트: <40hex> · 시험: bash tests/harness/test_r66_codex_serena_boot.sh rc=0 · 이슈: 0.
- 루트 지침: 완료 그 턴에 증거 줄 + arch#25 에 `[완료·휴식]` 1통.
- ★랜딩 뒤 master 집행(앞 단계 값이 다르면 멈추고 보고)★: PR → CI 확인 → 병합(별 명령) → 홈 BOOT cp 전 sha256 앞16 `329582414d727dd5` 확인 → 다르면 cp 0 · arch 반송(그사이 다른 판정이 BOOT 를 바꿨으면 덮어 지운다 — 675 실측) → 같으면 `.bak-r66-<날짜>` 백업 뒤 staged-r66 cp + cmp → 요청 원장 R66 닫힘 표기 → v65 arch(현역) 에 «codex 좌석 Serena 경로 BOOT 1 반영» 1줄.

## 상태
- base_sha: 1ed171ffba815e5726091888010312918f5d44a4 (spawn 2026-10-09)
- 2026-10-09 — 대기/ 생성 (byz-harness-arch-claude#25 · 판정 698 ② · R66 원인 실측 2: BOOT 문장이 Claude 판 전용 + 헤드룸 CCR 압축).
- 정본 영향: 홈 BOOT 1번 항목 1문장 · 프로젝트 Serena 지침 1~2줄 · 설정 변경 0.
- 별 후보(착수 0): ①codex Serena 고정 커밋을 Claude 쪽 판과 맞출지(버전 정합) ②헤드룸이 MCP 도구 출력(Serena)을 압축 제외할지 — 둘 다 설치·인프라 변경이라 오빠 컨펌 뒤.
- 2026-10-09 14:18 — 대기→진행 · 좌석 byz-harness-nano-r66-codex-serena-boot-path#0

## 결과
- 세트: 889c340a1f91f3079463f443ee2c2d48a158c11d · 시험: bash tests/harness/test_r66_codex_serena_boot.sh rc=0 · 이슈: 0
정본 영향 없음: 제품 정본 변경 없음 — 홈 BOOT 1조항 한 문장·serena 지침 2줄만 (arch 재현 #69016 · 판정서 §112).
- 2026-10-09 14:25 — 진행→완성 · DA design/teams/harness/OPS-VERDICTS-20261006.md#§112
