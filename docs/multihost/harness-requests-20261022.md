「tmm·tmuxc·tmux·fable-team 멀티 pc/맥 업그레이드 기획 — byz mac mini+jarvis OCI Tailscale 연동, cli 운용, 브라우저 시험 이관, 팀·나노 분산」(오빠 10-21) — 구현 P2~P4 착수 승인(오빠 AskUserQuestion 10-22).
골의 어느 축: 멀티호스트 «구현» 단계 진입 — 닫는 증거 = 아래 요청 3건이 하네스 카드로 받아들여지고, 각 카드의 rc=0 원문이 설계서 §13 의 명령과 일치.
상태: 초안(r1, 2026-10-22). 하네스 회신(#134276): ft-mbox.py·tmuxc·tmm 변경은 «하네스 카드로만» — 이 문서를 `byz-harness-master-claude#93` 앞에 보낸다.

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
