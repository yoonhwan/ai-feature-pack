# 인덱스: 나노 닫기 cherry·증거 게이트가 원격 추적 ref(origin/<feat>)를 받게 + 닫기 직전 그 ref fetch (R22)
<!-- ledger: design/teams/harness/GOAL-harness.md -->

## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
하네스 GOAL 표 / 닫는 증거(정본 복붙): 「REQUEST-LEDGER.md 행 + Issue 「채택/보류 + 오빠 값」 코멘트 + 반영 sha」.
골의 축: 6-b(오케 개선요청 접수·협의) + 원문 7(팀별로 쪼개 동시에 — main 을 base 로 쓰는 팀 나노가 표준 닫기를 못 하면 매 닫기가 사람 손으로 돌아온다). 핵심 한 줄: 원장 R22 — CFO 실측(master#10 #60193): `FT_NANO_FEAT=origin/main` 은 cherry 게이트가 「브랜치 없음(refs/heads/)」 REJECT, `main` 은 리포 루트의 로컬 main 이 약 18k 커밋 뒤라 대조가 끝나지 않는다. 로컬 main 은 루트 체크아웃이라 ff 하지 않는다(master 판단 유지).

## 배경 (한 단락 — 나노워커가 이 파일만 읽고 착수 가능해야 함)
`ft-nano-close.sh` 는 base 줄기 `_FEAT`(FT_NANO_FEAT · 341–343행)를 세 곳에 넘긴다. ①⑤ cherry 게이트 `ft-nano-cherry-gate.sh <feat> <nano>`(426행) — 이 스크립트 27행이 두 ref 를 `refs/heads/$r` 로만 확인해서 `origin/main` 을 거부한다. ②⑥ 증거 검사 `ft-nano-evidence-check.sh --feat`(393·402행) — 문서 전용 경로 38행이 같은 `refs/heads/` 검사를 한다. ③`ft-nano-freshness.sh --root`(430행) — 이미 `rev-parse --verify` 라 원격 ref 를 받는다(수정 0). 원격 추적 ref 를 쓰면 «언제 fetch 됐나»가 새 위험이다. 오래된 origin/main 이면 이미 랜딩된 나노 커밋이 «+» 로 보여 REJECT 쪽으로 틀린다(거짓 통과는 아니다). 그래도 닫기 직전에 그 ref 하나만 fetch 하고, 실패하면 REJECT 한다(#0 RULE — 조용한 옛값 사용 금지). `main` → `origin/main` 같은 자동 치환은 하지 않는다. 원격을 쓰려면 값을 `origin/<브랜치>` 로 «명시»해야 한다.

## 사전검증
- 소환: 아니오
- 면제: 수정은 ref 확인 조건 2곳 + fetch 1블록이다. 동작 변화는 «refs/heads 에 없고 refs/remotes 에 있는 값» 한 경우에만 생긴다(기존 값 동작 무변화). 되돌림 1커밋 revert. 최종 DA 는 완성 이동 때 1회. — arch 서명 byz-harness-arch-claude#7

## 조사 근거
- `scripts/fable-team-bin/ft-nano-cherry-gate.sh:27` `rev-parse --verify -q "refs/heads/$r"` — feat·nano 둘 다 로컬 브랜치만 받음.
- `scripts/fable-team-bin/ft-nano-evidence-check.sh:38` 문서 전용 경로의 `refs/heads/$FEAT` 검사.
- `scripts/fable-team-bin/ft-nano-close.sh:341` `_FEAT` 결정(341–343행) · 426행 cherry 호출 · 430행 freshness(이미 rev-parse).
- `scripts/fable-team-bin/ft-nano-freshness.sh:29` `rev-parse --verify -q "$ROOT_BRANCH"` — 원격 ref 수용(참고 · 수정 0).

## 구현 범위 (이 넷만 — 닫힌 목록 · 추적본 + 키트 사본 같은 바이트)
1. `scripts/fable-team-bin/ft-nano-cherry-gate.sh` 27행: «feat» 쪽만 `refs/heads/$FEAT` 또는 `refs/remotes/$FEAT` 둘 중 하나가 있으면 통과로 바꾼다. 거부 문구는 `브랜치 없음: $r (refs/heads/ · refs/remotes/)`. «nano» 쪽은 `refs/heads/` 그대로(좌석 브랜치는 로컬이어야 한다). 이후 git 명령은 이미 이름으로 부르므로 변경 0.
2. `scripts/fable-team-bin/ft-nano-evidence-check.sh` 38행: 같은 규칙(heads 또는 remotes) · 문구도 같은 꼴.
3. `scripts/fable-team-bin/ft-nano-close.sh`: 343행 뒤에 블록 추가 — `_FEAT` 가 `refs/heads/$_FEAT` 로는 없고 `refs/remotes/$_FEAT` 로 있으면(= `origin/<b>` 형태) `git -C "$ROOT" fetch -q <원격> <b>` 1회. 원격·브랜치는 첫 `/` 기준으로 나눈다. 실패하면 `bad+=("⑤ feat 원격 ref fetch 실패: $_FEAT — 옛값으로 대조하지 않는다")` 로 REJECT. 성공하면 `INFO feat=$_FEAT @ <short sha> (fetch 완료)` 1줄을 찍는다. 로컬 브랜치 값이면 fetch 0(기존 동작 그대로).
4. 시험 `tests/harness/test_nano_feat_remote_ref.sh` 신규 — mktemp 리포 2개(bare 원격 + 클론)만 쓰고 실제 리포·네트워크 0.
   - cherry-gate 에 feat=`origin/main`(클론에 로컬 main 없음): 랜딩된 나노 → exit 0 · 미랜딩 코드 커밋 나노 → exit 1(「+」 사유).
   - feat=`nope/main` → exit 1 + 문구에 `refs/remotes/`.
   - nano 를 원격 ref 로 주면 → exit 1(nano 는 heads 만).
   - evidence-check 문서 전용 경로에 `--feat origin/main` → 통과.
   - 기존 `tests/harness/test_nano_close_named_wt.sh`·`tests/harness/test_nano_team_env.sh`·`tests/harness/test_kit_bin_sync.sh` 무변화 rc=0 · cherry 게이트 기존 pytest `tests/scripts/test_nano_cherry_gate_script.py`·`tests/scripts/test_nano_cherry_gate_modes.py`·`tests/scripts/test_nano_close_cherry_override.py` 도 rc=0(`timeout 300 uv run pytest <3파일> -q` · REDIS_PORT=9 · LOCAL_VLLM_BASE_URL=http://127.0.0.1:9/v1).
   - close 의 fetch 블록은 시험 리포에서 원격 브랜치를 지운 뒤 닫기 → REJECT 문구 「fetch 실패」. 기존 close 시험 틀이 그 경로까지 가기 어려우면, 그 블록만 함수로 떼어 직접 호출해도 된다(함수명 `_fetch_remote_feat`).

커밋은 자기 브랜치, **push 금지**. **금지**: `main`→`origin/main` 자동 치환 · 로컬 main ff·reset · fetch 실패 시 옛 ref 로 계속(조용한 폴백) · 라이브 FT_BIN·팀 env 파일 쓰기(env 값 변경은 master 집행 · 아래).

## 완료 조건 (닫힘 판정 기준 — ops 수락 판정문)
- `bash tests/harness/test_nano_feat_remote_ref.sh` rc=0 · 위 기존 시험 전부 rc=0 · 세 파일 두 사본 `bash -n` OK · `cmp` 동일.
- RESULT 에 cherry-gate 실제 출력 2줄(origin/main 통과 · nope/main 거부) 복붙.
- 카드 증거 줄 형식(필수 · 시험 칸은 명령 1개 · 없으면 반송): `세트: <40hex> · 시험: bash tests/harness/test_nano_feat_remote_ref.sh rc=0 · 이슈: 0`.
- 랜딩 뒤 master 집행(카드 밖): `bin-cfo/cfo-env.sh` 의 `FT_NANO_FEAT=main` → `origin/main`(R18 에서 arch 가 정한 값을 바로잡음) · `bin-harness/harness-env.sh` 의 `FT_NANO_FEAT=feat/slack-inbound-820`(옛 트랙 값) → `origin/main` 검토 · 라이브 RT 3파일 단독 cp.
- 진행→완성 이동은 `ft-index-move.sh <파일> 완성 --da <판정문#§N>`.

## 상태
- base_sha: 0b5c2a5e9d244cae85e6217e27c079e519c761e9 (spawn 2026-10-07)
- base: 최신 origin/main.
- 2026-10-07 — 대기/ 생성 (byz-harness-arch-claude#7 · 원장 R22 · master#10 #60193).
- 정본 영향 없음: 하네스 나노 닫기 스크립트·시험만 — docs/architect 제품 정본 변경 없음
- 2026-10-07 21:24 — 대기→진행 · 좌석 byz-harness-nano-r22-nano-feat-remote-ref#0
- 2026-10-07 — 증거(나노 byz-harness-nano-r22-nano-feat-remote-ref#0 · 골 축 6-b·원문 7 원장 R22 · arch#7 재현):
  - 변경: ft-nano-cherry-gate.sh(feat 만 heads·remotes 허용 · nano 는 heads 그대로) · ft-nano-close.sh(`_fetch_remote_feat` — origin/<b> 면 그 ref 1개 fetch · 실패면 bad 1건 REJECT · 로컬 값이면 fetch 0) · ft-nano-evidence-check.sh(문서 전용 경로 같은 규칙) — 추적본=키트 cmp 동일 · tests/harness/test_nano_feat_remote_ref.sh 신규.
- 세트: c0165cbc35167477350b5d8f15c2f17ff60f0f55 · 시험: bash tests/harness/test_nano_feat_remote_ref.sh rc=0 · 이슈: 0
- 추가 시험: test_kit_bin_sync·test_nano_team_env·test_nano_close_named_wt ALL PASS · cherry pytest 3파일(tests/scripts/test_nano_cherry_gate_script.py 외 2) 39 passed · 세 스크립트 bash -n OK
- 정본 영향: 하네스 나노 닫기 스크립트 3개(추적본·키트)·시험만 — docs/architect 제품 정본 변경 없음 · 팀 env 값(cfo=origin/main · harness=ops/main-base)과 라이브 RT 3파일 cp 는 master 집행.
- 2026-10-07 21:28 — 진행→완성 · DA design/teams/harness/OPS-VERDICTS-20261006.md#§37
