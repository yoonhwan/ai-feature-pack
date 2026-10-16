골 원문(GOAL-LEDGER-airag.md 복붙):
최신 fable-team 하네스를 이식하고 기존 AIRAG 증거를 재대조한 뒤, Claude Opus 5.5 HELM·Sonnet 5.5 Master/Nano·GPT-6.1 Sol DA 완성 루프로 AIRAG를 운영 가능한 상태까지 닫는다.
A03 닫는 증거: 「Sonnet 5.5 Nano 구현·GPT-6.1 Sol DA 루프」 — A02 트리 5순위 C12(U2 launchd com.airag.consumer) 회복 관찰 + 6순위 C13(KakaoBot 통합 보고서) published 칸 채움.

골의 어느 축인가: A03 — C12 권한 팝업/간헐 타임아웃 해결. 설계 r9 DA REJECT(blocker 0 / major 3 / minor 2 / note 1) 정정판 = r10. (산출: arch-20261016-opa-popup-design-r10.md · 작성: ft-airag-arch-claude#2 · 발주 #2596 · 설계만, op 실행 0 · 정정판이므로 DA 가 r9 에서 수용한 라벨 읽기·L7 가설·n=2 제한·AppData≠팝업 부재는 다시 열지 않는다)

# 0. 결론 (먼저 읽기)
1. **DA 지적 6건 전부 수용**(소스·man·tick 코드를 행 단위로 직접 대조해 모두 사실로 확인, §1). 반박 0건.
2. **S2 정정:** `s2.sh` 는 이미 launchd(`ProcessType=Background`) 임시 작업으로 `s2.py` 를 실행한다 → «S2 는 터미널 실행·launchd 변형 구현 필요» 철회. 다만 실제 토큰 사용·최대 900초 측정이라 **실행은 보류·별도 HIL** 유지(§5).
3. **N4 를 «Background 대 키 생략(=Standard, light limits)» 대조로 재정의**하고, 변경 범위를 재명세했다: 기본 full 프로브의 `result.json` 스키마·출력·고지는 **한 글자도 바꾸지 않고**(새 필드는 옆 파일 `profile.json` 으로 분리), `--p0-only` 는 worker 까지 전달·`read_token()` 앞 분기·자기 job 대조 인자 단일 출처, N4 전용 단계 게이트·결과 발견·합성 시험 13종을 §4 에 정했다. 이 문서는 구현·실행 승인이 아니다(구현 DA → 정확한 상한·전체 고지 확정 → 오빠 HIL 순서 유지).

# 1. DA 근거 직접 대조 (행·파일 확인 결과)
| DA 주장 | 내가 연 곳 | 결과 |
|---|---|---|
| M1 `s2.sh` 가 임시 launchd job 등록 + `ProcessType=Background` | `s2.sh:215-239`(`write_plist`: ProgramArguments=`python -I s2.py --run DIR --mode M --credentials F`, `<key>ProcessType</key><string>Background</string>`), 머리말 `s2.sh:9-10` «registers one temporary launchd job», 시간 `s2.sh:143` `T_RESULT=900` | **사실.** r9 §5 의 «S2 는 terminal 에서 직접 실행(launchd 를 쓰지 않음)» 은 오류(py 파일에 등록 호출이 없는 것은 wrapper 가 하기 때문) |
| M2-② 키 생략 ≠ 자원 제한 해제 | `/usr/share/man/man5/launchd.plist.5:584-607`: «If left unspecified, the system will apply light resource limits … throttling its CPU usage and I/O bandwidth», `Standard` = «equivalent to no ProcessType being set» | **사실.** r9 §4.2-4·§4.3 의 «낮은 우선순위 설정 있음 → 없음» 은 부정확 |
| M2-① P0 를 «설정/컨테이너 접촉 이전 단계» 로 읽음 | r9 §2.2 마지막 문단이 같은 문단에서 «`op --version` 이 설정 경로를 읽는지는 미확인» 이라 적음 | **사실(자기모순).** 명령 이름으로 내부 초기화 순서를 알 수 없음 |
| M2-③ «launchd 한정이면 호출 3→1 효과 없음» | r9 §7 마지막 항목 | **사실(자료 없음).** 동시 호출 수·경합 상호작용은 미검증 |
| M3 `read_token()` 이 P0 앞에서 호출 | `probe.py:651`(`token = read_token()` 이 `stage_p4` 뒤·CLI 단계 루프 앞) | **사실** |
| M3 결과 검증은 정확한 키 집합 | `probe.py:705-738`: `STEP_FIELDS`·`S0_FIELDS`·`TOP_FIELDS`, `validate_result` 는 `set(document) != {*TOP_FIELDS,"steps","s0"}` 이면 False, `_fields_ok` 도 `set(document)==set(table)` | **사실.** 새 필드를 `result.json` 에 넣으면 기존 검증이 거부 |
| M3 자기 job 대조는 정확한 argv | `probe.sh:101-108` `owns_loaded_job` 의 `want_args` = `PYTHON_BIN -I probe.py --run DIR --mode M` (고정 5개) vs 로드된 job 의 `arguments`, 경로도 `job.plist` 와 동일 | **사실.** 새 인자를 job 에 넣으면 `want_args` 도 같이 바뀌어야 함 |
| M3 chain 은 N1=프로브·N2/N3=E1 결과를 찾음 | `chain.py:192-209` `_candidates`: `name=="N1"` 이면 `PROBE_NAME` 디렉터리의 `result.json`, 아니면 `E1_NAME`(`compare-….result.json`) 파일 | **사실.** 프로브 폴더를 N2 검색에 주면 `result_missing` |
| minor 2 키 읽기 실패 틱은 업무 pass 미시작 | `tick.py:245`(`load_keys(...)`, 실패하면 `TickError`) 가 `tick.py:247`(`_run_component(...)`) 보다 앞 | **사실.** «시작하지 않음»까지만 확인 가능, 전체 유실 없음은 별개 주장 |
| 나머지 | r9 §1.5(`10-13 10:05~12:05` timeout 2건) vs §2.2(«마지막 timeout 10:00») | **사실(모순).** |

# 2. r9 정정 (문구 단위 · 이 절의 문장이 r9 의 해당 문장을 대체한다)

## 2.1 M2 — 해석 정정 3건
1. **P0 의 의미:** 관측은 «**인증 계정/키 읽기 명령을 하지 않은 `op --version` 도 7.0초 기한 안에 끝나지 않았다**» 까지다. 이 호출이 설정·컨테이너·데몬·네트워크에 어떤 순서로 접촉하는지는 모른다. **P0 위치를 근거로 I-2(전용 설정 경로 ⑤)를 «무효»·«유효»·«선행 단계 이전»으로 읽는 문장을 모두 철회**한다. I-2 는 근거가 열려 있다 — 지지도 반박도 없다(P2·P1·P1b 는 두 번 모두 도달하지 못했다).
2. **N4 의 대조 조건:** 비교하는 것은 «**`ProcessType=Background` 를 지정한 작업 대 키를 생략한 작업**»이다. 키 생략은 man 상 `Standard`(light resource limits: CPU·I/O 조절 적용)와 같으며 **자원 제한을 끄는 것이 아니다.** 오빠 고지·해석표에서 «낮은 우선순위 있음 → 없음» 표현을 쓰지 않고 **«launchd 작업 종류 설정을 Background 로 지정 → 지정 안 함(시스템 기본, 가벼운 제한 있음) → Background»** 로 쓴다. 결과로 L1(우선순위/자원 정책 가설)의 «단독 작용»을 판정하지 않는다.
3. **호출 수 축소(③ 후보, 3→1):** 효과가 있다/없다 모두 **미검증**이다. 컨텍스트 안에서도 동시 호출 수·경합·시스템 상태와의 상호작용이 가능하고, 직렬/단일 대조(r4 B1)는 하지 않았다. 지금 권고하지 않는 선택지로만 둔다(근거 없는 기각 아님).
- **A-B-A 의 한계(네 행 전부에 적용):** B 가 한 번이므로 순간 부하·캐시·다른 사용자 상태가 고정되지 않는다. 전후 부하 3값은 그 상태를 통제하는 증거가 아니라 **참고 기록**이다. 따라서 네 행은 «연관 라벨·해석 보류» 원칙으로만 읽는다(§4.6).

## 2.2 minor 1 — 시각 구분
- **10-13 10:00 = 최장 연속 89틱(10-13 01:54~10:00) 구간의 끝**이다(timeout 이 사라진 시각이 아님).
- **10-13 10:05 = 성공 비율이 높아지는 구간의 시작 관측**이다. 10:05~12:05 에도 **10:32·10:49 에 timeout 2건**이 있었다(23틱 중 성공 21·timeout 2). «마지막 timeout 시각» 이라는 표현은 쓰지 않는다. 재부팅 인과 철회는 유지한다.

## 2.3 minor 2 — 틱 실패의 범위
- 확인한 범위: `load_keys` 가 실패하면(exit 30 `OP_READ_UNAVAILABLE`) **해당 틱은 `_run_component` 에 들어가지 않는다 = 해당 틱이 업무 pass 를 시작하지 않는다**(`tick.py:245-247`).
- **«데이터 손상·유실 없음 / 손실은 수집 지연뿐» 주장은 철회한다.** 원천 데이터의 보존과 이후 틱의 재수집 전제는 이 두 P0 결과와 tick 호출 순서만으로 증명되지 않는다. 그 전제(실패한 틱 뒤 다음 틱이 이어받는 계약)는 **기존 복구 계약(consumer 의 소스 오프셋·원장·백업 `backup_due` 보충 설계, ops-design-vs-reality 문서)으로 별도 확인할 항목**이며 이 설계가 보장하지 않는다. 실제 유실을 관측했다는 뜻은 아니다. 오빠께 말하는 재개 고지는 «연속으로 읽기 실패가 나면 그 틱의 업무 처리는 시작되지 않습니다»까지만 적는다.
- R-3 의 «오빠가 막힌 상태로 재개해 관찰» 명시 승인 경로는 유지한다.

## 2.4 r9 §1.3 보완
- 프로브 self PID 12473 은 보존된 `pids.json` 과 DeveloperTool 요청의 attribution PID 가 같으므로 «이미 종료돼 PID 대조 불가» 를 **«보존된 pids.json 의 프로브 부모 PID 와 일치»** 로 보완한다(DA 확인). 대상은 여전히 `op` 가 아니다.
- syspolicyd info/debug 세부 집계(GK 36/40 등)는 **작성자 당시 계수 보고**이며 DA 재조회에서 독립 재확인되지 않았다(보존 한계). 평가 대상 비공개·창 길이 차이·도구별 귀속 미확인 한계 유지, 평가 빈도만으로 L7 을 확정/배제하지 않는다. 터미널 18회는 독립 18개 컨텍스트가 아니며 원인 확정·동등성 증명에 쓰지 않는다.

# 3. 7초 룰 (변경 없음)
N4 의 모든 `op --version` 은 시도당 7.0초·재시도 0 · 총 상한은 §4.5(r8 §4.4 와 같은 단일 정본). 약 14초는 I-1 호출 예산이며 회수·반환 오버헤드와 구분한다. 7초 밖 측정·상수 변경은 규칙 소유자(오빠)의 별도 명시 판정 전에는 하지 않는다.

# 4. N4 재명세 (M3) — 구현 승인이 아님
**목적:** 같은 launchd 컨텍스트에서 **`ProcessType` 지정 vs 지정 안 함**만 다른 임시 작업 3개(Background → 지정 안 함 → Background)로 P4+P0 만 실행한다. 토큰 파일·계정 명령 없음.

## 4.1 기본 full 프로브 보존 원칙 (변경 0 보증)
- **`result.json` 스키마는 v1 그대로**다. `TOP_FIELDS`·`STEP_FIELDS`·`S0_FIELDS`·`validate_result`·`read_result`·`--validate`·`--report` 출력·`conclude` 는 **수정하지 않는다.** 새 정보는 **옆 파일 `profile.json`** 으로 분리한다(§4.3). 이유: 키 집합 고정 검증 때문에 `result.json` 에 필드를 넣으면 기존 도구(chain N1 게이트·S2·compare·기존 시험)가 거부하거나 계약 변경 재검수가 필요해진다.
- 기본 호출(`probe.sh --python PY`)은 job 인자·plist·단계·출력·고지가 **바이트 단위로 동일**해야 한다(골든 시험, §4.7-10). `--p0-only`·`--process-type` 은 명시했을 때만 효과가 있다.
- p0only 실행의 `result.json` 은 **유효한 v1 문서**다(P2·P1·P1b = `skipped_not_applicable`, 기존 열거형 안에서 `conclude` 가 `p0_blocked` 또는 `cause_unconfirmed`). 따라서 기존 v1 판독기가 그대로 읽는다. 이 문서가 «새 conclusion 값»을 만들지 않는다.

## 4.2 `--p0-only` 와 `--process-type` 의 전달 경로 (worker 까지)
1. **`probe.sh`:** 선택 인자 `--p0-only`(플래그), `--process-type background|unset`(기본 `background`). `--process-type` 은 `--p0-only` 와만 함께 허용(단독 사용·알 수 없는 값은 종료 2, job 미등록). 기본 호출은 두 인자 없음.
2. **job 인자의 단일 출처:** 셸에서 `WORKER_ARGS=( "$PYTHON_BIN" -I "$HERE/probe.py" --run "$PROBE_DIR" --mode "$MODE" [--p0-only --process-type-set true|false] )` 배열을 **한 번만** 만들고 `write_plist` 의 `ProgramArguments` 루프와 `owns_loaded_job` 의 `want_args`(`probe.sh:101-108`) 가 같은 배열을 쓴다. 로드된 job 의 `arguments` 와 정확히 일치하고 plist 경로가 `PROBE_DIR/job.plist` 일 때만 자기 job 으로 취급하는 기존 규칙은 그대로다. **다른 프로필·다른 실행의 job 은 자기 것이 아니므로 신호·bootout 대상이 되지 않는다.**
3. **plist 의 `ProcessType`:** `unset` 이면 `<key>ProcessType</key><string>Background</string>` 행만 출력하지 않는다(`probe.sh:211` 부근, 나머지 키·`RunAtLoad`·스트림·환경 `PATH` 동일). 결과·고지에 «지정 안 함 = 시스템 기본(Standard, light limits)».
4. **`probe.py`:** import 시점의 `--mode` 처리(`main()` 의 `--mode` 제거 로직과 같은 방식)로 `--p0-only`, `--process-type-set V` 를 argv 에서 읽고 제거한다. **`--run` 모드에서만 허용**(`--report`·`--validate`·`--close-timeout`·`--bounded` 와 결합하면 사용법 오류 종료 2, 아무것도 실행하지 않음). 두 인자는 항상 쌍으로만(한쪽만이면 종료 2). `probe.py` 를 import 하는 S2·compare 의 argv 에는 없으므로 **기본값(full)으로 동작해 영향 0**(기존 S2·compare 시험 전부 변경 없이 통과가 조건).
5. **`execute()`:** p0only 이면 `read_token()` **호출 자체를 하지 않는다**(`probe.py:651` 앞 분기). `done["P4"]` 실행 → P0 한 번 실행 → 나머지 CLI 단계(`P2`·`P1`·`P1b`)는 `blank_step(name,"skipped_not_applicable")`. P0 직전·직후에 `os.getloadavg()` 를 읽는다(서브프로세스 없음; `OSError` 이면 `null`). **토큰·계정 명령 경로가 코드에 도달하지 않는 것**이 계약이다.

## 4.3 옆 파일 `profile.json` (닫힌 스키마, 값 없음)
- **위치:** `PROBE_DIR/profile.json`(권한 0600, 원자적 쓰기) — p0only 실행에서만 생성. 기본 full 에는 생성하지 않는다.
- **키(정확히 이 집합):** `profile_version`(정수 1) · `profile`(`"p0only"`) · `process_type_set`(불리언, 워커가 인자로 받은 값) · `load_before`(길이 3 숫자 배열 또는 `null`) · `load_after`(같음). 숫자는 유한·0 이상·10000 미만. 다른 키·문자열·환경값 금지.
- **수집 불가 상태:** 부하를 못 읽으면 해당 배열이 `null`(해석 라벨에는 영향 없음, 참고 기록 없음으로 표기). `profile.json` 자체가 없거나 키 집합·형이 다르면 **N4 게이트가 그 단계를 중단**(`profile_missing`/`profile_schema`)하고 읽는 쪽은 부하·프로필을 쓰지 않는다.
- **독립 검증(자기 보고 의존 제거):** 게이트가 `PROBE_DIR/job.plist`(보존 증거) 텍스트에서 `<key>ProcessType</key>` 의 **유무**를 직접 확인해 `profile.json.process_type_set` 와 단계 기대값 모두와 대조한다(셋 중 하나라도 어긋나면 `profile_mismatch`).
- **버전·호환:** `profile_version` 이 1 이 아니면 읽지 않는다(후속 미실행). 구버전 도구가 만든 폴더(`profile.json` 없음)는 N4 에서 `profile_missing`. 기존 chain(N1·N2·N3)·S2·compare 는 `profile.json` 을 보지 않으므로 영향 0. **읽는 쪽 변경 범위 = N4 게이트 코드뿐**(`validate_profile` 신설, `validate_result` 무변경).

## 4.4 N4 단계 게이트·결과 발견 (r8 §4.2~4.3 원칙 재사용, 세 프로브 프로필 전용)
- **연속 실행 스크립트:** 새 제어 로직이므로 합성 시험 + 구현 DA 필수(r8 §4.5 그대로). 기존 chain(N1→N2→N3)과 **분리된 별도 진입**(예: `chain.py` 의 새 프로필 `n4`)이며 N1~N3 흐름 코드는 바꾸지 않는다.
- **결과 발견:** 도구 실행 전후 `~/.local/share/airag-probe/` 항목 목록을 비교해 **새로 생긴 항목이 정확히 1개**이고 이름이 `PROBE_NAME` 패턴인 **디렉터리**일 때만 `<dir>/result.json` 을 쓴다(= 기존 N1 분기). **E1 파일 패턴(`compare-….result.json`)은 N4 에서 후보가 아니다.** 0개·2개 이상·읽기 불가·JSON 불완전·크기 초과 = 후속 미실행(`result_missing`·`result_ambiguous`·`result_unreadable`). stdout 의 «결과 파일» 줄은 파싱하지 않는다.
- **단계 게이트 G4(종료코드 AND 결과 JSON AND profile.json):** 다음 단계로 가려면 모두 참이어야 한다.
  1. 도구 종료코드 0(비정상 코드 1·2·3·4·130·143·129 는 저장 코드 그대로 전파, 후속 미실행).
  2. `probe.validate_result(doc)` 참 · `complete=true`·`aborted_class=null`·`timed_out_wait=false`·`conclusion≠observation_unknown`(기존 `gate_probe` 재사용).
  3. 실행된 단계(`P4`·`P0`)에 `child_exit_unconfirmed=false`·`descendants_may_hold_pipe=false`·(`child_pid=null` 또는 `reaped=true`).
  4. **`P0.status ∈ {success, timeout}`** — `spawn_error`·`unsupported`·`observation_unknown`·`auth_error`·`network_error` 는 표 행이 아니므로 **중단(`p0_not_tabulable`)**. `timeout` 은 `reaped=true` 확인된 경우만.
  5. **토큰 비접촉 계약 확인:** `P2`·`P1`·`P1b` 가 **정확히 `skipped_not_applicable`** 이고 `account_type_confirmed=null`·`child_pid=null` — 아니면 `profile_violation` 으로 중단(p0only 인데 계정 명령 단계가 실행된 것).
  6. `profile.json` 유효 · `profile=="p0only"` · `process_type_set` 이 단계 기대값(A=true, B=false, A=true)·`job.plist` 의 키 유무와 일치.
- **`P4` 가 success 가 아닌 단계가 있으면** 진행은 하되 §4.6 표를 읽지 않고 «해석 보류(네트워크 도달 조건 상이)» 로 표시한다.
- **마감·소유·신호:** 단계당 도구 상한 75초(프로브 자체 하드 상한: 실행 60 + 정리 15), **전체 하드 상한 240초 단일 정본**, 전환 ≤3초×3, 단계 시작 조건 남은 시간 ≥83초(미달 시 `skipped_budget`), 한 단계 77초 초과 시 **직접 실행한 도구 프로세스에만** TERM → 최대 3초 → 그래도 남으면 «남은 것 확인 필요»·추가 신호 없음·종료 6 — 모두 r8 §4.4 의 값과 코드(`chain.py` 상수)를 **그대로 재사용**하며 새 시간 상수를 만들지 않는다. 기존/공유 `op` 데몬 등 남의 프로세스에는 어떤 신호도 보내지 않는다(정적 검사 포함). Ctrl-C/TERM/HUP 은 진행 중 도구에 한 번만 전달 후 정리·종료.
- 게이트 실패 종료코드 5, 중단 사유는 값 없는 열거형으로만 표시.

## 4.5 시간·고지 확정 시점
**정확한 상한과 전체 고지는 구현 DA 통과 뒤 확정**한다(DA 순서 유지). 이 문서의 수치는 r8 §4.4 정본의 재사용 선언일 뿐 새 승인이 아니다.

## 4.6 결과 해석표 — 관측 라벨만 (네 행 모두 «연관 라벨·해석 보류» 원칙)
적용 전제: **세 단계 모두 G4 통과·`P4=success`·`P0∈{success, 회수 확인된 timeout}`.** 아니면 표를 읽지 않는다. spawn_error·unsupported·종료 미확인·미실행·잔존·잘못된 결과·`profile_*` 중단은 **해석 보류·후속 미실행이 우선**이다. 아래 표는 «success / 회수 확인 timeout» 의 관측표이다. A-B-A 의 한계(B 한 번·순간 부하·캐시·다른 사용자 상태 비고정)와 부하 3값이 통제 증거가 아님이 모든 행에 적용된다.
| A1(Background) | B(지정 안 함) | A2(Background) | 읽는 법 |
|---|---|---|---|
| timeout | success | timeout | **`ProcessType` 지정 여부와 연관된 관측**(연관 라벨). 시스템 기본(Standard, light limits)은 자원 제한이 없는 상태가 아니다. 원인 확정 아님 · 순서·시간 간격 효과 미통제 |
| timeout | timeout | timeout | **키를 제거만 해서는 이번 재현이 사라지지 않음.** 이 결과로 L1(우선순위/자원 정책 가설)의 단독 작용을 판정하지 않음 · L2·L5·L7 확정 아님 |
| success | success | success | 이번 3회에서 재현되지 않음 — 시간·부하·상태 후보 열림. 재현 안 됨은 해결이 아님 |
| 그 밖의 조합(예: success/timeout/success, success/timeout/timeout 등) | | | 해석 보류, 같은 3단계 1회 더 필요 여부는 별도 판단 |
- 한 번의 A-B-A 로 원인이 정해지지 않는다. 얻는 것은 **연관 라벨과 다음 한 걸음 후보**(N5 책임 프로세스 대조·N6 비-op 서드파티 대조·N7 정지 중 스냅샷)이며, 운영 plist `ProcessType` 변경은 어떤 결과든 **별도 설계·DA·오빠 판정** 뒤에만 한다.

## 4.7 합성 시험 13종 (Master 구현 전 필수, 구현 DA 검수 대상)
기존 합성 stub `op`·가짜 `launchctl`·`PROBE_*` selftest 장치를 재사용한다(production 에서는 `PROBE_*`/`FAKE_*` 환경이 있으면 실행 거부 — 기존 규칙).
1. 정상 A-B-A(세 단계 종료코드 0·유효 `result.json`+`profile.json`) → 3단계 진행·라벨 출력·종료 0.
2. 단계별 `process_type_set` 불일치(B 의 `job.plist` 에 키가 있음 / `profile.json` 값 반대) → `profile_mismatch` 중단·종료 5.
3. p0only 결과인데 `P2` 등이 `skipped_not_applicable` 이 아님(또는 `account_type_confirmed` 가 null 아님) → `profile_violation` 중단.
4. `profile.json` 없음 / 키 집합 다름 / 형 불일치(문자열 부하·길이 2 배열·NaN) / `profile_version≠1` → 후속 미실행.
5. 결과 폴더 0개 / 2개 이상 / JSON 잘림 / 크기 초과 / E1 파일 패턴만 있음 → `result_*` 중단.
6. `P0` 가 `spawn_error` / `unsupported` / `observation_unknown` / `timeout` 인데 `reaped=false`(종료 미확인) → 중단, 표 미판독.
7. `P4=network_error` → 진행하되 표를 읽지 않고 «해석 보류» 표시.
8. 신호·초과: 실행 중 SIGINT/TERM(종료코드 전파·정리), 77초 초과(직접 도구에만 TERM 1회·3초 대기·«남은 것 확인 필요»·종료 6), 총 240초 상한·시작 조건 83초(`skipped_budget`).
9. **센티넬(토큰 비접촉):** `PROBE_TOKEN_FILE` 을 센티넬 값 파일로 지정하고 stub `op` 가 자기 argv·환경 이름·값을 selftest 전용 파일에 남기게 한 뒤, **P0 가 success 일 때와 timeout 일 때 모두** ⒜ `read_token` 이 호출되지 않음(selftest 한정 호출 기록 마커 또는 파일 접근 감사로 확인) ⒝ stub 의 argv·환경에 센티넬 0 ⒞ 프로브 폴더 전체·스크립트 출력에 센티넬 0 ⒟ 계정 조회 stub 호출 0.
10. **기본 full 프로브 골든:** 기본 호출의 job 인자·plist·단계 수·`result.json`·`--report`·고지 문구가 변경 전과 동일하고, 기존 프로브/S2/compare/chain 시험 전부가 수정 없이 통과.
11. **argv 오류:** `--p0-only` 없는 `--process-type`, `--run` 아닌 모드와의 결합, 알 수 없는 값, 한쪽만 있는 worker 인자 → 종료 2·job 미등록·실행 0.
12. **소유 대조:** 다른 프로필(또는 같은 라벨·다른 인자)의 job 이 떠 있을 때 `owns_loaded_job` 이 거짓 → 신호·bootout 0.
13. **값 비출력·신호 범위 정적 검사:** 환경·stdout 값 센티넬이 스크립트 출력·파일에 0 · 어떤 경로에서도 기존/공유 `op` 프로세스·그룹에 신호를 보내는 코드 없음.

## 4.8 오빠께 드릴 고지(구현 DA 뒤 확정 · 지금은 오빠 차례 아님)
> **질문(1개):** `! bash /tmp/h<N>` 한 줄을 1회 실행해 주세요(최대 확정 상한). 같은 `op --version` 을 launchd 임시 작업에서 «작업 종류를 Background 로 지정 → 지정 안 함(시스템 기본, 가벼운 제한은 있음) → Background» 순서로 3번만 실행합니다.
> - **스크립트가 하는 것:** 임시 launchd 작업 3개 등록·자동 내림, 네트워크 도달 확인(my.1password.com 연결) 3회, `op --version` 3회, 전후 시스템 부하 수치 기록. **서비스 계정 토큰 파일을 읽지 않고 `op` 에 토큰을 전달하지 않으며 계정 조회 명령도 없습니다**(여기서 «접촉 0»은 이 스크립트의 읽기·전달에 한정). `op` 프로그램이 내부적으로 설정 폴더·네트워크·이미 떠 있는 1Password 데몬에 접촉하는지는 모릅니다.
> - 팝업이 뜰 수 있으며(개수 보장 불가) 누르지 말아 주세요(«허용 안 함»도 설정으로 저장될 수 있음). 팝업창을 부작용 없이 없애는 방법은 확인되지 않았으니 뜨면 알려 주세요. 새로 생길 수 있는 것은 «남은 것 확인 필요»로 표시합니다.
> - 이 결과는 원인 확정이 아니라 «관측 라벨» 입니다. 팝업과 타임아웃이 같은 원인인지도 모릅니다. consumer 는 계속 꺼 둡니다. Ctrl-C 로 언제든 멈출 수 있습니다.

# 5. 지금 가능한 것 · 승인 · 순서 (r9 §5 대체)
| 항목 | 지금? | 필요한 승인 | 순서 / 이유 |
|---|---|---|---|
| 읽기 전용 사후 보존(op 직후 TCC·평가 계수, 값 없이) | **가능** | 없음(Master) | 매 op 단계 직후 |
| 팝업 관찰 수령(planner 경유) | 진행 중 | 없음 | 보고 없으면 «미확인» |
| **S2 실제 실행** | **가능한 도구(이미 launchd Background 로 실행됨)이나 실행은 보류** | **별도 오빠 HIL** | 보류 이유 4가지: ① **실제 서비스 계정 토큰·키 사용**(값 비출력이나 토큰 접촉) ② **최대 900초**(2조건×6라운드+60초 간격) ③ P0 가 launchd 에서 2/2 기한 초과인 상태라 결과가 같은 정지에 가려질 수 있어 읽기 한계가 큼 ④ 2조건(기본 HOME·전용 HOME)이 N4 대조와 변수가 다름. **«S2 변형 구현 필요»는 철회.** 즉 도구는 있고 승인·해석 한계 때문에 하지 않는 것 |
| **N4 구현**(프로브 두 인자·`profile.json`·N4 진입·합성 시험 13종) | 설계 승인 후 착수 가능 | 코드 승인(Master 발주) + 구현 DA | §4. 기본 full 프로브 무변경 골든 필수 |
| N4 실행 | 구현·DA·고지 확정 뒤 | **오빠 HIL**(op --version 만·토큰 파일 읽기 0, 스크립트 한정) | §4.8 |
| **운영 plist `ProcessType` 변경** | **불가** | 별도 설계 + DA + 오빠 판정 | N4 가 «지정 여부와 연관» 라벨을 낼 때만 후보가 생김. consumer disabled 라 plist 만 바꿔도 즉시 효과를 못 본다 |
| **I-2(전용 설정 경로)** | **불가** | 코드 승인 + 구현 DA | 근거가 열려 있음(§2.1-1: 지지도 반박도 아님). S2 지지 없음·P2/P1/P1b 미도달 |
| 설치본 I-1 갱신(timeout=30 → 7.0/14.0) | 별도 절차 | 기존 재설치 절차(HELM·사용자 확인) | 재개 전 반영(R-2) |
- **순서:** ① 보존·팝업 수령(지금) → ② N4 설계 승인 → 구현 → 합성 시험 → 구현 DA → ③ 오빠 HIL 1회 → ④ 라벨 → (지정 여부 연관이면) 운영 plist 별도 설계·DA·판정, (아니면) N5~N7 설계 → ⑤ 설치본 I-1 반영 → ⑥ 재개 조건 점검. S2 는 이 흐름과 독립으로 오빠 판단이 있을 때만(§5 표).

# 6. consumer 재개 조건 초안 (R-5 확정 — note 1 대응)
재개 = `launchctl enable` → bootstrap(plist 변경 금지). **이 문서는 재개를 승인하지 않으며** enable/bootstrap/bootout/disable 집행은 기존 HELM·planner 경로와 오빠 판정으로만 한다.
| # | 조건 | 지금 |
|---|---|---|
| R-1 | 서버 18703(llm)·18712(embedding) LISTEN + `/v1/models` 200 (Master 보고 — 이 설계·DA 가 운영 HTTP 를 확인한 것 아님, 재개 직전 재확인) | Master 보고상 충족 |
| R-2 | 설치본 I-1(7.0/14.0) 반영 + 설치 모듈 해시 = HEAD 소스 | 미충족 |
| R-3 | launchd 컨텍스트 `op` 호출이 기한 안에 끝나는 관측 **또는** 오빠의 «막히는 상태로 재개해 위험 관찰» 명시 판정 — **P0 한 번 success 는 실제 키 읽기 성공·팝업 방지와 같지 않으므로** 위험 관찰 승인과 구분 | 미충족 |
| R-4 | 팝업 가능성(개수 보장 불가·누르지 말 것)과 §2.3 범위 한정 고지를 받은 오빠의 재개 승인(HIL) | 미충족 |
| R-5 | **관찰 계획(확정):** 아래 | — |
**R-5 확정:**
- **기존 24틱 관찰을 대체하지 않는다.** 24틱은 재개 후 회복 관찰의 **전체 관찰 창(정상 종료 판정 단위)** 이고, R-5 의 두 기준은 그 창 안의 **조기 확인·조기 중단 기준**이다.
- **정상 종료 판정:** 24틱을 마칠 때까지 R-5 조기 중단 조건이 발동하지 않았고 틱 기록이 «ok/degraded 가 존재하는지·exit 30 연속 길이·팝업 보고»로 정리되면 관찰 종료. 24틱 종료 시점의 성공률·재개 유지 여부는 별도 판정(오빠/HELM).
- **조기 확인:** 처음 **3틱**의 `exit`·`status` 를 먼저 읽고 Master 가 HELM·planner 에 보고한다(판정 아님).
- **조기 중단 조건:** `OP_READ_UNAVAILABLE`(exit 30) 이 **연속 6틱**이면 «중단 후보» 로 올린다. **6틱은 횟수이며 시간 보장이 아니다** — 첫 틱 즉시 실행이면 여섯 번째 틱까지 **5개 간격**(`StartInterval=300` 기준 약 25분 + 틱 실행 시간)이고 30분을 보장하지 않는다.
- **조건부 중단의 명령 범위:** 재개 고지가 **중단 집행(bootout+disable)까지 사전 승인하지 않는다.** 중단 후보가 올라오면 **기존 HIL 경로(HELM·planner → 오빠)로 다시 판정**한다. 팝업 보고가 있으면 6틱을 기다리지 않고 같은 경로로 즉시 올린다. 이 설계는 enable/bootstrap/bootout/disable 어느 것도 집행하지 않는다.
- 숫자 3·6·24 는 초안 제안이며 구현·DA·오빠 판정으로 확정한다.

# 7. 후퇴안
- **후퇴안 A (A-B 2단계만):** 순서 효과를 통제하지 못하므로 표의 첫 행을 «관측 1쌍»으로만 쓴다(§4.6 의 한계 그대로).
- **후퇴안 B (추가 `op` 실행 없음):** 읽기 전용 결론에서 멈춘다. consumer disabled, 원인 미확정, 운영 가치 없음을 오빠께 명시.
- 어느 쪽이든 운영 plist·runtime.json·운영 DB 변경 0, 기존 full 프로브·E1·chain(N1~N3)·S2 코드 변경 0(N4 구현은 별도 승인 후 §4.1 보존 원칙 하에서만).

# 8. 미확인 (r9 유지 + 정정으로 추가)
- r9 §9 전부 유지. 추가: **`ProcessType` 지정 여부가 `op --version` 지연과 관계 있는지**(N4 가 연관 라벨만 줌) · 호출 수 축소(3→1)의 효과(미검증) · `op --version` 의 내부 접촉 순서 · 실패한 틱 뒤 재수집 전제(기존 복구 계약으로 별도 확인) · S2 를 지금 실행했을 때 결과가 P0 정지에 가려지는 정도.

# 9. 상태 요약
| 항목 | 상태 |
|---|---|
| `op` 실행(이 설계 작업) | **0** (소스·man·로그 읽기만) |
| 프로브·E1·chain·S2·tick 코드 | 변경 0 |
| N4 | 재명세만(구현·DA·HIL 별도 승인) |
| S2 | 도구 존재(launchd Background 실행)·실행 보류·별도 HIL |
| 운영 plist · runtime.json · 운영 DB | 변경 0 |
| consumer | disabled 유지 · 재개 조건 R-2·R-3·R-4 미충족 · 이 문서는 재개 승인 아님 |

# 10. DA 패턴 선점검
| 패턴 | 점검 | 결과 |
|---|---|---|
| 마감 전파 | 새 시간 정의 | 없음. N4 는 r8 §4.4 정본(75초/단계·240초 전체·시작 83초·77초 초과 TERM 1회·3초) 재사용 선언, 정확한 값은 구현 DA 뒤 확정 |
| 값 비출력 | 새로 읽는 것 | N4 게이트는 `result.json` 닫힌 스키마·`profile.json`(수치·불리언만)·`job.plist` 의 키 유무(원문 비저장)만 읽음. 센티넬 시험 §4.7-9·13 |
| 고지 정확성 | N4·재개 고지 | 「낮은 우선순위 없음」→ Background vs 지정 안 함(Standard, light limits) 정정, «토큰 접촉 0»= 스크립트 읽기·전달 없음 한정·CLI 내부 접촉 미확인 병기, 틱 실패는 «업무 pass 미시작»까지만, 6틱=5간격·30분 보장 아님 |
| 인과 과장 금지 | P0 위치 추론·호출 3→1 단정·all-timeout 행·A-B-A 통제 | P0 위치 근거 철회·I-2 지지/반박 없음, 3→1 미검증, all-timeout=«키 제거만으로 사라지지 않음»·L1 단독 판정 안 함, A-B-A·부하 3값은 통제 아님 → 네 행 모두 연관 라벨·해석 보류 |
