# r879 — 나노 sparse 가 남의 카드 증거 폴더·wav 를 꺼내지 않는다

## r3b (arch 149 보강 반송 · REWORK-r879-r3b · DA 전 반송 = 보류 횟수에 안 셈)
- 반송 사유: r3 제외량 120.9M = 목표(r2 판 665.5M 의 90% = 599M) 미달. 큰 글자 `result.json`(v65 팀 폴더 475.6M)·`*.jsonl`(67M)이 원인 — 미디어만 빼서는 안 찼다.
- 고침(구조 그대로 · 이름 규칙 3줄만 추가): `sparse_patterns` 의 미디어 루프 뒤에 `for _j in result.json '*.jsonl' '*.JSONL'` — `!/design/teams/<팀>/**/result.json` · `**/*.jsonl` · `**/*.JSONL`. 카드 글자 파싱은 그대로 0(되살리지 않음) · 허용 순서 그대로(`fixtures/**` → 자기 카드 stem 폴더가 «맨 뒤»).
- 결과 계약 ⓗ(남의 stem 폴더 result.json·x.jsonl·y.JSONL = OUT · 같은 폴더 summary.json = IN) · ⓘ(자기 stem 폴더 result.json·x.jsonl = IN + 새 파일 add rc0) 시험 추가 · 변이 2종: `result.json·jsonl 줄 제거` → ⓗ FAIL · `자기 stem 허용을 맨 앞으로` → ⓘ FAIL(둘 다 실제 FAIL 확인).
- negative control(빨강): 새 시험을 r3 판 bin(`cd1e2a31` · `r3b-red.txt`)에 돌리면 **딱 ⓗ 한 칸만 FAIL** — 나머지 9칸은 r3 그대로 통과.
- 시험 12 PASS(ⓐ ⓑ ⓒ ⓓ ⓔ ⓓ' ⓑ' ⓗ ⓘ ⓖ + 변이 2) · 기존 nano-spawn 시험 8종 PASS · `test_finished_cleanup_auto` PASS · kit 짝 cmp0 · 버전 1.1.255 그대로(같은 커밋 --amend).

### ★r3b 디스크 실측 = 목표 통과(99.7%)★
| 규칙 | IN | OUT(제외) | 제외율 |
|---|---|---|---|
| r3(미디어만) | 13679 파일 704.0M | 120.9M | 14.7% |
| **r3b(미디어 + result.json + jsonl)** | **13475 파일 161.2M** | **663.7M** | **80.5%** |
| r2 판(evid* 폴더 통째) | 10696 파일 159.4M | 665.5M | 80.7% |
- 실측 방법·기록 = `measure-r3b.txt`(`git sparse-checkout check-rules --no-cone` · 실제 체크아웃 0 · BYZ 44f807e3d0 · v65 팀 폴더 tracked 14250 파일 824.9M · r3 와 같은 트리). 663.7M = r2 판의 **99.7%** · 목표 599M 통과 · arch 추정치 663.7M 과 일치.

## r3 (DA⑥ r2 HOLD 2 · 하드 룰 14 재설계 · REWORK-r879-r3)
- 베이스: origin/main `fd3125e1`(r959 · 1.1.254) → `1.1.255`. ★origin/main 의 `sparse_patterns` 는 r444 판(자기 팀 폴더 통째)이었다★ — r879 r1·r2 는 착지 전이라 main 에 없고, r3 는 r444 판 위에 다시 올렸다(1커밋).
- 고침 1: `sparse_card_evidence()` 삭제 — 카드 본문 «글자에서 허용 경로를 뽑는» 길 전체를 없앴다(DA⑥ r1·r2 반례가 둘 다 여기서 샜다). `sparse_patterns` 는 이제 카드 파일을 안 읽는다($2 는 옛 호출 꼴 호환용).
- 고침 2: `!/design/teams/<팀>/**/evid*/` 폴더 통째 제외 삭제 → 자기 팀 폴더 안 «미디어 확장자»만 제외(wav mp3 m4a flac ogg mp4 webm mov png jpg jpeg gif zip tar gz tgz · 대소문자 두 벌). 글자 파일(md·txt·json)은 남긴다.
- 고침 3: `fixtures/**` 허용 그대로 · 자기 카드 stem 폴더 `design/teams/<팀>/evidence/<slug>/**` 는 맨 뒤에서 통째 허용(미디어 포함 · 나중 줄이 이김).
- 시험 재작성(단언을 IN/OUT 으로): ⓐ 미디어 OUT(wav·대문자 MP4·png·zip) · ⓑ 같은 폴더 글자 IN(md·txt·json) · ⓒ 카드 글자 0 이어도 결과 같음(파싱 없음) · ⓓ 자기 stem 폴더 wav IN+새 wav add rc0 · ⓔ fixtures wav·mp4 IN · ⓕ 남의 팀 OUT · ⓖ FT_NANO_SPARSE=0 전체 · ⓑ'·ⓓ' add 경계
- 변이 2종(python 정규식 · 적용 자체를 단언): 확장자 줄 제거 → ⓐ FAIL · 자기 카드 허용 줄 제거 → ⓓ FAIL
- 짝 사본 `harness/kit/fable-team/bin/ft-nano-spawn.sh` cmp0 · 기존 시험 `test_finished_cleanup_auto` ⓖ 기대값만 r3 로 갱신(글자 증거 IN · 남의 카드 증거 미디어 OUT)

### ★r3 디스크 실측 = 목표 미달 (REWORK §3 목표 90% · 실측 17.9%)★
`git sparse-checkout check-rules --no-cone`(실제 체크아웃 0 · BYZ 44f807e3d0 · v65 팀 폴더 tracked 14250 파일 824.9M):

| 규칙 | IN | OUT(제외) | 제외율 |
|---|---|---|---|
| r3 구현(미디어 확장자만) | 13679 파일 704.0M | 120.9M | 14.7% |
| r2 판(evid* 폴더 통째 + 카드 글자) | 10696 파일 159.4M | 665.5M | 80.7% |
| 제안(r2 − 카드 글자 파싱) | 10696 파일 159.4M | 665.5M | 80.7% |

- 원인: 656M 로 잡혔던 «증거» 의 대부분은 미디어가 아니다 — v65 팀 폴더의 `result.json` 합계가 **475.6M**, 미디어 확장자는 팀 폴더 전체 125.6M(그중 evidence 안 111.6M)뿐이다. 미디어만 빼면 큰 글자 파일이 그대로 남는다.
- 그래서 REWORK §3 의 «r1 제외량의 90% 이상 유지» 는 이 규칙으로 성립하지 않는다(120.9/665.5 = 17.9%). REWORK §5 가 «jsonl 같은 큰 글자 파일 = 범위 밖» 으로 둔 그 몫이 곧 이 차이다.
- 재설계 제안(arch 판단): r2 판에서 «카드 글자 파싱만» 빼면 반례(r1·r2)는 사라지고 제외량은 그대로다(위 3행 = r2 와 같은 665.5M · 이 트리에서 손실 0). 즉 «폴더 통째 제외 + 자기 카드 stem 폴더만 허용» 이 두 목적을 동시에 만족한다.

## r1 · r2 (기록)

## 바뀐 것 (ft-nano-spawn.sh · 키트 사본 cmp0)
- 자기 팀 폴더 안에서 `evid*` 폴더(evidence/ · evidence-* · evid-*)와 `*.wav` 제외 · `fixtures/` 는 유지(wav 포함)
- 허용 줄: 자기 카드 증거 `design/teams/<팀>/evidence/<slug>/**` + 카드 본문이 적은 «자기 팀» 증거 폴더(남의 팀 경로는 안 꺼냄)
- 카드에 증거 경로가 0 이어도 rc0(pipefail 아래 grep rc1 → sparse 실패 길 막음 · 시험 ⓑ')
- SPARSE 출력 줄에 새 증거 위치 + `git sparse-checkout add <폴더>` 안내

## r2 (DA⑥ r1 HOLD 1 · REWORK-r879-r2)
- 반례: 카드가 evidence/ 바로 아래 «파일»을 적으면(ops-alert-gchat-sink 카드 · design/teams/ops/evidence/INVENTORY-server-alerts-20261024.md) 정규식이 폴더만 뽑아 그 파일이 sparse 밖 → 새 파일 git add rc1
- 고침: evidence/ 아래 경로를 파일·폴더 둘 다 뽑음 — 끝 / 있음 = 폴더 `**` · 없음 = 그 경로 1줄 · 문장 끝 마침표는 뗌
- 실 카드 대조(BYZ origin/main ops-alert-gchat-sink.md): 패턴 끝줄 `/design/teams/ops/evidence/INVENTORY-server-alerts-20261024.md` 생김
- 시험 칸 추가: ⓑ 카드가 적은 evidence/ 바로 아래 파일(있는 것 체크아웃 · 새 것 git add rc0 · 마침표) — 고치기 전 FAIL(red) → 후 PASS
- 변이 추가: 파일 경로 추출 제거(`/?` → `/`) → 그 칸 FAIL
- 버전: main 4d8704c3(r886 · 1.1.232) 위로 옮겨 1.1.233

## 실측 (BYZ HEAD 5a5f5ddd13 트리 · `git sparse-checkout check-rules` · 실제 체크아웃 0)
| 나노 | 전 | 후 |
|---|---|---|
| v65 (카드 M5-1812) | 35478 파일 1020.1M | 31928 파일 355.7M (−664M) |
| harness | 21447 파일 197.5M | 같음 (팀 폴더 비어 있음 — 나머지는 범위 밖: design/evidence 40M · clients 41M · tests) |
- v65 fixtures wav 2개 유지 (design/teams/v65/fixtures/*)

## 시험 (test-run.txt)
- test_nano_spawn_sparse_evidence_r879.sh ALL PASS (ⓐ ⓑ ⓑ' ⓒ ⓔ변이 2종)
- 기존 nano-spawn 시험 7개 ALL PASS · test_finished_cleanup_auto ⓖ 기대값 갱신(남의 카드 증거 없음) PASS
- 기존 실패(이 카드 무관 · origin/main c059ddd1 에서도 같은 결과):
  - test_finished_cleanup_auto ⓒ — `ERROR tmux unreadable` (가짜 tmux 픽스처)
  - test_nano_spawn_teamset_cap ⓐ~ⓓ 7건 — `REJECT 전팀 정지 중(상태 폴더 없음 …)` (픽스처에 .fable-team/state 없음)

## 범위 밖
- 이미 있는 워크트리 줄이기 · 팀 워크트리(r881) · land 사본(r880) · design/evidence(팀 밖 · 시험 1개가 읽음)

## r4 (DA⑥ r3 HOLD 2 · REWORK-r879-r4 · 패턴 «글자 꼴» 손글자 0)
- 반례 2(DA 원문 · r3b 판 ft-nano-spawn.sh): ① `design/teams/lecture/evidence/other.wav/note.md` · `…/summary.json` 이 OUT(`*.wav` 가 «.wav 로 끝나는 폴더» 까지 뺀다 · git add rc1) ② `core.ignorecase=false` 에서 `other/a.WaV` · `other/b.PnG` 가 IN(소문자·대문자 «두 벌» 만 있어 섞인 대소문자를 놓친다)
- 고침 1 — `sparse_ext_glob()` 하나가 확장자 글자마다 대소문자 묶음을 만든다(`wav` → `[Ww][Aa][Vv]`) · 미디어 16종 + `result.json` + `.jsonl` 전부 이 함수를 지난다 · 손글자 패턴 0(두 벌 tr 루프 삭제)
- 고침 2 — `sparse_pair()` 가 `제외 줄` 바로 뒤에 «폴더 전용» 되살림 줄(끝 `/`)을 둔다 → 이름이 확장자로 끝나는 폴더(`other.wav/`)는 다시 IN, 그 안 미디어(`other.wav/x.wav`)는 제외 줄이 그대로 잡는다
- 허용 순서는 r3b 그대로: … 제외 짝들 → `fixtures/**` → 자기 카드 stem `evidence/<slug>/**`(맨 뒤 = 통째)
- 시험 칸 추가: ⓚ `other.wav/note.md`·`summary.json` IN(git add rc0) · `other.wav/x.wav` OUT · ⓛ `a.WaV`·`b.PnG`·`Result.JSON`·`x.JsonL` OUT · ⓐ'ⓑ' `core.ignorecase=false` 에서도 같은 판정(실제 git `sparse-checkout set --no-cone` + 체크아웃으로 IN/OUT 단언)
- ★측정 주의(실측)★ 기본 `core.ignorecase=true` 에서는 git 이 대소문자를 무시해 ⓛ 만으로는 r3b 판을 못 가른다 — r3b 판으로 새 시험을 돌리면 ⓛ 은 PASS, ⓐ'ⓑ' 만 FAIL(r4-red.txt). 판별 칸은 ⓐ'ⓑ' 다.
- 변이 2종 추가(전 4종 유지 = 6종): «폴더 되살림 줄 제거» → ⓚ FAIL · «대소문자 소문자 한 벌로 되돌림» → ⓐ'ⓑ' FAIL (둘 다 실제 FAIL 확인)
- 세트: 같은 squash 에 `--amend` 1커밋(버전 1.1.255 유지 · push 0) · 키트 짝 사본 `harness/kit/fable-team/bin/ft-nano-spawn.sh` cmp0
- 디스크(measure-r4.txt · `check-rules --rules-file` · BYZ 44f807e3d0 · 실제 체크아웃 0): v65 824.9M 중 OUT 663.7M(80.5%) = r3b 판의 100.0% · 목표 599.0M 통과 — 폴더 되살림 줄을 더해도 v65 트리에 «확장자로 끝나는 폴더» 가 없어 증감 0
- 기존 nano-spawn 시험 8종 전부 rc0(body_press 31P · search_roster 26P · pi_effort_kind 65P · pi_effort_serena 50P · recheck_cited 11P · reuse_info 24P · teamset_cap 18P · tier 43P) · `test_finished_cleanup_auto` ⓒ 1건만 FAIL(`ERROR tmux unreadable` — origin/main 판과 같은 base 실패 · 이 카드 무관)

## r5 (하드 룰 14 보류 3회 재설계 · REWORK-r879-r5 · 제외 규칙 = 실재 파일 literal)
- 왜 «고침» 이 아니라 «구조»: 제외 규칙을 만드는 줄이 전부 «사람이 쓴 glob 글자»였다. 글자 규칙은 git 의 매칭 규칙(폴더/파일 · 대소문자 · 되살림 순서)에 기대므로 입력 꼴마다 새 반례가 났다(r3 두 꼴 · r4 두 꼴). 제외 대상을 «git 이 아는 실재 파일 이름 그대로» 적으면 기댈 규칙이 없다.
- 고침 1 — `sparse_exclude_lines()`: `git ls-tree -r -z --name-only <BASE_BRANCH> -- design/teams/<팀>` 로 실재 경로를 받아 python 이 ①이름 끝 확장자를 **소문자로 바꿔** 미디어 16종과 비교 ②`result.json` · 끝 `.jsonl` 비교 → 맞는 «파일» 마다 `!/<경로>` 1줄. 폴더는 판정 대상이 아니다(이름이 `.wav` 로 끝나는 폴더 안 글자는 IN).
- 고침 2 — 이스케이프 1규칙(gitignore): `\` `!` `*` `?` `[` `]` `#` 앞에 `\` · 공백은 `\ `. `sparse_ext_glob()` · `sparse_pair()`(폴더 되살림 줄) 삭제 — 실재 파일만 빼므로 폴더 오인이 없다.
- 고침 3 — 순서 고정: 머리 3줄 → 제외 N줄 → 되살림 2줄(`fixtures/**` · 자기 카드 `evidence/<슬러그>/**`). gitignore «뒤 줄이 이김» 한 규칙만 쓴다.
- 계약 ③(새 파일): 트리에 없는 파일은 제외 줄에 없다 → 나노 자기 산출 `git add` rc0. r4 판은 glob 이라 «새 wav» 도 막았다(r5-red.txt ⓨ5').
- ★REWORK 문구와 다른 점 1개(실측 근거)★ REWORK 는 경로 출처를 `git ls-files` 로 적었다. 실측(2026-10-27) ① `worktree add --no-checkout` 직후 그 워크트리의 index 는 비어 있다(`ls-files` 0줄) ② `$ROOT` 의 index 는 ROOT 가 «체크아웃한 가지»의 것이라 BASE_BRANCH 와 다르다(base 에만 있는 파일이 빠졌다). ⇒ 트리(commit)에서 뜨는 `ls-tree -r <BASE_BRANCH>` 를 썼다. «실재 파일 이름 그대로» 라는 계약 ①의 뜻은 그대로다.
- 시험 칸 추가: ⓨ1 `other.wav/` 안 글자 IN(add rc0)·그 안 미디어 OUT · ⓨ2 섞인 대소문자 OUT(소문자 비교) · ⓨ3 `my report.md`·`INV(final).md` IN / `my song (final).WAV`·`weird[1].png` OUT(이스케이프) · ⓨ4 evidence 바로 아래 md IN·자기 카드 clip.wav IN·남의 카드 big.wav OUT · ⓨ5 규칙 줄 수 = 머리3+제외N+되살림2(실측 42=3+37+2)·새 wav/jsonl add rc0 · ⓨ6 미디어 15확장자 + 대문자 MP3·FlAc OUT
- 변이 4종(r5): «소문자 비교 삭제» → ⓨ2 FAIL · «이스케이프 삭제» → ⓨ3 FAIL · «파일/폴더 구분 없이 glob»(r3 판) → ⓨ1 FAIL · «되살림 줄을 제외 줄 앞으로» → ⓨ4 FAIL (전부 실제 FAIL 확인)
- r5-red.txt = 판 대조: r4(897a3293) 판 bin 에 새 시험 → ⓨ5'·ⓨ5 2칸 FAIL(나머지 PASS) — 새 시험이 r4 를 «구조» 로 가른다.
- 디스크(measure-r5.txt · `check-rules -z --no-cone --rules-file` · BYZ 44f807e3d0 · 실제 체크아웃 0): v65 824.9M 중 IN 13475 파일 161.2M · OUT 775 파일 663.7M(80.5%) = r3b·r4 판의 100.0% · 목표 599M 통과. 규칙 787줄 = 머리 3 + 제외 782 + 되살림 2 · 제외 782 vs 실제 OUT 775 = 7 파일이 되살림 줄에 다시 살아난 몫(«뒤 줄이 이김» 실측 확인).
- 기존 nano-spawn 시험 8종 전부 rc0(body_press · search_roster · pi_effort_kind · pi_effort_serena · recheck_cited · reuse_info · teamset_cap · tier) · `/bin/bash` 3.2 rc0 · 키트 짝 사본 cmp0
- 세트: 같은 squash 에 `--amend` 1커밋(버전 1.1.255 유지 · push 0 · 가지 `nano/r879-nano-spawn-sparse-exclude-evidence--r2`)

## r6 — DA⑥ r4 반례 1건(«파일명 속 개행»)만 고침 (REWORK-r879-r6.md · 2026-10-27)

- 반례(DA 원문 · da-20261026-230506-10132.out): `other/line\nbreak.wav`(이름 안 실제 개행) 는 IN(기대 OUT) · `other/line/note.md` 는 OUT(기대 IN). 원인 = 제외 규칙이 «줄 단위» 인데 이름 안 개행을 그대로 내보내 `!/…/other/line` + `break.wav` 두 줄로 갈라지고, 첫 줄이 `line/` 폴더를 통째 제외했다.
- 고침 1곳: `sparse_exclude_lines()` 의 이스케이프 루프에 제어 문자 갈래 1개 — 글자가 `\n` `\r` 또는 그 밖 제어 문자(`ord < 0x20` · `0x7f`)면 그 «한 글자» 를 `?`(gitignore 한 글자 와일드카드 · `/` 는 안 맞음) 로 적는다. 그 밖 글자는 r5 그대로(`\` `!` `*` `?` `[` `]` `#` · 공백). 머리 3줄·되살림 2줄 그대로.
- 계약 ①'(REWORK): 제외 줄은 실재 파일 이름 그대로이되 이름 안 제어 문자는 글자 하나당 `?` 한 글자 — 그 자리 한 글자만 대신하므로 폴더를 제외하지 않는다. 같은 폴더에 «그 자리만 다른 이름» 의 다른 미디어 파일이 있으면 함께 제외될 수 있다(계약 아님 · 실측 0).
- 시험 칸 추가: ⓨ7 DA 반례 그대로(`line\nbreak.wav` OUT · `line/note.md` IN · `line\nnote.md` IN · 규칙 줄 중 «/* 도 !/ 도 /design/teams/ 도 아닌 조각» 0) · ⓨ7' 트리에 없는 개행 이름 새 글자 파일 `git add` rc0 · ⓨ8 `tab\there.mp3`·`cr\rhere.png` OUT · 같은 폴더 `tab/x.md` IN
- ⓨ5 줄 수 계산을 줄 단위 grep → `ls-tree -z` + python 파일 세기로 바꿨다(개행 이름에서 인용부호·줄 갈라짐에 속지 않게). 값 = 머리3 + 제외40 + 되살림2 = 45.
- 변이 5종(기존 4 + «제어 문자 갈래 삭제» → ⓨ7 FAIL). 변이 하네스에 «MUT NOT APPLIED 면 실패로 센다» 가드 1줄 추가(변이 미적용이 통과로 새던 길).
- 음성대조(r6-red.txt): 새 시험을 r5 판 bin(54393c91)에 → ⓐ·ⓨ5·ⓨ7 3칸 FAIL(나머지 PASS) · r6 판 = 27 PASS ALL PASS(test-run.txt).
- 디스크(measure-r6.txt): 같은 rev·같은 카드로 만든 규칙이 r5 판과 `diff` 0(787줄 bit 동일) · IN 13475 파일 / OUT 775 파일(80.5%) · 목표 599M 통과. 실재 트리 design/teams/v65 14250 파일 중 이름 안 제어 문자 = 0, `?` 충돌 후보 = 0.
- 기존 nano-spawn 시험 8종 전부 rc0(body_press 31P · search_roster 26P · pi_effort_kind 65P · pi_effort_serena 50P · recheck_cited 11P · reuse_info 24P · teamset_cap 18P · tier 43P) · `/bin/bash` 3.2 rc0 · 키트 짝 사본 `harness/kit/fable-team/bin/ft-nano-spawn.sh` cmp0
- press 필요: 없음(라이브 오디오 무관 · 단위·픽스처 시험만)
- 세트: 같은 squash 에 `--amend` 1커밋(버전 1.1.255 유지 · push 0 · 가지 `nano/r879-nano-spawn-sparse-exclude-evidence--r2`)
