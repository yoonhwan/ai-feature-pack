# 인덱스: r387-da-hold2-redesign-research-loop — 같은 카드 DA 보류(HOLD) 2회 = 검증 끝: 3번째 DA 발주를 쪽지 가드가 REJECT(판정기 `ft_da_hold_gate.py` · 카드 «상태» 절의 `DA(②|⑥) rN HOLD` 줄 수 · `재설계:` 줄 뒤만 셈) → arch 재설계(판정 1641 승격) → 안 풀리면 리서치 나노(`ft-nano-spawn … --research` · opencode deepseek-v4-flash 무료 우선 · 또는 Fable 5) 가 RESEARCH 파일을 arch 에 → opencode 는 즉시 닫기(r286 reap) · Fable 은 끝나면 닫기. 판정 2282 · 전 팀장 공통(전역 하드 룰 14).
<!-- ledger: design/harness/GOAL-harness.md -->
- Issue: 없음 → 요청 원장 R(판정 2282 · planner#69 · desk #108768 오빠 원문 · master#67 108772)
- 제안서: 없음 — 설계 `design/harness/DESIGN-da-hold2-redesign-research-loop-20261018.md` r1(짧게 · 기존 재사용)
- 상태: 대기
- 설치: 있음 — LIVE `.fable-team/comm/mbox_guard.sh` + LIVE_BIN `ft-nano-spawn.sh`·`ft-index-lint.sh`·`ft_da_hold_gate.py` cp+cmp0 · 홈 2(`~/.claude/skills/fable-team/references/main-team-governance.md` 새 절 + `~/.claude/skills/tmuxc/COMM-GUIDE-BOOT.md` 40 — 키트 staged 사본 `design/harness/staged-r387/` 에서 cp+cmp0 · drift 0 · 오빠 h 1회 planner 경유) · `--range` OK
- 선행: 없음(지금 spawn 가능) · r286(opencode reap) 병행 — ⓒ 실사건의 opencode 닫기는 r286 설치 뒤 · 그 전엔 Fable 워커로 실사건 가능 · 완성 전
- 시험 입력: ⓐ `bash tests/harness/test_da_hold_gate.sh` fail=0 — 카드 픽스처 HOLD 0/1 → rc0 · HOLD 2 → rc3 · `재설계:` 줄 뒤 HOLD 1 → rc0 · 같은 라운드 중복 줄 1로 · 카드 경로 없음 → 가드 통과(fail-open 로그 1줄) ⓑ 가드 격리 실행: DA 좌석으로 `[DA⑥ 발주` + HOLD 2 카드 → `REJECT DA 보류 2회 …` rc3 · 큐 적재 0 · HOLD 1 카드 → QUEUED ⓒ `ft-nano-spawn --research --dry-run`: 좌석 이름 `-research` 꼬리 + 발주 본문 고정 문단 · `--agent opencode` 인데 r286 reap 없음 → REJECT 원문 · `--agent claude --model claude-fable-5-1[1m]` 통과 ⓓ `ft-index-lint.sh` HOLD 2 + 재설계/리서치 줄 없음 → INFO 1줄.
- 기준값(실측 10-18 17:1x): r382d 카드 = `DA⑥ r1 HOLD 4` + `DA⑥ r2 HOLD 1` 2줄 → 지금 판정기로 rc3 이어야 함 · 지금 가드 = DA 발주 머리 검사 0(사람 기억 의존 · 판정 2281 ④).

## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.
## 골좌표
하네스 GOAL 표 B(개선요청 등록·처리) / 닫는 증거(정본 복붙): 「REQUEST-LEDGER.md 행 + Issue 「채택/보류 + 오빠 값」 코멘트 + 반영 sha」 — 이 단위는 판정 2282 행 + 반영 sha + ⓐ지침 2줄 ⓑ장치 시험 ⓐ~ⓓ 원문 ⓒ하네스 실사건 1회. A6 골 4 «하네스팀 랜딩부터»(하네스팀 자신이 먼저 쓰고 전 팀 패치 · 오빠 «바로 하네스 업그레이드 · 거의 메인 지침»).

## 배경 (한 단락)
r382d 에서 DA⑥ 이 r1 HOLD 4 → r2 HOLD 1 로 두 번 막혔고, bounded_da_review 의 «second HOLD = stop serial review» 규칙은 있었지만 ★막는 장치가 없어★ 발주 전 HOLD 수 확인을 arch·master 가 기억으로 했다(판정 2281 ④). 오빠 판정 2282 는 이것을 전 팀장 공통 메인 지침으로 올렸다 — «2회 이상이면 문제를 다시 돌아보고 해결을 재설계 · arch+DA 로 안 나오면 리서치 나노워커(opencode 딥시크 플래시 무료 · 또는 Fable 5)를 넣어 자료·가설·BTS 결과를 arch 에 · opencode 는 쓰고 바로 닫기(메모리 버그) · Fable 은 재질문용 잠시 뒀다 끝나면 닫기». 판정 재료(카드의 `DA⑥ rN HOLD` 줄)와 발주 경로(mbox 가드)와 워커 경로(ft-nano-spawn --agent opencode · ft-nano-close · r286 reap)가 전부 이미 있어, 새로 만드는 것은 판정기 1개와 가드 분기 1줄·spawn 플래그 1개뿐이다.

## 사전검증
- DA② 1회(설계 r1 · 묻는 것 = ①HOLD 셈 규칙이 다른 팀 카드 꼴에도 거짓 양성 없이 맞는가 ②가드 fail-open 범위(카드 경로 못 찾음)가 우회로가 되지 않는가 ③`재설계:` 줄 리셋이 «이름만 바꿔 재발주» 를 막는가(bounded «rename does not restart») · bounded 10분) · DA⑥ 1회 · ★이 카드 자신도 DA 상한 2(판정 2282 ③)★.

## 조사 근거 (17:4x)
- `design/harness/indices/진행/r382d-team-move-occupancy-single-lsof-deadline.md` 상태 절(HOLD 2줄 실례) · `.fable-team/comm/mbox_guard.sh`(guard_check · 머리·수신자 검사 자리) · harness-ops 실재 `scripts/fable-team-bin/ft-nano-spawn.sh`(`--agent opencode` 는 `--model` 필수 REJECT :112 · `--recheck` 꼴) · `docs/rules/bounded_da_review.md` §Hard stop · 전역 `~/.claude/CLAUDE.md` 하드 룰 14(10-18 착지) · r286 카드 `indices/대기/r286-roster-opencode-nano-close.md`(opencode reap · 미구현) · opencode 모델 ID `deepseek/deepseek-v4-flash`(tmuxc 스킬 실재).

## 구현 범위 (나노 1 · base origin/main · 설계 §3 그대로 · 새 도구 최소)
1. 새 `scripts/fable-team-bin/ft_da_hold_gate.py`(≤60줄): `<카드>` → `HOLD n=<수> last_redesign=<줄|none>` · rc0/rc3 · «## 상태» 절 · `DA(②|⑥) r\d+ HOLD` · 마지막 `- 재설계:` 줄 뒤만 · 같은 라운드 중복 1.
2. `.fable-team/comm/mbox_guard.sh`(추적본 `scripts/harness-install/…/mbox_guard.sh`) 분기 1: 수신자 `*-da-*` ∧ 머리 `[DA② 발주`|`[DA⑥ 발주` → 본문·첨부에서 `indices/(대기|진행)/<카드>.md` 1개 → 판정기 rc3 이면 `REJECT DA 보류 2회 — …(재설계·리서치 안내 · BOOT 40)` · 못 찾으면 통과 + `state/mbox-guard-da.log` 1줄.
3. `scripts/fable-team-bin/ft-nano-spawn.sh` `--research`: 좌석 이름 꼬리 `-research` · 발주 본문 고정 문단(산출 `design/<팀>/RESEARCH-<카드>-<날짜>.md` · 코드 수정 0 · relay → arch · 즉시 [완료·휴식]) · opencode 인데 reap 도구 없으면 REJECT.
4. `scripts/fable-team-bin/ft-index-lint.sh` INFO 1줄(HOLD 2 + 재설계/리서치 줄 없음).
5. 문서(판정 2283 ⓐ): `design/harness/staged-r387/main-team-governance.md`(홈 정본 사본 + 새 절 «§10 DA 보류 2회 → 재설계·리서치 루프») + `design/harness/staged-r387/COMM-GUIDE-BOOT.md`(40 한 줄) — 홈 설치는 오빠 h(cp+cmp0 · drift 0). `docs/rules/bounded_da_review.md` 는 교차 참조만(변경 0).
6. 시험 `tests/harness/test_da_hold_gate.sh`(ⓐ~ⓓ) · 키트 cmp0.
7. 범위 밖: DA 모델 사다리 값 · bounded 시간 값 · r286 구현(병행 카드).

## 완료 조건
- 시험 ⓐ~ⓓ rc0 원문 · `bash -n`·ruff OK · `\b(600|300)\b` 0 · DA②·DA⑥ CLOSE(상한 2) · 착지 sha · 설치 cmp0 4파일 + 홈 2(governance 새 절 · BOOT 40 · 오빠 h · drift 0) · `--range` OK · 실사건 = 하네스 팀 1회: HOLD 2 카드(r382d 또는 다음 건)에 3번째 `[DA⑥ 발주` 시도 → `REJECT DA 보류 2회` 원문 + 리서치 나노 1석(opencode · r286 뒤 · 또는 Fable) 열고 RESEARCH 파일 arch 수신 mbox #N + 닫힘 증거(`ft-nano-close` rc0 · reap left=0 또는 Fable 좌석 kill 시각) 복붙.

## 정본
- 정본화: design/harness/staged-r387/main-team-governance.md
- 메모: 홈 정본 `~/.claude/skills/fable-team/references/main-team-governance.md` 의 staged 사본에 새 절 1(«DA 보류 2회 → 재설계·리서치 루프» · 판정 2282·2283) + BOOT 40 한 줄 — 둘 다 키트 설치·drift 0(판정 2283 ⓐ) · 전역 하드 룰 14 는 desk 가 올림(카드 밖 · 변경 0) · bounded_da_review 는 교차 참조만.

## 상태
- base_sha: c261ed6f0c60e64c43cab09a3ef0620b90630aa3 (spawn 2026-10-18)
- 규칙: 지침=~/.claude/CLAUDE.md · 강제=.fable-team/comm/mbox_guard.sh
- 2026-10-18 17:5x — 판정 2283 반영: ⓐ = governance 새 절 + BOOT 1줄(키트 staged 설치 · drift 0) · bounded_da_review 변경 0 · 전역 하드 룰 14 는 카드 밖 (byz-harness-arch-claude#86)
- 2026-10-18 17:4x — 대기/ 생성 (byz-harness-arch-claude#86 · 판정 2282 · master#67 108772 집행 순서 = arch 설계 → 나노 1석 → DA 상한 2 → 오빠 h 1회 → 설치 → ⓒ 실사건 1회) · spawn = 설계 DA② 뒤 master.
- 2026-10-18 17:5x — DA② r1 HOLD(판정 1회 · 지적 3 · `DA-r387-da2-20261018.md` · mbox #108836 · model: GPT-6 기반 Codex · provider: OpenAI) Q1 셈 규칙(실제 카드 꼴 3종 = r 없는 첫 판정 · 같은 판정 재기록 2줄 · ②r1/⑥r1 공존 → 줄 수 ≠ 사건 수) · Q2 우회로(카드 경로 fail-open · `[DA⑥ r2 발주 · 마지막]` 머리 누락 · 재설계 줄 자동 리셋 = bounded 충돌 · 리서치 코드 0 미검증) · Q3 닫기(워커별 close/reap 증거 + 부모 완성 게이트 없음) → arch#87 설계 r2 = DESIGN §7(사건 키 · fail-closed 입장 · 누적 유지 + 상위 해제 줄(mailbox seq 검증) · 워커별 닫힘 줄 + index-move 게이트 2 · bounded 변경 0) → DA② r2 발주(검토 2회째 · HOLD 사건 1/2 · r2 CLOSE 면 DA⑥ 0 = arch 통합 판단) (byz-harness-arch-claude#87)
- 2026-10-18 17:5x — DA② r2 HOLD 1(판정 1회 · `DA-r387-da2-r2-20261018.md` · mbox #108864 · model: GPT-6 기반 Codex · provider: OpenAI) Q1 CLOSE(사건 키 셈 · 실제 반례 2/1/3 사건 맞음) · Q3 CLOSE(워커별 닫힘 줄 + 부모 게이트) · Q2 HOLD(해제 줄 3필드 검사가 카드명만 언급한 보류·무관 쪽지도 통과 · 명시 승인·새 범위 검증 없음 · `2+released−events` 는 CLOSE 뒤 예산이 안 줄어 같은 해제로 추가 검토 가능 → 해제 seq 는 검토 입장 때 1회 소진) → ★HOLD 사건 2 = 이 카드 검증 끝(3번째 DA 발주 0 · 판정 2282 첫 실사건)★ → arch#87 재설계 §8(해제 쪽지 꼴 고정 + 소진 규칙) + 상위(master#67) 재설계 해제 결정 요청 · 리서치 나노 불필요(원인 = 규칙 의미 · 가설 공백 0) (byz-harness-arch-claude#87)
- 재설계 해제: #108869 · byz-harness-master-claude#67(명부 _master) → byz-harness-arch-claude#87 · 머리 [재설계 해제 r387-da-hold2-redesign-research-loop.md] · 해제=1 · 새 범위: 설계 §7+§8 구현(사건 키·fail-closed 입장·명부 기반 해제·소진·워커별 닫힘·부모 게이트) · DESIGN r3 — 이 해제 1건 = 검토 1회(DA⑥ r1 · 마지막) 소진 예정 · DA② r3 0
- 2026-10-18 17:5x — 나노 구현 범위 = 설계 `DESIGN-da-hold2-redesign-research-loop-20261018.md` §3 기본 + ★§7-4 + §8-4 산출 목록이 §3·§5 를 덮어씀★(새 1 ft_da_hold_gate.py · 수정 5 mbox_guard.sh·ft-nano-spawn.sh --research·ft-nano-close.sh·ft-index-move.sh·ft-index-lint.sh · staged 문서 2 governance §10·BOOT 40 · 시험 1 test_da_hold_gate.sh(§7-4 + §8-4 케이스 전부)) · base origin/main · spawn = master#67(--from) · DA⑥ 1회 · 실사건 ⓒ = 이 카드 자신(②r1·②r2 HOLD → 3번째 발주 가드 REJECT 원문 1회 + 해제 #108869 유효 판정 출력 1회 · 리서치 나노 실사건은 r286 뒤 다음 카드) (byz-harness-arch-claude#87)
- 2026-10-18 17:42 — 대기→진행 · 좌석 byz-harness-nano-r387-da-hold2-redesign-research-loop#0
- 2026-10-18 18:3x — 나노 구현 끝(설계 §7·§8 · 브랜치 nano/r387-da-hold2-redesign-research-loop · 커밋 9fcc379c32 [feature] + 4ee9b80974 [docs] · push 0): 새 ft_da_hold_gate.py · mbox_guard_da.sh(+mbox_guard.sh 3줄·check-drift) · spawn --research · close 위반/닫힘 줄 · index-move 완성 게이트 · lint INFO/REJECT · staged-r387 문서 2 · 시험 test_da_hold_gate.sh 68 PASS(실제 해제 #108869 유효 판정 포함) · 기존 mbox_guard 130·index_lint 75+13·index_move 4종·nano_close 4종·nano_spawn 3종 PASS · test_spawn_hold 1 FAIL 은 베이스에서도 동일(라이브 hold 2104)
- 설치 대상(master): 키트→LIVE_BIN 5파일(ft_da_hold_gate.py·ft-nano-spawn.sh·ft-nano-close.sh·ft-index-move.sh·ft-index-lint.sh) + comm 2파일(mbox_guard.sh·mbox_guard_da.sh · check-drift 목록 추가) cp+cmp0 · 홈 2(staged-r387 governance·BOOT → 오빠 h) — ★설치 즉시 DA 발주서에 `- 카드:` 줄 + 카드 `DA⑥ rN 발주` 줄이 없으면 막힌다(arch 발주 틀 갱신)★
- 설계 대비 판단 3: ①governance 새 절 번호 = §12(설계는 §10 이라 적었으나 §10 은 측정 조작 금지가 이미 점유) ②`--closing`(완성 이동) = «사건 ≥ 2 ∧ 유효 해제 0» 일 때만 거절(설계 문장 «rc3 면 REJECT» 를 그대로 쓰면 해제 뒤 소진된 카드도 영원히 못 닫는다) ③리서치 좌석 닫기 때 기존 증거 줄(⑥)·cherry(⑤) 게이트는 그대로 — RESEARCH 산출은 랜딩 0 이라 master 가 `--cherry-override` 를 써야 한다(설계 §7 범위 밖 · 필요하면 후속 카드) · ft-opencode-reap.sh(r286) 미구현이라 opencode 리서치는 REJECT(Fable 만 열림)
- press 필요: 없음(장치·문서 — 라이브 오디오 시험 0)
- 세트: 4ee9b8097425cd37e690a35fbf034f9357bb06c8 · 시험: bash tests/harness/test_da_hold_gate.sh rc=0 · 이슈: 0
- 2026-10-18 18:0x — arch#87 재현(나노 워크트리 · </dev/null): test_da_hold_gate.sh 68 PASS fail=0 rc=0 · ruff OK · bash -n 15파일 OK · 키트 cmp0 4 · merge-tree origin/main(0e894be3e2) rc0 · r382b 겹침 파일 0 · 600/300 추가 = 문서 인용 1·`[:300]` 2·시험 자체 검사 1(상한 아님) · diff 19파일 +869 −23 → DA⑥ r1 발주(`DA-BRIEF-r387-da6-20261018.md` · 질문 4 · 해제 #108869 소진 · 마지막) (byz-harness-arch-claude#87)
- DA⑥ r1 발주: 2026-10-18 18:0x · da#5 · 세트 4ee9b8097425cd37e690a35fbf034f9357bb06c8 · 발주서 DA-BRIEF-r387-da6-20261018.md (byz-harness-arch-claude#87)
- 2026-10-18 18:1x — DA⑥ r1 HOLD 4(판정 1회 · `DA-r387-da6-20261018.md` · mbox #108934 · model: GPT-6 기반 Codex · provider: OpenAI · 인정: 자체 68 PASS · 기존 회귀 표본 rc0 · 키트 cmp0 · comm 매핑) Q1 실제 카드 3꼴 사건 0/0/1(작성자 prefix skip · UNPARSED 도 skip 뒤) · Q2 같은 --entry 키 2회 모두 budget 1(소진 0) + 해제 #108869 가 승계(master#67→#68) 뒤 RELEASE-INVALID · Q3 reap 존재·left=1·rc1 을 pipefail 로 «도구 없음» 흡수 + exit 0 · Q4 staged BOOT 가 홈 14번 R382b 문장 삭제 → ★HOLD 사건 3(②r1·②r2·⑥r1) · 해제 #108869 소진★ → arch#87 재설계 §9(해제 발신자 = 계보+은퇴 기록 · 입장 기록 줄 = 소진 단위 · DUP-ENTRY) + 결함 3 → 나노 r2 반송(`BRIEF-r387-nano-r2-return-20261018.md`) → 상위 해제 2 요청(master#68) → DA⑥ r2(마지막) (byz-harness-arch-claude#87)
