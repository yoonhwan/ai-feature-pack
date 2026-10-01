최신 fable-team 하네스를 이식하고 기존 AIRAG 증거를 재대조한 뒤, Claude Opus 5.5 HELM·Sonnet 5.5 Master/Nano·GPT-6.1 Sol DA 완성 루프로 AIRAG를 운영 가능한 상태까지 닫는다.
A03 닫는 증거: 「Sonnet 5.5 Nano 구현·GPT-6.1 Sol DA 루프」 — 지금 대상은 A02 트리 5순위 «운영·백업 증거» U1(상시 서비스 키 주입 래퍼) DA 수렴.
골의 어느 축인가: A03 — A02 트리 5순위(후보 C12, C07은 운영 결정 뒤).

# HELM 인계 스냅샷 #1 (2026-10-01 17:40, HELM ft-airag-helm-claude#0 · 컨텍스트 417k)

## 복원 사건 (먼저 읽을 것)
- 17:26 tmux 서버 사망 → tmuxc restore 가 좌석 이름 ↔ `--resume` 대화 id 를 6칸 중 4칸 어긋나게 연결. 정본 매핑은 `INSTRUCTION-LEDGER-airag.md` «사건 2026-10-01 17:30».
- 정본: helm=f30b71e2(Opus) · master#0=290ec031 · nano-r1=b12972e7 · a01-analyst=36b3f6e4 · arch-claude#0=a98a9bf9 · master#1=00c55109.
- 재연결 스크립트 `scratchpad/relink-airag.sh` 는 17:3x 첫 실행이 `setsid` 부재로 무음 실패 → `tmux run-shell -b` 로 재실행. **결과는 `relink-airag.log` 와 `ps` 로 확인**(좌석 이름 ↔ 모델: helm 칸만 Opus).
- 재연결로 HELM 의 CronCreate 체크 루프(10분)가 소멸 → HELM 이 재설치(3,13,23,33,43,53 * * * *, 프롬프트 = 직전 체크 루프와 동일).
- 뉴스(launchd com.airag.ft-news-tick, 5분)는 내용이 바뀔 때만 `ft-airag-helm-claude#0` 으로 relay. 틱 스크립트 소유권 = arch-astra(복원 안 됨, 필요 시 되살림 판단은 사용자).

## 작업 상태 (HEAD fa94076, push 없음)
- ✅ H01~H03 · A01 · A02. A03 의 순위 1(형상 보존 bd5386a) · 2(회귀·DA r1~r3 PASS) · 3(정리) · 4(투어 14 사용자 수용, 승인 10·검증 10, 잔여 확인대기 51·검증대기 25 사용자 보류).
- 🔄 순위 5: 설계 vs 실재 조사(7e1f4f4) · 사용자 판정 U1~U6(지시 원장) · DA r6 잔존 수정(78c4c39) · 래퍼 tick.py(c079e96·53bc160) DA r8→r9→r10(major 1: 네이티브 stdout 버퍼 누출) → **architect 상향**(arch-claude#0 Sonnet 5.5): 설계 r1 REJECT(major 3) → r2 REJECT(major 2) → r3 완성(파일 `.fable-team/state/airag-arch-claude/arch-20261001-item5-u1-design.md`). 방향 = 구성요소 별도 프로세스 분리(DA 실험 지지). 새 DA `ft-airag-da-codex#0`(gpt-6.1-sol high) 에 r3 재발주 대기(da-sol#0/#1 은 복원 후 사라짐).
- ⏸ 이후: 설계 PASS → Nano 구현 → DA r11(major 0) → **사용자 수동 1회**(스냅샷 주의 3건: 설치 런타임에 tick 없음 · allow_gaps · op env 허용목록 프록시 제외) → U3 G1 `runtime.json` allow_gaps 한 줄(백업 후) → launchd `com.airag.consumer` 등록(StartInterval 300, run --once, 등록 전 launchd 환경 1Password 확인) → 라이브 관찰.
- ⏸ 순위 6 acceptance 8·9(KakaoBot 최종 통합 보고서). 보류: 멀티 부하 사다리 · gateway 용량 실험 · P08B.
- 3라운드에서도 설계 PASS 불가 시: architect 가 쟁점 정리 → Master → HELM 이 사용자에게 진행 방식 질문.

## 사용자 판정 요약 (원문은 지시 원장)
수집 대상 S1+G1 · 기억 추출 ON · 간격 5분 · 서비스는 «래퍼→수동 1회→등록» · push 금지(리포 PUBLIC) · 투어 14 되돌리기 = 백업 복원뿐 · 키 값은 어디에도 기록 금지.

## 알려진 하네스 사실
- ft-tmux-spawn 은 arch-astra 가 seats.json 자동 등록하도록 수정함(실증 필요). Claude 좌석 doorbell 도 수정됨.
- 디스크 여유 ~65Gi(대부분 타 프로젝트 임시 폴더, AIRAG 은 작음). pid 2405(테스트 키 보관 프로세스) 정지는 사용자 승인 사항.
- fable-5 는 주간 95% 소진 → 사용하지 않음.

## 인수 첫 일
1) 골 원문 대조 보고(위 3줄) 2) `ft-mbox.sh recv ft-airag-helm-claude#0` 3) CronCreate 체크 루프 재설치 4) 새 DA r3 판정 대기 5) 뉴스가 내 pane 에 도착하는지 확인(마지막 뉴스 /tmp/mbox/*news-tick*helm-claude*).
