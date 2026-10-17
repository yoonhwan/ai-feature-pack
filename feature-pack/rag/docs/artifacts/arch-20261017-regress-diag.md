최신 fable-team 하네스를 이식하고 기존 AIRAG 증거를 재대조한 뒤, Claude Opus 5.5 HELM·Sonnet 5.5 Master/Nano·GPT-6.1 Sol DA 완성 루프로 AIRAG를 운영 가능한 상태까지 닫는다.
A03 닫는 증거: 「Sonnet 5.5 Nano 구현·GPT-6.1 Sol DA 루프」 — A02 트리 5순위 C12(U2 launchd com.airag.consumer) 회복 관찰 + 6순위 C13(KakaoBot 통합 보고서) published 칸 채움.
골의 어느 축인가: A03 — C12. 설계 r17 구현(정독 DA 3차 PASS · 커밋 88315c7 · 구현 HEAD 4c72a95)을 «처음으로 실행한» 전체 회귀 21건 실패 — 재개 3회차(설치) 전 정정.

# 설계 r17 구현 회귀 21건 — 진단·정정 설계 (architect · Sonnet 5.5)

작성 2026-10-17 · 입력 `.fable-team/state/airag/regress-4c72a95-20261017.log`(1330 passed · 21 failed) · 코드 정독 + 단일 시험 재실행(출력 인용).

## 0. 결론 (한 줄씩)

1. **운영 코드 결함 0건.** 21건 중 **시험 결함 17건(결정적·재현됨)** · **부하/환경 4건(회귀 중 load1 60~83 · 단독 재현 0)** · 설계 r17 계약 변경 0 · DA 재심 불필요(시험만 바뀜).
2. Nano 가 예측한 두 위험(① 읽기 전용 열기에서 -shm 못 만듦 ② 둘째 틱·강제 종료 뒤 틱)은 **이번 실패의 원인이 아니다.** 실패한 서비스 시험 중 해당 경로(`kill-in-pass`·둘째 틱)는 전부 통과했다 — 실패 21건 안에 없음.
3. 정정 단위 3개(U1~U3, 시험 파일만) + 재실행 규칙 1개(U4). 예상 소요 합 ≈ 20분 + 부분 재실행 ≈ 10분.

## 1. 실패별 판정표

| 묶음 | 건수 | 판정 | 코드 결함? | 근거(요약) |
|---|---|---|---|---|
| A. `test_pass_gate` 가짜 SQLCipher | 10 | **시험이 틀림** | 아니오 | `FakeSqlcipher.connect(self, uri, **kwargs)` 가 코드의 `connect(uri_문자열, uri=True, …)` 와 키워드 충돌 |
| B. `test_tick` raw-output 파라미터 | 6 | **시험이 틀림(옛 단언)** | 아니오 | `set(frame) == {exit,summary,code,type}` — 설계가 프레임에 선택 키 `integrity` 를 추가함 |
| C. `test_tick` partial_failure | 1 | **시험 보조 함수가 틀림** | 아니오 | `everything_written` 이 log_dir 의 새 파일(pass-state.json·pass-trace.jsonl)까지 이어붙여 `[-1]` 줄이 tick 줄이 아님 |
| D. `test_tick` forked_descendant | 1 | **환경(부하)** | 아니오 | 손자 프로세스 `sleep(5)` 가 load1 71 의 틱(39.6 s) 안에 끝남 · 단독 통과 |
| E. `test_tick` normal_tick exit 40 | 1 | **환경(부하·메모리) 추정 — 미확정** | 아니오(증거 없음) | 단독 통과 · 4병렬(load 38)에도 통과 · 회귀 중 load1 83 |
| F. `test_compare_opa` 자식 pid | 1 | **별건 · 부하** | 아니오 | 시험·대상 스크립트 diff 0(아래 §5) |
| G. `test_s2_opa` partial_output | 1 | **별건 · 직전 회귀(5062086)에도 실패** | 아니오 | diff 0 |
| (참고) `test_probe_opa` | 0 | 이번엔 통과 | — | 직전 회귀 실패분은 이번에 통과 → 부하 변동 |

합 = 10+6+1+1+1+1+1 = 21 ✔ (로그 FAILED 줄 21개와 일치).

## 2. 묶음 A — 10건: 가짜의 시그니처 충돌 (확정)

**3자 대조**
- 코드 `_pass_gate.py` `_check_one`: `sqlcipher3.connect(uri, uri=True, isolation_level=None)` — 실제 `sqlcipher3.connect(database, …, uri=False)` 와 같은 모양. 코드가 맞다.
- 시험 `tests/test_pass_gate.py:315`: `def connect(self, uri, **kwargs)` — 첫 인자 이름이 `uri` 라서 `uri=True` 와 부딪힌다.
- 재현(내 단독 실행): `TypeError: FakeSqlcipher.connect() got multiple values for argument 'uri'`. 코드는 예외 종류·문구를 읽지 않고 `open_error` 로만 돌려준다(설계대로) → 단언이 `open_error != ok` 로 보인다.
- 이어 영향: 가짜를 쓰는 시험 중 «ok/not_ok/identity_error/deadline» 을 기대하는 10건이 전부 실패. «open_error 를 기대하는» 시험(`test_a_failure_while_opening_is_an_open_error`·`test_an_empty_cipher_version…`)은 **우연히 통과(가짜 녹색)** 중이었다 — 열기 단계까지 가지도 못하고 open_error 였기 때문.
- 사실상 이 파일의 시험은 «가짜 SQLCipher» 로는 한 번도 실제로 돈 적이 없다(정독 DA 만 거침). 실서비스 경로 시험(`service` 고정물 · 128 passed 구간)은 통과 → 코드의 실물 경로는 검증됨.

**정정(U1 · 시험만)** — 첫 인자를 위치 전용으로:
```python
def connect(self, target, /, **kwargs):   # the code passes uri=True as a keyword, so the first parameter must not be named "uri"
    self.uris.append((target, kwargs))
```
`test_the_check_opens_read_only…` 의 `uri, kwargs = fake.uris[0]` 는 그대로 동작(튜플 모양 불변).

**검증(내 실행, 저장소 밖 복사본)**: 위 한 줄을 고친 복사본에서 `check_databases([fake_target()], sqlcipher3=Fixed())` → `[{'db':'consumer','out':'ok','ms':0.129}]` · uris = `[('file:///synthetic/path/to/consumer.db?mode=ro', {'uri': True, 'isolation_level': None})]`. 같은 복사본으로 `test_pass_gate.py` 를 돌리면 위 10건 이름은 모두 통과(복사본에서 남은 8건 실패는 `_tick_component.py` 가 `HERE.parent/"src"` 로 src 를 찾는데 복사 위치에 없어서 생긴 경로 문제 — 저장소 안 실행인 회귀에서는 통과했던 시험들이다).

**가짜 녹색 방지(U1 에 포함, 선택이 아니라 권장)**: open_error 기대 시험 2종(`…while_opening…`, `…empty_cipher_version…`)에 `assert fake.uris` (열기까지 갔다)를 한 줄 추가 — 이번 같은 «열기도 못 한 채 우연히 맞는» 형태를 막는다. Red 확인: 정정 전 가짜로는 이 줄이 실패해야 한다.

## 3. 묶음 B — 6건: 옛 단언 (확정)

- 코드·설계: r17 §설계 «자식→부모 전달은 프레임에 선택 키 `integrity`(FRAME_KEYS 확장)» · `_result.py`: `set(frame) in (FRAME_KEYS, FRAME_KEYS | {"integrity"})`, 무효 integrity 는 그 필드만 제거. **설계대로 프레임에 `integrity` 가 붙는다.**
- 시험 `tests/test_tick.py:845`: `assert frame is not None and set(frame) == {"exit","summary","code","type"}` — 옛 계약. 6 파라미터 전부 같은 이유 (`Extra items in the left set: 'integrity'`). 단독 재실행 `[normal]` 도 동일 실패(내 실행 인용: `Extra items … 'integrity'`).
- 참고: 파라미터 중 `keylike`·`short` 는 `exit 2 · RUNTIME_FAILED`(pass 가 중간에 예외) 인데도 integrity 가 있음 — 게이트는 pass 앞이라 정상.

**정정(U2 · 시험만)**
```python
assert frame is not None and set(frame) - {"integrity"} == {"exit", "summary", "code", "type"}
# when present, integrity is the closed record, checked by the production validator (not re-declared here)
assert "integrity" not in frame or _result.integrity_valid(frame["integrity"])
```
뒤따르는 «키·MARKER·경로가 결과 파일에 없다» 단언(text 스캔)은 `integrity` 가 이름·enum·숫자뿐이라 그대로 유효 — 건드리지 않는다.

## 4. 묶음 C·D·E — test_tick 3건

### C. `test_a_partial_failure_tick_is_degraded_with_exit_zero` — 시험 보조 함수 결함 (확정 · 단독 재현)
- `everything_written()` = `captured.out + captured.err + logs/* 전체`. 새 변경으로 log_dir 에 `pass-state.json`(49 B · 끝 개행 없음) · `pass-trace.jsonl`(0 B) 가 생겼다(`--state-file/--trace-file` 가 `log_dir` 를 쓰기 때문 · 설계대로). `glob("*")` 순서는 디렉터리 순서(비정렬) → 이어붙인 문자열의 `splitlines()[-1]` 이 tick 줄이 아닌 `{"proj":…,"state":"clean"}` 줄이 될 수 있다 → `KeyError: 'status'`.
- 재현: 단독 실행 실패 + 실제 log_dir 목록(`pass-state.json · pass-trace.jsonl · tick-20260927.log · tick.lock`) 확인(내 실행).
- **정정(U3 · 시험만)**: `everything_written` 이 «tick 로그만 마지막에, 파일 사이는 개행으로» 이어붙이게 한다 — 예: `sorted(files, key=lambda p: p.name.startswith("tick-"))` 후 각 파일 텍스트 뒤 `"\n"` 보장. 다른 시험의 «전체 파일 스캔(비밀 누출)» 용도(11곳)는 그대로 모든 파일을 읽어야 하므로 스캔 범위를 줄이지 않는다. 또는 1281행만 `tick_line()` 이 쓰는 같은 파일 읽기로 바꿔도 된다(둘 중 Nano 선택, 전자가 11곳을 한 번에 안전하게 만든다).
- 추가 확인: `test_tick.py:613` 의 `captured.out.strip().splitlines()[-1]` 은 captured.out 만이라 영향 없음.

### D. `test_a_forked_descendant_neither_delays…` — 환경(부하) · 단독 통과(내 실행: `.` 통과)
- 손자가 `time.sleep(5)` 뒤 marker 를 쓴다. 회귀 로그: 이 틱의 `tick_total_s=39.641`, `load1=71.57` → 틱이 손자 수면보다 오래 걸려 marker 가 이미 있음. 코드 주석도 «outlives the rest of the pass even on a loaded machine» 라 가정했으나 load1 70 에서는 깨진다. **코드(부모가 손자를 기다리지 않음)는 정상** — 틱이 39 s 걸린 것이 부하.
- 이번 변경과의 관계: fork 는 pass 안(publish 단계)에서 일어나므로 게이트(≈10 ms)는 fork 이후 시간에 영향이 없다.
- **정정(U3b · 선택 · 시험만)**: 고정 5 s 수면을 «풀어주는 파일이 생길 때까지 대기(상한 60 s)» 로 바꿔 결정적으로 만든다 — 손자: `while not release.exists() and waited < 60: sleep(0.1)`; 시험: 틱 종료·`assert not marker.exists()` 뒤에 release 파일 생성. 부하와 무관해지고 7초 룰 취지(고정 상수 금지)와도 맞다. **필수 아님** — 하지 않아도 부하가 정상이면 통과한다. Master 가 «부하 의존 시험은 건드리지 않는다» 로 정하면 U3b 는 건너뛴다.

### E. `test_a_normal_tick_stays_ok…` exit 40 `COMPONENT_PROCESS_FAILED` — 환경 추정 (미확정, 정직하게)
- 의미: `_run_component` 가 `returncode ∉ {0,3}` 로 판정(자식이 비정상 종료·2·신호). 틱에는 시간 제한이 없으므로(timeout 인자 없음) «시간 초과» 가 아니라 자식 종료 코드 자체가 문제.
- 단독 실행 통과(내 실행: `1 passed in 13.41s`) · **4개 동시 실행(load1 38.8)에서도 4/4 통과**. 회귀 중 이 틱: `load1=83.13 · tick_total_s=22.6`.
- 가능한 원인(추정): 메모리 압박·극단 부하에서의 자식 프로세스 신호 종료(예: -9) 또는 import 지연 중 일시 실패. **로그에 자식 종료 코드가 없어 확정 불가.** 코드 결함 증거는 없다.
- 이번 변경과의 관계: 이 시험이 쓰는 경로(게이트 열기·pass·after_pass)는 같은 파일의 다른 시험(`…first_tick_logs_the_check…`)이 같은 회귀에서 통과했다 → 결정적 코드 결함이면 같이 깨졌을 것.
- **정정(U4 · 관측만)**: 코드 변경 없음. 같은 파일 재실행이 부하 정상(load1 < 30)에서 통과하는지를 판정선으로 한다. 한 번 더 `COMPONENT_PROCESS_FAILED` 가 부하 낮은 상태에서 나면 그때 `spy_component_run` 이 `proc.returncode` 를 단언 메시지에 싣게 하는 시험 보조 수정을 넣는다(지금 넣지 않는다 — 추측 방어는 은폐).

## 5. 묶음 F·G — 직전부터의 별건 (diff 0)

- `git diff --name-only 5062086..4c72a95` 중 `opa|s2|compare|probe` 에 걸리는 파일 = `tests/test_tick_probe.py` 하나뿐(틱 로그 모양 변경 시험 · 이번 실패 목록에 없음). `test_compare_opa.py`·`test_s2_opa.py`·`test_probe_opa.py` 와 그것이 시험하는 스크립트는 diff **0**. → **이번 변경과 무관(별건)**.
- F `test_compare_opa …descendant_holding_the_pipe…` : `len(descendants)==6` 인데 5 — 6회 시도 중 한 번의 손자가 기록되기 전에 끝난 시간 의존(load1 60+). G `test_s2_opa …partial_output` : `/bin/sleep 30` 무출력 시험이 0.3 s 상한에서 `partial_output True` — 직전 회귀(5062086)에도 실패한 기존 실패(2 failed 중 하나).
- 처리: 이번 정정 범위 밖. 부하 낮은 때 단독 재실행으로 재현 여부만 본다(U4).

## 6. Nano 발주용 단위 (TDD · 시험만)

| 단위 | 파일 | Red(정정 전 실패) | Green(정정) | 시간 |
|---|---|---|---|---|
| **U1** | `tests/test_pass_gate.py:315-321` + open_error 시험 2종에 `assert fake.uris` | 지금 10건 실패(`open_error != ok`) | `connect(self, target, /, **kwargs)` | 5분 |
| **U2** | `tests/test_tick.py:845` | `[keylike]…[normal]` 6건 실패(`Extra items: 'integrity'`) | `set(frame) - {"integrity"} == …` + `integrity_valid` 단언 | 5분 |
| **U3** | `tests/test_tick.py` `everything_written`(101-105행) | `partial_failure` 실패(`KeyError: 'status'`) | tick-*.log 를 마지막·파일 사이 개행 | 10분 |
| U3b(선택) | `_tick_component.py` `fork_descendant` + `test_tick.py:907` | 부하에서만 실패 → Red 만들기 어려움(고정 상수 제거라 시험 모양 변경) | 풀어주는 파일 대기 | 15분 |
| **U4** | 없음(재실행 규칙) | — | 아래 §7 | — |

설계 밖 결정(Master 가 정할 것): ① U3b 를 할지 — **권고: 한다**(고정 5 s 수면은 오빠의 7초 룰 취지와도 어긋나고 부하 때마다 재발). ② U3 를 «보조 함수 정렬» 로 할지 «1281행만 교체» 로 할지 — **권고: 정렬**(11곳 보호).

## 7. 재실행 규칙 (회귀 40분 대신)

1. 정정 후 순서: `test_pass_gate.py`(85) → `test_tick.py` → `test_pass_trace.py` → `test_tick_probe.py` — 한 파일씩.
2. 실행 전 `uptime` 의 load1 이 30 이하일 때. 회귀는 load1 60~83 에서 돌아 시간 의존 4건이 흔들렸다.
3. opa 별건 3종(`test_compare_opa`·`test_s2_opa`·`test_probe_opa`)은 같은 조건에서 단독 1회 — 실패해도 이번 변경 판정에 쓰지 않는다(diff 0).
4. 전체 회귀는 위가 모두 녹색일 때 낮은 부하 시각에 1회 — 재개 3회차 전 최종 근거.

## 8. 설계 r17·DA 에 대한 권고

- **설계 r17 계약 변경 없음.** `integrity` 프레임 키·`_pass_gate` 열기 순서·`PASS_STATE_UNAVAILABLE` 경로는 그대로.
- **DA 재심 불필요**(시험 파일만 바뀜). 단 U1 가짜의 `connect` 시그니처가 `sqlcipher3.connect(database, …, uri=…)` 와 같은 모양임을 정독 확인 한 줄은 Master 가 PASS 기록에 넣을 것.
- 교훈(재발 방지): «처음 실행» 시험이 21건 틀렸다 — 정독 DA PASS 3회가 시험 실행을 대체하지 못했다. 다음 단위부터 구현 커밋 전에 **해당 시험 파일만이라도 1회 실행**(Red→Green 증거)을 정본 증거로 요구한다.

## 9. 내가 하지 않은 것

저장소 파일 쓰기 = 이 문서 1개. 운영 DB·설치본·runtime.json·launchd·op 접촉 0 · 전체 회귀 0 · 단일 시험 7회·4병렬 1회(`--basetemp` 는 scratchpad). 비밀 출력 0. 시험 복사본·로그는 scratchpad 에만 있다(저장소 밖).
