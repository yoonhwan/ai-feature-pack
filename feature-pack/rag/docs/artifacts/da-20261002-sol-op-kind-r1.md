model: gpt-6.1-sol
provider: headroom

# OP_READ_UNAVAILABLE kind — lightweight code DA

판정: **PASS — blocker 0 / major 0 / minor 0**.

발주 #2168, 대상 `7e7a81f` [test] / `86045ad` [fix], 검토 HEAD `86045ad`. 세션 `ft-airag-da-codex#0`; Serena 프로젝트 활성화 및 `_clean_type` 참조/`load_keys` 심볼 확인. 요청 allocation low fast; 실제 창 크기/서비스 tier는 확인하지 못했다.

설계 근거 #2156 및 `.fable-team/state/airag/checker-op30-facts.json` 대조: 15:42:02 KST의 exit 30 / OP_READ_UNAVAILABLE 뒤 15:47:34 성공으로 복귀한 기록은 peer 사실이다. 과거 로그에는 type이 없어 timeout/OSError 구분이 불가능하다. 이번 수정은 **다음 발생의 구분을 가능하게 하며 과거 원인을 확정하지 않는다**. 실제 op/키/운영 DB에는 접근하지 않았다.

## 값 비노출 및 직접 로그 경로

`feature-pack/rag-consumer/src/airag_consumer/tick.py:105–106`은 잡힌 `(OSError, subprocess.TimeoutExpired)`의 `type(error).__name__`만 `_clean_type`에 전달한다. `str(error)`, `.args`, `.filename`, `.cmd`, stdout/stderr를 사용하지 않는다.

`_result.py:16`, `:153–154`의 필터는 문자열에 ASCII 식별자 형태 `[A-Za-z_][A-Za-z0-9_]{0,60}`를 fullmatch하고 연속 16 hex 문자가 있으면 빈 문자열로 치환한다. 빈 kind는 `tick.py:256`의 조건부 type 필드에서 생략된다. 이 필터는 허용된 식별자 형태를 검사하는 기존 필터이며 모든 임의 클래스명에 대한 stdlib whitelist는 아니다. 새 호출에서 원문 메시지를 클래스명으로 취급하는 경로는 없다.

독립 합성 예외 9종으로 실제 `tick.main` → stdout/로그를 실행했다: TimeoutExpired, FileNotFoundError, PermissionError, BlockingIOError 및 16hex/슬래시/공백/개행/길이 초과 클래스명. 앞의 4종은 정확한 클래스명이 기록되고 나머지 5종은 type 생략. 메시지·argv·파일 경로·토큰·키를 흉내 낸 marker와 임시 경로가 stdout/로그에 없음을 확인했다. 모두 **exit 30 / status key_error / code OP_READ_UNAVAILABLE**.

이 실행에서 `validate_frame`과 `_run_component`를 호출 시 실패하도록 patch했지만 호출되지 않았다. 정적 경로도 `main:230 load_keys` → `main:247–248 except TickError` → JSON/append_log이며 component frame 검증을 우회한다. 따라서 Nano의 직접 로그 경로 설명은 맞고, 새 호출 지점에서 정제하는 방식이 필요하다.

별도 `_clean_type` 경계 9개: 61자 허용/62자 거부, underscore/digit 식별자 허용, 숫자 시작/점 거부, 대소문자 16hex 거부, None/int 거부. 모두 기대대로 통과했다. 길이 검증에는 hex 문자와 겹치지 않는 Z를 사용해 길이와 hex 거부를 분리했다.

## exit/의존성 불변

- `EXIT_KEYS=30`, `STATUS[30]="key_error"` 불변. 변경은 OP_READ_UNAVAILABLE의 kind 추가뿐이다. OP_KEY_READ_OR_FORMAT_FAILED는 기존대로 응답 비0/형식 오류에 사용되고 type 없음. 서비스계정 부재/빈 토큰/기존 키 형식/키 중복 등 다른 exit 30 분기도 변경하지 않았다.
- `_clean_type`은 이번 커밋에서 **새로 명시 import**했다. 다만 tick이 `_result` 모듈을 RESULT_MAX_BYTES/validate_frame 용도로 import하던 관계는 이미 존재했다. `_result`는 stdlib 및 pure-data reason_codes만 import하고 tick/runtime을 import하지 않는다. 따라서 새 역방향 의존/순환 import는 없다. 독립 probe에서 tick/result import 이후 runtime 미적재도 확인했다. 비공개 함수 재사용은 기존 정제 정책을 같은 모듈에서 가져오는 이 소형 수정의 범위에서 문제 없음.
- 대상 두 커밋의 변경은 tick.py 6 diff lines(3 제거/3 추가) 및 test_tick.py +52다. runtime/bridge/core 무변경, retry/timeout/백업 행동 변경 없음.

## 독립 회귀/뮤테이션

Python 3.13.12 임시 venv, consumer source PYTHONPATH. `test_tick.py`의 op kind/거절/키 적재/credentials 및 `test_reason_codes.py` registry/reference 선택: **13 passed / 154 deselected, 4.69s**. 새 예외 4종/키 닮은 클래스명/거절 응답 케이스 포함. Master의 full clean 회귀 **428 passed / 321s**는 별도 peer 증거이며 이번 독립 실행으로 주장하지 않는다.

두 뮤테이션은 임시 consumer 사본의 실제 tick 소스에 대입하고 테스트는 유지했다.

1. OP_READ_UNAVAILABLE의 kind 인자 제거: **4 failed / 1 passed / 144 deselected, 4.28s**. 정상 예외 4종의 type 요구가 실패.
2. 정제 클래스명 대신 `str(error)`를 kind에 기록: **5 failed / 144 deselected, 2.38s**. 정상 예외 4종의 클래스명 요구 및 키 닮은 이름의 type 생략 요구가 실패.

각 사본은 finally에서 원문 복구했고 원본 tick.py와 byte 동일함을 확인했다. 원본 source/test 수정 없음.

독립 AST 분류: **registry 528**, frozen 집합 동일, 메모리 `render` 대 tracked reason_codes.py **diff 0**, **unclassified 0 / contradictions 0**. 원본 registry 쓰기 없음. `_clean_type` 추가는 reason-code 집합을 넓히지 않는다.

증거: `/private/tmp/da2168_probe.py`, `da2168_mutate.py`, `da2168-scoped.log`, `da2168-mutation-no_kind.log`, `da2168-mutation-message.log`. 합성 config/token/credentials/log만 사용했고 실제 op/1Password/운영 DB/rollout/live endpoint/서비스에는 접촉하지 않았다. unrelated untracked `.claude/`, `CLAUDE.md` 보존. commit/push 없이 본 판정 파일만 추가한다.
