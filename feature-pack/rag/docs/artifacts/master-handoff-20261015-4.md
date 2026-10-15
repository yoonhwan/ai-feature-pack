골 원문(GOAL-LEDGER-airag.md 복붙):
최신 fable-team 하네스를 이식하고 기존 AIRAG 증거를 재대조한 뒤, Claude Opus 5.5 HELM·Sonnet 5.5 Master/Nano·GPT-6.1 Sol DA 완성 루프로 AIRAG를 운영 가능한 상태까지 닫는다.
A03 닫는 증거: 「Sonnet 5.5 Nano 구현·GPT-6.1 Sol DA 루프」 — A02 트리 5순위 C12(U2 launchd com.airag.consumer) 회복 관찰 + 6순위 C13(KakaoBot 통합 보고서) published 칸 채움.

# Master 승계 스냅샷 #3 → #4 (2026-10-15 밤, 컨텍스트 401k 증류)

골의 어느 축인가: A03 — A02 트리 5순위(C12) 회복 관찰(권한 팝업/간헐 타임아웃 해결) + 6순위(C13) 보고서 마무리. 승계 첫 일 = 이 문서 + `.fable-team/state/airag/master-progress.md` 마지막 두 절 읽고 골 대조 + 부팅 3항(세션명 / 모델+창 / Serena 가부)을 mbox 로 보고한 뒤에만 착수.
작업 디렉터리: /Users/yoonhwan/Project/ai-feature-pack/.worktrees/rag-transplant (브랜치 feature/rag-transplant, push 금지 — PUBLIC 리포). 답변 한국어, 호칭 "yoonhwan 오빠". 오빠 지시(10-15): «권장으로 · 멈추지 말고 완성까지 계속».

## 현재 상태 (실측)
- **정지 해제됨**(10-15 오빠 지시) — 권한 팝업 해결 체인 진행 중. consumer(`com.airag.consumer`)는 아직 **disabled·미로드**(enable 은 해결 뒤, plist·runtime.json 변경 금지, HELM/planner 절차). 서버 18703(byz-llm)·18712(byz-embed)는 planner 가 IAP 터널로 열어 둠(planner 승계 시 끊길 수 있음 — lsof 로 확인).
- **정정(중요)**: 내가 오빠께 권한 «서비스 계정 방식»을 권했으나 설치본은 이미 그 방식이었음(설계 r1 §0). 타임아웃 231건은 전부 10-13 10:58 재부팅 «이전», 팝업 3건(11:44)은 별개일 수 있음 → 팝업/간헐 타임아웃을 분리 관리.
- **프로브 결과(h50)**: P4 success 707ms · P0(op --version, launchd 컨텍스트, 토큰 없음) 7038ms timeout → op 기동 자체가 막힘(p0_blocked). **E1(h52)**: 같은 명령 터미널 3조건×2 = 6/6 success 28~222ms(terminal_all_fast). → launchd 고유인지·시점 일시 상태인지 **미확정**.
- 설계(architect ft-airag-arch-claude#2) r1~r8 / 설계 DA(ft-airag-da-codex#1) 다수 라운드, 최신 r8 PASS(0/0/2). 구현 PASS: I-1(7초 룰, tick.py 7.0/14.0) · P 프로브 · E1 compare · chain(프로브→E1→taskpolicy -b E1, 6f1bca3) 전부 구현 DA PASS. S2(키 읽기 측정, 8160e0c·c5c20f6)는 구현만·DA 미검토·실행 보류(P0 막힘 해소 전).
- **열린 건 1**: Master clean HEAD 6f1bca3 전체 회귀 689 passed **6 failed**(test_s2_opa 5 + 1; 단독 실행은 33 passed, 병렬 실행 시 test_compare_opa 신호 시험 `test_a_signal_in_condition_a_ends_the_child_and_removes_the_unused_folder[1-129]` 1건 폴더 잔존 실패). **Nano ft-airag-nano-r1#5 에 원인 규명 발주 중**(#2562): 시험 결함이면 부하 내성 [test] 커밋, 도구(compare.*) 결함이면 먼저 master 에 보고→지시. 결과 mbox 대기. 요약 로그 `.fable-team/state/airag/regress-chain-fail-20261015.log`.

## 해야 할 것 (순서)
1. Nano#5 의 간헐 실패 원인 규명 결과 수신 → 도구 결함이면 수정 발주(Nano→DA)·시험 결함이면 [test] 커밋 확인 → Master clean HEAD 전체 회귀 재실행(≈20분, 한 번).
2. 오빠 HIL ③: chain 1회 실행(최대 240초) — planner(byz-planner-master-claude#52)에 `! bash /tmp/h<N>` 한 줄 상신(계획 파일은 hil-probe-plan.sh·hil-e1-plan.sh 형식 참고: `chain.sh --python ~/.local/share/airag/runtime/bin/python`, 고지문은 설계 r8 §4·§고지, bash -n·파일 존재 실측 후). 결과(result.json 값 없는 요약) 직접 읽고 architect 설계 r9 로 해석.
3. 그 해석에 따라 최종 수정(I-2 후보)·S2 실행 여부 결정. 서버 18712·18703 LISTEN 확인 후 consumer 재개(enable 먼저 → HELM/planner bootstrap) → 첫 틱 관찰(published 14 실패→성공·새 summary 필드·03:00 backup_created).
4. 보고서 `KAKAOBOT-INTEGRATION-REPORT.md` 절 C published 칸·A.7 예시 채움(서버 복구 뒤 실측만, [실행]/[인용] 표기 유지) → 변경분 문서 DA 재리뷰 → 오빠 수용 → A03 종결 → A04.
5. 마감(CLOSEOUT): 단위 끝 = 랜딩 → 정본 1장 → 좌석 닫기(닫기는 op-token 필요: checker#2·nano-r1#4 등). KakaoBot#18 에 완성본 sha + «로컬 경로·브랜치» 통지(오빠 값: 출처 = 로컬 워크트리, 원격 0, 통지 전 설치 0).

## 불변 규칙 (오빠 결정 — 재논의 금지)
- push 금지(PUBLIC). 키 값·비밀 출력 금지. 운영 DB 쓰기·runtime.json/plist 변경·런타임 재설치·서버 기동은 오빠 승인. **`op` 직접 실행 금지**(오빠 HIL 도구로만). 훅·가드 우회 금지(막히면 mbox [HIL]). 좌석 개설/닫기는 래퍼(`ft-tmux-spawn.sh`·`ft-tmux-kill.sh`)만.
- Master 는 원인 규명·수정 위치 지정·DA 직접 소환 금지. 체인 checker → Master → architect → (DA) → Master → impl. **서브에이전트(Agent 도구) 금지 — 나노·arch·DA 는 tmux 좌석만**(오빠 10-15 지시). 코드는 Nano.
- 7초 룰(외부 호출 시도당 7초+재시도 1, 70초 천장). 약어로 골 부르기 금지.
- 오빠 결정 기록(이전): published 0 은 해결 후 보고 · 진단 개선 · 보고서 수령자 = KakaoBot 개발자 · P08A-02 후속 · KakaoBot 코드 연결은 airag 완성 뒤.

## 좌석 (tmux)
- ft-airag-master-claude#3 (구, 이 문서 작성자) · ft-airag-arch-claude#2(architect) · ft-airag-da-codex#1(DA, gpt-6.1-sol) · ft-airag-nano-r1#5(구현, ctx ≈34%) · ft-airag-nano-r1#4(ctx 411k 로 증류됨·유휴) · ft-airag-checker-claude#2(유휴). 닫기는 op-token(standing 승인 구멍은 하네스 후속 후보).
- cron: 구 master#3 의 CronCreate f8610e69(세션 한정)는 구 좌석과 함께 사라짐 → 후계가 새로 CronCreate(10분 틱) 설치.

## 산출물 위치
- 설계 `feature-pack/rag/docs/artifacts/arch-20261015-opa-popup-design*.md`(r1~r8) · DA 판정 `da-20261015-sol-*.md` · 도구 `feature-pack/rag-consumer/ops/probe-opa/{probe,compare,s2,chain}.*` · 결과 `~/.local/share/airag-probe/` · E1 결과 사본 `.fable-team/state/airag/e1-result-20261015.json` · 진행표 `.fable-team/state/airag/master-progress.md`(gitignored).
- planner = byz-planner-master-claude#52(HIL 인터뷰·`ft-hil.sh --add` 담당). KakaoBot 회신처 = KakaoBot#18 의 ft-mbox.sh(경로는 쪽지 #2496 참조).
