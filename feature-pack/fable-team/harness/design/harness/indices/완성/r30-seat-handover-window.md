# 인덱스: 승계 때 오빠 창 자동 이관 — ft-seat-handover.sh(snapshot·apply·status) + 은퇴 좌석 relay 훅 + attach 떠넘김 Stop 훅 (R30)
<!-- ledger: design/harness/GOAL-harness.md -->
- Issue: 없음 → 요청 원장 R30(planner#9 → master#14 #62370 · 오빠 원문 relay #62371)
- 상태: 대기
- 선행: 없음(안 = design/harness/DESIGN-r30-succession-window-handover-20261008.md §2 r2 + §6 통합 이관 ①②)
- 시험 입력: 가짜 tmux 스텁(PATH 앞에 둔 `tmux` 스크립트 · list-clients/switch-client/has-session/show-option/set-option/display-message 응답을 fixture 파일로) + 가짜 명부 JSON + 가짜 장부 jsonl + Stop/UserPromptSubmit 훅 입력 JSON — 실제 tmux switch 0
- 기준값: 지금 승계하면 오빠 탭이 구 좌석에 남는다(실례 13:5x `/dev/ttys000` → byz-feature-master-claude#2 · 명부 _master = #3) · 구 좌석이 오빠께 attach 명령 2회 · 구 좌석이 판정 번호 매겨 충돌 2회(408·410)

## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
하네스 GOAL 표 / 닫는 증거(정본 복붙): 「이상 1건 = Issue 1건(team:shared-harness) + 검토 코멘트」.
골의 축: A(모니터·오빠 요청 — 오빠 원문 「이걸 나보고 하라는 것도 버그다 … 잘 혼자 하던 증류를 사용자에게 요청하면 버그」). 핵심 한 줄: 승계 창 이관을 좌석이 직접 하고, 은퇴 좌석은 판정 대신 후계로 넘기며, 오빠께 attach 실행을 맡기는 문장을 막는다.

## 배경 (한 단락 — 나노워커가 이 파일만 읽고 착수 가능해야 함)
오빠는 Ghostty 탭마다 tmux 클라이언트 1개로 좌석 세션 하나를 본다(13:5x `tmux list-clients` 10개 · 세션 10개 전부 다름). 좌석이 증류(승계)하면 후계 세션이 새로 열리지만 오빠 탭은 구 세션에 남고, 구 좌석은 오빠 입력을 계속 받아 판정 번호를 매기거나(충돌 408·410) tmuxc open 출력의 「접속: tmux attach -t」 줄을 오빠께 옮긴다. 처방은 셋이다. ①`ft-seat-handover.sh`: 승계 직전 `snapshot` 으로 구 세션 클라이언트를 영속 장부에 적고, 후계 부팅 보고 수신 뒤 `apply` 가 그 탭만 `switch-client` 로 후계에 붙인다(identity 3중 재확인 · T0 뒤 붙은 탭 제외 · ★T0 클라이언트가 2개 이상이면 전환 보류★). ②은퇴 판정 `status` = 장부 done 행 + 명부 `_<역할>` 대조(옵션 `@handed_over_to` 는 캐시) → UserPromptSubmit 훅이 RETIRED/MISMATCH/ACTIVE 를 주입해 은퇴 좌석은 새 판정 0 · 새 요청은 후계로 relay. ③Stop 훅: 인용 문맥(코드 펜스·`>`·따옴표·[HIL]/감사 메시지)을 «먼저» 떼어낸 뒤 남은 줄의 «오빠 실행 요청 형태»(`! ` 접두 · 요청어 동반)만 block, 나머지는 오탐 기록. DA 는 2 HOLD 로 리뷰 종료 — H3 승인, H1·H2 는 아래 시험으로 고정하고 구현 DA 에서 재확인한다.

## 사전검증
- 소환: 아니오
- 면제: 사전 DA 는 소환됐고 2 HOLD 로 리뷰 종료(bounded_da_review · 판정문 design/harness/DA-r30-handover-20261008.md §7·§8 · H3 APPROVE) → master#14 #62468 이 고정 범위 구현으로 승인 · 잔여 H1·H2 는 완료 조건 시험으로 고정하고 구현 DA 에서 재확인 — arch 서명 byz-harness-arch-claude#13

## 조사 근거
- `design/harness/DESIGN-r30-succession-window-handover-20261008.md:21` snapshot 규칙 · `:22` apply 순서(명부 대조 · identity 재확인 · skipped reason 4종) · `:25` status 호출 세션 고정(TMUX_PANE).
- `design/harness/DESIGN-r30-succession-window-handover-20261008.md:28` status 판정표 5행 · `:36` retired-seat-guard 주입 규칙(RETIRED 읽기 질의 허용 · 새 요청 relay + QUEUED·도달 확인 뒤 전달 문구 · 창 상태 단정 0).
- `design/harness/DESIGN-r30-succession-window-handover-20261008.md:41` Stop 훅 기준 · `:45` mbox 가드 제거 · `:75` ① H1 잔여(1탭만 follow) · `:81` ② H2 잔여(인용 문맥 선제외).
- `scripts/harness-install/fable-team/templates/settings-hooks.snippet.json:57` UserPromptSubmit 등록 자리(Stop 키는 아직 없음 — 새로 추가) · `scripts/harness-install/fable-team/templates/hooks/context-distill-gate.sh:588` additionalContext 주입 출력 꼴.
- `scripts/harness-install/fable-team/bin/ft-reach-check.sh:50` 도달 확인 인자 꼴(relay 뒤 도달 확인에 재사용).

## 구현 범위 (닫힌 목록 · 추적본 + 키트 사본 같은 바이트)
1. `scripts/fable-team-bin/ft-seat-handover.sh`(+ `scripts/harness-install/fable-team/bin/` 사본) — 장부 `${FT_HANDOVER_LEDGER:-$FT_ROOT/.fable-team/state/handover.jsonl}` append-only · 명부 경로 env 주입 가능.
   - `snapshot <구> <후계>`: `list-clients -t =<구> -F '#{client_tty} #{client_pid} #{client_created}'` → 1개면 `{"state":"pending","old","new","follow":[…],"ts"}` · ★2개 이상이면 `{"state":"pending","follow":[],"ambiguous":[…]}`★ · 0개면 follow 빈 목록.
   - `apply <구> <후계>`: 후계 `has-session -t =<후계>` + 명부 `_<역할>` == 후계 아니면 rc 1(아무것도 안 함) → follow 항목마다 실행 직전 재조회(tty·pid·created 모두 같고 client_session == 구)일 때만 `switch-client -c <tty> -t =<후계>` → 재조회로 후계 부착 확인 → `{"state":"done","moved":[…],"skipped":[{tty,reason}],"ambiguous":[…]}` 1줄 · `@handed_over_to=<후계>` 옵션(캐시) · 출력 1줄 `HANDOVER <구> -> <후계> moved=<n> skipped=<n> ambiguous=<n> (…)` · switch 실패 하나라도 rc 1.
   - ★ambiguous 처리 = 전환 보류 + 로그만(질문 0 기본)★: 출력 줄에 ambiguous tty 를 적고 `${FT_MBOX:-mbox.sh} send <_hil_route> <구> "[handover-ambiguous] <구>-><후계> tty=<목록> 전환 보류 — 은퇴 좌석 relay 로 입력 손실 0"` 1통(질문 문장 아님). 그 탭에서 오빠가 입력하면 2 의 RETIRED relay 가 후계로 넘기므로 안전 — 오빠께 묻는 것은 master 가 필요하다고 판단할 때만 `--client` 모드로(마지막 수단).
   - `apply --client <tty> --confirmed-by <seq>`: legacy·ambiguous 단발 · seq 없으면 rc 1 · 장부에 seq 근거.
   - `status <세션>`: 판정표 5행(설계 :28) 그대로 → `ACTIVE` / `RETIRED <X>`(옵션 없거나 다르면 X 로 복원) / `MISMATCH <세 근거 값>`.
2. 템플릿 훅 `scripts/harness-install/fable-team/templates/hooks/retired-seat-guard.sh`(UserPromptSubmit) — 세션 = `tmux display-message -p -t "$TMUX_PANE" '#{session_name}'` · `ft-seat-handover.sh status` 결과를 additionalContext 로(설계 :36 문구) · ACTIVE 면 출력 0 · status 실패 = 보이는 오류 주입(조용한 통과 0).
3. 템플릿 훅 `scripts/harness-install/fable-team/templates/hooks/no-attach-to-user.sh`(Stop) — transcript_path 의 마지막 assistant 텍스트 → ①1단 제외(코드 펜스 안 · `>` 줄 · 패턴이 따옴표 `"…"`·`「…」`·`'…'`·백틱 안 · 첫 줄이 `[HIL]`·`감사`·`AUDIT`·`DESIGN` 로 시작하는 메시지 전체) → 기록만 ②남은 줄에서 attach 패턴(`tmux attach`·`tmux a -t`·`attach-session`·`tmuxc attach`) + (`! ` 접두 또는 요청어 `해 주세요`·`하세요`·`붙어 주`·`접속해`·`들어가 주`·`실행해`) → `{"decision":"block","reason":"승계 창 이관은 ft-seat-handover.sh apply 로 직접 — 오빠께 attach 실행을 맡기지 않는다(R30)"}` ③기록 = `$FT_ROOT/.fable-team/state/hil-falsepos.log` 1줄 ④`stop_hook_active == true` 면 block 0(기록만).
4. `scripts/harness-install/fable-team/templates/settings-hooks.snippet.json`: `UserPromptSubmit` 에 retired-seat-guard 1줄 · `"Stop"` 키 신설 + no-attach-to-user 1줄.
5. 시험 `tests/harness/test_seat_handover.sh` — ★잔여 2건을 시험으로 고정(DA §8)★:
   - handover: ★T0 1탭 → move★ · ★T0 2탭(follow 1 + archive 1) → switch 0 + ambiguous 2 + planner 로그 1통(질문 문장 0)★ · T0 0탭 → no-client · T0 뒤 붙은 조회 탭 → switch 0 · 오빠가 다른 세션으로 → moved-by-user · tty 재사용 → identity-changed · 후계 없음 rc 1 · 명부 불일치 rc 1 · switch 실패 rc 1 · `--client` seq 없음 rc 1.
   - status: 판정표 5행 · 옵션 유실 → RETIRED + 복원 · 엉뚱한 옵션 → 장부·명부가 이김 · 다른 default 세션에서 호출(TMUX_PANE 고정).
   - Stop 훅: ★인용 줄 픽스처★ 「이전 좌석은 "tmux attach -t X 를 실행해 주세요"라고 요청했다」 → 기록 · 코드 펜스 안 `! tmux attach -t X` → 기록 · `[HIL]` 원문 메시지 → 기록 · 감사 문서 메시지 → 기록 · 맨 줄 `! tmux attach -t X` → block · 맨 줄 「tmux attach -t X 로 접속해 주세요」 → block · 맨 줄 attach-session + 「실행해」 → block · `stop_hook_active=true` + block 줄 → block 0.
   - guard 훅: RETIRED·MISMATCH·ACTIVE 주입 문구 3.
   - `bash tests/harness/test_kit_bin_sync.sh` PASS.

커밋은 자기 브랜치, **push 금지**. **금지**: 실제 tmux switch-client·kill · 라이브 FT_BIN·홈 `~/.claude` 쓰기 · mbox 실발신(시험은 FT_MBOX 스텁) · 이름 문자열로 후계 추측 · T0 2탭 이상 자동 전환 · 오빠께 질문하는 문장 자동 발신.

## 완료 조건 (닫힘 판정 기준 — ops 수락 판정문)
- `bash tests/harness/test_seat_handover.sh` rc=0 · `test_kit_bin_sync.sh` PASS · 사본 cmp · bash -n 전 파일.
- RESULT 에 ★T0 2탭 → switch 0 + ambiguous★ 출력 2줄과 ★인용 줄 → 기록(block 0)★ 출력 2줄 복붙 — 구현 DA 가 이 2건을 재확인.
- 카드 증거 줄 형식(필수 · 시험 칸은 명령 1개 · 없으면 반송): `세트: <40hex> · 시험: bash tests/harness/test_seat_handover.sh rc=0 · 이슈: 0`.
- 랜딩 뒤 master 집행(카드 밖): 라이브 FT_BIN cp · 훅 2 홈 설치 + settings 등록 · 정본 문장 3곳(governance §승계 · BOOT 13조 뒤 · 글로벌 CLAUDE.md 증류 절차 ③-b·⑤-b + 전파본) · 첫 적용 = feature 탭 `/dev/ttys000` 을 `apply --client /dev/ttys000 --confirmed-by <seq>` 로 1회 → 원장 R30 반영.
- 진행→완성 이동은 `ft-index-move.sh <파일> 완성 --da <판정문#§N>`.

## 상태
- base_sha: 550323859386004ca23282574d136294cc4b0d95 (spawn 2026-10-08)
- 2026-10-08 — 대기/ 생성 (byz-harness-arch-claude#13 · 원장 R30 · DA HOLD 2 → 리뷰 종료 · 통합 이관 → master#14 #62468 고정 범위 승인).
- 정본 영향 없음: 하네스 승계 도구·훅·시험만 — docs/architect 제품 정본 변경 없음.
- 2026-10-08 14:01 — 대기→진행 · 좌석 byz-harness-nano-r30-seat-handover-window#0
세트: 0c8045f678561d5402ed255d1ea42a59d72eefb9 · 시험: bash tests/harness/test_seat_handover.sh rc=0 · 이슈: 0
- 2026-10-08 14:37 — 진행→완성 · 좌석 byz-harness-nano-r30-seat-handover-window#0 · DA design/harness/OPS-VERDICTS-20261006.md#§57
