# 풀스택 시스템 다이어그램 — 정본 (ft-harness-arch#3 · 2026-10-05 · r1)

> 골 원문(GOAL-harness.md 복붙):
> 내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
> 하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
> 메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.
> 골의 축: 표 A(모니터 대상 지도) · 표 C(전 머신 배분·반영의 입력 = 머신·인프라 지도) · 원문 5(머신 단위 독립 배분). 닫는 증거 = IR+drawio 커밋 + DA 사실 정합 APPROVE + 오빠 「맞다」(ORDER 8줄).

## 1. 정본은 IR 이다 — 그림은 재생성물

| 파일 | 역할 | 손으로 고치나 |
|---|---|---|
| **`fullstack.ir.json`** | ★정본★ 노드 77 · 엣지 115 · 뷰 4. 노드마다 `properties.status`(사실/추측) + `provenance`(파일:줄 또는 명령) | **여기만** |
| `build.py` | 검사(고아 0 · 출처 없는 노드 0 · status 없는 노드 0 · 뷰 참조 무결 · 시크릿 패턴 0) → `fullstack.drawio` 생성 | 규칙 바꿀 때만 |
| `fullstack.drawio` | 뷰 4 페이지(ⓐ~ⓓ) · 매번 재생성 | 아니오 |
| `fullstack.system.drawio` | 전체 모델 1 페이지 · **수동 배치를 보존하는 `sync` 대상** | 배치만 |
| `policy.yml` · `findings.json` | drawio-skill 규칙(`no-orphans` · `no-direct-internet-to-database`) · 최근 결과 | — |
| `FACTS-fullstack-20261005.md` | nano 사실 수집(읽기 전용 · [사실] 44 · [추측] 6) — 노드 출처의 대부분 | 재수집 때 새 파일 |
| `facts-raw/F*.txt` | 수집 명령 원출력(시크릿 0 · 변수 이름만) | 아니오 |
| `export/view-{1..4}.png` · `export/walkthrough.html` | 오빠용 그림 · HTML 워크스루(키보드·텍스트 대안 포함) | 아니오 |

계층(그룹) = ①외부서비스 ②머신·인프라 ③앱 서비스(로컬 dev) ④하네스 ⑤파일시스템. 엣지 종류 = `sync/async/read/write`(데이터) · `control`(제어) · `mbox`(메시지) · `deploy`(배포).

## 2. 뷰 (한 모델에서 · `fullstack.drawio` 페이지 순서)

| 뷰 | 노드 | 무엇을 보나 |
|---|---|---|
| ⓐ 풀스택 개관 | 30 | 다섯 층을 한 장에 — 오빠 → planner → 메인 3 → mbox, 앱 → 프로바이더/GCP, 머신 2 |
| ⓑ 인프라·배포 | 48 | 이 Mac 의 listen 포트 전부·IAP 터널 3·docker·launchd 데몬·GCE GPU VM·Cloud Run · **표 C 머신 분배 자리 = `jarvis` 노드 + `slack → jarvis 배포 수신(아직 0)` 엣지** |
| ⓒ 하네스 트리·메시지 흐름 | 31 | P2 §3 트리(10-05 13:37 tmux 실측으로 갱신 · 세션 0 인 좌석은 「세션 0」 표기) + mbox 큐 + 슬랙 미러 3 데몬 + 틱 + zombie-clean |
| ⓓ 로컬 파일시스템 | 28 | 리포 루트 11 폴더 · `~/.claude`·`~/.hermes`·`~/.codex`·`~/.baton`·LaunchAgents·`/tmp` ↔ 누가 읽고 쓰나 |
| ⓔ 일 한 건의 길(P8 13단계) | — | **미작성(선택)** — 완성 후 · P8 랜딩 뒤에 노드 겹치기 |

## 3. 재생성 · 검증 절차 (drift 점검 = 이 절 그대로)

```bash
cd design/teams/harness/diagrams
python3 build.py --check                      # 정본 무결 (exit 0)
python3 build.py                              # fullstack.drawio 재생성
S=~/.claude/skills/drawio-skill/scripts
python3 $S/diagramctl.py test fullstack.drawio --rules policy.yml -o findings.json   # errors 0
python3 $S/diagramctl.py sync fullstack.system.drawio fullstack.ir.json --from ir -o /tmp/next.drawio  # added/changed/removed 0 이면 drift 0
for i in 1 2 3 4; do drawio -x -f png --width 3000 -p $i -o export/view-$i.png fullstack.drawio; done
python3 $S/diagramctl.py story fullstack.ir.json -o export/walkthrough.html
```

r1 결과(2026-10-05): `build.py` nodes=77 edges=115 views=4 추측=2 · `test` errors 0 warnings 0 · `validate.py --score` 0 error(교차 경고만 · autolayout) · `sync` 2차 실행 added 0 changed 0 conflicts 0 · PNG 4장 육안 점검 2라운드(ⓐ 노드 40→30 축소 · ⓑ/ⓓ 방향 TB · ⓒ 고아 2 해소).
사실이 바뀌면: FACTS 재수집(nano 읽기 전용 · ORDER-nano-facts 재사용) → IR 의 해당 노드 `provenance`·`label` 갱신 → 위 절차.

★ `diagramctl sync` 는 단일 페이지 모델에만 유효(다중 뷰 파일에 걸면 1페이지 기준으로 「added 47」 — 실측). 수동 배치는 `fullstack.system.drawio` 에서만 한다.
★ drawio-skill 은 `disable-model-invocation: true` 라 `Skill` 도구 호출이 거부된다 — 이 트랙은 `SKILL.md` 를 Read 하고 `scripts/*.py` 를 Bash 로 직접 썼다. 상시 쓰려면 ops 가 설치본 frontmatter 를 `false` 로 바꾸거나 오빠가 `/drawio-skill` 로 연다(설치 키트 항목 후보).

## 4. [추측] 노드 0 — DA r1 HOLD 8건 반영(r2 · 2026-10-05T13:48Z 재실측)

| DA # | 반영 |
|---|---|
| 1·2 | `py-8000` = IAP 터널 → `byz-agents-gce-llm-dev:8000`(cwd ccu-stress) · `:38311` → `ccu-stress-vllm:8000` · `:8100` → `byz-agents-gce-stt-tts-dev:8100`(cwd c-level-planning). GCE 노드 = 「터널 대상 기준 · 원격 실재 미검증」. 출처 `ps -o command= -p <pid>`(인스턴스·포트만) + `lsof cwd` |
| 3 | `redis-dev` = docker `v6-realtime-live-redis-1 :6379` · gateway/worker 엣지는 「설정상 · 트래픽 미관측」 |
| 4 | `gcp-cloudrun` = CCU 배포(ccu-stress gateway·worker·redis) · environment `ccu-stress` · prod 인벤토리는 별도 출처가 생길 때 노드 추가 |
| 5 | `slack-mirror`·`ft-ticks` = plist 설치됨 · `launchctl list` 미로드(실행 0) · 관련 엣지 전부 「설정 · 비활성」 |
| 6 | 로컬 컨테이너 노드 4 추가(`supabase-local` cfo-p0-pg :54321~54324 · `qdrant-local` :6333/6334 · `pg-containers` :5432/5433/5434 · `langfuse` :3100 + onecli :10254/10255) — 「사용 앱 미기재」 엣지만 · `postgres-local` 은 homebrew 로드 vs docker :5432 listen 「미확정」 |
| 7 | planner → 팀 엣지 = 「큐 갱신·판정 통지」(배분 아님 · Issue 배분은 issue-manager) |
| 8 | `ft-bin → mbox` = tick peek/recv · `ft-bin → home-claude` = reach-check 가 `projects/*.jsonl` 세션 기록을 읽음(큐 ≠ 도달) |
| 스냅샷 | tmux 13:48Z **17 세션**: FB_CFO#52 · KakaoBot#14/#17 · byz-planner-arch#3 · ft-airag-helm-claude#5 · ft-airag-master-claude#2 · ft-harness-arch#2/#3 · ft-harness-da#1 · ft-harness-nano#1 · ft-harness-ops#1/#2/#3 · ft-v65-master-claude#135/#136/#137 · tmm (FACTS 의 13 은 13:37Z 값 — 시각 붙여 둘 다 유지) |

r2 결과: nodes=81 edges=123 views=4 추측=0 · `test` errors 0 warnings 0 · `sync` added/changed/removed/conflicts 0.

### r3 — 오빠 값 반영 (`VALUES-fullstack-20261005.md` · 읽기 전용 실측 2026-10-05T13:55Z)

| 오빠 값 | 반영 |
|---|---|
| Q1 머신 3기 = 이 Mac + jarvis + **byz mac(tailscale)** | 노드 `byz-mac` = `tailscale status` 의 **`byzs-mac-mini`**(macOS · online · 역할 미확인 · 하네스 미반영) + `tailscale` 메시 노드(이 Mac = `yoonhwans-macbook-pro` · `gamfss-mac-mini-2` offline 16d · iOS 3) · 엣지 `slack → byz-mac 배포 수신(표 C · 아직 0)` · `tailscale → byz-mac`(ping 1회 direct 미성립 → 경로 미확정 · 점선 의미) · 그룹 `②/머신 3기` 에 jarvis·byz-mac 같이 |
| jarvis 정체 | 문서상 **OCI VM · 원격 hermes 1기**(로컬 hermes 와 쌍으로 슬랙 양방향 · `PROPOSAL-slack-driven-ops.md:40·42`) · tailscale 목록엔 없음 → 라벨에 명시 (DA r3 HOLD 1: 「hermes 2기」는 원격+로컬 합계였음 → 정정) |
| 부수 정정 | `ssh-tunnels` 는 jarvis 가 아니라 **colima ssh mux 포트 포워드**(docker VM → 호스트 :3100/5432/54321/10254…) — `ps -p 85595` 실측 · jarvis 추측 엣지 삭제 · docker 컨테이너 3 노드로 연결 |
| Q2 타 레포 | 그대로(`other-repos` 1 노드) |
| Q3 drift → RELEASE | 구현 조각 후보로 §3 절차 그대로 유지 · 「구현 시작」 뒤 |

r3 결과: nodes=83 edges=127 views=4 추측=0 · `test` 0/0 · `sync` 0. DA 는 추가분(byz-mac·tailscale·jarvis 라벨·ssh-tunnels 정정)만 1회.

## 5. 사실 수집에서 나온 발견 (표 A 「이상 1건 = Issue 1건」 후보 · 판단은 ops)

1. **docker redis 컨테이너 40+ 잔존**(`c1c-ta-red-*` · `terminal-dup-red-*` · `byz-act-tier-b-*` — pytest 픽스처가 정리되지 않음 · `facts-raw/F2-docker.txt`). 메모리·포트 잠식. 정리는 HIL(컨테이너 삭제).
2. **GCE 봉투 위반 26h 미해소**(`A1P:ccu-stress-stt-tts` · `A1P:ccu-stress-vllm` · `state/gce-op-model/BREACH.md`) — 이미 SessionStart 훅이 매 세션 띄우는 중. 노드 `gce-guard` 에 표기.
3. **루트 `.fable-team/bin/` 비어 있음** · 실행 사본 = `.worktrees/v6-realtime-live/.fable-team/bin/`(36개) — #816 과 같은 줄. ⓓ 뷰 엣지 `worktrees → ft-bin 실행 사본 위치`.
4. tmux 31 → 13 세션(P2 14:3x 대비 −18) — P2 §3 트리의 v65 하위 4·issue-manager·repro-e2e 는 지금 세션 0. ⓒ 에 「세션 0」 으로 표기(명부에만 있는 좌석).

## 6. 오빠 질문 (최대 3 · 추천 첫째 · ops 인터뷰)

| # | 질문 | 추천 |
|---|---|---|
| Q1 | 표 C 「전 머신」 = 이 Mac + **jarvis** 둘뿐인가, 더 있나? (다이어그램은 jarvis 1대를 「미반영」 점선 자리로 둠) | **둘로 시작** — 머신이 늘면 IR 에 노드 1 + `slack → <machine>` 엣지 1 추가가 전부 |
| Q2 | 같은 tmux 의 다른 레포 세션(KakaoBot ×2 · airag ×2)은 정본 밖(「트리 밖」 노드 1개)으로 둬도 되나? | **밖** — 레포마다 자기 정본 · 여기선 「같은 서버를 쓴다」 사실만 |
| Q3 | drift 점검을 RELEASE 절차에 거나(구현 조각 후보 · 지금 0)? | **건다** — RELEASE-<ver> 마다 §3 의 `--check` + `sync` 0 확인 1줄을 머신별 「반영됨」 행 옆에. 구현은 「구현 시작」 뒤 |

## 7. 길 (ORDER §길)

nano 사실 ✅ → arch IR·뷰 ✅ → da#1 사실 정합 r1 HOLD 8 → r2 **APPROVE**(미반영 0 · `DA-fullstack-r1.md`·`DA-fullstack-r2.md` · 실브레인 = launcher 선언 gpt-6.1-sol low · provider 헤더 미노출 ⚠) → ops 수락·커밋 49aa8ecaaa → 오빠 값 3(4b8a1be31e · `VALUES-fullstack-20261005.md`) → r3 머신 3기 반영 → da#1 r3 HOLD 1(jarvis 라벨) → r3b **APPROVE**(미반영 0 · `DA-fullstack-r3.md` 끝) → **ops 커밋 ← 지금** → 정본 확정. 남은 오빠 확인 1: `byzs-mac-mini` 의 역할(무엇을 돌리는 머신인가 — 실측 불가 · RELEASE 머신 행에 적을 값).
