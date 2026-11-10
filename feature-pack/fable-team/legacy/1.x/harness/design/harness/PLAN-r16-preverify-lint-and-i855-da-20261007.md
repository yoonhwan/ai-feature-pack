# PLAN — R16 카드 사전검증 lint + i855 DA 소환 판단 (arch#6 · 2026-10-07 · 미커밋)

## 골 원문 (GOAL-harness.md 복붙)
> 내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
> 하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
> 메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

골의 축: 6-b(R16 = feature master#0 #59567 · 오빠 「arch da 기획 안하고 바로 나노」 / R12 Issue 855 닫힘 판정).

---
## (B) i855 215f52056a — DA 소환: ★예★ (먼저 처리)

이유 3줄:
1. 제품 파일 shared/config/settings.py 에 «설정을 안 읽는 스위치» 가 들어갔다(#0 RULE 경계).
2. ★카드에서 벗어난 2곳★ — ⓐ RuntimeError 조건에 `PYTEST_CURRENT_TEST` 탈출구 추가(카드는 «pytest 미적재면 raise» 하나) — 시험이 띄운 자식 프로세스를 위한 것으로 이유는 맞아 보이나, 이 env 하나만 있으면 제품 프로세스도 스위치를 통과한다. 실측: 비시험 코드에 PYTEST_CURRENT_TEST 를 세팅·참조하는 곳 0(git grep · settings.py 자기 자신뿐). ⓑ pulse 2건: 카드는 «실 번역 경로를 여는 키를 코드 대조로 확정 → delenv», 나노는 키 확정 없이 retranslate_rescue._translate_single 을 «빈 번역» stub 으로 바꿨다 — 시험이 원래 보려던 rescue 결과를 가리는지 판정이 필요하다.
3. RED 가 카드 기대(gpu 3 FAILED)와 다르게 2 FAILED — 3번째 건이 왜 RED 에서 안 깨졌는지 설명이 없다(그 건이 Redis·시계에 기대는지, 아니면 재현 조건이 달랐는지).

DA 범위(bounded — docs/rules/bounded_da_review.md: 10분+10분 · HOLD 2회면 중단·사람):
- Q1 스위치가 제품 프로세스(gateway·worker·스크립트)에서 켜질 경로가 0 인가 — PYTEST_CURRENT_TEST 탈출구 포함 · 시험이 띄운 자식이 .env 가 «필요한» 경우(서버 기동 시험)가 조용히 달라지지 않나.
- Q2 pulse stub 이 test_caseA_carry_fires·test_session_isolation 의 단언을 무력화하지 않나(stub 전후 단언 대상이 같은가) · 실 번역 경로를 연 «키» 가 무엇인가(코드 대조).
- Q3 conftest 의 os.environ 강제가 tests/ 밖에서 도는 pytest(있다면)에 안 닿는 것이 맞나.
- 대상 diff = 215f52056a 5파일만 · 판정 형식 = APPROVE / HOLD(구체 반례) / REJECT.

독립 검증 범위(master 가 돌릴 것 — 안전 조건 필수):
- ★env 고정★: PAYMENT_MODE=local_mock · REDIS_HOST=localhost · ★REDIS_PORT=9★(6379 = v6-realtime-live 라이브 dev 컨테이너 — 절대 금지) · LOCAL_VLLM_BASE_URL=http://127.0.0.1:9/v1 · timeout 래퍼 · 대칭 deselect 3(struct3 and finalized · TestHostEnter · selfhost_warms_qwen_vllm) · 명령 = ci.yml 145행 그대로.
- ★.env 있는 실행은 수정 커밋(215f52056a)에서만★ — base 에서 .env 붙인 pulse 실행 = 실 번역 과금 경로(arch#5 실측). base 쪽 RED 는 gpu 파일만.
- 판정: 수정 커밋에서 «.env 있음» 실패 집합 == «.env 없음(git archive 사본)» 실패 집합 → 남은 차이 = CI 의 Redis 서비스뿐. 855 5건은 두 실행 모두 PASS. 집합이 다르면 그 차이가 곧 결함.
- 중복 금지: 나노가 같은 묶음을 18:40부터 돌리는 중(scratchpad ci_withenv.txt · 18:57 에 91% · F 27). 그 결과 파일을 먼저 회수하고, master 실행은 «.env 없음» 1회만 추가하면 비교가 된다(25분 × 2 → × 1). 동시 실행은 CPU 경합으로 타임아웃 위험 — 순차.
- 카드 증거 줄: 게이트 형식(세트: sha · 시험: rc · 이슈: 0) + RED 2 vs 3 설명 1줄 — 없으면 닫지 않는다.

---
## (A) R16 — 카드 사전검증·조사 근거 lint

### 결론
승인(수정 1) — ft-nano-spawn 은 이미 65행에서 ft-index-lint.sh 를 부르고 실패면 REJECT 한다 → ★spawn 이 아니라 lint 에 검사 ⑦⑧ 을 추가★하면 spawn 코드 변경 0. 적용 범위는 «팀 env 스위치»로(팀 이름 하드코딩 0): feature-env.sh 에 `FT_CARD_REQUIRE_PREVERIFY=1`. 다른 팀 카드는 무변화.

### 실측
- ft-index-lint.sh 는 키트 scripts/harness-install/fable-team/bin/ 에만 있다(67행 · 추적본 scripts/fable-team-bin 에 사본 없음) · 라이브 RT(v6-realtime-live/.fable-team/bin) 와 cmp 동일. 검사 ①골 3줄 ②필수 6절 ③닫는 증거 원장 실재 ④배경 인용 ≤N ⑤구현 범위·완료 조건 비지 않음 ⑥구현 범위 경로 1개 이상 실재. 전용 시험 파일 0(tests/harness 에 test_index_lint 없음).
- ft-nano-spawn.sh 65행 `bash "$HERE/ft-index-lint.sh" "$IDX" || { echo "REJECT lint 실패"; exit 1; }` — lint 와 같은 폴더의 것을 쓴다. 팀 env 는 21~24행에서 lint 호출 «전»에 source 된다 → 스위치가 lint 에 닿는다.

### 검사 설계 (FT_CARD_REQUIRE_PREVERIFY=1 일 때만)
- ⑦ 「## 사전검증」 절 필수 + 본문에 둘 중 하나:
  - `DA: <판정문 경로>[#§N]` — 경로가 실재(카드 워크트리 루트 기준 또는 절대경로)하고 그 파일에서 «단어 경계»로 뽑은 마지막 APPROVE·HOLD·REJECT 가 APPROVE. (정정 10-07 arch#6: 초안의 PASS 허용 삭제 — PASSWORD·「26 PASS」 같은 글자에 걸려 HOLD 판정문이 통과됐다)
  - `면제: <사유 10자+> — arch 서명 <좌석명>` — 좌석명이 ft-name-lint PASS 이고 역할 토막 = arch.
  - 「소환: 예」 인데 DA 줄이 없거나 「소환: 아니오」 인데 면제 줄이 없으면 REJECT(템플릿이 소환 여부를 명시하게).
- ⑧ 「## 조사 근거」 절 필수 + `경로:줄` 1개 이상 — 경로 실재 + 줄 번호 ≤ 그 파일 줄 수(내용 대조는 안 함).

### 기존 lint 와 겹침
- ⑥(구현 범위 경로 실재)과 ⑧ 은 같은 «경로 실재» 함수를 쓴다(복제 0 · 함수로 추출은 같은 커밋이 아니라 [structure] 커밋 먼저 — Tidy First).
- 절 이름 SECTIONS 배열은 그대로(6절) — ⑦⑧ 절은 스위치 켜진 팀만 추가 요구.

### 거짓 거절 위험과 대응
| 위험 | 대응 |
|---|---|
| 줄 번호 drift(base 가 움직여 파일이 짧아짐) | 줄 ≤ 파일 길이만 확인 · 내용 대조 0 → drift 는 «파일이 짧아진» 경우만 걸림(그땐 근거를 다시 읽어야 하므로 정당한 거절) |
| DA 판정문이 다른 워크트리(v65 DA 좌석)에 있음 | 절대경로 허용 |
| 판정문 단어가 APPROVE 가 아님(예: 승인) | APPROVE 만 인정(단어 경계) — 정본 판정 형식이 APPROVE/HOLD/REJECT 라서. 「승인」만 쓴 판정문은 판정 형식 위반으로 보고 DA 에 반송 |
| 판정문에 HOLD·REJECT 도 함께 있음(회차 이력) | ★마지막 판정 줄★ 기준 — 판정문 끝에서 처음 만나는 APPROVE/HOLD/REJECT 가 APPROVE 여야 통과 |
| arch 서명 위조(나노가 스스로 면제 줄 작성) | lint 로는 못 막는다(이름 형식만 확인) — 면제 줄은 arch 가 카드를 «대기/» 에 쓸 때만 넣고, 진행/ 이동 뒤 면제 줄 diff 가 있으면 ft-index-move 가 경보(별건 · 이번 범위 밖) |
| 이미 진행/ 인 카드 소급 | lint 는 spawn 때만 돈다 → 기존 진행 카드 무영향. feature 팀 «소급 검증 중» 카드는 master 가 수동 대조 |

### 템플릿
- feature 팀 카드 견본(design/feature/indices/README.md 또는 템플릿 파일 · 없으면 신규) 에 「## 사전검증」(소환: 예/아니오 · DA 줄 또는 면제 줄)·「## 조사 근거」(경로:줄 목록) 두 절 추가. SEATBELT-README §5 공통 형식은 무변화(v65 정본 · 다른 팀 영향 0).

### 카드 구성
| 카드 | 파일 | 겹침 |
|---|---|---|
| r16-lint-preverify (하네스 나노) | 키트 ft-index-lint.sh(+ 라이브 RT 는 master 설치) · tests/harness/test_index_lint.sh(신규 — ①~⑧ 각각 OK/REJECT 사례 · 스위치 꺼짐 = 무변화) · R/.fable-team/bin-feature/feature-env.sh 1줄(master 집행) | ft-nano-spawn 무변화 · 진행 중 카드와 파일 겹침 0 |
| 템플릿 문구 | feature 카드 견본 | arch 초안 → master cp |
- 닫는 증거: 스위치 켠 상태에서 ⑦⑧ 없는 feature 카드 → spawn REJECT · DA APPROVE 줄 있는 카드 → OK · 면제+arch 서명 카드 → OK · 스위치 없는 harness 카드 → 지금과 같은 OK.
