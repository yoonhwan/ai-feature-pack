# 인덱스: 나노 닫기 — 좌석 워크트리 후보 접두를 팀 env(FT_NANO_WT_PREFIX)로 (v65- 고정 제거)
<!-- ledger: design/harness/GOAL-harness.md -->

## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
하네스 GOAL 표 / 닫는 증거(정본 복붙): 「REQUEST-LEDGER.md 행 + Issue 「채택/보류 + 오빠 값」 코멘트 + 반영 sha」.
골의 축: 6-b · 원문 5(팀 독립 배분). 핵심 한 줄: 원장 R14 후속 — 신설 feature 팀(오빠 10-07 「신설 · 종합안 그대로」) 나노를 닫으려면 close 의 좌석 워크트리 후보가 팀 접두를 따라야 한다(kk 팀이 같은 결함으로 4석을 못 닫음 · CLOSEOUT-kk §5). 출처: arch#6 R14 안 · master#9 #59484.

## 배경 (한 단락 — 나노워커가 이 파일만 읽고 착수 가능해야 함)
대상은 추적본 `scripts/fable-team-bin/ft-nano-close.sh` + 키트 `scripts/harness-install/fable-team/bin/ft-nano-close.sh`(같은 바이트 · test_kit_bin_sync). base = nano-close-named-wt(0103bccf3e) 랜딩판. spawn 은 이미 팀 접두를 쓴다 — ft-nano-spawn.sh 123행 `WTDIR="$ROOT/.worktrees/${FT_NANO_WT_PREFIX:-v65-}$SLUG"`. 그런데 close 의 좌석 워크트리 해석 `_resolve_seat_wt`(0103bccf3e 기준 269행)는 `[[ "$rel" =~ ^v65-${_KEY}(-r[0-9]+)?$ ]]` 로 v65- 를 고정해, feature-<키>·harness-<키>·kk-<키> 워크트리는 «pane cwd 가 살아 있을 때»(①)만 찾고 세션이 죽었거나 cwd 가 다른 곳이면 ②에서 0 후보 → ⑥ REJECT 한다. 같은 v65- 문구가 274행(에러 문구)·393행(⑥ 에러 문구)·59·248·250행(주석)에 있다. 팀 env 는 close 30~36행에서 좌석명 byz-<팀>-nano- 로 자동 source 되고 FT_NANO_WT_PREFIX 를 준다(harness=harness- · planner=planner- · kk=kk- · feature=feature-).

## 구현 범위 (이 둘만 — 닫힌 목록)
1. `scripts/fable-team-bin/ft-nano-close.sh`(+ 키트 사본 같은 바이트): 269행 정규식의 `v65-` 를 `${FT_NANO_WT_PREFIX:-v65-}` 값으로(정규식 안전 — 접두는 소문자·숫자·'-' 만이라는 것을 한 줄로 확인하고 아니면 REJECT · 추측 0). 274·393행 에러 문구와 59·248·250행 주석의 「v65-<key>」 를 「<접두><key>」 로. 기본값(env 없음 = 옛 ft-v65-temp-* 좌석) 동작·출력은 바이트 그대로.
2. `tests/harness/test_nano_team_env.sh`에 사례 추가: FT_NANO_WT_PREFIX=feature- 팀 좌석 · 세션 없음(ABSENT) · 워크트리 .worktrees/feature-<키> + 브랜치 nano/<키> → ⑥ 후보 1개로 해석(REJECT 아님) · 같은 조건에 워크트리가 v65-<키> 이름이면 0 후보(다른 팀 워크트리를 집지 않음) · -r2 재착수 이름 feature-<키>-r2 해석 · env 없는 옛 좌석은 지금처럼 v65-<키>.
커밋은 자기 브랜치, **push 금지**. **금지**: 라이브 FT_BIN 쓰기 · ①pane cwd 경로·--shared-wt·--wt/--branch 모드 동작 변경 · spawn 변경.

## 완료 조건 (닫힘 판정 기준 — ops 수락 판정문)
- `bash tests/harness/test_nano_team_env.sh` rc=0 · `bash tests/harness/test_nano_close_named_wt.sh` rc=0 · `bash tests/harness/test_kit_bin_sync.sh` 의 ft-nano-close 행 OK(다른 행의 기존 실패는 base 와 같으면 무관) · 두 사본 `bash -n` OK · `cmp` 동일.
- ★카드 증거 줄 필수★: 이 파일 «상태» 절에 `증거: 커밋 <sha> · 시험 rc(파일별) · cmp 동일` 1줄 — 없으면 닫지 않는다(앞 카드 2장이 이 줄 없이 올라와 반송됨).
- 진행→완성 이동은 `ft-index-move.sh <파일> 완성 --da <판정문#§N>`.

## 상태
- base: nano-close-named-wt(0103bccf3e) 랜딩 뒤 최신 origin/main.
- 2026-10-07 — 대기/ 생성 (byz-harness-arch-claude#6 · 원장 R14 후속 · master#9 #59484).
- 정본 영향 없음: 하네스 나노 도구·시험만 — docs/architect 제품 정본 변경 없음
