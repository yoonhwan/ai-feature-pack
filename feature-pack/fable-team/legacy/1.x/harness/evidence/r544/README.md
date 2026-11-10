# r544 증거 — 고장 데몬 3개(WorkingDirectory 누락 · 지운 경로 실행)

카드: `design/harness/indices/진행/r544-broken-daemons-plist-root-and-exist-check.md` · 팩 브랜치 `nano/r544-broken-daemons-plist-root-and-exist` · 1.1.96

| 파일 | 무엇 |
|---|---|
| `before-test_plist_workdir_exist_r544.txt` | 고치기 전(코드 2파일 stash) 새 시험 → **FAIL 4**(ⓐ·ⓑ멱등·ⓓbin-list 7·ⓔDRIFT 0) |
| `after-test_plist_workdir_exist_r544.txt` | 고친 뒤 같은 시험 → **ALL PASS 18** |
| `after-existing-install-tests.txt` | install·install-check 계열 11 rc · PASS/FAIL 수 |
| `after-two-preexisting-fails.txt` | rc1 2건의 FAIL 줄 — base(`r538/base-origin-main-preexisting.txt`)와 같은 기존 실패 |
| `real-dry-run.txt` | 실제 루트 `install.sh --dry-run` = `LAUNCHD rendered=7 changed=2`(secret-scan·weekly-review 가 목록에 들어옴) |
| `real-diff-installed-vs-render.txt` | 설치본 ↔ 렌더본 차이 = `WorkingDirectory` 추가 · weekly-review 실행 경로 워크트리 심 → 루트 심 |
| `real-drift-gce-guard-repro.txt` | 설치 검사가 «지운 워크트리를 가리키는 plist» 를 `DRIFT launchd … missing=` 로 찍은 원문(temp HOME 재현 · 쓰기 0) |
| `real-state-before.txt` | 실사건 현재 상태(읽기만) — gce-guard plist 는 이미 루트 정본 · secret-scan·weekly-review 는 `WorkingDirectory` 키 없음 |
| `real-install-check-drift.txt` | 실제 루트 `ft-live-install-check.sh --all` 전문(읽기만 · rc1) |

press(라이브 오디오) 0 — 이 카드는 launchd·파일 축이라 press 필요 없음. master 집행 뒤 실사건 3(종료 0 · 로그 오류 0 · DRIFT 원문)으로 닫는다.
