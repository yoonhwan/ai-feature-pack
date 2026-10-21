「tmm·tmuxc·tmux·fable-team 멀티 pc/맥 업그레이드 기획 — byz mac mini+jarvis OCI Tailscale 연동, cli 운용, 브라우저 시험 이관, 팀·나노 분산」(오빠 10-21) — 구현 P2~P4 착수 승인(오빠 AskUserQuestion 10-22).
골의 어느 축: 멀티호스트 «구현» 단계 진입 — 닫는 증거 = 아래 요청 3건이 하네스 카드로 받아들여지고, 각 카드의 rc=0 원문이 설계서 §13 의 명령과 일치.
상태: r2(2026-10-22) — 하네스 회신(#134412) 반영: 카드 A=r673(P2) · B=r674(P4) · C=r675(P3) · 덤 r676(recv 15% 이중 소비). 착지 순번 r646→r673→r674→(r469→r676)→r430·r432·r627→r675. 구현 순서 P2→P4→P3 오빠 확정. 구현은 하네스 나노가 함 — 이 팀은 구현 착수 0. 요청 D(P1 aifp-gate)를 아래에 추가.
(이전 상태: 초안 r1.) 하네스 회신(#134276): ft-mbox.py·tmuxc·tmm 변경은 «하네스 카드로만» — 이 문서를 `byz-harness-master-claude#93` 앞에 보낸다.

# 하네스 요청문 초안 — 멀티 호스트 P2 · P4 · P3

공통 전제 (세 요청 모두)
- **호스트가 1개일 때 지금 동작은 문자 단위로 불변**(회귀 0). 멀티 호스트는 켜는 스위치(`.fable-team/hosts.json` 이 없거나 `local` 하나뿐이면 새 코드 경로 0).
- 설계 정본: `docs/multihost/DESIGN-multihost-20261021.md` (가지 `docs/multihost-plan-20261021`, DA 승인 `DA-verdict-r8-1.md` 커밋 994a6c5b · 승인 유지 `DA-verdict-r8-2.md`). 줄 번호는 아래 «설계서 절»로 대신하고, 카드 작성 시 그 절을 그대로 인용.
- 시험 먼저(TDD): ①기준선 골든(현재 코드, 초록) ②새 동작 시험(빨강 확인) ③구현(초록). 변경 유형 분리(시험 커밋 / 기능 커밋).
- 시험은 가짜 tmux·ssh 로만 — 제품 우편함·제품 Redis·실제 tmux 서버·원격 접속 0.
- 모델/나노: pi flash 가 쓰기 쉬운 크기로 쪼갬. 이 맥 swap 여유가 빠듯하다(1.6GB) — 나노 동시 1석.

---

## 요청 A — P2 · tmuxc `--host` 디스패치  (★먼저, 다른 카드와 겹침 없음★)

| 항목 | 내용 |
|---|---|
| **무엇을** | `feature-pack/tmuxc/core/bin/tmuxc` 의 `main()` 맨 앞(진입 직후)에서만 `--host <h>` 또는 환경 `TMUXC_HOST` 를 본다. 없거나 `local`: 그 뒤 코드는 한 줄도 바뀌지 않는다(인자 분기 추가뿐). `<h>`: `ssh aifp-<h>-op aifp-gate tmuxc` 에 stdin JSON `{"argv": [...]}` 을 보내고 stdout/stderr/rc 를 그대로 돌려준다(ssh 255 → rc 7 `UNREACHABLE`). `attach` 만 `ssh -t … aifp-gate attach <seat>`, `clean` 은 원격으로 넘기지 않음. 추가: `open --seat-env K=V`(반복 가능) → `create_tmux_session` 의 `-e` 인자로(FT_SEAT 를 심는 자리), 플래그 없으면 동작 불변. |
| **왜** | 원격 호스트의 tmux·pgrep·ps·lsof·홈 경로를 «원격 tmuxc 가 원격 안에서» 쓰게 한다(호출 단위 원격화는 124+14건 허용 목록 때문에 폐기 — research-nano-2). 멀티 호스트의 모든 좌석 조작(open/send/kill/list/probe…)의 입구. |
| **골든 회귀 0 시험** | `feature-pack/tmuxc/test/host-dispatch-golden.sh` — 가짜 tmux/pgrep/ps(기존 `test_tmuxc_opencode_model.sh` 방식)로 대표 명령 open·send·kill·list·capture·attach·save/restore 를 분기 «전»·«후» 커밋에서 실행해 ①호출 순서 ②argv ③종료코드 ④stdout/stderr ⑤스냅샷 경로·`latest.json` 위치 5가지 동일. `--host` 모드: 가짜 ssh 로 stdin JSON argv 가 원래 argv 와 같음(여러 줄 본문 포함)·rc 전달·255→rc 7. |
| **닫는 증거(rc=0)** | `bash feature-pack/tmuxc/test/host-dispatch-golden.sh; echo "rc=$?"` → `rc=0` 원문 + 기존 `feature-pack/tmuxc/test/verify.sh` 통과 원문 |
| **설계서 절** | §7(tmuxc `--host` 디스패치) · §13 P2 행 · §3 의 `--seat-env`(L137 부근) · §2 연결 수 상한(ControlMaster 1개 재사용) |
| **겹침** | 열린 카드 r430·r432·r627·r660 중 tmuxc `main()` 앞단을 건드리는 것이 있는지 **하네스 확인 필요**(카드 본문을 이 쪽에서 읽지 못함 — 아래 «카드 대조 표»). 알려진 것: r660 은 `24020b3a`(manifest 1.1.185) 로 이미 main 착지 — 쪽지 길 판정기이며 tmuxc `main()` 과 무관. |
| **선행** | 없음. 가장 작고 되돌리기 쉬움 → **첫 카드로 권장**. |

## 요청 B — P4 · tmm HOST 열  (P2 뒤)

| 항목 | 내용 |
|---|---|
| **무엇을** | 호스트가 2개 이상일 때만 `tmm` 에 HOST 열(2~3자 약칭, 폭 ≤58 규칙). 행 키 `host<US>session`(0x1f). 호스트당 ssh 1회 일괄 스캔(`tmm rows --tsv` 를 원격 tmm 이 만들어 K2 `rows`·`pane-capture` 로 가져옴), 호스트끼리 병렬, 느린 호스트가 판을 막지 않게 `timeout 7` → `UNREACHABLE` 행(침묵 누락 금지). dead 뷰는 «모름» 호스트의 좌석을 «죽음»으로 표시하지 않음(모든 호스트 live 이름 합집합으로 제외). 캐시 키(`tmm:96` 의 `socket_path`)에 host 포함. |
| **왜** | 운영자가 보는 콕핏(U1 확정: tmm 안 «호스트 판» `^B`). 원격 행이 없으면 분산 운용이 눈에 안 보임. |
| **골든 회귀 0 시험** | `feature-pack/tmm/test/host-col.sh` — ①호스트 1개: 행 출력이 기존 골든(`feature-pack/tmm/test/golden`)과 `cmp` 동일 ②호스트 2개 중 하나를 응답 없는 스텁으로: 첫 화면까지 **7초 이내**(재시도 0), 그 호스트 `UNREACHABLE` 행, dead 뷰에 그 호스트 좌석 0. |
| **닫는 증거(rc=0)** | `bash feature-pack/tmm/test/host-col.sh --out docs/multihost/p4-tmm.tsv; echo "rc=$?"` → `rc=0` + tsv |
| **설계서 절** | §6(tmm HOST 열) · §13 P4 행 · 운영 계층 `DESIGN-multihost-ops-ux-20261021.md` §2(`^B` 호스트 판 — O3 에서) |
| **선행** | 요청 A(P2): 원격 행 조작이 `tmuxc --host` 로 위임되므로. |
| **겹침** | tmm 을 건드리는 열린 카드가 있는지 **하네스 확인 필요**. |

## 요청 C — P3 · 우편함 멀티 모드  (★가장 큼·겹침 많음 — 마지막★)

| 항목 | 내용 |
|---|---|
| **무엇을** | 수신 호스트 소유 우편함: `inbound/`·`outbound/`·`quarantine/`·deliver·route·forwarder·`--replay`·`seats.lock`·스풀·세대 필터(recv 합침). 단일 모드의 `mailbox.jsonl` 경로는 그대로. 상세 계약 = 설계서 §3(3.1~3.8)·§4·§11. |
| **왜** | 원격 좌석이 쪽지를 주고받는 길. DA 8회 심사로 확정된 구조(소비는 항상 로컬, 네트워크는 배달만). |
| **골든 회귀 0 시험** | `feature-pack/fable-team/test/mbox-multihost-fault.sh` — 격리 우편함(임시 `FT_MBOX_DIR`)에서 정상 왕복 N=200 + 장애 16종(F1~F21, 설계 §13 P3 행·DA `IMPL-TEST T1~T4`). |
| **닫는 증거(rc=0)** | `bash feature-pack/fable-team/test/mbox-multihost-fault.sh --n 200 --transport shim,ssh:oci --out docs/multihost/p3-mbox.tsv; echo "rc=$?"` |
| **설계서 절** | §3 · §4 · §11 · §12 · §13 P3 행 · `DA-verdict-r8-1.md` IMPL-TEST T1~T4 · `measured-a-fs.md`(APFS 원자성·fsync·동시 recv 15% 이중 소비·JSONL 재작성 종료) |
| **선행** | ★recv 잠금 부분은 r469·r553 착지 뒤★(아래 표) · 요청 A(P2) · P1(`aifp-gate`) 은 별도 카드. |

---

## 카드 대조 표 — 열린 카드와의 겹침 (이 쪽에서 확인한 것만 «확정», 나머지는 «하네스 확인»)

| 카드 | 이 쪽에서 아는 것 | 근거 | 겹침 판정 |
|---|---|---|---|
| **r469** (대기) | 상위 전달 요약: «doorbell 이 recv 를 중간 소비». 카드 본문은 이 맥에서 읽지 못함 | worker-master #3080 | **직접 겹침 가능**: doorbell 경로는 `ft-mbox.sh` 의 `doorbell()`(L37~), recv/소비는 `ft-mbox.py` `recv()` L585 · `_consume` L575 — 요청 C 의 recv 변경과 같은 함수 |
| **r553** | mbox 보낸 사본 `.1~.N` 보관(매거진 창) — **이미 main 착지**(PR #171, manifest 1.1.105) | `git log main` | ft-mbox 로그 보관. recv 잠금과는 별개 파일 영역 → 겹침 작음 |
| **r430** | 증거 폴더 `evidence/r430/master-steps.md` 만 확인 | main 트리 | **미확인** — 하네스에 범위 확인 |
| **r660** | desk 창구 고정(쪽지 모든 길 앞 판정기) — **이미 main 착지** `24020b3a`(manifest 1.1.185) | `git log main` | 쪽지 길 앞단 판정. 요청 C 의 `ft-mbox.sh send/recv` 앞단 변경 시 **충돌 가능성 있음**(같은 파일) — 순서 확인 |
| **r432 · r627** | 카드 본문 못 찾음 | — | **미확인** |

### 실측 A 의 «기존 recv 동시 이중 소비 15%» 는 r469 범위인가?
- 사실: `ft-mbox.py recv` 를 **doorbell 없이 두 프로세스로만** 동시에 돌려도 100회 중 15회, 같은 seq 를 둘 다 읽는다(행 유실 0). 원인 = `recv`(L592)의 읽기 잠금과 소비 잠금(`_consume` L582)이 **따로**라서 그 사이가 열려 있음. 재현 스크립트·수치: `docs/multihost/measured-a-fs.md` §1-5, `docs/multihost/measure/a-fs-atomicity.sh`.
- 대조: r469 가 «doorbell 이 recv 를 중간 소비»라면 **doorbell 쪽 고침(스탬프·억제)만으로는 위 15% 가 닫히지 않는다**(doorbell 없이도 재현되므로). 다만 실제 운용에서는 doorbell 이 recv 를 한 좌석에 연달아 일으켜 두 recv 가 겹치는 것이 이 창을 여는 가장 흔한 경로일 수 있다.
- **하네스에 묻는 것**: ①r469 범위에 «recv 읽기+소비를 한 잠금 안에서» 가 포함되는가 ②포함이 아니면 이 15% 를 r469 의 한 항목으로 넣을지 별도 카드로 쓸지. 어느 쪽이든 **빨간 시험**은 이 쪽에서 줄 수 있다(`measure/a-fs-atomicity.sh` 의 동시 recv 항목 → 카드의 red 시험으로 이관 가능).

## 순번 제안 (오빠 확정 순서 P2 → P3 → P4 와 하네스 제약을 함께 반영)
1. **A(P2)** — 겹침 없음·되돌리기 쉬움. 하네스 제약: «설치 1.1.187 끝나기 전 팩 main 위 새 가지 금지»·«자원 동결 해제 전 나노 추가는 큐» → 카드 접수와 가지 개설은 하네스가 정한 시각에.
2. **B(P4)** — A 착지 뒤(원격 행 조작이 `tmuxc --host` 위임).
3. **C(P3)** — r469·r553 착지 sha 뒤. (r553 은 이미 착지.) 오빠가 말한 P2→P3→P4 에서 P3 와 P4 의 순서는 **P4 를 앞**으로 권한다 — P3 는 선행 카드(r469)에 막혀 있고 P4 는 막혀 있지 않다. 오빠 확정 순서와 다르므로 **오빠께 한 줄 확인**(상위가 처리).

## 하네스에 요청하는 것 (한 줄씩)
1. 위 A·B·C 를 카드(r 번호)로 접수, 번호와 착지 순번을 회신.
2. 카드 대조 표의 «미확인» 4장(r430·r432·r627 + r469 본문)의 범위를 알려 주기.
3. 15% 이중 소비를 r469 에 넣을지 별도 카드로 할지.

---

## 요청 D — P1 · `aifp-gate` 실물 + K1/K2 키 + 원격 설치 h  (★별도 카드 필요 — 요청 A~C 와 독립★)

| 항목 | 내용 |
|---|---|
| **무엇을** | ①`aifp-gate`(원격 고정 진입점, 새 스크립트 1개): ssh 강제 명령으로만 실행, 인자 = `SSH_ORIGINAL_COMMAND` 의 «동사 이름만»(`[a-z-]+`, `attach` 만 3번째 토큰으로 좌석 이름), 본문은 stdin JSON(셸 해석 0), 로그는 동사 이름·호출자·rc 만(인자·본문 0). 동사 표 = 설계서 §10.3 그대로(K1: `ping`·`route`·… / K2: `ping`·`pty-check`·`tmuxc`·`attach`·`pane-capture`·`rows`·`inbox`·`git`·`probe`·`e2e`). 표 밖 동사는 `REJECT verb=<이름>` rc 2. ②키 2종 생성·등록 h: K2(허브→원격) 개인키는 **허브(mini)** 에서 생성해 book·oci 에 `restrict,pty,from="<허브 100.x>",command="…/aifp-gate --role remote"` 로 등록 / K1(원격→허브)은 book·oci 각각 생성해 mini 에 `restrict,from="<그 호스트 100.x>",command="…/aifp-gate --role hub --caller <host>"` 로 등록. ③원격(book·oci·mini)에 `aifp-gate` 설치 h(복사 + 실행 권한 + 버전 대조, 대화형 0). 기존 h84 가 이 맥에 만든 `~/.ssh/id_ed25519_aifp_op` 는 **임시**(허브 이전 전) — 새 키로 교체하는 단계 포함. |
| **왜** | 모든 원격 조작(P2 디스패치·P3 우편함·P4 tmm 스캔)이 지나는 유일한 입구이고 보안 경계(K1=우편함 권한만 · K2=조작 권한)이다. 이것이 없으면 P2~P4 는 가짜 ssh 로만 시험되고 실제 호스트에서 동작하지 않는다. |
| **골든 회귀 0 시험** | 단일 호스트 영향 0: `aifp-gate` 는 새 파일이고 호스트가 1개면 호출되지 않는다. 시험은 `ft-host-probe.sh --keys` 7항목(키×동사×결과) — 설계서 §13 P1 행. |
| **닫는 증거(rc=0)** | `bash feature-pack/fable-team/skill/scripts/ft-host-probe.sh --all --via tailnet --keys --expect 'book=OK oci=OK mini=OK' --out docs/multihost/probe-p1.tsv; echo "rc=$?"` → `rc=0` + tsv (K1 ①~③·K2 ④~⑦: 바이트 동일 왕복·동사 거절·PTY 거절·`pty-check`·표 밖 동사·포워딩 거절 `administratively prohibited`) |
| **설계서 절** | §10.1(키) · §10.2(거절 2종) · §10.3(동사표) · §13 P1 행 · §2(연결 수 상한 — OCI ufw limit: 새 연결 6회/30초, `measured-oci-tailscale.md` §2) |
| **선행** | 요청 A(P2)와 독립. 요청 C(P3)의 `inbox` 동사 구현은 C 와 함께(표만 먼저 고정). 허브 이전(book → mini) 계획과 키 위치를 함께 정해야 해서 **오빠 승인 h** 가 들어간다(원격 쓰기). |
| **하네스 제약 확인** | `fable-team` 소유 파일 신설(`ft-host-probe.sh`·`aifp-gate`)이라 번호 직렬(1.1.x) 대상 — 카드 번호 요청. 원격에 설치되는 실물은 «복사 + 버전 대조» 로 단순하게(설치 확인 = LIVE_BIN 과 루트 `.fable-team/comm` 정본 `cmp`). |

## 오빠 손이 필요한 항목 — 현재 상태 (2026-10-22 00:1x KST · 읽기 전용 실측)

| # | 항목 | 어디서 | 상태 | 확인 근거 | 다음 |
|---|---|---|---|---|---|
| 1 | OCI Tailscale 로그인 | 브라우저 | ✅ 완료 (aifp-oci-jarvis 100.115.169.113) | h83 rc=4 이지만 실제 로그인 완료 · `measured-oci-tailscale.md` | — |
| 2 | **OCI 키 만료 끄기** | 브라우저 `login.tailscale.com/admin/machines` → aifp-oci-jarvis 줄 «…» → **Disable key expiry** | ⏳ **미완** | `tailscale status --json` 의 KeyExpiry = **2027-04-19T14:09Z**(약 180일 뒤 — 끄지 않으면 그날 조용히 끊김) | 오빠 1회 클릭 |
| 3 | Mac mini ssh 키 배포 | mini | ✅ 완료 (h84 rc=0, 사용자 byz) | `measured-mini-probe.txt` | — |
| 4 | Mac mini BlackHole 2ch | mini 터미널 | ✅ 완료 (h135 rc=11 후 오빠 설치 + coreaudiod 재시작, 장치 보임) | `measured-mini-blackhole.md` | — |
| 5 | **mini 마이크·소리 사전 점검** | 이 맥 `! bash /tmp/h143` → mini 터미널 한 줄 | ⏳ **미실행** | `/tmp/h143.ran` 없음 · mini `/tmp/aifp-mini-audio-check.sh` 아직 없음 | 오빠: h143 → mini 앞에서 `bash /tmp/aifp-mini-audio-check.sh`(소리 1초·마이크 허용 팝업 1회) |
| 6 | Tailscale ACL(tag:aifp) | 브라우저 Access controls | ⏸ 대기(지금 하지 않음) | `tagOwners` 정의 선행 필요 · K1/K2 사용 직전에 JSON 을 드림 | 요청 D 의 키 등록 직전 |
| 7 | 병합(docs 가지) | 이 맥 `! bash /tmp/h<N>` | ⏸ 대기 | 가지 `docs/multihost-plan-20261021` · 설계·실측 마감 후 한 번에 | 마감 때 |

오빠 손 합계(지금 당장): **2건**(#2 키 만료 끄기 · #5 mini 소리 점검). 둘 다 구현 대기와 무관하게 할 수 있음.
