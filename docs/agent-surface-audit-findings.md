# agent-surface-audit — 검증 findings

> **상태: 전부 해결됨 (fable-team ft-implementer 수정 + 오케스트레이터 직접 재검증 완료)**
> Bug 1 `--public-safety` 플래그 구현, Bug 2a/2b manifest↔PRIVATE_NAMES 동기화, Gap 3 `.omo` 추가 — 4건 모두 코드/테스트 반영 확인. 신규 테스트 2개 추가(`test_public_safety_json_contains_only_repo_root_and_public_safety`, `test_private_names_cover_settings_directory_and_omo`). `verify.sh` 5/5 PASS, 회귀 없음.

> codex(OMO start-work 하네스)가 완료한 `feature-pack/agent-surface-audit/` 구현을 fable-team 크루(ft-checker + ft-tester)로 독립 재검증한 결과. 스펙 문서(`docs/agent-surface-sync-execution-plan.md`) ↔ 코드(`feature-pack/agent-surface-audit/core/agent_surface_audit/`) ↔ 실제 실행(3자대조) 기준. 모든 항목은 직접 실행/grep으로 재현·확인됨 (추측 없음).

## 검증 방법
- ft-checker(sonnet-4.6, 읽기전용): 스펙 문서 전체 vs 코드 정적 대조
- ft-tester(sonnet-5): `verify.sh`/pytest 직접 실행 + 스펙의 "Verification Plan" 커맨드 3종 실행 + 추가 엣지케이스 8종 실행
- 오케스트레이터(나): CLI 직접 실행으로 `--public-safety` 버그 최초 확인 + manifest.json/paths.py 원본 재대조

## Bug 1 [High] — 스펙이 요구하는 `--public-safety` 플래그가 구현에 없음

- 위치: `docs/agent-surface-sync-execution-plan.md:321` (Verification Plan 섹션)이 최소 검증 커맨드로 `agent-surface-audit --dry-run --public-safety` 를 명시.
- 실제: `feature-pack/agent-surface-audit/core/agent_surface_audit/cli.py`의 `parse_args`는 `--public-safety`를 모름.
- 재현:
  ```
  $ ./feature-pack/agent-surface-audit/core/bin/agent-surface-audit --dry-run --public-safety
  agent-surface-audit: unknown argument: --public-safety
  exit: 2
  ```
- 확인: 오케스트레이터 직접 실행 + ft-tester 독립 재현, 2회 일치.
- 결정 필요 (구현 전 택1 — 여러 해석 있음, 임의로 하나 고르지 않음):
  1. `--public-safety` 플래그를 실제 구현 — human/json 리포트에서 `public_safety` 섹션만 필터링해 출력하는 옵션으로 (가장 유력한 해석, `--format`과 유사한 패턴).
  2. 스펙 문서 쪽을 수정 — 이 플래그가 애초에 불필요하다고 판단되면 `docs/agent-surface-sync-execution-plan.md`의 예시에서 제거.
  - 스펙이 "1. First Implementation Target"의 권위 있는 소스이므로 기본은 (1) 권장하되, 최종 판단은 구현 단계에서 확정.

## Bug 2 [Medium] — `manifest.json`의 `private_state_exclusions`와 코드의 `PRIVATE_NAMES`가 서로 어긋남

파일: `feature-pack/agent-surface-audit/manifest.json:13-24` vs `feature-pack/agent-surface-audit/core/agent_surface_audit/paths.py:7-28`

### 2a. 코드가 manifest보다 좁아서 실제 누락되는 케이스 (기능적 버그)
| manifest 선언 | PRIVATE_NAMES 실제 매칭 | 영향 |
|---|---|---|
| `"settings"` | 없음 (코드엔 `"settings.json"`만 있음) | `feature-pack/<pkg>/settings/` 같은 디렉토리명이 있으면 private로 분류 안 되고 `sources`/일반 스캔에 노출됨. manifest는 제외를 약속했는데 코드가 못 지킴. |
| `"caches"` (복수) | 없음 (코드엔 `"cache"`/`".cache"`만 있고 `"caches"`는 없음) | 위와 동일 — `caches/` 정확히 이 이름의 디렉토리는 필터를 통과 못 함. |

### 2b. 코드가 manifest보다 넓어서 문서에 안 적힌 케이스 (문서 완결성 문제, 기능은 안전)
`.pytest_cache`, `__pycache__`, `log`(단수), `session`(단수), `token`(단수), `hooks.json` — 코드(PRIVATE_NAMES)에는 있으나 `manifest.json`에는 선언 안 됨. 실행에는 안전(코드가 더 엄격)하지만, manifest.json만 읽고 "무엇이 제외되는가"를 판단하는 사람/도구는 실제 동작을 과소평가하게 됨.

- 확인: ft-checker 정적 대조 + 오케스트레이터가 두 파일 원문 재대조로 검증.

## Gap 3 [Low/예방적] — `.omo`(이 도구를 만든 하네스 자신의 상태 디렉토리)가 어느 제외 목록에도 없음

- 이 저장소 루트에 `.omo/`(untracked, `feature-pack/` 밖 최상위)가 실제로 존재하며 `.omc`/`.omx`/`.baton`/`.fable-team`과 동일한 "생성된 런타임 상태" 카테고리.
- `paths.py`의 `PRIVATE_NAMES`와 `manifest.json`의 `private_state_exclusions` 둘 다 `.omo`를 포함하지 않음.
- 현재 실해 없음: `audit.py:65,71`의 `scan_sources`가 `config.repo_root / "feature-pack"` 안쪽만 순회하므로 repo-root 최상위 `.omo/`는 애초에 스캔 대상이 아님 (재현: dry-run 전체 출력에 `.omo` 문자열 없음 — "OMO"는 무관한 고정 문구 "Codex/OMO skill exposure..."에서만 등장).
- 리스크: 향후 스캔 범위가 repo-root 전체로 넓어지거나(스펙 Phase 0의 "Scan tracked and untracked candidates... across the repo" 의도와 일치), `.omo` 유사 디렉토리가 `feature-pack/<pkg>/` 안쪽에 생기면 그 순간 필터 없이 노출됨.
- 권장: `.omc`/`.omx`와 같은 급으로 `.omo`를 두 목록에 선제 추가 (지금 고쳐도 side effect 없음 — 현재 스캔 범위에 영향 안 줌).
- 확인: ft-tester 직접 재현 + grep.

## 확인됨 — 버그 아님 (ft-tester 전수 재현, 전부 PASS)

| 항목 | 커맨드 | 결과 |
|---|---|---|
| verify.sh | `bash test/verify.sh` | PASS 5/5, exit 0 |
| pytest 직접실행 | `python3 test/test_agent_surface_audit.py` | exit 0 |
| 실제 레포 dry-run | `--dry-run` (repo root) | exit 0, 시크릿/세션 내용 미노출 |
| `--json` 파일 출력 | `--dry-run --json ...` | exit 0, human+json 동시 정상 |
| `--repo-root`에 파일(디렉토리 아님) | | 적절히 exit 2 |
| `--json` 부모 디렉토리 미존재 | | 자동 mkdir 후 정상 기록 |
| `--format JJSON`/대소문자 오류 | `--format JSON` | 적절히 exit 2 (주의: `\| head` 파이프로 처음 확인 시 exit 코드가 가려져 오판 위험 있었음 — 파이프 없이 재확인함) |
| 인자 순서 변경 | `--format human --dry-run` | 정상 |
| 같은 플래그 중복 지정 | `--format json --format human` (역순도) | 마지막 값이 이김 — 의도된 동작 |
| `feature-pack/` 없는 빈 레포 | | 크래시 없이 0건 정상 리포트 |
| `--dry-run` 누락 | | 적절히 exit 2 |

## 참고 — 버그 아님, 설계상 의도 (참고용, 조치 불필요)

- **rollback 명령이 전부 주석(`# rollback future action for X: ...`)**: `.omo/plans/agent-surface-audit.md`의 명시적 스코프 결정 — "installer/live migration은 이번 단계에 없음"이라 placeholder가 의도된 동작. 스펙의 "Proposed rollback commands" 요구는 "미래 installer가 만들 명령을 렌더링"하는 것이지 지금 당장 실행 가능한 명령이 아님.
- **`is_private_path`의 이름 부분문자열 매칭** (`"token" in lowered or "auth" in lowered`, `paths.py:48-49`): "authenticator" 같은 이름의 패키지가 있다면 오탐 가능성 있는 설계지만, 실제 `feature-pack/` 안에 해당 이름 패키지 없음 확인(`find feature-pack -maxdepth 1 -iname "*auth*" -o -iname "*token*"` → 결과 없음). 이론적 리스크로만 기록, 현재 버그 아님.
- **`.omo/plans/agent-surface-audit.md`의 Final verification wave(F1-F4) 체크박스가 `[ ]` 미완료 표시**: `.omo/evidence/agent-surface-audit/`에 ruff/basedpyright/verify/adversarial-summary 등 통과 증거가 이미 다 있음 — 단순 문서 갱신 누락으로 보임(기능 버그 아님).

## 다음 단계 (제안)
1. Bug 1: `--public-safety` 방향 결정(플래그 구현 vs 스펙 문서 수정) 후 ft-implementer에 위임.
2. Bug 2a: `PRIVATE_NAMES`에 `"caches"` 추가, `"settings"`(확장자 없는 디렉토리명) 매칭 추가 — 수술적 1줄 수정.
3. Gap 3: `PRIVATE_NAMES` + `manifest.json` 양쪽에 `.omo` 추가 — 예방적 1줄 수정.
4. Bug 2b: manifest.json에 `.pytest_cache`/`__pycache__`/`hooks.json` 등 누락 항목 보강해 문서-코드 계약 일치.
5. 수정 후 `test/verify.sh` + pytest 재실행으로 회귀 확인.
