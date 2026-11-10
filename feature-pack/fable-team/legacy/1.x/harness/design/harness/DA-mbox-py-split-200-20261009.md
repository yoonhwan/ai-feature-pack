# mbox-py-split-200 최종 DA — r1
model: GPT-6 (runtime; exact variant/window size not exposed)
provider: OpenAI

대상 427ebdddbc · 기준 9b774bef56 · 고정 Q1~Q3 · 라이브 설치 제외.

- Q1 APPROVE(의존 모듈 import가 성공하는 경로) — conf는 위치 무관 상수, store/guard/ops 최상위는 함수 정의/None뿐이며 진입이 CANON/_ROOT/_SEQCTR/SEQ_FLOOR/_GUARD를 묶은 뒤 명령 분기에서 함수를 호출합니다(mbox.py:98-109, 각 모듈:1-4). import *에는 conf의 공용 상수/표준 모듈만 들어가고 private 함수는 명시 import되어 호출 전 미정의 전역을 사용하는 최상위 코드는 확인하지 못했습니다.
- Q2 HOLD — CLI 링크 실행에서만 sys.path[0]가 실파일 폴더라는 전제가 성립합니다. 임시 live 배치 comm/mbox.py→bin/mbox.py, 모듈4개 bin에만인 상태에서 `sys.path.insert(0, comm); import mbox`는 새 판만 ModuleNotFoundError(mbox_conf) rc1입니다(mbox.py:43). 동일 배치/FT_MBOX_DIR의 옛 판 import는 rc0·CANON=comm, 두 CLI peek은 모두 rc0을 독립 확인했습니다. 요청의 import mbox 시험/도구 경로도 유지하려면 실파일 모듈 디렉터리를 import 경로로 명시하되 _repo_root/CANON은 링크 진입 위치 기준을 보존하고 이 fixture를 추가해야 합니다.
- Q3 APPROVE(수정 시험 의미) — send가 실제 사용하는 ops._reply_exempt를 바꿔치기하고 guard_record가 읽는 guard.time에 가짜 시계를 주는 것으로 원래 호출횟수/창 검사가 유지됩니다. 모듈 전체 복사 및 변이 대상 1개 assert 뒤 한 번 교체는 분리된 실제 실행 함수의 변이를 시험하며 기존 단언을 삭제하지 않았습니다(test_mbox_inbox_notify_reply_rate.sh:115-126, :139-151; test_mbox_reply_exempt_cap.sh:69-76, :94-108). 다만 링크 폴더 import 회귀는 현 시험이 덮지 못한 Q2 잔여입니다.

독립 검증은 임시 두 root/bin/comm 배치의 옛/새 CLI peek 및 링크 디렉터리 import 4 probes입니다. 실제 좌석 쪽지·라이브 comm/bin 쓰기 0; arch의 시험3종/12시나리오·sentlog6 결과는 보고 증거로 구분합니다. 반송 원인 1개는 링크에서 import한 진입점의 새 부속 모듈 탐색 실패이며 수정/설치는 같은 나노/master 책임입니다.

HOLD

# mbox-py-split-200 최종 DA — r2
model: GPT-6 (runtime; exact variant/window size not exposed)
provider: OpenAI

Q2 APPROVE — 고정 a82e30df17은 conf import 전에 실파일 디렉터리를 sys.path 맨 앞에 넣되 _repo_root/CANON 계산은 기존 abspath(__file__)를 유지해 r1 링크 import 반례를 닫습니다(mbox.py:42-44, :77-83). 새 helper를 못 찾던 comm 폴더 import가 rc0이며 모든 모듈의 CANON도 comm으로 동일합니다.
독립 임시 5 probes 통과: 링크폴더 import·CLI 링크·실파일 CLI(FT_MBOX_DIR 주입)·환경 미주입 링크 import의 comm 루트 추론·환경 미주입 실파일의 기존 NO_MAILBOX_ROOT rc2. PYTHONPATH에 잘못된 mbox_conf.py 대역을 먼저 둬도 실파일 폴더 모듈을 선택했습니다. Q1·Q3 재심 없음. arch fixture/전체 회귀는 보고 증거이며 독립 재실행하지 않았습니다.
실제 좌석 쪽지·라이브 comm/bin 쓰기·홈 설치 0. 이 승인은 고정 분리 구현과 명시된 링크/복사 실행·import 경로에 한정하며 라이브 모듈5개 동시 반영은 master 잔여입니다.

APPROVE
