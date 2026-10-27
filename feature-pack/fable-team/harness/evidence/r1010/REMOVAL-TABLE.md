# r1010 걷음/남김 표 (나노 1석 · 2026-10-27)

base = 팩 origin/main `1dfe2550` · 브랜치 `nano/r1010-overfit-branches-removal-sweep` · 규칙 = 하드 룰 18(이름 줄바꿈·탭)·19(도구 산출 파일 종류)·20(외부 명령 실패 주입)
선행 미착지 실측: r843(`68941e02`)·r880(`39875223`)·r975(`633d5e5b`) 모두 NOT-landed → 그 카드가 만지는 파일 손 0(arch#165 #175702 확인). r945(`81c0b46c`)·r955(`463cd8e4`)는 이미 origin/main.

## 걷음 (이번 커밋 5행)

| 카드 | 파일 | 걷어낸 줄 범위 | 대신하는 규칙 | 시험 칸 삭제 | 왜 걷어도 되나 |
|---|---|---|---|---|---|
| r849 | bin/ft_stall_scan.py (+kit 짝) | `act_l()` 안 `if cell.exists() and not cell.is_file():` 분기 3줄 · `cell_kind()` 정적 메서드 3줄 · docstring 한 줄 | 나 | tests/scripts/test_seat_logged_out_r849.py `test_r6_cell_is_folder_errors_not_silent` · tests/test_seat_logged_out_r849.sh 변이 «칸 폴더 조용한 통과 되살림» | 칸 자리가 폴더인 꼴 = 도구가 만든 파일 종류를 일부러 바꾼 입력(19) |
| r849 | bin/ft_api_outage_util.py (+kit 짝) | `is_quick_turn` 의 `isinstance(duration_ms, (int, float))` + `int(duration_ms)` → `isinstance(duration_ms, int)` | 나 | (시험 칸 없음 — 기존 시험 그대로 통과) | durationMs = 정수 ms. 소수 ms 는 실사용에 없는 꼴 |
| r868 | bin/ft_postboot_measure.py (+kit 짝) | 상태 기록 실패 `except` 안의 로그 회전 «재호출» 1줄 + «읽기 전용 폴더» 사유 주석 → `logst = "-"` | 나 | tests/test_postboot_measure_r868.sh ⓗ R3(상태 폴더 chmod 555) · ⓗ R4(이름 개행 세션 id) · 변이9·변이10 · `tmux_ids()` 픽스처 | 읽기 전용 폴더·이름 개행 = 19·18 로 범위 밖 |
| r988 | bin/ft-root-bin-migrate.sh (+kit 짝) | `os.path.islink(path)` / `os.path.islink(path + ".bak-r962")` REPORT 가드 4줄 | 나 | tests/test_r988_root_bin_migrate.sh ⓧ(심링크 꼴 2) 절 전체 | 심링크로 바꾼 plist = 19 로 범위 밖 |
| r983 | bin/ft_da_metrics.py (+kit 짝) | `mark()` 의 `re.sub(r"[\r\n\t]+", "?", r["stem"])` → `name = r["stem"]` | 가 | tests/test_da_metrics_r983.sh ⓑ 수용 5(파일명 개행) 칸 | 카드 이름 속 개행·탭 = 18 로 범위 밖 |
| r984 | bin/ft_card_map_lint.py (+kit 짝) | `load_map()` 의 `if f and os.path.isfile(f):` → `if f:` (환경값 경로 방어) | 다 | (시험 칸 없음 — 기존 시험 그대로) | FT_CARD_ADDED_MAP_FILE 는 lint 가 mktemp 로 만들어 넘기는 값 하나 |

## 남김 (이번에 손 0)

| 카드 | 대상 | 남긴 이유 |
|---|---|---|
| r957 | 시험 9개 전후 세션 수 비교 R1 변형 가드 | 실 소켓 빈 값은 실제 생김(arch 판단 그대로) |
| r961 | ft_live_install_check.py «용도별 받는 함수 2» | 카드 §구현 2 — arch 결정 줄 없음(손 0) |
| r983 | 다단 쪼갠 카드 합산 분기 | «실제 꼴이면 남김» = 합산은 실 카드 꼴(쪼갠 카드 실재) |
| r984 | kit/fable-team/bin/ft-index-lint.sh `mktemp`+`trap` 사슬(사전 파일 정리·TMPDIR) | 사전 파일이 남으면 다음 lint 가 옛 값을 읽는다 = 판정 계약(실사용 꼴). 걷으려면 계약 자체를 바꿔야 함 |
| r-autonomy-hooks | env -S·--repo·--delete 우회 방어 | arch 판단 «r961 착지 뒤 별 판단» |
| r955 | sat-mbox 큐 재측정 분기 | arch 판단 «남김» |
| r975·r843·r880·r945·r839 | 구조 교체 카드 6장 | 선행 미착지(3장) 또는 그 카드가 흡수 |

## 자리 미확정 — 다음 판단 필요 (코드 수정 0)

| 카드 | 카드에 적힌 걷을 것 | 이번 실측 |
|---|---|---|
| r844 | ft-wt-sweep.sh 서명 소실·gitdir 000 분기 시험 칸 | tests/test_wt_shell_scan_live_seat_r832.sh 에 권한 000 칸 다수(ⓐ·ⓐ'·ⓓ) — «서명 소실» 이 어느 칸인지 카드에 줄 번호 없음 |
| r845 | ft-scratch-repo.sh 제어 문자 입구 거절 1줄 · 옛 깨진 줄 WARN(reg_cat) · 4열 장부 분기 | bin/ft-scratch-repo.sh 에 «제어 문자»·«reg_cat»·«4열» 문자열 0 — r945 착지가 이미 흡수했을 가능성 |
| r897 | ft-scratch-repo.sh 호출자 4곳 stat 실패 처리 → 한 곳 | stat 실패 처리 자리(G6 소유자·G8 장치/inode) 다수 — «4곳» 특정 불가 |
| r874 | ft-tick.sh stamp 폴더 검사 시험 칸 | write_stamp/read_stamp 에 폴더 검사 분기 0 · 해당 시험 칸도 0 = 이미 없음 가능성 |
| r955 | oneline() 위조 방어 분기 | kit/ops-intake·bin 어디에도 `oneline()` 함수 0 — 흡수됐을 가능성 |
| r978 | 판정기 개행·탭 경로 시험 칸 · TMPDIR 실패 주입 칸 | «판정기» 파일명이 카드에 없음 |

## 시험 (이번 회차 실측)

| 시험 | rc | 초 | 결과 |
|---|---|---|---|
| tests/test_seat_logged_out_r849.sh | 0 | 41 | PASS 25 · FAIL 0 |
| tests/test_postboot_measure_r868.sh | 0 | 29 | PASS 70 · FAIL 0 |
| tests/test_r988_root_bin_migrate.sh | 0 | 5 | PASS 82 · FAIL 0 |
| tests/test_da_metrics_r983.sh | 0 | 4 | PASS 39 · FAIL 0 |
| tests/test_card_map_lint_r984.sh | 0 | 37 | fail=0 (단, 부하 12 대에서 «3.2 전체 lint» 칸이 내 변경 **전** 베이스에서도 rc≠0 = 기존 플레이크) |
| kit·bin 짝 cmp0 | 0 | - | 6파일 전부 cmp0 |

## press 필요

없음 — 이 카드는 코드 삭제만(동작 축 = 하네스 도구 · 라이브 오디오 무관).
