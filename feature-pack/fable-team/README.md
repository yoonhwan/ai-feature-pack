# 🧠 fable-team — 일반화된 팀 오케스트레이션 하네스

**오케스트레이터는 전달·조율·모니터링만, 두뇌 작업은 브레인들이.**

Claude Code 네이티브 팀 하네스(Agent/Workflow) 위에서 역할별 서브에이전트 팀을 설치·구동하는 스킬 팩. tmux 불필요.

## 역할 구조

| 층 | 브레인 (설치 시 변경 가능) | 스폰 경로 | 전담 |
|----|--------------------------|-----------|------|
| 오케스트레이터 | ultracode 지원 최상위 모델 (fable5 등) | 현 세션 | 태스크 분해, 전달, 모니터링 루프, 게이트 분기 — **기획·문제해결 금지** |
| planner | fable5 / effort max | Workflow | 원인 분석·해결 설계 → 설계 파일 산출 |
| checker × N | sonnet4.6 / low | Agent | 문서·코드·로그 확인 (병렬) |
| implementer | opus4.6 / max | Agent | 설계 파일 기반 구현 + 프로젝트 Skill 호출 |
| tester | sonnet5 / high | Workflow | 테스트 설계·실행·repro |
| DA 게이트 | **codex gpt-5.5 / xhigh** (비대화 `codex exec`) | Workflow/Agent 드라이버 | DA review + approve loop (최대 2라운드) |

핵심 불변식: ① 워커 `tools:`에서 Agent/Task 제외 → **서브의 서브 스폰 차단** ② planner 외 워커에 fable-5/opus-4-8 금지 ③ 단계 간 전달은 파일 경유(설계 파일) → 오케스트레이터 컨텍스트 최소화 ④ codex 미가용 환경은 설치 시 자동 감지 → 대응 모델 추천 (`skill/references/brain-availability.md`).

## 설치

```bash
./install.sh user                      # 사용자 레벨 (~/.claude/skills/fable-team)
./install.sh project:/abs/path        # 프로젝트 레벨
```

이후 **새 Claude Code 세션**에서 "fable-team 설치 인터뷰" 요청 → 브레인 가용성 체크 → 에이전트 .md 생성(템플릿 치환) → 프로브 검증. 상세: [INSTALL.md](INSTALL.md)

## 구성

```
skill/SKILL.md                        # 트리거 게이트(ultracode 체크) + 스폰 경로 분리 규칙 + 실측 함정
skill/references/
  brain-availability.md               # §0 가용성 프로브 + 대체 추천표
  install-interview.md                # 설치 인터뷰 (placeholder 치환)
  feature-interview.md                # 피처 접수 + 프로젝트 자산 서치 → 추천 설계
  orchestration-playbook.md           # 6단계 파이프라인
  monitoring-loop.md                  # 멈춤 감지 + 진로이탈 교정 + 상태 원장
  agent-templates/*.md.tpl            # planner/checker/implementer/tester/da(+da-claude 대체)
```

## 실측 검증 (2026-07-02, E2E)

mul 음수 버그 수정 사이클: planner(fable5 max) 설계 파일 → implementer(opus4.6) 2줄 패치 → tester ALL_PASS(8케이스) → DA(codex gpt-5.5/xhigh) APPROVED — 오케스트레이터 개입 없이 파일 릴레이만으로 완주.
