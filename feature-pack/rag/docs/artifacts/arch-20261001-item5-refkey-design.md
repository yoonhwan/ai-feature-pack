model: claude-sonnet-5-5[1m]
provider: claude-code session (ft-airag-arch-claude#0, effort=high)

# AIRAG 상시 틱 exit 40 `MISSING_OR_INVALID_REFERENCE_SOURCE_KEY` — 원인 규명·설계

골 원문: 최신 fable-team 하네스를 이식하고 기존 AIRAG 증거를 재대조한 뒤, Claude Opus 5.5 HELM·Sonnet 5.5 Master/Nano·GPT-6.1 Sol DA 완성 루프로 AIRAG를 운영 가능한 상태까지 닫는다.
골의 어느 축인가: A03·A02 5순위 U1(C12·C07) — 사용자 수동 1회가 exit 40 으로 멈춘 건의 원인 규명(체인 3단계). 입력: `.fable-team/state/airag/checker-refkey-facts.json`(HEAD 672f7c0) + HELM 관찰. 이 설계는 HEAD c0cb5e1 에서 `runtime.py`·`tick.py`·`_pass_child.py` 를 직접 다시 읽어 확인했다. 코드·runtime.json·launchd 는 건드리지 않았고 키 값은 열람하지 않았다.

---
## ① 원인 규명

### 한 줄 결론
**상시 틱의 `run --once` 경로는 reference 키를 한 번도 쓰지 않는데, `AIRAGRuntime` 생성자가 reference 절이 있으면 모든 서브커맨드에서 그 키를 «필수»로 요구한다.** 키를 쓰는 곳은 `search` 하나뿐이다. 틱은 의도적으로 스토어 키 3개만 다루므로(`tick.NAMES`, `_pass_child` 의 정확한 3키 집합), 사용자 셸·launchd 환경에 변수가 없으면 패스가 시작도 못 하고 exit 40 으로 멈춘다. 이것은 틱 구현 결함이 아니라 **«키가 필요한 시점»과 «키를 검사하는 시점»의 불일치(검사가 사용처보다 앞섬)** 다.

### 근거 (파일:라인, HEAD c0cb5e1)
| # | 사실 | 위치 |
|---|---|---|
| 1 | 던지는 곳: reference 절이 있으면 `environ.get(source_key_env)` 가 None·빈 문자열·64hex 아님 → 전부 같은 코드. 생성자 시점(락·DB 생성 전) | `runtime.py:452-459` |
| 2 | 모든 서브커맨드가 생성자를 먼저 통과: `AIRAGRuntime(...)` 생성 후 분기 | `cli.py:99-102` |
| 3 | 틱 자식도 `cli_main(["--config", cfg, "run", "--once"])` 로 같은 생성자 경유. 자식 env = `{**os.environ, **키 3개}` — reference 키를 채우는 코드 없음 | `_pass_child.py:80-82`, `tick.py:169-170` |
| 4 | **키 «사용처»는 `search` 하나뿐**: `self.reference_source_key` 를 읽는 줄은 `search_tour_reference(...)` 호출 인자(1156) 한 곳. `run_once`(990-1019: 수집·발행·기억·보관·백업)와 `status`·`init`·`memory-*`·`backup`·`verify` 는 reference 키를 읽지 않는다 | `runtime.py:1145-1156` (유일한 소비), `:990-1019` |
| 5 | `search` 안에는 이미 `reference_source_key is None → 같은 코드` 방어 분기가 있다. 생성자 검사가 통과하면 도달 불가라 «죽은 방어»지만, **설계가 «키 없이도 객체가 만들어질 수 있음»을 상정했던 흔적**이다 | `runtime.py:1146-1147` |
| 6 | 틱은 의도적으로 3키만: `NAMES` 3개·`load_keys` 가 NAMES 만 op read·stdin 키 집합이 `set(NAMES)` 와 정확히 같아야 함(r3 DA 가 승인한 경계) | `tick.py:30-31,66-116`, `_pass_child.py:35-43` |
| 7 | 이전 라이브 성공은 전부 투어 도구 경유 — 투어 도구가 `tour['key_file']` 에서 읽은 키를 «자기 프로세스 env dict»에만 설정. 운영(launchd/CLI 직접)에는 공급 코드·문서 없음 | `deployment_setup.py:155,180-184,195`, `first_collection.py:103-105` |
| 8 | 현재 테스트가 «키 없음 → 생성자 거부»를 고정하고 있다. 즉 이 동작은 **의도된 계약처럼 박제**돼 있으나, 그 계약은 «reference 검색이 있는 투어 맥락»에서 쓰였고 상시 틱 맥락(키를 쓰지 않는 패스)은 고려되지 않았다 | `tests/test_runtime.py:335-342` |
| 9 | 키의 정체: reference 키는 «기존 투어 DB(읽기 전용)»를 여는 키다(`reference.py:1`, DECISIONS.md:398-402). 상시 서비스가 필요로 하는 비밀이 아니라 **조회 시에만 쓰는 별개 DB 의 열쇠**다. 운영 3키와 값이 달라야 한다(`runtime.py:460-464`) | — |

### 배제한 가설
- «틱이 3키만 처리하는 것이 버그» — 아니다. 3키 경계는 r3 DA 가 승인한 보안 경계이고 reference 키는 패스에서 쓰이지 않는다. 4번째 키를 틱에 추가하는 것은 아래 선택지 A 이며 «필요해서»가 아니라 «생성자가 요구해서» 하는 일이 된다.
- «로그에 키 값이 새어서/주입 순서 문제» — 아니다. 오류는 생성자의 단순 `None` 검사다(변수 미설정). 호출 시점에 변수가 있었는지는 로그에 없으나(checker 보충 관찰), 틱 코드에는 이 변수를 설정하는 곳이 없고 사용자 셸에도 없었다는 HELM 관찰과 코드가 모순 없이 일치한다.
- **주의(내 판정의 경계):** 사용자 셸에 변수가 실제로 없었다는 것은 코드로 증명한 것이 아니라 HELM 관찰이다. 다만 변수가 «있었다면» 이 오류는 나지 않으므로(코드상 64hex 이면 통과) 결론(검사가 사용처보다 앞섬)은 관찰에 의존하지 않는다.

---
## ② 해결 선택지 비교

| | A. 틱에 reference 키 4번째 주입 | B. 상시 서비스용 설정에서 reference 절 제외 | **C. 키 검사를 «사용처(search)»로 늦춤 (권고)** | D. 사용자가 셸에 변수 export |
|---|---|---|---|---|
| 내용 | `NAMES`·op read·stdin 프로토콜·`_pass_child` 정확-집합 검사를 4키로 확장 + 키 보관 위치 신설 | 서비스 전용 runtime 설정(예 reference 없는 복사본)을 launchd 가 사용 | 생성자는 «없음»을 허용(None 보관), `search` 시작 시 필수 검사. 있으면(비어있지 않으면) 형식·distinct 는 지금처럼 생성자에서 거부 | 수동 실행 셸에 투어 키를 환경변수로 둠 |
| 코드 변경 | 큼: `tick.py`·`_pass_child.py`·r3 DA 승인 경계(프로토콜·테스트 다수) 재개방 | 없음(설정 파일만) | 작음: `runtime.py` 약 8줄 + 테스트 1건 수정·4건 추가 | 없음 |
| 새 키 보관 위치 | **생김**(1Password 항목 신설 또는 평문 key_file 직접 읽기) → **사용자 승인 사안** | 없음 | 없음 | 셸 히스토리·프로세스 env 에 투어 키 노출(수동) |
| 최소권한 | 상시 서비스가 쓰지도 않는 조회용 DB 열쇠를 5분마다 메모리에 올림 → **악화** | 유지(상시 서비스는 투어 DB 열쇠 없음) | 유지(키는 search 때만 필요) | 악화(셸 env) |
| 되돌리기 | 코드·보관 위치 되돌림 필요 | 원본 설정 복원(쉬움) | 커밋 되돌리기 한 번 | 변수 unset |
| 부작용 | 키 분배 면적 확대. 틱 보안 경계(r3 PASS) 재검증 필요 | 설정이 둘로 갈라짐(drift 위험). 투어 도구는 `config.reference.source_key_env` 를 읽으므로(`first_collection.py:105`) **같은 파일을 쓰는 투어가 깨짐 — 별도 파일이어야 함**. 서비스 설정에서 `search` 의 투어 병합 검색이 사라짐 | CLI `search` 는 reference 키가 없으면 `search` 시작 시점에 같은 코드로 거부(동작 보존). 단 «키 없이 객체 생성» 이 허용되므로 위 테스트(8번 근거) 갱신 필요 | 임시 우회일 뿐 상시 틱(launchd)은 해결 안 됨 |
| launchd 상시 서비스 해결 | 예 | 예 | **예** | **아니오** |

### 권고: C
- **원인(검사가 사용처보다 앞섬)을 직접 고친다.** A·B 는 «검사를 통과하려고 비밀을 더 퍼뜨리거나(A) 설정을 쪼개는(B)» 우회다.
- 키 사용 시점 = 검사 시점이 되어 «상시 서비스는 투어 DB 열쇠를 갖지 않는다»는 최소권한이 코드로 보장된다.
- 이미 존재하는 죽은 방어 분기(`:1146-1147`)를 살려 쓴다 — 새 개념 추가 없음.
- 보안 방향: 키가 없으면 투어 DB 에 접근하지 못할 뿐 열리는 것이 아무것도 없다. 키가 «있는데 틀리면» 여전히 즉시 거부(fail-closed 유지).
- **사용자 결정 필요 여부: 불필요.** 새 키 보관 위치·설정·launchd 변경이 없다(Master 기준 «키 보관 위치가 새로 생기는 선택만 사용자 승인»에 해당 없음). 단 사용자가 **상시 서비스 안에서 투어 DB 병합 검색(reference 검색)까지 돌리길 원한다면** 그때는 A(키 주입)를 별도 결정으로 올려야 한다 — 현재 코드에서 상시 틱이 reference 검색을 하는 경로는 없다(근거 4).
- DA: 설계 단계 DA 는 생략을 권고한다 — 변경이 생성자 8줄 + 테스트이고 «있으면 엄격·없으면 지연» 불변식이 단순하며 Nano 구현 뒤의 코드 DA 게이트가 어차피 있다. Master 가 설계 DA 를 원하면 1라운드면 충분하다.

---
## ③ 권고안 C — 변경 명세

### 3.1 불변식
- R1: reference 절이 **없으면** 지금과 동일(키 무관).
- R2: reference 절이 있고 변수가 **None 또는 빈 문자열** → 생성자는 통과, `reference_source_key = None`. (프로필 키의 None/빈값 관례와 동일 — `runtime.py:436-440`)
- R3: 변수가 **비어있지 않은데 64hex 가 아님** → 생성자에서 `MISSING_OR_INVALID_REFERENCE_SOURCE_KEY`(지금과 동일 fail-closed — 잘못 설정된 키가 조용히 무시되지 않는다).
- R4: 변수가 64hex 이고 스토어 3키·프로필 키와 같은 값 → 생성자에서 `REFERENCE_SOURCE_KEY_MUST_BE_DISTINCT`(지금과 동일).
- R5: `search` 는 reference 절이 있고 `reference_source_key is None` 이면 **락·원장 열기 이전**(인자 검증 직후)에 `MISSING_OR_INVALID_REFERENCE_SOURCE_KEY` 로 거부한다 — 지금은 번들 검색까지 수행한 뒤 1146 에서 늦게 실패한다. 기존 1146-1147 방어 분기는 유지(이중 방어).
- R6: reference 키가 없을 때 reference 검색/helper(`search_tour_reference`)와 그 경로의 source DB open·snapshot DB 생성은 일어나지 않는다. (DA 설계 r1 D2·코드 r12 R12-m2 반영 — profile bootstrap 은 별도의 명시 profile 키로 보호되며, `profile_source_db` 가 `reference.source_db` 와 같은 물리 파일이면 profile 키로 읽힐 수 있다. 새 경로 alias 금지는 요구하지 않는다.)

### 3.2 변경 위치 (HEAD c0cb5e1)
| 위치 | 변경 |
|---|---|
| `runtime.py:452-459` | `raw_reference_key = environ.get(...)` 가 `None`/`""` 이면 `reference_source_key` 를 None 으로 두고 distinct 검사는 키가 있을 때만(`bytes.fromhex` 이후 기존 로직 그대로). 비어있지 않고 `str` 아니거나 64hex 불일치 → 기존 `_error`. 프로필 키 처리(436-451)와 같은 모양으로 맞춘다 |
| `runtime.py:1120-1123` `search` 첫 줄들 | 기존 `INVALID_SEARCH_REQUEST` 검증 직후, `with self._lock()` **앞**에 `if self.config.reference is not None and self.reference_source_key is None: _error("MISSING_OR_INVALID_REFERENCE_SOURCE_KEY")` |
| `runtime.py:1146-1147` | 유지(이중 방어) |
| `tests/test_runtime.py:335-342` | 기존 «키 없음 → 생성자 거부» 단언을 새 계약으로 교체(아래 4.1) |
| 이유 코드 레지스트리 | **변경 없음** — 코드 값 불변. `reason_codes.py` 드리프트·닫힌 세계 테스트는 값 기준이라 통과(새 `_error("MISSING_…")` 출현은 «선언» 으로 자동 분류) |
| `tick.py`·`_pass_child.py`·`_result.py` | **변경 없음**(3키 경계는 r3 PASS 상태 그대로) |

### 3.3 하지 않는 것 / 범위 밖
- 틱 NAMES·stdin 프로토콜 확장(= 선택지 A).
- runtime.json·launchd·키 보관 위치 변경. 운영 환경에 투어 키를 주입하는 일.
- `search` 의 투어 병합 로직 자체.
- «이전 동작에 의존하던 호출자» — 생성자 거부를 기대한 곳은 위 테스트 한 곳뿐(grep 로 확인: `test_runtime.py:339-342`; 코드 쪽 `except` 로 이 코드를 처리하는 곳 없음). Nano 는 구현 전에 `grep -rn "MISSING_OR_INVALID_REFERENCE_SOURCE_KEY"` 로 호출자를 한 번 더 확인한다.

---
## ④ 테스트 명세 (Nano Red→Green — 합성 fixture만, 실제 op·투어 키·운영 경로 접촉 금지)

`project(tmp_path, now=now, with_reference=True)`·`environment()` 기존 헬퍼를 쓴다(`test_runtime.py:97 project`, `:85 environment`).

### 4.1 `tests/test_runtime.py`
| ID | 방법 | 단언 (Red = 현 코드에서 실패) |
|---|---|---|
| T-ref-missing-constructs | reference 설정, 환경에서 `AIRAG_REFERENCE_SOURCE_KEY_HEX` 제거 → `AIRAGRuntime(...)` 생성 | **생성 성공**(현 코드는 RuntimeError → Red). `reference_source_key is None` |
| T-ref-empty-constructs | 같은 변수를 `""` 로 | 생성 성공 |
| T-ref-invalid-rejected | 변수를 비어있지 않은 비-hex(`"zz"`)·63자 hex·65자 hex 로 | `MISSING_OR_INVALID_REFERENCE_SOURCE_KEY` (현재 동작 보존 — 이미 Green) |
| T-ref-distinct-kept | 변수 = `PROJECTION_KEY.hex()` | `REFERENCE_SOURCE_KEY_MUST_BE_DISTINCT` (보존) |
| T-ref-missing-run-once | 변수 없음 + 정상 합성 config → `run_once()`(또는 `init()` 후 `run_once`) | 성공(수집 결과 dict) · 스냅샷 디렉터리에 `reference-*.db` 없음(R6) |
| T-ref-missing-status | 변수 없음 → `status()` | 성공, `reference_enabled` True |
| T-ref-missing-search-fails-early | 변수 없음 → `search("q")`; `_lock`·`_open_ledger`·bridge `search_history` 를 호출하면 실패하는 spy/monkeypatch | `MISSING_OR_INVALID_REFERENCE_SOURCE_KEY` · **spy 호출 0회**(R5: 락·원장 이전 거부) |
| T-ref-present-search-unchanged | 기존 reference 검색 테스트 그대로 | 통과(회귀 0) |
| T-no-reference-unchanged | reference 절 없는 config, 변수 없음 | 생성·run_once 성공(R1) |
| (교체) 기존 `:335-342` | `pytest.raises(...)`(생성자) → 위 T-ref-missing-constructs 로 대체; `reused`(distinct) 부분은 T-ref-distinct-kept 로 유지 | — |

### 4.2 `tests/test_tick.py` (통합 — 이번 증상의 직접 재현)
| ID | 방법 | 단언 |
|---|---|---|
| T-tick-reference-config-no-key | `project(..., with_reference=True)` 로 만든 합성 config, `base_environment()`(3키·reference 키 모두 없음, `credentials()`+`stub_op` 로 3키 채움) → 기존 `component`(normal) 모드로 `tick.main` | **exit 0**(`status: ok`) · 출력·로그에 `MISSING_OR_INVALID_REFERENCE_SOURCE_KEY` 없음 · 자식 env·stdin 이 3키만(기존 불변식 I3 유지 — reference 키를 추가하지 않았음을 확인). Red: 현 코드는 exit 40 + 위 코드 |
| T-tick-reference-key-garbage | 같은 config, 환경에 비-hex `AIRAG_REFERENCE_SOURCE_KEY_HEX` | exit 40 · `MISSING_OR_INVALID_REFERENCE_SOURCE_KEY`(R3 — 잘못 설정된 값은 조용히 무시되지 않음) · 값 비노출 |

### 4.3 회귀
`../rag/.venv/bin/python -m pytest tests -q -p no:cacheprovider`(consumer 디렉터리) 전체 통과. 기준선 숫자는 Nano 가 S0 에서 기록(HEAD c0cb5e1 기준 현재 통과 수 — 이 설계는 실행하지 않았다).

---
## ⑤ Nano 구현 단계

| 단계 | 내용 | verify |
|---|---|---|
| R0 | 기준선 전체 테스트 + `grep -rn "MISSING_OR_INVALID_REFERENCE_SOURCE_KEY" feature-pack .fable-team` 호출자 확인 | 통과 수 기록 · 호출자 = 레지스트리·runtime·테스트뿐 |
| R1 (Red) | 4.1 T-ref-missing-constructs·T-ref-missing-run-once·T-ref-missing-search-fails-early(+ 4.2 T-tick-reference-config-no-key) 추가 | 4건 Red(이유: 생성자 거부) |
| R2 (Green) | `runtime.py:452-459` 완화(R2·R3·R4)·`search` 조기 검사(R5) | R1 의 4건 Green · 나머지 4.1 보존/회귀 테스트 통과 |
| R3 | 기존 `:335-342` 테스트 교체·T-ref-empty/invalid/distinct/status/no-reference 추가 | 전체 통과 |
| R4 | 전체 회귀 + `git diff --stat`: `runtime.py`·`tests/test_runtime.py`·`tests/test_tick.py` 3개만(`tick.py`·`_pass_child.py`·`reason_codes.py` 무변경 확인) | N passed · exit 0 |
| R5 | `docs/artifacts/nano-…-refkey-result.md` 에 R1~R6 각 불변식의 «닫는 테스트» 매핑 + 변경 3파일 | 코드 DA 대조용 |

변경 유형 분리(Tidy First): 전부 행위 변경이므로 구조 커밋 없음 — 단일 `[fix]` 커밋(테스트 포함).

---
## ⑥ 잔여·한계 (과대 보장 금지)
1. **reference 검색(투어 DB 병합)을 상시 서비스 안에서 쓰는 경로는 이 설계가 만들지 않는다.** 필요해지면 선택지 A(키 보관 위치 신설 — 사용자 승인) 가 별도 결정이다.
2. 운영 사용자가 수동으로 `search` 를 reference 포함으로 돌리려면 그 호출 환경에 reference 키가 있어야 한다. 이 키의 운영 주입 방법은 여전히 «문서 없음» — 이 설계는 문서를 만들지 않는다. Master 가 원하면 `ops-design-vs-reality-20261001.md` U 표(기존 파일)에 «reference 키 = search 전용, 상시 틱 불필요» 한 줄 추가를 제안한다(신규 *.md 아님).
3. 사용자 셸 env 에 변수가 없었다는 것은 HELM 관찰이며, 로그에는 호출 시점 환경 기록이 없다(checker 보충 관찰). 결론은 이 관찰에 의존하지 않는다(① 배제한 가설 참조).
4. C 는 «키 없이 생성 허용»으로 기존 생성자 계약(테스트 `:335-342`)을 바꾼다. 이 계약이 «투어 맥락에서 우발적»이었다는 것은 코드 구조(죽은 방어 분기·`run_once` 무사용)로 추론한 것이며 작성 당시 의도 문서는 못 찾았다(DECISIONS.md 의 «키 미제공은 저장소 생성·열기 전 거부»(:447-452)는 스토어 키 서술이고 reference 키를 명시하지 않는다).
5. 이 설계 단계에서는 실제 테스트·코드를 실행하지 않았다(정적 읽기). 새 코드의 값 비노출·회귀는 Nano 구현 후 코드 DA 가 확인할 게이트다.
