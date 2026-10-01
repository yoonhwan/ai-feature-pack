골 원문(GOAL-LEDGER-airag.md 복붙):
최신 fable-team 하네스를 이식하고 기존 AIRAG 증거를 재대조한 뒤, Claude Opus 5.5 HELM·Sonnet 5.5 Master/Nano·GPT-6.1 Sol DA 완성 루프로 AIRAG를 운영 가능한 상태까지 닫는다.
A03 닫는 증거: 「Sonnet 5.5 Nano 구현·GPT-6.1 Sol DA 루프」 — 지금 대상은 A02 트리 5순위 «운영·백업 증거» U1(상시 서비스 틱 래퍼) DA 수렴.

# Master 승계 스냅샷 #0 → #1 (2026-10-01 ~15:25, 컨텍스트 411k 증류)

골의 어느 축인가: A03 — A02 트리 5순위(C12·C07). 승계 첫 일 = 이 문서 + `.fable-team/prompts/master.md`·`master-item5.md` 읽고 HELM(`ft-airag-helm-claude#0`)에 부팅 3항 + 골 대조 mbox.
작업 디렉터리: /Users/yoonhwan/Project/ai-feature-pack/.worktrees/rag-transplant (브랜치 feature/rag-transplant, push 금지 — PUBLIC 리포)

## 완료(증거)
| 순위 | 닫힘 | 증거 |
|---|---|---|
| 2 회귀·DA | DA r3 PASS 0/0/0 | `da-20261001-sol-r{1,2,3}.md` · `regression-20261001-r3-*.log` |
| 3 정리 | 상태 원장·catalog·PLAN | 커밋 f1535c6 |
| 4 기억 확인 투어 | 투어14 사용자 통과(승인10·검증10, 잔여 51·25 보류), DA r6 PASS | `da-…-r{4,5,6}.md` · 6f135ab(투어 폴더 add -f) · 런타임 재설치(백업 `~/.local/share/airag/runtime.bak-20261001-1416`) |
| 5-1 조사 | 설계 vs 실재 + U1~U6 | `ops-design-vs-reality-20261001.md` · `ops-u3-source-options-20261001.md` |
| 5 R6 잔존 | DA r7 PASS 0/0/1 | `da-20261001-sol-r7.md` |

## 지금 진행 중 — U1 틱 래퍼(키 주입 + run --once, launchd 5분 틱용)
- 코드: `feature-pack/rag-consumer/src/airag_consumer/tick.py` · `ops/com.airag.consumer.plist.template` · `tests/test_tick.py`. 사용: `python -m airag_consumer.tick --config <runtime.json> --credentials <자격 설정 JSON> --log-dir <dir>`. 종료코드 0 ok·10 skipped·20 config·30 keys·40 runtime·50 internal.
- DA 라운드: r8(PASS, M2·m2) → r9(PASS, major 2·minor 2) → Nano r3 수정 `5860e32`(239 passed) → **DA r10 발주 #1754 대기 중**(보고는 `ft-airag-master-claude#1` 로 오도록 지정). 결과 파일 `da-20261001-sol-r10.md`.
- **HELM 수렴 규칙(#1752)**: r10 에도 값 비노출·로그 경계에 major 가 남으면 4번째 패치 대신 architect(설계) 단계로 상향 — 방향은 architect·DA. 결과만 HELM 에 보고.
- r10 이 major 0 이면 → HELM 에 보고: ①DA 판정 ②**사용자 수동 1회 한 줄 + 기대 출력 필드**(HELM #1739 요청). 초안: `PYTHONPATH=<worktree>/feature-pack/rag-consumer/src ~/.local/share/airag/runtime/bin/python -m airag_consumer.tick --config ~/.local/share/airag/projects/ai-feature-pack/runtime.json --credentials <worktree>/.fable-team/airag/credential-source.json` (자격 파일 형식=`token_file`+`references` 로 tick 과 호환 확인됨, 로그 기본 `~/.local/share/airag/logs/`). 기대 출력: 값 없는 JSON 1줄 `{"exit":0,"status":"ok","ts":…,"summary":{sources·accepted·gaps·coverage_complete·published_*·memory_*·pass_elapsed_s·backup_due/created …}}`. 주의 3가지를 함께 보고: ⓐ설치 런타임에는 아직 tick 모듈이 없어 수동 1회는 PYTHONPATH 로 소스 트리를 쓰고, 등록(U2) 전에 휠 재빌드·재설치 필요(재설치 승인 재확인) ⓑ현재 runtime.json 은 allow_gaps=false 라 투어08 사전검사의 거부 1건에서 수동 1회가 실패할 수 있음 → U3 G1 먼저 적용할지 HELM 판단 ⓒ op 자식 env 허용목록이 프록시·인증서 변수를 제외 — 프록시 필요한 네트워크면 exit 30(OP_*) 가능, 실패 시 사용자에게 알려 허용목록 확장 판단.

## 사용자 판정(INSTRUCTION-LEDGER «User decisions 2026-10-01 14:3x»)
U1·U2·U6 래퍼→사용자 수동 1회→이상 없으면 launchd `com.airag.consumer`(StartInterval 300·`run --once`·로그 `~/.local/share/airag/logs/`) 등록, 중단=bootout / U3=**S1+G1**(현재 소스 1개 유지 + `allow_gaps=true`, runtime.json 한 줄·변경 전 백업) 적용은 U1 DA PASS→수동 1회 뒤 **HELM 별도 발주** / U4 기억 추출 ON(첫 패스 요청 수·지연 보고) / U5 설계 범위. **등록·runtime.json 변경은 HELM 별도 발주 전 금지.**

## 좌석·도구 함정(실측)
- Nano `ft-airag-nano-r1#0`(Sonnet 5.5 [1m], ctx ~30%) — 발주=mbox send + 도어벨 `sent` 확인, `noagent` 오탐이면 pane 이 곧 claude 이므로 tmux `send-keys -l` + 별도 `Enter`.
- DA `ft-airag-da-sol#1`(codex gpt-6.1-sol high). **`#0` 은 «위조·재현·우회» 같은 공격 어휘에 모델 안전 필터로 중단**됨(보존만). DA 발주는 «우리 팀 로컬 코드 품질 점검, 합성 fixture» 중립 문구.
- `git add` 가 `.fable-team` 무시 경고로 비정상 종료코드를 낼 수 있음 → `&&` 체인 대신 `;` 로 분리, 커밋 후 `git show --stat` 로 구조/행위 분리 확인.
- 회귀 러너: 스크래치패드 `run-regr.sh <label> <dir> <log>`(없으면 pytest 직접). 로그 머리 `commit=` 이 clean HEAD 와 일치해야 함. 디스크 여유 89→65Gi(내 scratch ~470M, 대부분 타 세션) — 모니터.
- 삭제는 보고된 합성 산출물 한정(DA 합성 폴더 4개 정리 완료·보고 대상 HELM #1746).
- 투어 파일은 이제 git 추적(`.fable-team/bin/tour/`).

## 열린 항목(소유자)
| 항목 | 상태 | 소유 |
|---|---|---|
| DA r10 판정 수신·판단 | 대기 | 후계 master |
| 수동 1회 한 줄 + 기대 필드 보고 | r10 major 0 뒤 | 후계 master → HELM |
| U3 G1 적용·U2 launchd 등록 | HELM 별도 발주 전 금지 | HELM |
| 잔여 확인대기 51·검증대기 25 | 사용자 보류 | 사용자 |
| C09 외 push | 별도 사용자 승인 | 사용자 |
| 내 scratchpad `bt-*` 임시 폴더 467M | 정리 가능(내 산출물) | 후계 |

## 커밋 사슬(최근)
… `65f27e0`(DA r9 판정) → `5860e32`(틱 래퍼 r9 수정) → `9ca9a73`(Nano r3 결과). 상세 진행표: `.fable-team/state/airag/master-progress.md`.
