# DA 요청 — bd-judge-split-200 최종 DA(완성 이동 · 1회 · bounded 10분 + 정정 10분 · 2 HOLD 면 리뷰 종료 → arch 서명) (arch#21 · 2026-10-09)

## 골 원문 (3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.
골의 축: C(전 좌석 Bash 훅을 200줄 규칙 안으로) + 원문 5(키트를 받는 머신이 두 파일을 같이 받고 홈 정합 검사가 두 파일을 다 본다).

## 고정 대상
- 커밋 `7e8b08cb7e3228c1f0cea3aaa781b173c08814ba`(브랜치 `nano/bd-judge-split-200` · base origin/main `4f5009a926` · 2커밋: `6fad9ddf84` [structure] · `7e8b08cb7e` [test]) · 5파일 +139 −127: 키트 `templates/hooks/block-destructive.sh`(209→87) · 새 `templates/hooks/block-destructive-judge.py`(123 = 머리 주석 2줄 + 옛 26–146행) · `install.sh`(홈 정합 루프 `*.py` 포함 · `.py` settings=n/a) · `tests/harness/test_block_destructive_inject.sh`(+1 판정기 cp) · `tests/harness/test_install_hook_check.sh`(+9 판정기 존재·cmp).
- 카드 `design/harness/indices/진행/bd-judge-split-200.md`(또는 대기/).

## arch#21 독립 재현 (7e8b08cb7e 아카이브 · 명령 실행 0)
- 본문 `diff <(origin/main 훅 26–146행) <(판정기 3행~)` = 0 · 훅 = arch 처방 사본과 cmp 동일 · `bash -n` · `py_compile` OK.
- test_block_destructive rc=0 blocked=74 pass=23 fail=0 · inject rc=0 block=22 pass=32 mutant=15 fail=0(둘 다 기준값과 같은 수).
- test_install_hook_check rc=1 = `block-destructive 템플릿 != 홈 파일` 1줄뿐(홈 = 분리 전 판 · 홈 설치 뒤 rc=0 예정) · 판정기 홈 cmp = SKIP(홈 파일 없음).
- install.sh: `hook block-destructive.sh home=diff settings=registered` · `hook block-destructive-judge.py home=absent settings=n/a`.
- JSON 31행(§95 재현 세트) 불일치 0 · 판정기 없음(훅만 다른 폴더로 복사) + `echo '<파괴 명령 인용>'` = 2 / 판정기 있음 = 0 → fail-closed.

## 질문 (bounded · 새 요구 금지)
- **Q1 판정 동일**: 분리 전후 `EFFECTIVE`·종료코드가 모든 입력에서 같은가 — heredoc(`python3 - "$@" <<'PYEOF'`) → 파일 실행(`python3 "$JUDGE" "$@"`) 전환에서 달라지는 것(`sys.argv[0]`·표준입력·`__file__`·인코딩·작업 폴더)이 판정에 닿는가.
- **Q2 판정기 경로**: `JUDGE="$(dirname "${BASH_SOURCE[0]}")/…"` 가 홈 등록(`bash /Users/yoonhwan/.claude/hooks/block-destructive.sh`)·키트·시험 사본에서 맞는 파일을 고르는가 · 파일 없음·실패 = `|| EFFECTIVE=$CMD`(fail-closed)로만 떨어지고 «더 느슨해지는» 경로는 0 인가 · 다른 폴더의 같은 이름 파일을 부를 수 있는가.
- **Q3 정합 검사**: install.sh·test_install_hook_check 가 두 파일을 다 보는가 · 기존 `.sh` 행 보고·합계 회귀 0 · bash 3.2(install.sh 의 `[[ … == *.py ]]`).
- 범위 밖: 홈 설치 절차(master · 카드 «랜딩 뒤 홈 설치» 절) · 심링크 설치(카드에 알고 둔 경계) · 판정 규칙 자체.

## 판정문
`design/harness/DA-bd-judge-split-200-20261009.md` — 실행 헤더 `model:`/`provider:` 두 줄 · Q 별 APPROVE/HOLD + 근거 줄 · 끝 줄 APPROVE 또는 HOLD.
