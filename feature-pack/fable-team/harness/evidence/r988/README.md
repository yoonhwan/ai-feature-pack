# r988 증거 — ft-root-bin-migrate.sh (라이브 plist 6 · env 10 의 v6 시작 경로를 공용 루트 bin 으로)

카드: `design/harness/indices/진행/r988-live-root-bin-migrate-tool-16-files.md` (harness-ops · arch#151 · desk #171354)
브랜치: `nano/r988-live-root-bin-migrate-tool-16-files` (팩 `/Users/yoonhwan/Project/ai-feature-pack/.worktrees/r988-live-root-bin-migrate-tool-16-files` · base `origin/main` `44aa6978` · 선행 r962 `3f70f435` 착지 확인)
좌석: `byz-harness-nano-r988-live-root-bin-migrate-tool-16-files#0` (pi · deepseek-v4.1-flash-ultrafast · ctx 1m)

## 왜

하네스 데몬(틱·뉴스·감시)의 시작 경로가 v65 워크트리 `.worktrees/v6-realtime-live/.fable-team/bin` 안이다. 그 폴더가 사라지면 데몬이 전부 멈춘다. r962 는 «앞으로 설치하는 plist» 를 공용 루트 bin 으로만 받게 막았다. 이 카드는 «이미 깔린 16파일» 을 한 번 옮기는 이전 도구 하나를 착지시킨다. 범용 변환기가 아니다.

## 고친 곳 (도구 1벌 = kit/bin 짝 2 · 시험 1 · 증거 1)

| 파일 | 무엇 |
|---|---|
| `kit/fable-team/bin/ft-root-bin-migrate.sh` · `bin/ft-root-bin-migrate.sh` (cmp0) | **새 설계 0** — 이미 구현된 세트 `d2cb5dc5`(r962 r4 `82e96b2e` + r5 `d2cb5dc5` 의 최종 바이트)에서 가져왔다. 기본 dry-run · `--apply` 만 쓰기 · `.bak-r962` · 내부 Label 정본 · `<string>` 제자리 치환 · env 바이트(CRLF) 보존 · 재해석 비교 + `plutil -lint` · 실패 = 복원 + rc≠0 · 멱등. **r1(DA⑥ 수용 3)**: 주석 구간 건너뛰기 · 백업 임시 이름 + 바이트 대조 뒤 mv · 교체 = 임시 → 검사 → `os.replace` 만 |
| `tests/test_r988_root_bin_migrate.sh` | 세트의 `test_r962_root_bin_migrate.sh` 에서 **이름만** r988 로 옮김 + 머리 주석 1줄 + r1 칸 3(ⓤⓥⓦ) + 변이 2(14·15). 시험 본문(ⓜⓝⓞⓠⓠ2ⓡⓢⓣ + 변이 9·10·11·12·13) 그대로 = **82 PASS** |
| `evidence/r988/` | 이 README + 채집물 |

이 도구가 만들지 않은 것: `ft-tick-install.sh` 변경(r962 앞쪽 몫) · 렌더 쪽 표식(goal__X__.sh · root__SCRIPT__ — r962 몫). 카드 §반례 R3 대로 손대지 않았다.

`d2cb5dc5` 대비 바뀐 줄 3곳(+43/-5): ① `index_strings` 에 `comment_spans` 건너뛰기(주석 속 `<string>` 미계수) ② `backup()` = 임시 이름 `.bak-r962.tmp.<pid>` → 바이트 대조 → `os.replace`, 기존 백업이 원본과 다르면 `None`(쓰기 0) ③ `apply_plist` 끝 = 백업 → 임시 쓰기 → `plutil -lint` → `os.replace` 만, 검사 실패는 임시 삭제뿐(원본을 열지 않는다). env 쪽은 백업 `None` 안전 가드 2줄 추가가 전부다(값 판정·치환 로직 변경 0).

## 계약 ↔ 시험 (카드 대응표 그대로)

| 계약 | 시험 | 값 |
|---|---|---|
| ① dry-run 은 쓰기 0 · launchctl 0 · 표 출력 | ⓜ | rc=0 · MIGRATE 17 · REPORT 4 · ERROR 0 · `shaall` 전후 동일 · `.bak` 0 |
| ② (r1) 주석 속 `<string>` 태그는 값이 아니다 | ⓤ | rc=0 · `WorkingDirectory` 치환 성공 · 주석 2줄 바이트 보존 · 다른 값 그대로 |
| ⑤ (r1) 불완전 백업은 재사용하지 않는다 | ⓥ | 1회차(백업 쓰기 실패 주입) rc≠0 · 원본 그대로 · 백업 16B 남음 → 2회차 rc≠0 · `ERROR … 백업 불일치` 1줄 · 원본 바이트 불변 · 백업 덮어쓰기 0 |
| ⑤ (r1) plutil 실패 = 복원 쓰기 0(원본을 열지 않는다) | ⓦ | rc≠0 · 원본 바이트 불변 · **mtime 불변** · `쓰기 0(원본 그대로)` 1줄 · `.bak 복원` 문구 0 |
| ② apply 는 대상 key 의 `<string>` 값만 바꾸고 주석·들여쓰기·다른 key 불변 | ⓢ ⓣ | 주석 `KEEP_COMMENT` 보존 · diff 2줄(값 한 줄) · `&amp;` 이스케이프 · 바뀐 key 목록 `['WorkingDirectory']` · 같은 값을 품은 다른 key 불변 |
| ③ 내부 Label 이 관리 라벨이 아니면 쓰기 0 · REPORT | ⓠ | 비관리 Label 파일 바이트 불변 · REPORT 에 파일명·Label 병기 · Label 없음 = ERROR rc≠0 |
| ④ env 는 CRLF·주석 보존 · 그 줄만 바뀜 | ⓡ | `repr` 비교 동일 · CRLF 3줄 유지 · 주석 줄의 v6 글자 그대로 |
| ⑤ 실패 = 복원 + rc≠0 · 멱등 · .bak-r962 | ⓝ ⓞ + 변이 10 | 새 값 실재 0 → 그 파일 불변 + rc≠0 · 다른 파일은 진행 · 재실행 MIGRATE 0 · `.bak` 16 그대로 |
| ⑥ kit 짝 cmp0 · /bin/bash 3.2 | `cmp-kit.txt` · `test-run-binbash32.txt` | `cmp rc=0` · sha256 동일 · GNU bash 3.2.57 로 82 PASS |

변이 7종이 각각 잡힌다(채집물 `test-run-*.txt` 의 `변 … → …FAIL` 줄): 변이 9 값 부분 일치 → 사람 글 바뀜 · 변이 10 `.bak` 없이 쓰기 · 변이 11 파일명 판정 되살림 → 비관리 라벨 이전 · 변이 12 text mode 읽기 → CRLF 소실 · 변이 13 plistlib dumps 되살림 → 주석 소실 · **변이 14 백업 대조 끔 → 불완전 백업 재사용해 원본이 바뀜** · **변이 15 원본 `wb` 되살림 → 원본을 다시 열어 mtime 이 바뀐다**.

## 라이브 dry-run 표 (읽기 전용 · 쓰기 0 · `../r988/live-dryrun.tsv`)

명령: `bash kit/fable-team/bin/ft-root-bin-migrate.sh --root /Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents`
결과: **rc=0** · `SUM mode=dry-run plist_migrate=6 plist_report=61 plist_error=0 env_migrate=10 env_report=1 env_error=0` · `.bak-r962` 생성 0

이전 16칸 (= 라이브 plist 6 · env 10):

| 파일 | 칸 | 옛값 | 새값 |
|---|---|---|---|
| `com.byz.ft-tick.plist` | `WorkingDirectory` | `<루트>/.worktrees/v6-realtime-live` | `<루트>` |
| `com.byz.ft-resource-watch.plist` | `ProgramArguments/1` | `<…>/v6-realtime-live/.fable-team/bin/ft-resource-watch.sh` | `<루트>/.fable-team/bin/ft-resource-watch.sh` |
| `com.byz.ft-weekly-review.plist` | `EnvironmentVariables/FT_LIVE_BIN` | `<…>/v6-realtime-live/.fable-team/bin` | `<루트>/.fable-team/bin` |
| `com.byz.ft-weekly-review.plist` | `EnvironmentVariables/FT_PLANNER_REPO` | `<…>/v6-realtime-live` | `<루트>` |
| `com.hermes.byz-slack-talk-inbound.plist` | `ProgramArguments/12` | `<…>/v6-realtime-live/.fable-team/bin/ft-inbox.sh` | `<루트>/.fable-team/bin/ft-inbox.sh` |
| `com.hermes.byz-slack-mbox-inbound.plist` | `ProgramArguments/11` | `<…>/v6-realtime-live/.fable-team/bin/ft-inbox.sh` | `<루트>/.fable-team/bin/ft-inbox.sh` |
| `.fable-team/bin-{ccu,cfo,chatbot,feature,harness,issues,kk,knowledge,ops,planner}/<팀>-env.sh` (10) | `FT_BIN` | `export FT_BIN=<…>/v6-realtime-live/.fable-team/bin` | `export FT_BIN=<루트>/.fable-team/bin` |

`<루트>` = `/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents` (값 전문은 `live-dryrun.tsv`).

보고만 62칸 (파일 손대지 않음):

| 꼴 | 수 |
|---|---|
| 비관리 Label (파일명·Label 병기) | 58 |
| `plistlib` 이 못 읽는 옛 꼴(주석 안 `--`) — Label 만 읽음 = REPORT | 3 (`com.byz.colima-periodic-restart`·`-restart-unlock`·`net.pulsesecure.SetupClient`) |
| env 줄이 «정확히 같은 줄» 이 아님(인라인 주석) — R1 알려진 한계 | 1 (`bin-graphics/graphics-env.sh`) |

## 채집물

| 파일 | 무엇 |
|---|---|
| `live-dryrun.tsv` | 라이브 dry-run 원본(탭 구분 · MIGRATE 16 · REPORT 62 · SUM 1) |
| `test-run-binbash32.txt` | `/bin/bash` 3.2.57 · `tests/test_r988_root_bin_migrate.sh` 82 PASS |
| `test-run-bash5.txt` | homebrew bash 5.3.9 · 같은 82 PASS |
| `cmp-kit.txt` | kit·bin `cmp rc=0` · sha256 동일 (r1 고침 뒤 다시 채집) |

## 남은 것 (나노 소관 밖 — master+DA)

1. **착지** = 나노 브랜치 → `feat`/`main` (push 는 master).
2. **설치 cmp0** — 공용 루트 `.fable-team/bin/ft-root-bin-migrate.sh` 로 복사 후 `cmp`.
3. **dry-run 표를 사람이 본 뒤 `--apply` 1회(h 1장)** — `bash <공용 루트>/.fable-team/bin/ft-root-bin-migrate.sh --root <BYZ-Agents 공용 루트> --apply`. 팩 리포에서 돌리면 migrate=0 이다.
4. **apply 뒤** = `RELOAD_NEEDED` 라벨 `launchctl kickstart` → **실사건: 데몬 정상 틱 로그 1줄** (R4 · 시험 밖).

press 필요: 없음 — 이 카드의 증거는 단위 시험 82 PASS 와 읽기 전용 라이브 dry-run 표다. 라이브 오디오 시험(press)은 이 카드 범위가 아니다. 실사건(데몬 정상 틱 1줄)은 master apply 뒤 로그로 남긴다.

## 상태

- 2026-10-27 — 작성. 도구 세트 `d2cb5dc5` 바이트 그대로 · 시험 74 PASS(bash 3.2·5.3) · kit cmp0 · 라이브 dry-run rc=0(MIGRATE 16 · REPORT 62 · ERROR 0) · push 0.
- 2026-10-27 r1(DA⑥ r1 HOLD 수용 3 반영 · 같은 가지 amend) — 도구 고침 3곳(+43/-5) · 시험 칸 3 + 변이 2 → **82 PASS**(bash 3.2·5.3) · kit cmp0 · 라이브 dry-run 다시 rc=0 = MIGRATE 16 · REPORT 62 · ERROR 0 · `.bak` 0 · push 0.
