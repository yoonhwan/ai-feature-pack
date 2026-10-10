# 인덱스: 사람이 `!` 로 칠 명령 = 짧은 한 줄 `! bash /tmp/h<번호>` — 등록 도구 ft-hil.sh + 출력처 3곳 (R83 · 판정 850·852·853)
<!-- ledger: design/harness/GOAL-harness.md -->
- Issue: 없음 → R83(오빠 직접 지시 판정 850 · planner#21 #71964 · master#26 발주 #71971)
- 상태: 대기
- 선행: 없음(제안 Issue #1184 · 판정 852 ① 번호 · ★판정 853 r1: 진입점 = /tmp · 홈(~/) 생성 0★ — 카드 r1 은 이 지시 반영본)
- 제안서: #1184
- 시험 입력: 임시 디렉터리를 `/tmp` 대신 쓰는 `HIL_DIR` 환경변수 · 임시 계획 파일 · pbcopy 셸 스텁 — 실 /tmp·실 클립보드·실 계획 실행 0
- 기준값: 지금 사람 실행 안내 = `! bash <절대경로>` — 10-10 실측 115자(`.fable-team/state/wt-clean/orphan-v65-m5-lst-loud-r81.sh.hil`) · 화면 줄바꿈으로 두 조각 복사 → no such file. 출력처 3곳(아래 조사 근거) 전부 절대경로를 그대로 낸다 · `hil` 명령 없음(`command -v hil` 0)

## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
골의 축: B 「메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의」 + C 「업그레이드하고 레포에 커밋 푸시 … 배포 발행(슬랙) 수신해 반영」. 오빠 직접 지시(판정 850).

## 배경 (한 단락 — 나노워커가 이 파일만 읽고 착수 가능해야 함)
하네스 도구는 자율 범위 밖 정리를 «계획 파일(`*.sh.hil`)»로 만들고 사람에게 `! bash <절대경로>` 를 치게 한다. 경로가 100자를 넘어 pane·인터뷰 상자에서 줄바꿈되면 두 조각으로 복사돼 실패한다(10-10 v65 고아 정리 · 오빠 「앞으로 명령 한줄 스크립트로 줄바꿈 안걸리게 개선」). 이 카드는 머신마다 설치되는 짧은 진입점 `hil` 을 만든다: 계획 파일을 짧은 번호(`h<N>`)로 등록하고(`~/.hil/h<N>` 심링크), 안내는 `! hil h<N>` 한 줄만 내며 같은 줄을 클립보드에 넣는다. 실행은 언제나 사람 손이고, 계획 파일 내용·검사 로직은 바꾸지 않는다. ★r1(판정 853 · 오빠 「tmp에 만들어야지 너가 지울래?」): 진입점은 `/tmp/h<N>` 심링크(재부팅 소멸) · 홈(`~/.local/bin`·`~/.hil`)에 아무것도 만들지 않는다 · 사람 안내는 `! bash /tmp/h<N>` 코드블록 한 줄(원격 화면이라 클립보드는 보조) · 손 선례 `/tmp/h1`(v65 고아 계획 심링크)·`/tmp/h2`(손 계획 파일)와 번호가 겹치지 않게 «있는 `/tmp/h<숫자>` 최대값 + 1».★

## 사전검증
- 소환: 아니오
- 면제: 새 진입점 1개(등록·목록·실행 — 계획 파일은 기존 그대로 실행) + 기존 출력 3곳의 안내 문자열 교체 · 파괴 경로 신설 0(실행은 사람 `!` 그대로) · 시험으로 닫음 — arch 서명 byz-harness-arch-claude#27

## 조사 근거 (기준 = origin/main · 2026-10-10 실측)
- `scripts/fable-team-bin/ft-nano-close.sh:524` — `사람 ! 실행: ! bash $PLAN` 출력(`--wt/--branch` 모드 계획 `.sh.hil` · `:80`).
- `scripts/fable-team-bin/ft-nano-spawn-undo.sh:130`~`:133` — 단독 모드 계획 생성 후 `PLANNED <좌석> <절대경로>`.
- `scripts/fable-team-bin/ft-wt-sweep.sh:28`~`:29` — skipped·실패 계획을 `.sh.hil` 로 옮기고 `[HIL] … · 스크립트 <절대경로>`.
- 세 파일 모두 `scripts/harness-install/fable-team/bin/` 에 바이트 동일 두 벌(킷).
- 클립보드 선례: `scripts/harness-install/fable-team/bin/ft-op-token.sh:13`(pbcopy · macOS 전용).
- 사고 원문: mbox #71921(v65 master#161 → planner · 손으로 만든 `.sh.hil` 의 `! bash "<115자>"`) — 도구 밖 손 계획도 `hil --add` 로 등록하게 안내가 필요.

## 구현 범위 (닫힌 목록 · 나노 브랜치는 origin/main 기준)
1. 새 파일 `scripts/harness-install/fable-team/bin/ft-hil.sh` (bash · 실행 권한 · 같은 바이트로 `scripts/fable-team-bin/ft-hil.sh` · 100줄 이하 · 사람이 아니라 도구·오케가 부른다):
   - 진입점 폴더 = `${HIL_DIR:-/tmp}` (시험만 바꿈) · 링크 = `$HIL_DIR/h<N>` · 홈(`$HOME`) 아래 쓰기 0.
   - `ft-hil.sh --add <계획 파일>`: 파일 실재 아니면 REJECT · 같은 대상(realpath)을 가리키는 `h<N>` 링크가 이미 있으면 그 번호 재사용 · 아니면 `$HIL_DIR/h<숫자>`(링크·파일 모두) 최대값 + 1 로 심링크(`mkdir` 락 `<HIL_DIR>/.hil.lock` 안 · 이미 있는 이름은 절대 덮지 않음) → stdout `! bash $HIL_DIR/h<N>` 1줄 · `pbcopy` 가 있고 `HIL_CLIP` ≠ 0 이면 `bash $HIL_DIR/h<N>` 을 클립보드에(실패해도 출력은 그대로 · 경고 1줄).
   - `ft-hil.sh --cmd '<명령>'`: `$HIL_DIR/hil-cmd/<시각>.sh` 로 `#!/usr/bin/env bash` + 명령 1줄을 쓰고 `--add` 와 같은 처리.
   - `ft-hil.sh` (인자 없음): `h<N>  <대상>  <대상 실재 여부>` 목록.
   - 금지: 계획 파일 수정·삭제 · 실행 기능(실행은 사람 `bash /tmp/h<N>`) · `eval` · 기존 `h<N>` 덮기·지우기.
2. 출력처 3곳(각 두 벌 동일 · 안내 문자열만 · `ft-hil.sh` 는 같은 bin 폴더(`$HERE`)에서 부른다):
   - `scripts/fable-team-bin/ft-nano-close.sh:524`: 계획 생성 뒤 `ft-hil.sh --add "$PLAN"` 결과 줄로 `사람 ! 실행: ! bash /tmp/h<N>` 안내 · `ft-hil.sh` 가 없거나 실패하면 지금 문구 그대로 + `WARN ft-hil 실패`.
   - `scripts/fable-team-bin/ft-nano-spawn-undo.sh:133`: `PLANNED <좌석> <경로> · 사람 ! 실행: ! bash /tmp/h<N>`(뒤에 덧붙임 — 앞부분 유지해 호출자 파싱 보존) · 실패면 지금 그대로 + WARN.
   - `scripts/fable-team-bin/ft-wt-sweep.sh:28`~`:29`: `.sh.hil` 로 옮긴 직후 `ft-hil.sh --add` · `[HIL] … · ! bash /tmp/h<N>` · 실패면 지금 그대로 + WARN.
3. 설치 변경 0 — `ft-hil.sh` 는 킷 bin 의 일반 파일이라 기존 install.sh 가 같이 복사한다(PATH·홈 설치 0).
4. 시험(`tests/harness/test_hil.sh` 새 파일 · 임시 `HIL_DIR` · pbcopy 셸 스텁):
   - ①`--add` → `! bash <HIL_DIR>/h1` · 링크 1 · 클립보드 스텁 입력 = `bash <HIL_DIR>/h1` ②같은 계획 재등록 = h1 재사용 ③미리 있는 `h2` 파일(손 선례) + 새 등록 = h3(덮기 0) ④없는 파일 = REJECT · 링크 0 ⑤`--cmd 'echo hi'` → 링크 대상 실행 시 hi ⑥`HIL_CLIP=0` = pbcopy 호출 0 ⑦목록에 사라진 대상 표시 ⑧`$HOME` 아래 새 파일 0(임시 HOME 으로 확인) ⑨실 /tmp 기준 출력 줄 `! bash /tmp/h<N>` 길이 ≤ 18자.
   - 출력처 3곳: 각 기존 시험(`tests/scripts/test_nano_spawn_rollback.py` 단독 모드 · nano-close·wt-sweep 기존 시험)에 `HIL_DIR`=임시 폴더 · 안내 줄에 `! bash` + `/h` 포함 · `ft-hil.sh` 실패 스텁 = 기존 문구 + WARN.
   - 기존 시험 전부 PASS.

커밋은 자기 브랜치, **push 금지**. **금지**: 계획 파일 생성 로직·검사 조건 변경 · 자동 실행 · 홈(`~/`) 아래 파일·링크 생성 · 실 /tmp·실 클립보드·실 계획 실행 · 라이브 `.fable-team/bin` 직접 수정 · `ft-op-token.sh` 클립보드 경로 변경.

## 완료 조건 (닫힘 판정 기준 — ops 수락 판정문)
- `bash tests/harness/test_hil.sh` rc=0 · 출력처 3곳 관련 기존 시험 rc=0 · `bash -n` 새·바뀐 셸 · 킷 두 벌 `cmp` 동일 · `ft-hil.sh` 100줄 이하 · 바뀐 세 파일 순증 각 6줄 이하.
- 카드 증거 줄 형식(필수 · 시험 칸은 명령 1개 · 없으면 반송): `세트: <40hex> · 시험: bash tests/harness/test_hil.sh rc=0 · 이슈: 0`.
- 랜딩 뒤 master 집행(카드 밖): 라이브 `.fable-team/bin/` 세 파일 `.bak-r83-<날짜>` → cp → cmp + `ft-hil.sh` 새 복사 · 대기 중인 `.sh.hil` 은 `ft-hil.sh --add` 로 `/tmp/h<N>` 등록(손 링크 `/tmp/h1` 은 같은 대상이면 재사용됨) → planner 경유 오빠께 `! bash /tmp/h<N>` 1줄 · 다른 머신은 RELEASE 발행 후 각 머신 install.
- 안내 규칙 1줄(master 가 `main-team-governance.md` §7 에 추가 — 카드 밖): 「사람에게 줄 명령은 `! bash /tmp/h<번호>` 코드블록 한 줄만 · 계획 경로 직접 기재 금지 · 손 계획은 `ft-hil.sh --add <경로>` · 홈(~/)에 진입점 생성 금지」.
- 진행→완성 이동은 `ft-index-move.sh <파일> 완성 --da <판정문#§N>`.

## 상태
- base_sha: ddcf90affcbe518650b182973f6affe24e588092 (spawn 2026-10-10)
대기 — 확정(#1184 · 판정 852) · master spawn 대기
- 슬랙: C0C6MJGRR89 1791603505.082469

## 결과
(닫을 때 증거 줄)
- 2026-10-10 12:42 — 대기→진행 · 좌석 byz-harness-nano-r83-hil-short-command#0
세트: 3ab02fe6a461b1ce1bc3d677ea63a766b5bedd76 · 시험: bash tests/harness/test_hil.sh rc=0 · 이슈: 0
- 2026-10-10 — 나노 완료(3ab02fe6a4[feature]) · 마스터 재실행 test_hil ALL PASS · pytest rollback 25 passed · 홈 새 파일 0 · /tmp/h1·h2 불변 · 판정 856 재승인(오빠 · /tmp 만) · 랜딩은 push 승인 뒤
