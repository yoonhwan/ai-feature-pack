# r465 — master 단계 (나노 산출 · 실행 0)

1. 팩 PR: 가지 `nano/r465-seat-retire-sync-role-cells-across-` push → PR (나노 push 금지) → 병합 `gh pr merge <N> --match-head-commit <가지 HEAD 40자>`.
   가지 = origin/main(339117c5 · r486·r492 착지 뒤) 위. CHANGES 머리 + manifest 1.1.51 은 이 가지에 넣었다 — 다른 가지가 먼저 착지하면 번호만 다음으로 올린다.
   파일 = bin·kit 짝(cmp 0) 2: `ft-seat-retire.sh` · `ft_roster_lib.py` (+ 시험 `test_seat_retire_rosters.sh` r465 절 · `test_seat_retire.sh` 기대값 3 · CHANGES · manifest).
2. 되돌림 준비(설치 전): `cp -p <LIVE_BIN>/ft-seat-retire.sh{,.bak-r465}` · `cp -p <LIVE_BIN>/ft_roster_lib.py{,.bak-r465}`. 명부는 도구가 쓸 때마다 `.bak-retire-<ts>` 를 남긴다.
3. 착지 뒤 `bash <팩>/feature-pack/fable-team/harness/install.sh --apply --project <BYZ 루트>` → `cmp <키트>/ft-seat-retire.sh <LIVE_BIN>/ft-seat-retire.sh` = 0 · `cmp <키트>/ft_roster_lib.py <LIVE_BIN>/ft_roster_lib.py` = 0 · `ft-live-install-check.sh --range <병합 전 main>..<착지 sha>` OK.
4. 1회 보정(지금 남은 칸 · 손 편집 0): 옛 공유 좌석이 남아 있으면 `ft-seat-retire.sh <옛> <후계>` 재실행 → `FIXED … roles=[…]`(이미 은퇴 행이어도 남의 명부 칸 보정) · 빈 역할 칸은 같은 호출이 ` FILLED <명부>:<칸>`.
5. 실사건 1(닫는 증거): 다음 공유 역할 좌석 승계 1건 → 첫 줄 `RETIRED … roles=[<남의 명부>:_arch…]` + `python3 -c` 로 모든 `seats*.json` 의 «값이 <옛 이름> 인 `_*` 칸» = 0 + `ft-seat-close <옛> --reason …` 이 «현역 역할 좌석» REJECT 없이 통과 · 쪽지 번호.
   (카드의 `grep -l '<옛 이름>' seats*.json = 0` 은 은퇴 행 키(`"<옛>": {… _replaced_by …}`)가 남아 늘 1 이다 — «값이 옛 이름인 `_*` 칸 0» 으로 잰다.)
6. 뒤 일(arch 손 · 착지 뒤): `COMM-GUIDE-BOOT.md` 13 끝에 «공유 역할 좌석 승계 = `ft-seat-retire` 가 그 좌석을 가리키는 모든 명부 칸을 함께 후계로(r465 · 명부 손 편집 0 그대로)».

## 동작 요약 (카드 §구현 범위 대조)
- 1 lib: `scan_cells(p, old)` = 같은 폴더 다른 명부의 최상위 `_*` 문자열 칸 중 값 == old 전부(손상 = bad) · `apply_cells` = apply_routes 와 같은 쓰기(파일마다 `.bak-retire-<ts>` · tmp→교체) → (roles, routes) 나눔(`is_route`) · `role_cell(dd, new)` = 후계 이름 역할 토큰 칸.
- 2 retire: `:151` R282 ② «다른 명부에서 현역 → REJECT» 삭제(close 의 판정 `ft-seat-close.sh:42-45` 는 불변) · 은퇴·재실행 둘 다 scan_cells/apply_cells · 출력 `files=N roles=[…] routes=[…]`.
- 2 재실행: 이미 `_replaced_by == <후계>` 인데 남은 칸(자기·남의 명부) 또는 채울 칸 있으면 `FIXED <구> -> <후계> file=… keys=[…] files=N roles=[…] routes=[…]` · 없으면 옛 `NOOP` 그대로.
- 2a 채우기: 자기 명부 옛 이름 칸 0 · 후계 행 실재 · 역할 칸(`_master`·`_arch`·`_da`·`_tester`) "" 또는 없음 → 후계 + 첫 줄 끝 ` FILLED <명부>:<칸>` · 살아 있는(tmux has-session) 다른 좌석 = `REJECT` rc1 쓰기 0 · 죽은 다른 좌석 = 채우기 0.
- 3 close: 변경 0.

## 편차 (나노 판단 · 근거)
- ① 시험 위치: 카드는 `test_seat_retire.sh` 절 추가였지만 r465 절은 같은 계열(r429) 픽스처가 있는 `test_seat_retire_rosters.sh` 에 넣었다 — `test_seat_retire.sh` 는 ⑧ 이 선재 빨강(`test_ft_tick_master_seat.sh` rc4 · origin/main 0051effd 같은 4줄)이라 rc0 이 될 수 없다. `test_seat_retire.sh` 는 기대값 3곳(③⑨ `roles=` 칸 · ⑬ REJECT→RETIRED)만 고쳤다.
- ② ⓓ «후계 이름이 어느 명부에도 없음 → 기존 REJECT»: 지금 코드는 후계 행이 없으면 만든다(REJECT 아님). «기존 REJECT 그대로» 를 ⓓ 명부 후보 0 + 이름 lint 실패 REJECT rc1 · ⓓ' 후계 이미 은퇴 rc3 두 경로로 쟀다.
- ③ 출력: 재실행 보정은 첫 낱말 `FIXED`(NOOP 은 «바꾼 것 0» 일 때만) · 채우기는 RETIRED/FIXED 첫 줄 끝 ` FILLED <명부>:<칸>` — 둘째 줄 `RESUME …` 계약(ft-role-spawn 안내)을 지키려고 줄을 늘리지 않았다.
- ④ 옛 시험 기대값 개정: rosters ⓑ(남의 `_master` 불변 → 후계) · ⓒ'(REJECT → RETIRED) · test_seat_retire ⑨(같은 TMP 폴더 seats-b.json `_master`=M#1 도 후계 → files=2) · ⑬. 카드 계약(값 == 옛 이름인 칸 전부)의 결과.

## 시험
- 원문 `harness/evidence/r465/tests-rc.txt` · r465 사례 `r465-cases.txt`.
