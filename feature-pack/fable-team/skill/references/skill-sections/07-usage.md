## 사용 절차

0. **브레인 가용성 체크** (설치 시작 전 필수): `references/brain-availability.md` — codex/cursor 등 미가용 시 남은 choices 재제시
1. **설치 인터뷰** (최초/변경 시): `references/install-interview.md`
2. **케이스 하네스 카탈로그**: `references/orchestration-cases.md` — **4그룹(규명/수정/구축/판정) · 8케이스**(조사보고·빠른확인·원인수정·긴급직행·반복수선·신규구축·구조정리·검증판정 + 직접처리) + 상시/선택 **모듈** 분리 + 스위치(이중오케·기록비서·빠른확인선행·이중판정 등) + 킥오프 템플릿 공통 1형. 스텝3 분류·배치 추천의 SSOT (구 deployment-patterns.md P-코드는 별칭 유지)
3. **피처 인터뷰** (매 피처 시작 시): `references/feature-interview.md` — 무엇을 할지 한 줄/파일로 받고, 프로젝트의 스킬·플러그인·하네스·도구를 서치해 추천 기반 설계 인터뷰 진행
4. **오케스트레이션** (파이프라인 실행): `references/orchestration-playbook.md`
4. **모니터링·지원 체크 루프** (파이프라인 상시): `references/monitoring-loop.md` — 멈춤 감지 + 진로이탈 교정 + 상태 원장
5. **컨텍스트 관리** (상태 외재화·compact/clear/재시작·복원): `references/context-management.md` — 디스크 SSOT(`.fable-team/state/`) write-through, ctx 임계 정책, 세션 재시작 복원 절차. **새 세션 트리거 시 피처 인터뷰 이전에 §4(ACTIVE 감지·복원)를 먼저 수행.**
6. **업데이트** ("FT 업데이트" 시): `references/update.md` — 팩 소스 → 로컬 설치본 패치(스킬 파일 + 에이전트 .md 재치환, 인터뷰 답변 보존) + 새 세션 프로브 재검증.
7. **강제 게이트** (오케 폭주·컨텍스트 방어): `references/orchestration-gate.md` — 4-레이어(선언·역할·기준·강제) + 프로젝트 설치 지원(`templates/install-gate.sh`). 부팅 시퀀스에서 설치 상태 확인·제안.
8. **반복 문제해결 루프 + 7원칙** (로그드리븐 BTS): `references/rapid-iteration-loop.md` — 큰 수정(재설계) 금지, **빠른 테스트→문제발견→수술적 대응→재테스트 반복**으로 작업리스트 완성. 문제해결 7원칙·안티패턴·역할 체인은 이 파일이 정본(아래 §문제해결 방법론엔 오케 레벨 큰 틀 2개만). 로그는 얼마든 심되 증명 후 정리. 3자대조(로그↔코드↔스펙).
8-1. **검증 루프 수렴 · DA 반증 (전역 팀지침 · 오빠 10-27)**: `references/converge-loop.md`(회차 예산·카드 크기·착지 큐·승계·쌍 지표) + `references/da-counterexample.md`(DA 산출=반례 · 1회차 전수 · 3값 판정 · 반송 상한 2회 · 발주/반송 문구). 정본은 `~/.claude/guides/harness-converge.md` · `~/.claude/guides/da-counterexample.md` — 값이 어긋나면 정본이 이긴다.
