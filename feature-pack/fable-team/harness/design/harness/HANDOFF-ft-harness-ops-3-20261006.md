# HANDOFF — ft-harness-ops#3 → #4 (2026-10-05 야간 · 컨텍스트 404k 증류)

## ★골 원문 (GOAL-harness.md 복붙 — 읽기 전엔 착수 금지)★
> 내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
> 하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
> 메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.
> (원문 7) 정말 많은 양의 이슈와 테스트, 그리고 큰 병렬적인 메인 플랜을 얼마나 잘 수행해내느냐에 핵심이 달려 있다 … 큰일을 얼마나 별개로 쪼개서 동시에 아주 잘 해결하느냐에 달려 있다. 이게 기획에 반영되어야 한다.
★승계 첫 일 = 골 대조 3줄을 planner(`byz-planner-arch#3`)에 mbox 보고 + 부팅 3항(세션명/모델·창/Serena) 후 착수. 이 단위는 오빠가 harness-ops pane 에서 직접 지휘 — AskUserQuestion 허용(끝나면 원복). 응답은 GUIDE-human-report 틀(결론→오빠가 할 일→바뀐 것 3줄→근거 1줄 · 내부어는 첫 등장에 풀이 · 약어 인덱스 금지).

## 지금까지 확정된 것 (전부 오빠 값 확정 · 정본 = design/harness/issue-improvement/)
PIECES.md 의 P1~P10 + MERGED(충돌 16행·구현 조각 C1~C11) 전부 «수락 + 오빠 값 확정». 값 원장 = `VALUES-pieces-P3-P5-20261005.md`(P3·P5·P6·P7·P8·P9·MERGED·P10 전부) · 풀플로우 본선 13단계 = `SPEC-full-flow-20261005.md` · 풀스택 지도 = `design/harness/diagrams/`(IR 83노드·127엣지 · 커밋 9a02598f56). **구현은 0 — 오빠 「구현 시작」 대기**(MERGED C11 문서 정정은 구현 시작과 함께). 구현 순서 = 설치 키트(C1) 먼저 + C3·C4·C5·C8 동행.
핵심 확정: 슬랙=발행 전용(인터뷰 카드·팀 뉴스)·역방향 0 · tmm=질문 원장 화면 · issue-manager=Issue 0 루프 책임(메인 Issue 수정·close=소유 오케, size:small 만 직접) · 정렬=사건만(시간 트리거 0) · 시험 묶음=카드당 1·tester 1·architect 직접 보고 · byz-e2e 증거 범위 현행 유지 · 브랜치 삭제 HIL 유지 · 머신 3기(이 Mac·jarvis·byz mac=tailscale byzs-mac-mini).

## ★열린 단위 1 (최우선) — 오빠 새 지시 = 조각 P11 「GitHub Issue 드리븐 개발」 — 아직 발주 안 함★
오빠 원문 (2026-10-05 마지막 지시):
> 「한가지 정말 중요한 축이 있는데. 이슈는 이제 매니저가 아무도 아무것도 안 해도 0 으로 만들기 위해 최선을 다해야 함. 테스트도 하고 완성하고 정본화 문서화하고 브랜치 워크트리도 정리하며 완성.」
> 「다른 핵심은. 내가 기획 세션을 임의로 메인오케 마스터를 임의로 만들어서 실험하고 기획하고 정리한 내용을 issue manager 에 넘겨 issue 로 등록하거나, 아니면 직접 세션 에이전트가 등록, 또는 내가 진짜 github 에서 등록(버그), 또는 사내 멤버가 git 에 버그를 확인 요청. 이것들을 진짜 이제 github issue 드리븐으로 개발 구현한다는 것」
해석(확인 필요): ①issue-manager = 「아무도 아무것도 안 해도」 자율 완주(시험·완성·정본화 문서·워크트리/브랜치 정리까지) — **P10 오빠 값(루프 책임·정렬=사건만)과 부딪힐 수 있음**: 「아무도 안 해도」 는 사건 없이도 도는 자율 구동을 뜻하는지(시간 트리거 0 과 충돌) · 「브랜치 정리」 는 HIL(브랜치 삭제) 규칙과 충돌 → **오빠 질문으로** ②입력 경로 4종 = 오빠 임의 기획 세션(실험·정리 후 매니저에게 넘김) · 세션 에이전트 직접 등록 · 오빠가 GitHub 에서 직접 등록(버그) · 사내 멤버 GitHub 버그 확인 요청 → 전부 Issue 로 일원화(P1 Issue 체계·P3 §1·P5 큐 입력 Q-6 과 연결, 「사내 멤버」 신규 입력).
할 일: ORDER(골 원문 3줄·오빠 원문·할 일) 작성 → 새 arch 세션 개설(arch#3 은 347k+ 로 닫힘 — 후계 `ft-harness-arch#4`, tmuxc open · `--model claude-fable-5-1[1m] --ctx 1m --effort high` · `zsh -lc` 로 감쌈) → nano 사실(읽기 전용: 입력 경로 4종의 현재 실재 · Issue 템플릿·라벨·`gh` 권한 · 사내 멤버 접근 · 워크트리·브랜치 현황) → arch SPEC(≤200줄 · 구현 0 · 충돌 표 · 질문≤3) → da#1 1회 10분 → ops 수락 → /eli5 → 오빠 인터뷰.

## 열린 단위 2~
2. 오빠 「구현 시작」 대기 → C1 설치 키트 발주(새 arch 세션 · P11 이 구현 순서에 영향 주면 반영).
3. 오빠 확인 대기: byzs-mac-mini 가 무엇을 돌리는 머신인가(RELEASE 머신 행 값 · 지도에서 점선).
4. 풀플로우 설명 페이지(https://claude.ai/artifact/2HHmNZXWsKUK8ZLkGDZ76J)는 13단계 버전으로 덮어씀(삭제 불필요).
5. 임시 산출(미커밋): scratchpad `BYZ-핵심-한장.drawio`(핵심 17노드 한 장 · 오빠 「좋네」) — 저장소에 둘지 오빠 확인(「좋네 그 draw.i…」 이후 문장이 끊겨 미수신 — 오빠가 다시 말하면 처리).
6. 「내 질의응답 기획 보강」(오빠 지시, 의미 불명 — 선택지 질문을 오빠가 거절): 질문 원장·슬랙 왕복 / 오빠께 가는 질문·설명 방식 / 오빠 질문에 답하는 체계 중 무엇인지 오빠가 다시 말하면 착수. P10 에서 슬랙·tmm 은 정리됨.

## 좌석 · 도구
ft-harness-arch#3(정지 · 347k+) · arch#2(정지) · da#1(codex sol low · 대기형) · nano#1(opencode deepseek flash · 대기). 닫기(kill)는 오빠 판단(keep-last-2). mbox=`/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.fable-team/comm/mbox.sh`. 새 arch 는 «다음 발주 시점»에 연다(빈 세션 상시 대기 금지).
- 설치함: `~/.claude/skills/drawio-skill`(Agents365-ai v3.4.0 · sha 88fd923 · MIT · 소스 검토함 · `disable-model-invocation:true` → Skill 호출 거부 · SKILL.md Read + `scripts/diagramctl.py` 직접 실행) · draw.io CLI `/opt/homebrew/bin/drawio` · graphviz `dot` 설치됨. 정본 지도 = `design/harness/diagrams/fullstack.ir.json`(`build.py --check`·`diagramctl test`·`sync`).
- eli5 페이지(비공개 · 앞 https://claude.ai/artifact/): P7 `AJVaj7Ltqa8QaXdP2GNrFr` · 풀플로우 `2HHmNZXWsKUK8ZLkGDZ76J` · P9 `VLE8DtA2buWL2oXcowdLLx` · MERGED `1yJM3qNRoBcAqkKyfqN4pj` · 풀스택 지도 `EuKdCAVxafsT5wj1ztSvqv` · P10 `SjpkMa6Ss7fMKQ8zbZ9bcB`.

## 함정 (실측)
- 파일 삭제 명령(rm 계열)은 훅이 차단 — 오빠에게 `!` 명령으로(AskUserQuestion 에 리터럴 명령). 문서 본문에 그 명령 문구가 있어도 Bash heredoc 은 차단되므로 Write 도구로 쓴다. 아티팩트 delete 도 이 세션에서 확인 불가 → 같은 URL 덮어쓰기.
- `mbox.sh relay` 는 워크트리 루트 기준 상대 경로에서 실행 · nano/arch 의 «커밋 요청»: 비밀 스캔(식별자·공개 URL 매칭은 무해) → 경로 지정 add(`git add -A` 금지) → sha 회신.
- eli5 페이지 생성: 머리글은 기존 페이지(scratchpad `merged.html`·`flow2.html` 계열)의 CSS 토큰 재사용 · 선택지 라벨 오타 주의(「사례」→「사건」 사고 1회).
- draw.io XML 라벨의 br 태그는 `&lt;br&gt;` 로 이스케이프해야 파싱됨(core.drawio 사고 1회).
- 시험 입력: byz-e2e Hard Rule #0-1 = BlackHole 루프백·실제 UI 클릭만 통과 증거(오빠 값: 현행 유지).
- ORDER 는 항상 골 원문 3줄+축 1줄 선두 · 응답은 GUIDE-human-report 틀.
