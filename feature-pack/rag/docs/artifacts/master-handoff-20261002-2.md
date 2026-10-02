골 원문(GOAL-LEDGER-airag.md 복붙):
최신 fable-team 하네스를 이식하고 기존 AIRAG 증거를 재대조한 뒤, Claude Opus 5.5 HELM·Sonnet 5.5 Master/Nano·GPT-6.1 Sol DA 완성 루프로 AIRAG를 운영 가능한 상태까지 닫는다.
A03 닫는 증거: 「Sonnet 5.5 Nano 구현·GPT-6.1 Sol DA 루프」 — 지금 대상은 A02 트리 5순위 U2(launchd com.airag.consumer 상시 서비스) 첫 틱 관찰 + published 0/10 사실 수집.

# Master 승계 스냅샷 #1 → #2 (2026-10-02 ~15:25, 컨텍스트 ~410k 증류)

골의 어느 축인가: A03 — A02 트리 5순위(C12·C07). 승계 첫 일 = 이 문서 + `.fable-team/state/airag/u2-procedure-draft.md` + `master-progress.md` 마지막 절 읽고 HELM(`ft-airag-helm-claude#2`)에 부팅 3항 + 골 대조 mbox.
작업 디렉터리: /Users/yoonhwan/Project/ai-feature-pack/.worktrees/rag-transplant (브랜치 feature/rag-transplant, push 금지 — PUBLIC 리포). 보고 대상 HELM = `ft-airag-helm-claude#2`(#1·#0 은 유휴).

## 지금 진행 중 (먼저 할 일)
1. **U2 첫 틱 관찰**: `com.airag.consumer` 를 15:23 에 `launchctl bootstrap` 했고 첫 틱(RunAtLoad)이 실행 중이었다(pid 97865, runs=1, 아직 종료 안 함 — 재수동은 128.5s 걸렸다). 해야 할 것: `launchctl print gui/$(id -u)/com.airag.consumer | grep -E 'state|last exit|runs'` · `~/.local/share/airag/logs/tick-20261002.log` 새 줄(값 없는 JSON 1줄) 확인 → exit 0 status ok 이면 HELM 에 «첫 틱 결과» 보고(관찰 절차 = u2-procedure-draft.md §5 7항, 64hex 0 확인, launchd.err.log 비었는지). **launchd 환경에서 op read 가 처음 돈 틱이다 — exit 30(키)이면 환경 문제, 그대로 사실 보고.** 이상 시(같은 오류 2틱 반복·키 노출 의심·exit 50·디스크 급증) 사용자 결정 ②대로 **자율 bootout 허용**(`launchctl bootout gui/$(id -u)/com.airag.consumer`, 삭제·kill 없음, 사후 보고).
2. **published 0/10 사실 수집**: checker `ft-airag-checker-claude#0` 에 발주 #2034(산출 `.fable-team/state/airag/checker-published-facts.json`) — 오면 architect `ft-airag-arch-claude#0` 에 넘겨 판정(내가 원인 판정 금지, 체인 checker→architect). 등록은 이미 진행(사용자 결정 ③).
3. **6순위 phase 8·9 보고서 초안**: 첫 틱 관찰 뒤 바로(HELM #2033 ④).

## 이번 세션에서 닫은 것 (증거)
| 항목 | 증거 |
|---|---|
| U1 틱 래퍼 DA 라운드 r10~r17 | `da-20261001-sol-r{10..17}.md`·설계 `arch-20261001-item5-*.md` · 열린 코드 항목 없음(알려진 한계: R15-m1 PLAN.md 기록 · 다른 볼륨 복제 prefix 수용 = 사용자 수용 «내용 연속성» · fork 손자 락 PROJECT_BUSY 잔여) |
| exit 40 reference 키 | 원인 = 생성자가 틱이 안 쓰는 키를 필수 검사 → 지연 검사(커밋 6b34a70) · 사용자 판정 «상시 서비스에 투어 DB 검색 불필요» |
| exit 40 binding 불일치 | 원인 = 재부팅으로 st_dev 변경 → device 비교 제외(커밋 9a18980) · 사용자 명시 답 «① 내용 연속성 수용» |
| 재수동 3회(HELM 실행) | exit 0 ok · accepted 746 · gaps 1 · coverage_complete false · backup_due/created true · memory attempts 1(provider_called true·candidate 0) · **published_attempted 10·succeeded 0** · pass 128.5s |
| U2 집행(HELM #2033 GO) | §1 백업 runtime.bak-20261002-1522(232M)·runtime.json.bak-pre-u2-20261002-1522 ✅ · §2 휠 ac5d59e 재설치(두 패키지만 교체·모듈 6종 해시=HEAD) ✅ · §3 자격 파일 ~/.config/airag/credential-source.json(0600, 원본 동일) + plist 생성(plutil OK) ✅ · §4 bootstrap ✅(첫 틱 실행 중) |
| 커밋 최근 | …`ac5d59e`(DA r17) · 이후 문서 커밋만. HEAD 확인 `git log -3`. consumer clean HEAD 364 passed. |

## 사용자 결정 (지시 원장 기록됨 — HELM #2029·#2033)
①`__CREDENTIALS__`=~/.config/airag/credential-source.json(0600 복사, 원본 유지) ②관찰 중 이상 시 자율 bootout 허용(삭제·kill 없음, 사후 보고) ③published 0/10 은 checker 사실 수집 병행·판정은 architect, 등록은 진행. ④push 계속 보류. **금지: runtime.json 추가 변경(allow_gaps=true 는 G1 로 이미 적용, 백업 runtime.json.bak-20261001-184932)·운영 DB 쓰기·push·launchd 외 추가 서비스 등록은 사용자 승인/HELM 별도 발주 전.**

## 좌석·도구 함정 (실측)
- 쓰던 좌석이 zombie-clean 으로 회수되면 «같은 대화 복원» 규칙 — **`tmuxc restore` 후보는 모델이 gpt-5.5/high 또는 [1m] 없음으로 잡히니 쓰지 않는다.** claude 좌석: `tmux new-session -d -s '<세션명>' -c <워크트리> "$HOME/.headroom/claude-hr.sh --dangerously-skip-permissions --model 'claude-sonnet-5-5[1m]' --effort high --resume <uuid> --name '<세션명>'"` (uuid 는 `tmuxc restore --scan --since 40 --agent claude` 목록의 cmd 줄). DA(codex): `codex resume 01a0f693-a0d0-7a03-bd38-d07a46a67330 --dangerously-bypass-approvals-and-sandbox -c model_reasoning_effort="low" -c model="gpt-6.1-sol" -c service_tier=priority` — **DA 는 사용자 지시로 gpt-6.1-sol low fast**(발주·기록에 그렇게 표기).
- 현재 좌석: arch#0(uuid a98a9bf9…)·checker#0(f258f05b…)·nano-r1#1(35fe472a…[1m])·da-codex#0 — 일부 회수됐을 수 있으니 `tmux ls | grep airag` 후 필요 시 복원.
- 파괴 명령 차단 훅(`block-destructive.sh`)은 명령 «본문 문자열»에도 걸린다(heredoc 안의 삭제·kill 어휘 포함). 문서는 Write 도구로 쓰고, 정리 폴더는 만들지 않는다. `.fable-team/` 는 gitignore — 진행표(master-progress.md)는 커밋 대상 아님(HELM 이 뉴스에 그대로 보여 주므로 «단계 바뀔 때 같은 턴에 갱신»).
- 체인 규칙: checker(사실) → architect(원인·설계·DA 소환 결정) → Master(라우팅·커밋 집행) → Nano → 코드 DA. Master 는 원인 규명·수정 방향 지정·DA 직접 소환 금지(이번 세션 예외로 DA 소형 확인 라운드는 HELM 허용 하에 발주함).
- 회귀 러너: `cd feature-pack/rag-consumer && ../rag/.venv/bin/python -m pytest tests -q -p no:cacheprovider`(≈4분). 클린 HEAD 에서 Master 가 직접 재실행해 Nano 보고를 대조한다.

## 열린 항목(소유자)
| 항목 | 상태 | 소유 |
|---|---|---|
| U2 첫 틱 결과 확인·HELM 보고 | 진행 중 | 후계 master |
| published 0/10 사실→architect→(설계) | checker 발주함 | checker→arch→master |
| 6순위 phase 8·9 보고서 초안 | 첫 틱 뒤 | 후계 master |
| 다음 03:00 KST 슬롯 backup_due/created 관찰(C12 닫힘 증거) | 내일 | 후계 master |
| 후속 목록: 투어 도구 재실행 경로 plan device 비교(상시 틱 무관)·불일치 필드 이름 로그 진단 개선 제안 | 후속 | HELM |
| 잔여 확인대기 51·검증대기 25 | 사용자 보류 | 사용자 |
| push | 별도 사용자 승인 | 사용자 |
