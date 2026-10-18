# SPEC — 메인 하네스 오케 리스트 · mbox 전송 · 하위 구성 트리 (r4 · ft-harness-arch#0 · 2026-10-05)

> MERGED 반영 r+1 (C11 · 2026-10-06): 표 1 issue-manager 행·트리 도구 줄에 「(size:small 한정)」(충돌 ①) · 트리 checker 좌석 줄 삭제 → `시험묶음:` 1줄(충돌 ⑬).

> 골 원문(GOAL-harness.md 복붙):
> 내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
> 하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
> 메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.
>
> 골의 축: 축 A(모니터) 첫 단위 「누가 메인 오케이고 그 밑이 어떤 구성인지」. 닫는 증거 = DA APPROVE + 오빠 「맞다」.
> 발주 = ops#2 ORDER-main-orch-list-20261005(#56946 · 오빠 「스택이 너무 크다 … 메인 하네스 오케스트 리스트부터 … 트리로 출력」) + 오빠 확정(#56948→#56950→#56951→**#56952 최종**) **「오빠 ↔ planner(컨트롤 베이스·거시) ↔ {v65·cfo·harness-ops 메인 · ccu·kk 위성} 는 planner 아래 서로 동등 · issue-manager = planner 가 쓰는 Issue 실행 도구(정의된 GitHub Issue 단위 폴링·수정·테스트·랜딩·클린업) · 상세 예시는 v65·cfo·ccu」**. 범위 = 표 1 + 그림 1 + 트리 1. Slack·Issue·설치·멀티머신 제외.
> r3→r4: DA r2(`DA-orch-tree-r2.md` b6b84f3001) 잔여 1건 반영 — 도어벨 결과 4(sent·absent·noagent·skipped) · 미소비 도어벨 120초 억제(`FT_MBOX_DOORBELL_STARVE`) · ring 은 억제 둘 다 무시 · 3초/120초 = 설정 가능 기본값.
> 실측 시각 **2026-10-05 12:2x(세션·에이전트 · FACTS F1) / 14:3x(명부·워크트리 · arch 직접 + nano `FACTS-orch-tree-20261005.md` T1~T3)** · 이 Mac 1대. [사실] = 명령으로 본 것. r2→r3: DA r1(`DA-orch-tree-r1.md` 8139c5aaaa) 발견 1~3 반영(도달 판정 = 받는 쪽 세션 jsonl · `--urgent`·recv 5건·peek 출력 조건 · arch#155 워크트리) + nano T1~T3 대조(v65 `_master` 없음·#135 role 빈 값 · kakao 명부 중첩 경로). r1→r2: 오빠 확정 구조(planner 컨트롤 베이스 · 아래 5 팀 동등 · issue-manager 도구) · 상세 예시 3팀 · cfo 명부 하위 22행 사실 추가.

## 1. 메인 하네스 오케 리스트 (표 1)

«오케» = 팀의 일을 받아 좌석을 열고 보고를 모으는 세션 1개. 구조(오빠 확정 #56952): **오빠 ↔ planner(컨트롤 베이스)** · planner 아래 **v65·cfo·harness-ops(메인) · ccu·kk(위성)** 가 서로 동등 · **issue-manager 는 planner 의 Issue 실행 도구**.

| 팀 | 역할 한 줄 | 오케 세션명 | 모델 · 에이전트 | 워크트리 | 명부 파일(`.fable-team/`) | 살아 있나(tmux + 에이전트 pid) |
|---|---|---|---|---|---|---|
| **v65** | 실시간 통역 제품(howtotalk) | `ft-v65-master-claude#136` | claude-sonnet-5-5[1m] · claude | `v6-realtime-live` | `seats.json` 행 `role:master`(파일에 `_master` 필드 없음 · nano T2) | **Y** (직전 `#135` 도 살아 있음 — 명부 role 은 빈 값 · 세션 2개) |
| **cfo** | 운영툴·과금·인프라·납품 | `FB_CFO#52` | claude-opus-5-5[1m] · claude | `c-level-planning` | `seats-cfo.json`(`_doc`: v65 와 섞지 않음) | **Y** |
| **ccu** | 동시접속 부하 시험(위성) | `FB_CCU#12` | claude · 모델은 명부 없어 미기재 | `ccu-stress` | **없음 — 6파일 어디에도 행 0** | **Y** (명부 밖에서 살아 있음) |
| **planner** | **컨트롤 베이스(상위)** — 오빠와 상호작용 · 거시 관점 · BOARD 원장 · 팀 배정·운영 · 판정 요청 창구(`_hil_route`) | `byz-planner-arch#3` | claude-fable-5-1[1m] · claude | `v6-realtime-live` | `seats-planner.json` `_master` | **Y** (`#1` 잔존) |
| **harness-ops** | 공용 키트(bin·env·mbox)·스킬 관리 · 팀 옆에 붙는 공통 서비스 | `ft-harness-ops#2` | claude-sonnet-5-5[1m] · claude | `harness-ops` | `seats-harness.json` `_master` | **Y** (`#0`·`#1` 잔존) |
| **issue-manager** | **planner 의 도구** — 정의된 GitHub Issue 단위를 폴링·수정·테스트·랜딩(size:small 한정)·클린업 + 재현 e2e | `ft-issue-manager#0` | claude-sonnet-5-5[1m] · claude | `issue-manager` | `seats-issues.json` `_master` | **Y** |
| **kk** | 언어 품질 피드백 루프(위성) | `FB_KK#4` | claude-opus-5-5[1m] | `kk-lang` | `seats-kk.json`(`#3` closed → `_replaced_by #4`) | **N** — 세션 0(랜딩 후 닫힘 · CLOSEOUT-kk) |

[사실] 「오빠에게 묻는 길」: `seats-harness.json`·`seats-issues.json` 의 `_hil_route = byz-planner-arch#3` — harness-ops·issue-manager 의 판정 요청은 planner pane 으로 가서 거기서 AskUserQuestion 이 뜬다. v65·cfo 는 `_hil_route` 없음(자기 pane). ccu 는 GPU·오디오 순번을 v65 master 에 mbox 로 요청(DESIGN-ccu-stress-infra §GPU 공유 · 자원 순번).
[사실] 구조는 오빠 확정(#56952) — 명부(`_hil_route`)·planner 정본(STRUCTURE-main-satellite「메인 PM」)과 일치. [추측] 5 팀 사이 권한 규칙(누가 누구를 닫나)을 적은 문서는 못 찾았다(closeout-policy·orchestration.md 는 좌석 내부 규칙만).
[사실] 명부가 실재와 다른 곳 2: ① `seats-cfo.json` 에 정지 표시 없는 하위 행 **22**(`CFO_F_NANO#20~26`·`CFO_DA#1`·`DATA_PG#4` …)가 있으나 tmux 세션은 `FB_CFO#52` 1개뿐 ② ccu 는 명부 0 인데 세션 1.

## 2. mbox 전송 방식 (그림 1 · 세 팀 예시)

```
  보내는 쪽                                 파일 큐(이 Mac 안)                                    받는 쪽
  ─────────                       ──────────────────────────────────────                        ───────
  FB_CCU#12 가 v65 에 순번 요청:
  mbox.sh send ft-v65-master-claude#136 FB_CCU#12 "[FB_CCU#12->ft-v65-master-claude#136] press 순번 요청 …"
        │
        ├──▶ mailbox.jsonl        큐 · 받는 좌석별 최근 10건만 보관 · 읽으면 사라짐(consume-on-read)
        ├──▶ mailbox.log.jsonl    보낸 쪽 사본(enqueue 기록) · 안 사라짐 · «보냈다»의 증거일 뿐 «도착»의 증거는 아님
        ├──▶ bodies/<seq>.txt     700자 넘는 전문
        ├──▶ .mbox-seq            번호표 → 이 발주는 #56951 같은 번호를 받는다
        │
        └──▶ 도어벨: 받는 좌석의 tmux 창에 한 줄을 «타이핑»한다
             「[발주 #56951] bash …/mbox.sh recv ft-v65-master-claude#136 — 실행하고 그 안의 지시를 즉시 착수하라」
             (울릴지 = 받는 좌석이 seats.json 에 tick 이 있으면 조용히, 없으면 울림 · --urgent 는 tick 과 무관하게 «울려 달라»는 요청일 뿐
              — 세션 없음(absent) · pane 에 에이전트 없음(noagent) · 직전 도어벨 3초 안 또는 앞 도어벨 미소비 120초 안(skipped) 이면 안 울린다 · --no-notify 는 무시+경고)
             ★도착 판정★ = 받는 좌석의 세션 기록(jsonl)에 그 `[발주 #seq]` 줄이 «제출된» 것으로 남았는가 — ft-reach-check.sh 가 이걸 본다.
               pane 이 움직이는 것은 «바쁘다»는 힌트지 «이 발주를 받았다»는 증거가 아니다.

  받는 쪽(v65 master):  mbox.sh recv ft-v65-master-claude#136   → 내 것 중 «최신 5건»만 꺼내 읽음(큐에서 삭제 · 더 오래된 건 HELD 로 표시)
                        mbox.sh recv … --all                      → 5건 제한 없이 전부
                        mbox.sh peek ft-v65-master-claude#136   → 안 꺼내고 pending=N (+ latest_seq · from · scanned)
  답은 같은 길 거꾸로:  mbox.sh send FB_CCU#12 ft-v65-master-claude#136 "[…] 순번 GO 15:00"
  안 읽으면:            mbox.sh ring ft-v65-master-claude#136 56951   → 큐는 그대로, 도어벨만 다시(3초·120초 억제 둘 다 무시 · 세션/에이전트 없으면 역시 못 울림)
  긴 글(설계서 등):     mbox.sh relay FB_CFO#52 CFO_OPS_ARCH#2 design/cfo/X.md "요약 1줄"
                        → 요약은 큐 · 전문은 /tmp/mbox/<시각>-<from>-to-<to>-X.md
```

| 명령 | 하는 일 | 큐 | 사본 로그 | 도어벨 |
|---|---|---|---|---|
| `send <받는좌석> <나> "본문" [--urgent]` | 3~5줄 보냄 · `#seq` 발급 | 추가 | 추가(보낸 쪽 사본) | tick 없는 좌석이면 시도 → 결과 4: `sent` / `absent`(세션 없음) / `noagent`(pane 에 에이전트 없음) / `skipped`(직전 도어벨 3초 안, 또는 앞 도어벨이 아직 안 읽힌 채 120초 안 — `FT_MBOX_DOORBELL_STARVE`) |
| `relay <받는좌석> <나> <파일> "요약"` | 요약 + 전문 경로 | 추가 | 추가 | 같음 |
| `recv <나> [--all]` | 내 것 꺼내 읽음(소비) · 기본 최신 5건(나머지 HELD) · `--all` 전부 | 삭제 | — | — |
| `peek <나>` | pending=N · latest_seq · from · scanned | — | — | — |
| `ring <좌석> [seq]` | 도어벨만 재발 — 억제 규칙 둘(3초 · 미소비 120초) 다 무시 | — | — | 세션/에이전트 있을 때만(absent/noagent 는 그대로) · 3초·120초는 기본값(설정 가능) |

규칙 3: ①한 값은 한 좌석에만(같은 발주를 둘에 안 보냄) ②답 안 온 상대에게 또 send 하지 않고 `ring` ③보냈다 ≠ 도착했다 — 도달은 받는 좌석의 세션 기록(`ft-reach-check.sh`)으로 판정 · pane 이 움직이는 건 힌트일 뿐 · 안 보이면 `ring`.
[사실] 구현 = `mbox.sh`(226줄 · 도어벨·알림 정책) + `mbox.py`(큐·LIFO·ring 10·flock) — 둘 다 루트 `.claude/fable-team/bin/` 의 심링크(의도적 비추적). 10-04 로그 기준 가장 많이 오간 쌍 = ccu 내부(`CCU_ARCH#17`↔`FB_CCU#12`↔`CCU_NANO#25` 76건).

## 3. 오케 하위 구성 트리 (트리 1 · 오빠 확정 구조 #56952 · 살아 있는 세션 ★ · 괄호 = 명부에만 있음, 단 ccu 하위 2는 10-04 mbox 로그에만 · 워크트리 = `tmux display #{pane_current_path}` 14:3x)

```
오빠 ── tmm(폰 피커) / tmux attach
 ↕ 상호작용(AskUserQuestion · 지시)
planner  ★byz-planner-arch#3   [fable-5-1 · claude · v6-realtime-live]   = 컨트롤 베이스(거시)   (★#1 잔존)
 ├─ 도구: issue-manager  ★ft-issue-manager#0   [sonnet-5-5 · claude · issue-manager]   정의된 Issue 단위 폴링·수정·테스트·랜딩(size:small 한정)·클린업
 │        └─ tester  ★repro-e2e#0   [sonnet-5-5 · claude · repro-main(main HEAD 전용)]
 │
 │  ── 아래 5 팀은 planner 아래에서 서로 동등(메인 3 · 위성 2) ──
 │
├─ v65  ★ft-v65-master-claude#136   [sonnet-5-5 · claude · .worktrees/v6-realtime-live]   (★#135 잔존)
│   ├─ arch    ★ft-v65-arch-claude#155        [opus-5-5 · claude · .worktrees/v65-732-redis-audio-ref]   설계·판정
│   ├─ tester  ★ft-v65-tester-claude#13       [sonnet-5-5 · claude · v6-realtime-live]    press·시험
│   ├─ nano    ★ft-v65-temp-m7-p90-lang-update-gap-decomposition#0      [sonnet-5-5 · claude · .worktrees/v65-*]
│   └─ nano    ★ft-v65-temp-m7-p90f-n06-n10-durable-four-of-five-rea#0  [sonnet-5-5 · claude · .worktrees/v65-*]
│   시험묶음: ft-v65-tester-claude#13 · 열린 카드# = 명부 `test_bundle` 칸 값(P7 §3 · 이 문서는 현황 스냅샷이라 값 미조회)
│        (da 는 필요할 때 열고 닫음 — 지금 0 · checker 는 역할이지 좌석 아님 → 묶음 줄 안 · 팀마다 `시험묶음:` 1줄 형식 = P7 §3)
│
├─ cfo  ★FB_CFO#52   [opus-5-5 · claude · .worktrees/c-level-planning]
│   ├─ (arch   CFO_OPS_ARCH#2)      명부엔 있으나 세션 0
│   ├─ (da     CFO_DA#1)            〃
│   ├─ (impl   CFO_IMPL#4 · DATA_PG#4) 〃
│   └─ (nano   CFO_F_NANO#20~#26 ×7) 〃  → 명부 하위 22행 전부 세션 없음 = 정지 표시 누락
│
├─ ccu(위성)  ★FB_CCU#12   [claude · .worktrees/ccu-stress · 명부 없음]
│   ├─ (arch   CCU_ARCH#17)   10-04 mbox 로그에만 · 세션 0
│   └─ (nano   CCU_NANO#25)   〃
│        ↑ GPU·오디오 순번은 v65 master 에 mbox 로 요청(자원 순번 · 서열 아님)
│
├─ harness-ops  ★ft-harness-ops#2   [sonnet-5-5 · claude · harness-ops]   (★#0·#1 잔존)
│   ├─ arch   ★ft-harness-arch#0   [fable-5-1 · claude]      ← 이 문서
│   ├─ da     ★ft-harness-da#1     [gpt-6.1-sol low · codex]
│   └─ nano   ★ft-harness-nano#1   [deepseek flash · opencode]
│
└─ kk(위성)  (FB_KK#4 세션 0 · seats-kk 12행 중 closed 10 — 랜딩 후 닫힘)

같은 tmux 서버의 다른 레포(트리 밖): KakaoBot 9 세션(명부 = `KakaoBot/kakao-agent-bot-planning/.fable-team/seats.json` 중첩 경로) · airag 3(`ft-airag-master-claude#2` 가 그쪽 master) · tmm 피커 1. 31 세션 = 프로젝트 루트 4개에 분산(nano T1).
```

읽는 법: 오케 1 밑에 arch(설계) · da(반박 게이트) · nano(구현 워커 · 워크트리 1개씩) · tester(시험) · checker(확인). **지금 살아 있는 하위 좌석 = v65 4 · cfo 0 · ccu 0 · harness-ops 3 · issue-manager(도구) 1 · planner 직속 0.** 세션 31(14:3x) 중 이 레포 18(오케 7 중 생존 6 + 잔존 4 + 하위 8) · 다른 레포 12 · tmm 1.

## 4. 남은 일(이 단위 밖 · 하나씩)
1. cfo 명부 하위 22행에 정지 표시(또는 명부를 tmux 에서 생성) · ccu 명부 행 추가.
2. 이 표·트리를 명령 1줄(`ft-orch-tree.sh`)로 뽑기 — 손으로 다시 안 그리게.
3. 오케 교체(#135→#136) 때 구세대 종료 규칙(keep-last-2 와 겹침 정리).
