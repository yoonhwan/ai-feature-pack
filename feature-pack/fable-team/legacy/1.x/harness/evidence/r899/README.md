# r899 팀 폴더 이동 뒷정리 — 증거 지도

| 파일 | 무엇 |
|---|---|
| 00-verify-real-oldtool.txt | 고치기 전 옛 도구 `--verify --all` 실측 원문(VERIFY ERR=2753 WARN=465 · 카드 기준값 2749 와 4 차이 = 그 사이 새 좌석) |
| 01-classify-real.txt | 새 도구 `--classify --all` 실 리포 읽기 전용 원문(CLS 줄 + 끝줄 CLASSIFY) |
| 02-verify-real-newtool.txt | 새 도구 `--verify --all` 실 리포 읽기 전용 — 좌석 칸이 카드 워크트리·팀 루트도 보므로 ERR 2753 → 2019 (나머지 대부분 = 닫힌 좌석 기록, 보관 대상) |
| 03-rehearsal-copy.txt | 실 명부·nano-card-base «사본»에 계획→plan.sh 실행→verify→되살림. 보관 2302 · 다시 씀 14 · verify ERR 46 · 되살림 2316 → 사본 = 실 원본 바이트 동일(DIFF 0) |
| 04-plan-table.tsv | 리허설 계획 표(분류·팀·저장소·좌석·옛 경로·사유) |
| 05-classify-byz-branch-code.txt | BYZ 가지(실행 경로 12파일 고침 + design/TEAM-MOVE-ALLOW.tsv) 기준 코드 칸 — v65·ops·harness CODE-RUN 0, 픽스처 7 = 허용 목록(사유) |
| 07-verify-r2-old-sameplace.txt | r2 비교 «前» — r1 도구(같은 자리 · BYZ 메인 루트) `--verify --all` → ERR=2020 WARN=877 |
| 08-verify-r2-new-sameplace.txt | r2 비교 «後» — r2 도구(같은 자리 · 같은 루트) → ERR=2019 WARN=878 · 차이 = 1줄 `clients/web/__tests__/fixtures/v65-owner-source-join.ts`(허용 목록이 코드 확장자에 효력 0 → RUN 아님(NOTE) = ERR→WARN) |
| 09-cas-window.txt | r4 — «남는 창»(B2 읽기 → os.replace) 을 run 이 실제 부르는 경로에서 20회: med 11µs · p95 19µs · max 19µs (r3 의 cas_write 단독 200회 값은 폐기) |

## r2 (DA⑥ r1 HOLD 5 반례) — 무엇을 고쳤나

| 반례 | 고침 | 시험 |
|---|---|---|
| 1 tmux 생존 재확인 | `--cleanup-run` 이 파일 잠금을 «전부» 먼저 집고(못 집으면 쓰기 0) 잠금 안에서 tmux 목록 1회(행마다 0) | ⓖ 잠금 REJECT·죽은 잠금 회수·tmux 호출 = 파일 수 |
| 2 계획 두 번 읽기 | `plan_path.read_bytes()` 1회 → 그 바이트로 sha 대조 + 파싱 | ⓖ probe(Path.read_bytes/read_text 계수) plan_bytes=1 plan_text=0 |
| 3 분류·지문 따로 읽기 | `--classify`가 읽은 행에서 `row_sha` 를 같이 만들고, `--cleanup-plan` 은 다시 읽지 않는다 · `--cleanup-run` 은 잠금 안 재읽기 1회 | ⓖ probe roster_text=1 · 계획 뒤 행이 바뀌면 SKIP |
| 4 되살림 판정 | archive.json 에 «다시 쓴 뒤 행 전체 지문»(new_row_sha) → 되살림은 그것이 그대로일 때만 | ⓖ 다른 칸이 바뀌면 SKIP 「다시 쓴 뒤 또 바뀜」 |

## r3 (DA⑥ r2 HOLD · 재설계) — 잠금이 아니라 «교체 직전 비교(CAS)»

r2 전제(«잠금 안에서 잘 확인하면 안전»)는 틀렸다 — 명부를 쓰는 다른 도구(ft-nano-spawn·ft-role-spawn·ft-seat-retire)는 이 잠금을 모른다. 안전은 **쓰기 직전 비교 후 교체(CAS)** 에서 나온다.

| 고침 | 무엇 | 시험 |
|---|---|---|
| CAS 교체(run·restore 공통) | B1 = 판정에 쓴 바이트의 sha → tmp 쓰기·fsync → **교체 직전 B2 다시 읽기** → sha(B2)≠B1 이면 교체 0 · tmp 삭제 · 그 파일 「바뀜 — 다시 실행」 SKIP(rc1 · 다른 파일은 계속 · 재시도 0) | ⓗ 동시 쓰기(run) · ⓘ (restore) |
| rename 잠금 | pid 를 먼저 쓴 `<잠금>.tmp.<pid>` → `os.rename` 으로 잠금 이름에 올림(빈 잠금 폴더 창 0) · 회수 실패를 포함해 **반복 어느 지점에서든** 5초를 지나면 REJECT · 잠금은 집자마자 해제 목록에 | ⓙ 빈 창 0 · 회수 영구 실패 → 5~7초 REJECT · pid 쓰기 실패 → 잔류 0 |
| tmux 순서 | (r4 로 대체됨 — 아래 r4 절) r3 는 B2 뒤 tmux · 2판 루프 → B2~교체 사이에 일이 끼었다 | 기존 ⓑ SKIP 칸 유지 |

**남는 창**(B2 읽기 → os.replace) 실측 = `09-cas-window.txt`(r4 재측정). 이 창은 **범위 밖 · 수용**이고, 완전한 닫기 = spawn 계열이 같은 잠금을 잡는 **별 카드**(arch 등록).

## r4 (DA⑥ r3 HOLD · «설계 순서와 구현 순서가 다름») — 파일당 순서를 의사 코드 그대로

r3 구현은 B2 비교와 교체 «사이» 에 tmux 조회·보관 기록 쓰기·copymode 를 넣어, tmux 대역이 그 사이에 쓴 새 행이 유실됐다. 고침 = 파일 하나당 이 순서만:

```
B1 읽기 → tmux 조회(실패 = 그 파일 SKIP rc1 · tmp 전) → 계산(순수 · I/O 0) → tmp 쓰기·fsync·copymode
→ B2 재읽기(다르면 tmp 삭제 · SKIP rc1) → os.replace «바로 다음 줄» → 교체된 파일만 archive.json 에 기록
```

| 반례 | 고침 | 시험 |
|---|---|---|
| 1 B2~replace 사이 tmux·archive 쓰기·copymode | tmux 는 B1 뒤 «tmp 만들기 전» · copymode 는 B2 앞 · 보관 기록은 교체 «뒤» · tmux 2판 루프 삭제 | ⓚ tmux 조회 도중 새 행 → 그 파일 교체 0 · 기록 0 · tmp 0 · rc1 / 변이9 |
| 2 restore 행 단위 교체 · 기록 파일 되살림이 «있나 검사 → 덮어씀» | 같은 파일의 «다시 쓴 칸 되돌리기 + 보관 행 넣기» 를 1번 교체(`restore_file`) · 기록 파일은 `os.link`(없을 때만 만들기 — 덮어쓰기 0) | ⓛ 같은 파일 2행 · 첫 fsync 때 새 행 → 둘 다 그대로 · rc1 / 변이10 · ⓜ 경쟁 새 파일 → 덮어쓰기 0 · rc1 |
| 3 둘째 파일 교체 거부 시 기록·tmp | 교체 실패(OSError)도 그 파일 SKIP rc1 · 교체된 파일만 기록 · tmp 는 `finally` 로 항상 삭제 | ⓝ 둘째 파일 PermissionError → 기록은 첫 파일만 · tmp 0 / 변이11 |

고치기 전 바이트는 `archive 폴더/orig/<sha12>-<파일>` 에 교체 «앞» 에 남긴다(교체 뒤 기록 쓰기 전에 죽어도 사람이 되살릴 길 · 지우기 0).

★범위 밖으로 넘기는 3★: ① spawn 계열 도구가 명부 잠금을 잡게 하는 일(별 카드) ② CAS 비교와 os.replace 사이 남는 창(위 실측) ③ tmux 조회 뒤 열린 좌석의 보관(지우기 0 · `--cleanup-restore` 로 되살림).
| 5 분류 정규화 | 경로 앞 `./` · 따옴표 안 앞뒤 공백을 지운 뒤 판정 · 허용 목록은 코드 확장자(.py .sh .ts .tsx .js)에 효력 0 | ⓖ `./design/x/…`·`"  design/x/…  "` → CODE-RUN · 허용 목록에 있어도 코드 파일 = ERR |

변이 5개(각 고침을 끄면 그 칸이 빨강) = 시험 ⓖ 마지막 절.

★잠금 실측★: 반송서의 «ft-nano-spawn·ft-role-spawn 이 명부를 쓸 때 잡는 그 잠금» 은 **없다**(둘 다 seats*.json 을 잠금 없이 · tmp 교체도 없이 직접 쓴다). 이 카드는 `<파일>.lock.d`(mkdir + pid · 죽은 pid 회수 · 상한 5s)를 **새로** 만들었고, 그 둘은 아직 이 잠금을 안 잡는다.
⇒ **보관 행은 «되살림» 으로 되돌아온다**(지우기 0) · 그러나 **동시에 다른 도구가 그 파일을 바꿨다면 교체 자체를 하지 않는다** — 그 파일은 SKIP 「바뀜 — 다시 실행」 이고 사람이 다시 돌린다(덮어쓰기 0 이므로 새 좌석 행이 유실되지 않는다).

★측정 주의★: 이 워크트리(sparse)에서 `--verify --all` 을 돌리면 자기 팀 밖은 `SPARSE-HIDDEN` 이라 셈이 안 된다(실측 ERR=295 = harness 만). 그래서 07·08 은 **BYZ 메인 루트**에서 쟀다.

## master/오빠 실행 (명부 쓰기 = 이 두 줄만)

```
bash <LIVE_BIN>/ft-team-move.sh --cleanup-plan --all --out <폴더>    # 계획만 · 쓰기 0
bash <폴더>/plan.sh                                                 # 보관(지우기 0) · 실행 시점 tmux 재확인 · 끝줄 archive=<…>/archive.json
bash <LIVE_BIN>/ft-team-move.sh --cleanup-restore <archive.json>    # 되살리기 1줄
```

## ⓔ 못 줄이는 남은 것 (리허설 뒤 ERR 46 → BYZ 가지 착지 뒤 예상 25)

| 묶음 | 수 | 사유 | 누가 |
|---|---|---|---|
| v65·ops·harness 코드 옛 경로 | 21 | BYZ 가지 nano/r899-team-move-cleanup-stale-paths 에서 고침(실행 경로 14 → 새 경로 · 픽스처 7 → 허용 목록) — 착지 전이라 main 에서는 아직 ERR | master 착지 |
| 살아 있는 좌석 LIVE-HAND | 11 | 좌석은 살아 있는데 옮긴 경로에 카드 없음 — inbox 폴더(빈 폴더 · git 미추적) 또는 막 열린 나노의 진행/ 카드가 명부 기준 워크트리에 아직 없음. 상태 폴더 이동은 spawn·close 와 겹쳐 자동으로 따라가지 않는다 | 그 팀 master(명부 손 정리) |
| 닫힌 역할 좌석 KEEP-LINEAGE | 16 | 계보 최댓값 행 — ft-role-spawn.sh:83 가 «tmux + 명부 키 최댓값 + 1» 로 다음 번호를 매겨 빼면 번호 재사용 · 옛 index 의 새 경로도 없음 | 남김(번호 기준) |
| feature map-lint | 1 | feature 팀 지도 린트 ERR 1(이동 도구 밖) | feature |
| ccu 코드 옛 경로 (BYZ 가지 base 기준) | 131+8 | ccu 팀이 막 design/teams/ccu/ 로 옮기는 중(6d5fcfcf2d) — 그 팀 이동 단위 몫 · 이 카드 범위 밖 | ccu |
| BYZ `scripts/debug/m6_gpu0_live_contrast.py:94` timeout 90초 | 1 | 이 카드 밖(경로 이동과 무관한 타임아웃 값) — r899 r2 반송 ⑦ | v65 |

press 필요: 없음(오디오 경로 0).
