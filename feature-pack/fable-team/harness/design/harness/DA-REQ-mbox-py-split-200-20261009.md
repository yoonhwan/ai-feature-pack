# DA 요청 — mbox-py-split-200 최종 DA(완성 이동 · 1회 · bounded 10분 + 정정 10분 · 2 HOLD 면 리뷰 종료 → arch 서명) (arch#21 · 2026-10-09)

## 골 원문 (3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.
골의 축: C(통신 큐 본체를 200줄 규칙 안으로).

## 고정 대상
- 커밋 `427ebdddbc7d29af76c7da0b1fab0dc579ba987f`(브랜치 `nano/mbox-py-split-200` · base origin/main `9b774bef56` · 2커밋: `5626a173d0` [structure] · `427ebdddbc` [test]) · `tools/comm-canonical/mbox.py` 637→125 + 새 `mbox_conf.py` 41 · `mbox_store.py` 186 · `mbox_guard.py` 146 · `mbox_ops.py` 167 · `check-drift.sh` +4행 · 시험 3개(`test_mbox_inbox_notify_reply_rate.sh` · `test_mbox_reply_exempt_cap.sh` · `test_inbox.sh`).
- 카드 `design/harness/indices/진행/mbox-py-split-200.md`(배경에 함정 2개) · 처방 도구 `design/harness/evidence/mbox-py-split-200/`(ops/main-base).

## arch#21 독립 재현 (427ebdddbc 아카이브)
- 결정성: origin/main `mbox.py` 에 처방 도구를 다시 돌린 5파일 == 커밋 5파일(cmp 5/5) · `py_compile` 5개 OK.
- 시험: notify_reply_rate ALL PASS · inbox fail=0 · exempt_cap ALL PASS(변이 행 포함) · `test_mbox_sent_log.py --noconftest` 6 passed(분리 전도 6).
- 분리 전후 12시나리오(send · fan-out 가드 rc=3 ×2 · 이름 거부 · relay · peek · recv · recv --all · 빈 recv · 회신 인용 · 모르는 명령 · 인자 없음) + 우편함 파일 목록·로그 키·가드 키 diff = 시나리오 제목의 임시 경로 1줄뿐.
- 라이브 꼴 링크 배치(`root/.fable-team/comm/mbox.py` → `root/.claude/fable-team/bin/mbox.py` · 모듈은 bin 에만): 옛·새 모두 send rc0 · recv 1건 · 우편함 = `root/.fable-team/comm` · bin 에 엉뚱한 우편함 0 · 실제 경로로 직접 실행 = `NO_MAILBOX_ROOT` rc2(옛 판도 같음).
- 모듈 없는 폴더의 진입 = `ModuleNotFoundError` rc1.

## 질문 (bounded · 새 요구 금지)
- **Q1 동작 동일**: 옮긴 함수가 전역(`CANON`·`_ROOT`·`_SEQCTR`·`SEQ_FLOOR`·`_GUARD`)을 «호출 시점»에 자기 모듈에서 읽는데, 진입의 묶기(import 직후 대입)가 모든 실행 경로(명령행 · `import mbox` 하는 시험·도구)에서 함수 호출 «전»에 끝나는가 · import 시점에 묶이지 않은 값을 쓰는 모듈 최상위 코드가 남았는가 · `from mbox_conf import *` 가 옛 단일 이름공간과 다른 이름을 가리키는 곳이 있는가.
- **Q2 정본 루트**: 루트·CANON 계산이 진입에만 있어 링크 설치(`comm/` 링크 → `.claude/fable-team/bin` 실파일)에서 우편함 자리가 옛과 같은가 · 모듈을 다른 폴더의 같은 이름 파일로 잘못 import 할 경로가 있는가(`sys.path[0]` = 실제 폴더).
- **Q3 시험의 뜻**: 시험 수정(바꿔치기 대상 `mbox_ops._reply_exempt`·`mbox_guard.time` · 모듈 전부 복사 · 대상 글자가 든 모듈 하나만 변이)이 원래 검사하던 것을 그대로 검사하는가(약해진 단언 0).
- 범위 밖: 라이브 설치 절차(master · 카드 «랜딩 뒤 라이브 설치» 절) · check-drift 의 옛 경로 행 · mbox.sh.

## 판정문
`design/harness/DA-mbox-py-split-200-20261009.md` — 실행 헤더 `model:`/`provider:` 두 줄 · Q 별 APPROVE/HOLD + 근거 줄 · 끝 줄 APPROVE 또는 HOLD.

## r2 요청 (arch#21 · 2026-10-09 · Q2 만 · bounded 10분 + 정정 10분 · 이번이 두 번째 · HOLD 면 리뷰 종료 → arch 서명)
- 고정 대상: 커밋 `a82e30df172acb795f8b0d5dfc4370c484250e73`(r1 `427ebdddbc` 위 2커밋: `e4fec82c2f` [structure] 진입 `mbox.py` 42행 앞 `import os, sys; sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))` 1줄 · `a82e30df17` [test] 새 `tests/harness/test_mbox_py_link_import.sh` 19줄). 루트·CANON 계산(`abspath(__file__)`) 불변.
- arch#21 독립 재현(a82e30df17 아카이브): 결정성 cmp 5/5(갱신 도구 `80e3173278`) · fixture ALL PASS(CLI 링크 send·recv · comm 폴더 `import mbox` rc0 + CANON = 링크 위치 realpath · bin 에 엉뚱한 우편함 0) · fixture = 도구 폴더 파일 cmp 동일 · 추가 줄을 뺀 변이 = fixture 2 FAIL · 분리 전 옛 판도 fixture ALL PASS · 기존 시험 4종 · 12시나리오 diff 임시경로 1줄 · 링크 왕복 · 모듈 없는 폴더 진입 = ModuleNotFoundError rc1.
- Q2(r2): r1 반례(링크 폴더를 sys.path 에 넣고 import)와 같은 부류 — 진입 `mbox.py` 를 링크·복사·다른 경로로 부르거나 import 할 때 모듈을 못 찾거나 «다른 폴더의 같은 이름 모듈»을 집거나 우편함 자리가 옛과 달라지는 꼴이 남는가. 새 요구 금지 · Q1·Q3 재심 0.
- 판정문: 같은 파일 `design/harness/DA-mbox-py-split-200-20261009.md` 끝에 `# mbox-py-split-200 최종 DA — r2` 절(헤더 `model:`/`provider:` 두 줄 · Q2 APPROVE/HOLD + 근거 · 끝 줄 APPROVE 또는 HOLD).
