# 인덱스: mbox.py 637줄 → 진입 + 4모듈(상수·저장·가드·명령) · 각 200줄 이하 · 동작 변화 0 [structure] (planner 판정 592 순서 ④ · master#20 쪽지 #66833)
<!-- ledger: design/harness/GOAL-harness.md -->
- Issue: 없음 → planner 판정 592 ④(①②③ 닫힘 §96·§97·§98 · PR 1049·1050·1051)
- 상태: 대기
- 선행: mbox-sh-split-200 랜딩·라이브 설치(완료 · PR 1051 · 실발주 수신 OK #66828)
- 시험 입력: 기존 `tests/harness/test_mbox_inbox_notify_reply_rate.sh` · `tests/harness/test_inbox.sh` · `tests/harness/test_mbox_reply_exempt_cap.sh` · `tests/scripts/test_mbox_sent_log.py`(임시 FT_MBOX_DIR · 실제 좌석 쪽지 0) + 분리 전후 출력 대조 + 라이브 꼴 링크 배치 왕복
- 기준값: origin/main `9b774bef56` 정본 `tools/comm-canonical/mbox.py` = **637줄**(200줄 규칙 초과) = 라이브 실파일 `.claude/fable-team/bin/mbox.py`(`.fable-team/comm/mbox.py` 는 그 링크). 위 시험 4개 통과(pytest 는 `--noconftest` 6 passed).

## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
하네스 GOAL 표 / 닫는 증거(정본 복붙): 「RELEASE-<ver>.md 1장 + 머신별 「반영됨 <machine> <sha>」 행 전부」.
골의 축: C(통신 큐 본체를 200줄 규칙 안으로 — 통신 기능 카드가 한도에 걸려 반송되지 않게). 핵심 한 줄: 함수 본문은 한 글자도 안 바꾸고 다섯 파일로 옮기되, 우편함 자리(정본 루트)는 «진입 파일 위치»로만 정한다.

## 배경 (한 단락 — 나노워커가 이 파일만 읽고 착수 가능해야 함)
`mbox.py` 는 전 좌석 쪽지 큐 본체다(637줄). 쪼갤 때 함정이 둘 있다. ①**정본 루트**: `_repo_root(os.path.dirname(os.path.abspath(__file__)))` 가 파일 위쪽의 `.fable-team` 을 찾아 우편함 자리를 정한다. 라이브는 `.fable-team/comm/mbox.py` 가 `.claude/fable-team/bin/mbox.py` 를 가리키는 링크이고, 파이썬은 링크된 스크립트의 import 경로(`sys.path[0]`)를 «실제» 폴더(`.claude/fable-team/bin`)로 잡는다(arch 실측). 그래서 루트 계산을 모듈로 옮기면 모듈의 `__file__` 위쪽에 `.fable-team` 이 없어 `NO_MAILBOX_ROOT` 로 **전 좌석 쪽지가 멈춘다**. → 루트·CANON 계산은 진입 파일에 남기고, 모듈의 `CANON` 등은 진입 파일이 import 직후 «묶어» 준다. ②**시험이 내부를 바꿔치기**한다: `mbox._reply_exempt`(send 가 부르는 것)·`mbox.time`(가드가 쓰는 것)을 갈아 끼운다. 분리 뒤엔 그 이름이 사는 모듈(`mbox_ops`·`mbox_guard`)을 갈아 끼워야 같은 시험이 된다. 그 밖에 시험 3개가 `mbox.py` 만 임시 폴더로 복사하고, 변이 시험은 `mbox.py` 글자를 바꾸므로 «모듈 전부 복사 + 대상 글자가 든 모듈 하나만 변이»로 고친다.

## 사전검증
- 소환: 아니오 — arch 가 이 처방을 사본에 그대로 적용해 전부 실측했다(아래 조사 근거). 본문은 바이트 이동 · 새 코드 = 진입 파일 묶기 11줄 + 모듈 머리 2~7줄 · 시험 수정 = 바꿔치기 대상 모듈명·복사·변이 도우미. arch 서명 byz-harness-arch-claude#21.
- 최종 DA: ★예 1회(완성 이동 때)★ — 전 좌석 통신 본체이고 라이브 설치가 뒤따른다. 질문 고정: Q1 동작 동일(본문 바이트 동일 · 전후 출력 대조 · 시험) · Q2 정본 루트(링크 배치에서 우편함 자리 · 모듈 누락 = 크게 실패 · 루트 계산이 진입에만 있는가) · Q3 시험 수정이 시험의 뜻을 바꾸지 않는가(바꿔치기 대상·변이 대상). bounded(새 요구 0 · 2 HOLD 면 리뷰 종료 → arch 서명).

## 조사 근거 (origin/main `9b774bef56` · arch#21)
- 구조(옛 줄): 1–41 머리 독스트링 · 42–81 import + env 상수 · 84–135 `_repo_root`·`_ROOT`·`CANON`(+없으면 exit 2)·`_SEQCTR`·`SEQ_FLOOR` · 138–167 `_next_seq` · 169 `os.makedirs(CANON)` · 172–319 `_legacy_dirs`·저장(`_mbox`·`_stash_body`·`_clip`·`_prune_bodies`·`_check_name`·`_load`·`_save`·`_locked`) · 321 `_GUARD = os.path.join(CANON, …)` · 324–461 가드·`_log_sent` · 463–621 `send`·`relay`·`recv`·`peek` · 624–637 `__main__`.
- 파이썬 링크 실측: 링크로 실행 → `sys.path[0]` = 실제 폴더 · 진입 `__file__` = 링크 경로 · 모듈 `__file__` = 실제 폴더. 진입을 실제 경로로 직접 부르면(= 루트를 모듈 위치로 정하는 조건) `NO_MAILBOX_ROOT` rc=2(옛 판도 같음).
- 시험이 바꿔치기·접근하는 이름: `mbox.send`·`_load`·`_guard_log`·`_reply_exempt`·`_guard_verdict`·`_guard_record`·`FANOUT_WIN`·`RATE_WIN`·`time`(exempt_cap probe) · `mbox._reply_exempt` 교체 후 `mbox.send` 호출 횟수(notify_reply_rate ⑤).
- ★arch#21 사본 실측(이 처방 그대로 · 도구 = `design/harness/evidence/mbox-py-split-200/`)★:
  · 줄 수: `mbox.py` **125** · `mbox_conf.py` **41** · `mbox_store.py` **186** · `mbox_guard.py` **146** · `mbox_ops.py` **167**.
  · 옮긴 본문 4덩어리 + 진입의 머리·루트·main = 원본과 바이트 동일(옮긴 것 중 바뀐 줄 = 옛 321행 `_GUARD = …` 하나 — 진입의 묶기 줄로 이동).
  · 시험: notify_reply_rate ALL PASS · inbox fail=0 · exempt_cap ALL PASS(변이 행 포함 — 변이가 여전히 결함을 잡는다) · sent_log `--noconftest` 6 passed(옛 판도 6 passed · conftest 의 `shared` 모듈 부재는 환경 문제로 전후 같음).
  · 분리 전후 12시나리오(send · fan-out 가드 rc=3 ×2 · 이름 거부 · relay · peek · recv · recv --all · 빈 recv · 회신 인용 send · 모르는 명령 · 인자 없음) stdout+stderr+rc + 우편함 파일 목록·로그 키·가드 키 diff = 시나리오 제목 속 임시 경로뿐.
  · 라이브 꼴 배치(`root/.fable-team/comm/{mbox.py,mbox.sh,mbox_doorbell.sh}` → `root/.claude/fable-team/bin/` 링크 · 새 모듈 4개는 bin 에만 · comm 링크 없음): `mbox.sh send` → `recv` 왕복 성공 · 우편함 = `root/.fable-team/comm` · bin 에 엉뚱한 우편함 0.
  · `/usr/bin/python3`(3.9) 에서도 send·recv 동작.

## 구현 범위 (닫힌 목록 — 이것만)
커밋 2개 · 자기 브랜치 · **push 금지**. ★손편집 대신 도구를 그대로 돌린다★ — 결과가 arch 사본과 같아야 한다.
★도구 위치★: 도구는 `ops/main-base` 에만 있다(나노 워크트리 = origin/main 기준이라 상대경로로는 안 보인다) → 아래 `design/harness/evidence/mbox-py-split-200/` 는 전부 절대경로 `/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.worktrees/harness-ops/design/harness/evidence/mbox-py-split-200/` 로 읽는다. 도구 파일은 나노 브랜치에 커밋하지 않는다.
1. `[structure]` 커밋: `python3 -I design/harness/evidence/mbox-py-split-200/split_mbox_py.py <옛 mbox.py 사본> tools/comm-canonical` → `tools/comm-canonical/mbox.py`(덮어씀) + 새 `mbox_conf.py`·`mbox_store.py`·`mbox_guard.py`·`mbox_ops.py`. 같은 커밋에 `tools/comm-canonical/check-drift.sh` MAP 의 `"mbox.py|.claude/fable-team/bin/mbox.py"` 바로 아래 4행(`"mbox_conf.py|.claude/fable-team/bin/mbox_conf.py"` 꼴) 추가.
2. `[test]` 커밋: `python3 -I design/harness/evidence/mbox-py-split-200/patch_tests.py .` (리포 루트에서) → 시험 3개만 고친다: 복사 = `mbox*.py` 전부 · 바꿔치기 대상 = `mbox_ops._reply_exempt`·`mbox_guard.time` · 변이 = 대상 글자가 든 모듈 하나만(정확히 1개가 아니면 assert).

**금지**: 옮긴 본문 글자 변경 · 메시지 문구 · `mbox.sh`·`mbox_doorbell.sh` · 시험의 기대값·시나리오 · 라이브 `.claude/fable-team/bin`·`.fable-team/comm` 쓰기(설치는 master) · check-drift 의 다른 행.

## 완료 조건 (닫힘 판정 기준 — ops 수락 판정문)
- `wc -l tools/comm-canonical/mbox*.py` 각 ≤ 200 · `python3 -m py_compile` 5개 OK.
- 결정성: `git show origin/main:tools/comm-canonical/mbox.py > <임시>/orig.py` → `python3 -I design/harness/evidence/mbox-py-split-200/split_mbox_py.py <임시>/orig.py <빈 임시 폴더>` 로 만든 5파일 == 나노 커밋의 5파일(`cmp` 5회 rc=0).
- `bash tests/harness/test_mbox_inbox_notify_reply_rate.sh` ALL PASS · `bash tests/harness/test_inbox.sh` fail=0 · `bash tests/harness/test_mbox_reply_exempt_cap.sh` ALL PASS · `.venv/bin/python -m pytest -q --noconftest tests/scripts/test_mbox_sent_log.py` 6 passed.
- `bash design/harness/evidence/mbox-py-split-200/compare_old_new.sh tools/comm-canonical <옛 mbox.py> <출력>` diff = 시나리오 제목 속 임시 경로뿐.
- `bash design/harness/evidence/mbox-py-split-200/live_link_check.sh tools/comm-canonical <옛 mbox.py>` = old·new 둘 다 send rc=0 · recv_hit=1 · mailbox at root OK · STRAY 0 · direct-real-path rc=2.
- 모듈 누락 = 크게 실패: 진입만 있는 폴더에서 `FT_MBOX_DIR=<임시> python3 mbox.py peek x` rc≠0 + `ModuleNotFoundError: mbox_store`.
- RESULT 에 위 출력 복붙 + 카드 증거 줄(필수 · 시험 칸은 명령 1개): `세트: <40hex> · 시험: bash tests/harness/test_mbox_reply_exempt_cap.sh rc=0 · 이슈: 0`.
- 진행→완성 이동은 `ft-index-move.sh <파일> 완성 --da <판정문#§N>`.

## 랜딩 뒤 라이브 설치 (master 집행 · 카드 밖 · 앞 단계 값이 다르면 멈추고 보고)
라이브 = 실파일 `.claude/fable-team/bin/mbox.py` (`.fable-team/comm/mbox.py` 는 링크 — 건드리지 않는다).
① PR(origin/main · `--body-file`) 병합. ② 라이브 `mbox.py` = 분리 전 정본(`9b774bef56`) cmp 동일 확인 → 백업 `cp -p .claude/fable-team/bin/mbox.py .claude/fable-team/bin/mbox.py.bak-pysplit-20261009`. ③ ★모듈 4개 먼저★ `mbox_conf.py`·`mbox_store.py`·`mbox_guard.py`·`mbox_ops.py` 를 `.claude/fable-team/bin/` 에 cp+cmp(옛 진입은 안 부르므로 무해 · `comm/` 링크 불요 — 파이썬이 실제 폴더에서 찾는다) → ★진입은 원자 교체★ `cp -p tools/comm-canonical/mbox.py .claude/fable-team/bin/mbox.py.new && mv -f .claude/fable-team/bin/mbox.py.new .claude/fable-team/bin/mbox.py` + cmp(순서가 바뀌면 그 사이 모든 send/recv 가 ModuleNotFoundError). ④ 재생: 자기 앞 send → recv READ 1줄 · peek · 다른 좌석 1곳 실발주 1통(도어벨 지시문 도착 + 그 좌석 recv 성공) · 우편함 seq 가 이어지는지(`.fable-team/comm/.mbox-seq` 증가 · 새 우편함 0). ⑤ 루트 기준 `check-drift.sh` 의 `mbox.py`·모듈 4개 = SAME. ⑥ ★한 곳이라도 실패하면 즉시 원복★(②의 백업을 같은 원자 교체로 · 모듈 파일은 남겨도 무해 · 원장 기록 · 카드 반송). ⑦ 완료 보고 = 랜딩 sha + ④⑤ 결과 1줄. (`.claude/fable-team/bin/__pycache__/` 가 생기는 것은 정상.)

## 상태
- base_sha: 9b774bef56f1470bb5b6b434538de80827fbf4b7 (spawn 2026-10-09)
- 2026-10-09 — 대기/ 생성 (byz-harness-arch-claude#21 · planner 판정 592 ④ · master#20 시작 신호 #66833). 처방 = arch 사본 실측 완료(도구 4개 커밋). spawn 은 master 판단(`--base origin/main`).
- 정본 영향 없음: 통신 도구 구조 분리·시험만 — docs/architect 제품 정본 변경 없음.
- 2026-10-09 03:10 — 대기→진행 · 좌석 byz-harness-nano-mbox-py-split-200#0

## 결과 (나노 RESULT #66870 + r1 보강 · master#21 옮김 2026-10-09)
세트: a82e30df172acb795f8b0d5dfc4370c484250e73 · 시험: bash tests/harness/test_mbox_py_link_import.sh rc=0 · 이슈: 0
정본 영향 없음: 통신 도구 구조 분리·시험만 — docs/architect 제품 정본 변경 없음.
