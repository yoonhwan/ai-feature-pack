# Seatbelt — 하네스 운영 지침 (이 파일 하나로 시작한다) · 팩 SSOT 사본 1.0.1

> **이 파일은 fable-team 팩의 정본 사본이다.** 원본은 v65 트랙 `design/v65/SEATBELT-README.md`(BYZ-Agents 리포).
> 아래 본문의 `design/v65/…`·`ft-v65-temp-`·`@zc_v65_active`·`NANO-LEDGER-pm1-…`·`GOAL-LEDGER-v65.md` 는 **전부 v65 트랙의 «예시» 값**이다.
> 다른 트랙은 스크립트 env 로 바꾼다: `FT_NANO_PREFIX` · `FT_NANO_WT_PREFIX` · `FT_ACTIVE_TAG` · `FT_NANO_LEDGER` · `FT_GOAL_LEDGER` ·
> `FT_GOAL_LINES_FILE` · `FT_SEATBELT_README` · `FT_INBOX_ROOT` · `FT_TICK_MASTER_MSG` · `FT_TICK_PM_MSG` · `FT_SEATS_JSON`.
> 골 3줄(아래)도 v65 의 것이다 — 트랙의 골 3줄로 바꾸고 `FT_GOAL_LINES_FILE` 에 같은 3줄을 둔다.
> 템플릿: `templates/seats.json.example` · `templates/index.md.example`.

목표는 빠른 유용 원문, 실시간 교정, N언어의 병렬·독립 발행, 소실·비의도 중복 없는 최종 말풍선이다.
LST ON 우선이며 LST OFF/전환과 기존 M0–M7·통합 조건도 남긴다.
단순히 실패 사례를 많이 모았다는 이유로 실험을 닫지 않는다.

> **너는 어떤 에이전트여도 된다** — claude · codex · cmd · opencode, 어떤 모델이든.
> 이 파일을 읽고 아래 «부팅 5단계»를 그대로 하면 지금 상황을 알고, 남의 일을 이어가거나 새 일을 시작할 수 있다.
> 버전·좌석 명부의 정본은 `<리포 루트>/.fable-team/seats.json` (`_version` 필드). 설계·진행표 정본(예시: v65)은 `design/v65/20260914/DRAFT-harness-upgrade-v65.md`.

---

## 1. 원리 세 줄

1. **작업 = 인덱스 파일 1개.** `design/v65/indices/{대기,진행,완성}/<이름>.md`. 파일이 없으면 작업이 아니다. 파일 안에 골 3줄·골좌표·닫는 증거·배경·구현범위·완료조건이 «전부» 있어 누가 읽어도 착수할 수 있다.
2. **상태 = 폴더.** 대기→진행은 spawn 이 옮기고, 진행→완성은 **DA 판정문 경로가 있을 때만** 옮긴다. 「닫힘」을 손으로 쓰는 자리는 없다.
3. **좌석은 갈아 끼운다.** 한도·소실·증류로 좌석이 죽어도 **파일(인덱스·인박스·원장)이 상태**라 다음 좌석이 그 파일을 열면 이어진다. 대화 맥락에만 있는 것은 없는 것이다.

## 2. 부팅 5단계 (모든 좌석 공통 · 순서대로 · 건너뛰지 않는다)

```
① 골 대조    : 위 3줄을 읽었다. 내가 맡을 일이 어느 M?/K? 축인지 «한 줄» 적을 수 있어야 착수.
② 내 자리    : cat <루트>/.fable-team/seats.json  → 내 세션명이 있나 · role · agent · tick · index
              없으면 → 내가 «누구인지» 발주문에서 확인하고 seats.json 에 1행 등록(§5 형식)
③ 내 일      : role=nano  → seats.json 의 index 경로를 연다. 그 파일 §구현범위·§완료조건이 전부다.
              role=master/da/pm → design/v65/indices/inbox/<role>/ 를 정렬해 «맨 위» 부터.
              (inbox 폴더의 README.md 는 형식 견본이다 — 항목 파일 NN-*.md 가 없으면 발주문 + RUNLOG 최신 E 번호.)
④ 통신       : bash <루트>/.fable-team/comm/mbox.sh recv <나>   ← 내 앞 메시지 (1개 우편함만 읽는다)
              보고 = mbox send <상대> <나> "<3~5줄>"  — 알림 여부는 seats.json 이 정한다. --no-notify 쓰지 않는다. 급하면 --urgent.
⑤ 첫 보고    : master 에게 mbox 로 «세션명 / 모델·창 / Serena 가부 / ①의 골 대조 한 줄» — 이게 나가기 전엔 코드를 열지 않는다.
```

증류선: claude `[1m]` 80% · fable 70% · codex 는 auto-compact(게이지가 «남은 %»라 반대로 읽지 마라). 마무리 = 후계 pane 읽기 → 발주 send → **후계 응답 recv** → seats.json 행 교체 → 정지 레디. 하나라도 빠지면 마무리가 아니다.

## 3. 나노(작업 좌석) 생명주기

| 단계 | 누가 | 무엇 |
|---|---|---|
| 인덱스 작성 | **DA** (원인을 확정한 §N 과 같은 커밋에) | `indices/대기/<이름>.md` — §5 템플릿. pm 은 lint·이동·원장만 |
| 열기 | master | `ft-nano-spawn.sh <인덱스> [--agent claude\|codex\|cmd\|opencode] [--model ID]` — 워크트리·`remain-on-exit`·`@zc_v65_active`·seats.json 등록·대기→진행 이동·첫 발주(인덱스 경로 한 줄)·도달 확인까지 한 번에 (0.3) |
| 일하기 | 나노 | 인덱스 §구현범위만. 커밋은 자기 브랜치, **push 금지**(master). 산출 경로를 mbox 로 |
| 테스트·판정 | master + DA | §완료조건 값. 나노 소관 아님 |
| 닫기 | master | `ft-nano-close.sh <좌석>` — 결과 보존·회수·유휴 3조건 값 검사 → seats.json 삭제 → NANO-LEDGER append. kill 은 keep-last-2 뒤 (0.3) |
| 완성 | DA 판정 뒤 | `ft-index-move.sh <파일> 완성 --da <판정문#§N>` (0.3) |

## 4. 역할 좌석 교체 (master · da · pm — 한도·소실 시)

한 줄로 한다 (0.3): `bash .fable-team/bin/ft-role-spawn.sh <master|da|pm> [--agent claude|codex|cmd|opencode] [--model ID] [--effort E] [--from <발주좌석>] [--dry-run]`
— 호출한 워크트리에서 `ft-v65-<role>-<agent>#<N+1>` 을 tmuxc 로 열고(`--ctx 1m` 은 claude 만·`--effort` 는 claude·cmd·codex 만 넘긴다) `remain-on-exit`·`@zc_v65_active` 를 pane_id 로 박고, seats.json 의 그 role 행을 **교체**하고, 첫 발주를 `ft-send-verified.sh` 로 넣어 jsonl 도달까지 본다. exit 0 열림+도달 · 1 REJECT(사유 stdout) · 2 usage · 5 열렸으나 도달 미확인. `--dry-run` 은 PLAN 한 줄 + tmuxc dry-run 만.

1. **교체는 «행 추가 + 계보»다** — 같은 role 의 현역 행(`_replaced_by` 없는 행)에 `"_replaced_by": "<새 좌석>"` 을 찍고, 새 행에 `"_replaces": [구 좌석…]` 을 적는다. 구 행은 지우지 않는다. ★구 좌석은 kill 하지 않는다★ — 정지 레디(HIL). seats.json 을 읽는 쪽(틱·모니터)은 `_replaced_by` 가 있는 행을 «현역 아님»으로 건너뛴다.
2. 새 행은 `tick=null`(알림 울림) · `index="design/v65/indices/inbox/<role>/"`. 틱 데몬이 seats.json 을 따라오는 것은 0.4 — 그 전까지는 울리는 쪽이 안전하다.
3. 첫 발주 = 「이 README §2 부팅 5단계 → `indices/inbox/<role>/` 정렬해 «맨 위» 부터」 한 줄. 본문은 인박스 파일에 있다.
4. **인박스** `design/v65/indices/inbox/{master,da,pm}/` — 각 폴더 `README.md` 가 형식 견본(나노 인덱스와 같은 6절, lint 그대로 통과). 항목은 `NN-<제목>.md`(NN 이 순서), 끝난 것은 `inbox/<role>/done/` 으로 `git mv`.
5. 구 좌석이 살아 있으면 §2 증류선 마무리 3순서로 응답까지 받고 닫는다.

런타임 자리는 `<워크트리>/.fable-team/bin/`(gitignore) — 추적 사본은 `scripts/fable-team-bin/ft-role-spawn.sh`(`ft-goal-check` 관례). 실전은 런타임 자리에서 돌린다(`ft-send-verified.sh` 가 같은 디렉터리에 있어야 한다 — 없으면 REJECT).

### 4-2. 틱 — 데몬 3종 대신 `ft-tick.sh` 하나 + launchd (0.4)

한 줄: `bash .fable-team/bin/ft-tick-install.sh` — `seats.json` 의 `tick != null` 이고 `_replaced_by` 없는 좌석마다 그 종류(`ft-master-tick` 900s + goal-tick 240s · `ft-pm-tick` 600s, pm 의 보고처 = 현역 master 행)를 매 루프 «다시 읽어» 적용한다. 승계 = seats.json 한 줄 교체, env 재기동 없음. 생존은 `KeepAlive`(`~/Library/LaunchAgents/com.byz.ft-tick.plist` · 로그 `/tmp/ft-tick.log`). 점검 `bash ft-tick.sh --once --dry-run`(대상·메시지 앞 80자) · 제거 `ft-tick-install.sh --uninstall`. 4중 디바운스·프롬프트 본문은 구 틱에서 그대로 옮겼다(좌석별 stamp `/tmp/ft-tick-<좌석>.<종류>.last`).

**전환 절차 (사람이 한다 — install 은 구 데몬을 죽이지 않는다)**: ① `ft-tick.sh --once --dry-run` 이 현역 master·pm 만 나열하는지 본다 → ② `ft-tick-install.sh` 로 올리고 `launchctl print gui/$UID/com.byz.ft-tick` 에 `state = running` 확인 → ③ 그 뒤에만 구 데몬 2개(`pgrep -af 'ft-(pm|master)-tick'`)를 사람이 `kill -TERM`(그 전엔 틱이 2중 발사된다).

## 5. 형식

**seats.json 행**
```json
"ft-v65-temp-<이름>#0": {"role":"nano","agent":"claude","tick":null,"model":"fable-5.1[1m]","index":"design/v65/indices/진행/<이름>.md"}
```
role ∈ master·pm·da·nano·tester·harness-design. tick ∈ null · `ft-master-tick` · `ft-pm-tick`. **tick=null 이면 알림이 울린다.**

**인덱스 파일 필수 절** (`ft-index-lint.sh` 가 없으면 거부)
```
# 인덱스: <이름>
## 골 원문 (항상 이 3줄)            ← 위 3줄 바이트 일치
## 골좌표                           ← M?/K? + 닫는 증거 «정본 복붙»(GOAL-LEDGER-v65.md 에 실재해야 통과)
## 배경                             ← 한 단락. 정본 인용 ≤4 개
## 구현 범위                         ← 좌석 컨텍스트 안에서 끝나는 크기. 「이 셋만」식으로 닫힌 목록
## 완료 조건                         ← 값·통과조건·관측조건. master+DA 소관 명시
## 상태                             ← 날짜·좌석명·seq·폴더 이동 이력
```

## 6. 지금 어디까지 (버전 = seats.json `_version`)

| 버전 | 닫힌 것 | 증거 |
|---|---|---|
| **1.0.0** | §0 닫는 증거 성립 — 「나노 1건이 대기→진행→완성 을 스크립트로만 통과하고, 그 사이 좌석 정지·메시지 소실·판정 오기입 0」 (2026-09-14 · ft-harness-upgrade-design#0 판정) | 나노 3건이 `ft-nano-spawn`→산출→`ft-nano-close` 만으로 완주 · launchd 틱 running + `stall()` 실측 · recv 3중 읽기 0 · lint REJECT 0 / 완성/ 이동은 DA §N 필수. **미실전 1**: `ft-role-spawn.sh da` (dry-run 4종 OK) |
| **1.0.1** | 팩 재동기 — 모델 순위(`ft-nano-spawn.sh --tier {checker\|tester\|impl}[:N]` · `FT_CMD_ENABLED` 게이트) + 뉴스 5차(제품만·사람 말·불릿·「세션 상태」 절 «세션명 - 상태 - 역할 - 진행내용»·발행 뒤 1건 착수) + stall 대상 role 에 impl·checker (v65 런타임 2026-09-14 오빠 지시 4건, 나노 `sb-pack-resync-tier`) | `bash -n` 3파일 · `--dry-run` tester/tester:2/impl/impl:2/`FT_CMD_ENABLED=1 tester` 5종 PLAN · 런타임↔팩 diff 는 env 기본값 줄만 |

0.1 → 0.4.1 의 단계별 증거표는 원본 `design/v65/SEATBELT-README.md` §6 (BYZ-Agents 리포, 예시 트랙) 을 본다 — 팩 사본은 «현재 버전 한 행»만 둔다.

## 5-1. 역할별 기본 모델 (오빠 2026-09-14 「checker·tester 는 컨텍스트가 많이 필요하니 … 되는 모델로 속도와 컨텍스트 낭비를 막자. sonnet 이 가장 마지막 선택지. 비싸니까」)

| 역할 | 1순위 | 2순위 | 3순위 | 마지막 | 왜 |
|---|---|---|---|---|---|
| **checker · tester** (press 실행·poller/BTS 대조·읽기조사) | **luna** `--agent codex --model gpt-5.6-luna --effort high --fast on` | **sonnet** `--agent claude --model claude-sonnet-5[1m]` | (cmd — `FT_CMD_ENABLED=1` 일 때 1순위로 복귀) | — | 오빠 확정 「luna > sonnet」(2026-09-14: zcode 구독 없음 → 제외 · cmd 월제한 9/18 해제까지 제외 「cmd도 넘기자」). 로그·poller 를 통째로 읽어 컨텍스트를 많이 먹는다 — 싸고 빠른 것부터, sonnet 은 마지막 |
| **impl** (구현 나노) | `claude` `claude-fable-5-1[1m]` — **메인** | luna | (cmd, `FT_CMD_ENABLED=1` 시 :2) | — | 오빠 「fable 이 구현은 메인으로 사용」. 인덱스 1건을 컨텍스트 안에서 끝내는 자리. 싼 순위는 «컨텍스트 소모형 구현»(로그 파싱·대량 치환·회귀 돌리기)에 선택 |
| master · da · pm | 현행(README §2) | | | | |

★워커 종류는 셋 — **checker(BTS+poller 대조) · tester(press 실행) · impl(구현)** — 전부 «나노» 로 열고 `--tier` 로 모델을 고른다★ (오빠 「checker(bts+poller), tester, impl 다양하게 워커로 사용 … 그외 여러 컨텍스트 소모 작업에 다양하게 선택 사용」). 인덱스 §구현 범위가 «읽고 대조·press 쏘기» 면 checker/tester 1순위(zcode), «코드를 고친다» 면 impl 1순위(fable). 한 인덱스에 둘 다 있으면 나노 2개(impl 뒤 checker) — 한 좌석에 섞지 않는다(HARNESS-TREE checker 계약: 판정 라벨 금지).

- 한 줄: `ft-nano-spawn.sh <인덱스> --tier tester[:N]` — N 생략=1순위 luna, `:2` sonnet (impl 은 `:1` fable `:2` luna). **cmd 복귀**: 9/18 월제한 해제 뒤 `FT_CMD_ENABLED=1` 을 주면 tester `:1`·impl `:2` 에 cmd 가 끼어들고 나머지가 한 칸 밀린다. 한도·거부(`usage_limit_reached`·429·「insufficient credits」)면 다음 N 으로 재spawn — 전환은 master 가 seats.json 행 교체로. ★사다리 첫 실측(2026-09-14)★: zcode «No payment method»(구독 없음 → 제외) · cmd 「insufficient credits」(월제한, 9/18 해제 → 그때까지 제외) · luna OK.
- codex 좌석은 `--ctx` 를 받지 않고 게이지가 «남은 %»다(§2 증류선). cmd 는 `cmd status` 크레딧 확인(COMM-GUIDE §cmd).
- 마지막 선택지(sonnet)를 쓸 땐 세션 상태 진행내용에 «sonnet 사용 — 앞 3순위 불가 사유» 를 적는다.

## 6-1. 멈춰 있지 않는다 (오빠 2026-09-14)

- **좌석**: `[stall-wake]` 가 창에 뜨면 그 순서대로 — ① `mbox recv` ② 내 `index`/inbox 열어 다음 단위 ③ 정말 없으면 master 에 «정지 레디» 1줄. 판단이 갈리면 묻지 말고 값과 함께 master 에.
- **master**: 틱마다 «뉴스»(지금·남은 것·테스트 계획·완성 전망 — 제품만·사람 말·불릿·인덱스 파일명 0) + 빈 줄 + 「세션 상태」 절 «- 세션명 - 상태 - 역할 - 진행내용»(상태는 `ft-seat-status.sh` 값). `[stall]` 이 오면 뉴스 첫 줄에 «확인할 세션: <좌석> — <이유>», 교체·개입 선택은 AskUserQuestion 으로 오빠께 묻고 답을 그 좌석·pm 에 전파. ★발행하고 끝내지 않는다★ — 같은 턴에 대기 좌석에 발주·press GO·pm 정렬 중 1건 착수. 좌석이 전부 «대기»면 master 가 안 굴린 것이다(오빠 2026-09-14).
- 정지 판정 정본 = `ft-seat-status.sh stalled`(jsonl mtime AND pane). pane 텍스트 단독 판정 금지.

## 7. 하지 않는다

- pane `❯` 텍스트를 지시·제출로 읽지 않는다 — 판정은 jsonl(`ft-reach-check.sh`) · 상태는 seats.json.
  좌석 «정지» 판정 정본은 `ft-seat-status.sh stalled [--min N]`(jsonl mtime age ≥ N분 **AND** pane 스피너 없음) — `list`/`one` 은 4열(`좌석 PANE JSONL_AGE AGENT`), `--json` 동일값. pane 만으로 정지를 말하지 않는다.
- 좌석·브랜치·워크트리·DB 를 사람 승인 없이 kill·drop 하지 않는다. 자기 테스트 러너는 예외.
- 완료 증명은 press 뿐. 「유닛 통과」「구현 완료」는 그렇게만 쓴다.
- 골·작업을 약어(A/B/C/D 등)로만 부르지 않는다 — 좌표는 M?/K? + 닫는 증거 복붙.
