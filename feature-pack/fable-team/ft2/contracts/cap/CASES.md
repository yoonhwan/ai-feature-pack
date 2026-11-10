# ft2 기록 cap·회전 계약 사례표 (r1548)

ft 2.0 PR② 구현이 통과해야 닫히는 **기록 사건 → 기대 결과** 표다. 사례는 r1528 독립 checker v4 4사례
(`design/harness/research/ft-2.0/journal-cap-v4-checker/`)에서 옮겼고, 실험 코드는 실행하지 않는다.

## 원자료 재계수 (2026-11-10 · BYZ origin/main `db18c453c77868355ffeb813d3b4c49f2047806a`)

| 항목 | 값 | 근거 |
|---|---|---|
| checker v4 사례 | **4** (S1·S2·S3·S4) | `results/a-compare.json` 의 사례 파일 4 |
| checker v4 변이 | 3 (Ma·Mb·Mc) | `results/a-compare.json` 의 mutant 3 + `c-mutants.json` |
| checker v4 경계 | 2 (b1·b2) | `results/boundary1.json` · `results/boundary2.json` |
| 사례표 파일 | **4** | `cases/*.json`(`_checker.json`·`_source.json` 은 사례 아님) |
| 관측 대조 키 | **44** | 사례 32 + checker 회차 12 |
| core.html «5사례» | 5 | 다른 수다 — core.html «cap·회전·포화 복구 독립 checker 5사례 관측·FAIL 0» 은 r1504 v1 C1~C5 기준이다. 이 표는 r1528 checker v4 가 본 4사례만 옮긴다(두 값 모두 여기 적는다) |

★이 4사례는 카드가 지정한 v4 세트다. v1 C1~C5 전체에 대응한다는 인증이 아니다★ — v1 의 C4(ENOSPC)·C5(상태본 포화)와
v1 의 ops 코드 관측은 이 표 범위 밖이고, 옮기지 않았다. 표가 4사례를 덮는다는 뜻이지 cap 실험 전체를 덮는다는 뜻이 아니다.

## 결과 낱말 — 정본 «처리 결과» 7군 (새 낱말 0)

정본 `PLAN-ft20-single-module-and-slack-20261109.md` §파일 배치·최소 상태 의미 후보 표
«처리 결과: 접수 성공/거부·복구 필요·낡은 실행권·BUSY·용량 부족·완료 유보·회수 결과를 구분» 을 그대로 쓴다.
`접수 성공/거부` 가 한 군이라 **군은 7, 낱말은 8** 이다. 사례표 `expect.처리 결과` 는 이 8낱말 밖으로 나가지 않는다.

| 군 | 계약 낱말 | 실험 관측 낱말(계약 아님 · 인용) |
|---|---|---|
| 1 | 접수 성공 · 접수 거부 | OK · TOTAL_FULL · ENOSPC |
| 2 | 복구 필요 | RECOVERY_REQUIRED · RECOVER |
| 3 | 낡은 실행권 | STALE_REJECT · 옛 fd 줄 거절 |
| 4 | BUSY | BUSY |
| 5 | 용량 부족 | TOTAL_FULL · DEFERRED |
| 6 | 완료 유보 | DEFERRED_ENOSPC |
| 7 | 회수 결과 | 회수 실행 · seg_unlink · body_unlink · 멱등 재실행 |

## 사례표 4행

| id | 사례 (checker 사례) | 처리 결과 | 근거 검증 | 관측 대조 | 비채택 |
|---|---|---|---|---|---|
| case_01_segment_reclaim | 회전 뒤 segment 회수 (S1) | 회수 결과 | 회수 2 · 회전 4 · 지운 segment 2 · 미처리 든 segment 보존 | 8키 | 1 |
| case_02_reclaim_crash_resume | 회수 도중 크래시 → 재기동 복구 (S2) | 복구 필요 | 정지점 2 · 복원 = 크래시 전 상태 · 재실행 멱등 | 9키 | 1 |
| case_03_full_crash_recover | 포화 뒤 크래시 → RECOVER · 신규 접수 거절 유지 (S3) | 용량 부족 | TOTAL_FULL · 복구 전후 접수 성공 0 · RECOVER 사용 196 ≤ 532,480 | 9키 | 1 |
| case_04_append_boundary_cap | journal append 경계의 공존 총량 (S4) | 접수 성공 | trace 6 모두 append 경계 · 공존 peak < 8 MiB · 순서 위반 0 | 6키 | 1 |

각 사례 파일 칸 = `id` · `출처`(정본 경로·sha·함수·줄 + 실험 literal 필드명) · `given`(기록 사건 열) ·
`expect`(처리 결과 · 근거 검증 · 관측 대조) · `비채택`.
`expect.관측 대조` 는 checker 원자료 값을 **한 글자도 바꾸지 않고** 옮긴 것이고, 키 꼴은
`<파일 이름표>#<JSON pointer>`(`/` 는 `~1` 로 적는다)이다. 파일 이름표는 `cases/_source.json` 에 있다.

## checker 회차 관측 (`cases/_checker.json` — 사례 아님)

| 관측 | 값 | 뜻 |
|---|---|---|
| 변이 Ma·Mb·Mc 판정 | FAIL 3/3 | 사례 판정기가 변이를 잡는다 |
| 변이 독립 신호 | detected 3/3 | 판정기 밖 신호도 같은 변이를 잡는다 |
| 경계① 이어 센 규칙 뒤 첫 OK | 2 | 보정 세트(6fa43dd5)에서 예약 위반 반례가 닫혔다 |
| 경계① 누적 끝 | 604,625 | 예약 532,480 을 넘는 누적을 서로 다른 규칙으로 센 값 |
| 경계② 크래시 seq 상태 | state.json = done · journal = open | 크래시 시점 상태본과 journal 이 어긋난다 |
| 경계② RECOVER 사용 | 1,548 | 잔여 tmp 없는 크래시 복구는 「몫」 안에서 끝난다 |

## 비채택 — 정본이 계약으로 채택하지 않은 관측

| 사례 | 실험 관측 | 표시(정본 문장) |
|---|---|---|
| 01 | r1504 v1 C3 퇴출 = 완료 본문 오래된 순 100건 삭제 | 비채택: 미처리는 조용히 버리지 않는다 — 완료 근거 Git 보존·참조 0 회수만 |
| 02 | 회차 wall_s 3.073 | 비채택: 숫자는 확정값이 아니다 |
| 03 | 포화 때 자리를 만들려고 지우는 방식 | 비채택: 포화면 업무 접수를 거부하고 용량 부족을 알린다 |
| 04 | append 순간 peak 8,276,932 B | 비채택: 숫자는 확정값이 아니다 — 총 cap 8 MiB 도 격리 시험 후보값 |

수치(총 cap 8 MiB · 예약 532,480 B · segment 64 KiB 등)는 **후보값**이다. 정본은 「숫자 확정·실측 PASS 아님」을
명시하므로 이 표는 수치를 확정값으로 쓰지 않고, 기대 낱말과 관측 대조로만 판정한다.

## 재생 검사

```
FT20_BYZ_REPO=<BYZ 저장소 절대경로> python3 ft2/contracts/cap/replay_check.py
```

검사 6: A 사례 수·id · B 칸·결과 낱말 · C 관측 1:1(44키) · D 수치는 «후보값» 표식 · E 미처리 삭제 기대 0 ·
F 낱말↔관측 결속.

## F 낱말 결속 — 결과 낱말이 그 사례 관측으로 뒷받침된다 (DA R1 보정)

DA R1(쪽지 278002) 지적: 포화 거절을 «접수 성공» 으로 바꿔도 43키 대조가 PASS 였다. 낱말이 관측과 결속되지 않았기 때문이다.
그래서 낱말마다 뒷받침 관측을 못박았다. 결속이 없으면 rc≠0 이다.

| 낱말 | 결속 규칙 (사례 관측 대조 안에서) |
|---|---|
| 회수 결과 | 어떤 trace 의 `seg_unlink` > 0 (실제로 지운 segment 가 있다) |
| 복구 필요 | 어떤 trace 의 `restart/recover_use_recount` > 0 (재기동 복구가 예약을 썼다) |
| 용량 부족 | 어떤 trace 의 `max_total / cap ≥ 0.9` (포화 근접) — 그 trace 의 `cap` 관측이 있어야 한다 |
| 접수 성공 | 어떤 trace 의 `journal_append_rows` > 0 (기록이 실제로 append 됐다) |

이 규칙으로 DA R1 변이를 다시 재현하면 rc=1 이다: 포화 사례를 «접수 성공» 으로 바꾸면 case_03 에
`journal_append_rows` 관측이 없어 F 가 FAIL 한다(반대 방향 «회수 결과»→«용량 부족» 도 FAIL).
원자료를 못 읽으면 rc 3(no silent fallback) — 빈 표로 통과하지 않는다.

## 알려진 한계

- 실 디스크 포화·전원 손실은 정본대로 미시험이다(격리 모형 관측만 있다).
- 이 표는 시험 자료다. 제품 cap 구현·수치 확정은 PR② 의 몫이고, 이 표 통과가 제품 완료는 아니다.
