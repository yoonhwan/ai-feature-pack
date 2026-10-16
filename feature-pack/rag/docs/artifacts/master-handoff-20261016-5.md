골 원문(GOAL-LEDGER-airag.md 복붙):
최신 fable-team 하네스를 이식하고 기존 AIRAG 증거를 재대조한 뒤, Claude Opus 5.5 HELM·Sonnet 5.5 Master/Nano·GPT-6.1 Sol DA 완성 루프로 AIRAG를 운영 가능한 상태까지 닫는다.
A03 닫는 증거: 「Sonnet 5.5 Nano 구현·GPT-6.1 Sol DA 루프」 — A02 트리 5순위 C12(U2 launchd com.airag.consumer) 회복 관찰 + 6순위 C13(KakaoBot 통합 보고서) published 칸 채움.

# Master 승계 스냅샷 #4 → #5 (2026-10-16 17:3x, 컨텍스트 400k 증류)

골의 어느 축인가: A03 — A02 트리 5순위(C12) 권한 팝업/간헐 타임아웃 해결 + 회복 관찰, 6순위(C13) 보고서 마무리. 승계 첫 일 = 이 문서 + `.fable-team/state/airag/master-progress.md` 마지막 절들 읽고 골 대조 + 부팅 3항(세션명/모델+창/Serena 가부)을 mbox 로 보고(orch 와 현역 planner 에 «tmux ls» 로 이름 확인 뒤 생존 1줄)한 뒤에만 착수. CronCreate 10분 틱 1개를 새로 걸고 id 를 planner 에 회신(구 master#4 의 cron 62c01651 은 구 좌석과 함께 사라짐).
작업 디렉터리: /Users/yoonhwan/Project/ai-feature-pack/.worktrees/rag-transplant (브랜치 feature/rag-transplant, push 금지 — PUBLIC 리포). 답변 한국어, 호칭 "yoonhwan 오빠". 서브에이전트(Agent 도구) 금지 — 나노·arch·DA 는 tmux 좌석만.

## 현재 상태 (실측)
- consumer(`com.airag.consumer`) **disabled·미로드** 유지. 운영 plist·runtime.json·운영 DB 변경 0. 서버 18703(byz-llm)·18712(byz-embed) LISTEN(planner 터널 — 승계 시 끊길 수 있음, lsof 로 확인).
- **chain(h67, 10-16 14:23)**: launchd P0(op --version) 7초 초과 2/2(10-15 포함) · 터미널 평상·taskpolicy -b 전부 빠름(25~157ms). 팝업 «없음».
- **N4(h87, 10-16 16:59, rc=0 33초)**: A1 Background 지정 = P4·P0 둘 다 7초 초과 / B 미지정 = 0.6초 / A2 Background = P0 2.4초 성공. 팝업 «없음». → 설계 r11: 해석 보류(r10 §4.6 표에 없는 조합·P4=success 전제 위반) · 운영 plist 변경 근거 부족 · «첫 launchd 작업 × 지정 여부» 4칸 중 (첫 작업+지정 안 함) 관측 0.
- **N4 구현**: 완료·DA PASS (probe.py/probe.sh/chain.py/chain.sh --plan n4·G4, HEAD 0e6d48b까지 · 전체 회귀 949 passed). S2 구현 DA PASS(r3, c64c7b1) — 실행은 별도 HIL 보류.
- **설계 r12 (arch-20261016-opa-popup-design-r12.md, 커밋 0fd7eff)**: r11 DA REJECT(0/2/2) 정정판. D2 판독 H0→H1→R1~R4(16조합 검산)·R-3 증거(기한 내 P0 관측 2건 확보)/결정(재개 미승인은 R-2·R-4) 분리·D2 h 파일 계약.
- **열린 건 1**: 설계 DA r12 재심 결과 도착 직전 — 쪽지 **#2625**(ft-airag-da-codex#1 → master#4)가 r12 DA 판정 회신일 가능성이 큼(발주 #2624, 판정 파일 `feature-pack/rag/docs/artifacts/da-20261016-sol-opa-design-r12.md`). **이 쪽지는 큐에 남아 후계가 받는다**(`ft-mbox.sh recv ft-airag-master-claude#5`로 계보 수신).

## 해야 할 것 (순서)
1. #2625 수신 → DA r12 판정 전문 읽기 → 판정 파일 커밋(`git add` 해당 파일). REJECT 면 지적 전문을 architect(ft-airag-arch-claude#2)에 r13 발주(Master 는 원인 규명·수정 위치 지정 금지), PASS 면 2번.
2. **D2 h 파일 작성**(설계 r12 계약대로): `probe.sh --python ~/.local/share/airag/runtime/bin/python --p0-only --process-type unset` → 이어서 `--process-type background`(chain 을 거치지 않음, 기존 도구 인자만 · 호출당 75초 자체 상한). 첫 호출 rc≠0(잔존 4·신호 129/130/143)이면 둘째 미시작·코드 보존, 결과 폴더 1:1 대응. 계획 파일은 `.fable-team/state/airag/hil-d2-plan.sh`(형식: hil-n4-plan.sh 참고), 사전 점검 `bash -n`·도구 실재·consumer python 실재·consumer disabled·대화형 프롬프트 0. planner(현역 이름은 `tmux ls | grep planner-master` 로 확인 후 보냄)에 `! bash /tmp/h<N>` 한 줄 상신(고지: 순서 «지정 안 함→Background», op --version·P4 각 최대 2회, 토큰 접촉 0 은 스크립트 한정, 호출당 75초·chain 240초 감시 미적용, 팝업 가능·누르지 말 것, 관측 라벨일 뿐 원인 확정 아님). 질문은 1개.
3. 오빠 실행 뒤 결과(3중 대조: result.json·profile.json·job.plist 키 유무)를 Master 가 직접 읽고(§4.2 H0→H1→R1~R4 사전 판독 규칙) architect r13 해석 발주. 팝업 관찰 질문 1개 planner 경유.
4. 그 해석에 따라: D2 가 첫 작업 효과를 지지/반증/보류 → 표본 보강 설계 또는 R-3 위험 관찰 판정 경로를 오빠께 상신. consumer 재개 조건: R-1 서버 LISTEN·R-2 설치본 I-1(7.0/14.0) 반영(현재 timeout=30, 재설치는 «지금 재설치» 절차)·R-3 증거 병기·R-4 오빠 재개 승인(팝업 고지)·R-5 관찰 계획(24틱 창 안 조기 확인 3틱·중단 후보 6연속 exit 30, 중단 집행은 기존 HIL 경로). 재개 집행은 enable 먼저→HELM/planner bootstrap, 오빠 승인으로만.
5. 보고서 `KAKAOBOT-INTEGRATION-REPORT.md` 절 C published 칸·A.7 예시 채움(서버+consumer 재개 뒤 실측만, [실행]/[인용] 표기 유지) → 변경분 문서 DA 재리뷰 → 오빠 수용 → A03 종결 → A04. 마감(CLOSEOUT): 랜딩 → 정본 1장 → 좌석 닫기(op-token). KakaoBot#18 에 완성본 sha + «로컬 경로·브랜치» 통지(오빠 값: 출처 = 로컬 워크트리, 원격 0, 통지 전 설치 0).

## 불변 규칙 (오빠 결정 — 재논의 금지)
- push 금지(PUBLIC). 키 값·비밀 출력 금지. 운영 DB 쓰기·runtime.json/plist 변경·런타임 재설치·서버 기동은 오빠 승인. **`op` 직접 실행 금지**(오빠 HIL 도구로만). 훅·가드 우회 금지(막히면 mbox [HIL]). 좌석 개설/닫기는 래퍼(`ft-tmux-spawn.sh`·`ft-tmux-kill.sh`)만.
- Master 는 원인 규명·수정 위치 지정·DA 직접 소환 금지. 체인 checker → Master → architect → (DA) → Master → impl. 코드는 Nano.
- 7초 룰(외부 호출 시도당 7초+재시도 1, 70초 천장). 약어로 골 부르기 금지. 해석표: «약화/배제/판명/우세» 표기 금지, 원인 확정 금지, 관측 라벨·연관 후보만.
- 백그라운드 작업을 기다릴 때는 pane 문구만 보지 말고 `pgrep` 으로 프로세스 생존까지 실측(Nano 변이 스크립트가 죽은 채 25분 대기했던 건 — 10-16 15:5x 진행표 기록). 상위(planner/desk)에 보내기 전에 `tmux ls` 로 현역 이름 확인(planner·desk 승계가 잦아 쪽지가 이전 이름에 묶여 미독으로 남은 사례 다수).
- 오빠 결정 기록: published 0 은 해결 후 보고 · 보고서 수령자 = KakaoBot 개발자 · P08A-02 후속 · KakaoBot 코드 연결은 airag 완성 뒤 · 팝업 관찰 «없음» 2건(h67·h87)은 팝업 부재의 보장 아님.

## 좌석 (tmux, 10-16 17:3x 실측)
- ft-airag-master-claude#4(구, 이 문서 작성자) · ft-airag-arch-claude#2(architect, 설계 r12까지) · ft-airag-da-codex#1(DA, gpt-6.1-sol, 컨텍스트 압축 반복됨) · ft-airag-nano-r1#5(구현, ctx ≈37%) · ft-airag-nano-r1#4·ft-airag-checker-claude#2(유휴). 닫기는 op-token(standing 승인 구멍은 하네스 후속 후보).
- planner = byz-planner-master-claude#57(현역은 `tmux ls` 확인) · desk = byz-planner-desk-claude#6(오빠 인터뷰 대기열 — 팝업 질문 등은 planner 경유). cron: 후계가 새로 CronCreate(10분 틱) 설치.

## 산출물 위치
- 설계 `feature-pack/rag/docs/artifacts/arch-2026101{5,6}-opa-popup-design*.md`(r1~r12) · DA 판정 `da-2026101{5,6}-sol-*.md`(설계·구현·S2·N4) · 도구 `feature-pack/rag-consumer/ops/probe-opa/{probe,compare,s2,chain}.*` · 결과 `~/.local/share/airag-probe/`(N1 20261016-142318-…, N4 20261016-1659xx 3폴더) · 진행표 `.fable-team/state/airag/master-progress.md`(gitignored) · 회귀 로그 `.fable-team/state/airag/regress-*.log`(최신 0e6d48b 949 passed).
- 브리프 파일(발주 재사용): `.fable-team/state/airag/{da-opa-design-r12-brief,arch-r12-brief,hil-n4-plan.sh,hil-chain-plan.sh}` 등.
