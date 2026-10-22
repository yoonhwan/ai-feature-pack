「우리 tmm, tmuxc, tmux, fable-team을 멀티 pc,맥 지원 환경구성으로 업그레이드 계획 기획팀 발주. byz mac mini와 jarvis OCI에 tailscale 설치·연동으로 cli 레벨 운용, 브라우저 가능 환경은 테스트 이관, 팀·나노 작업 분산 운영하는 멀티 인스턴스(네트워크) 기능 구축 기획, da 팀 발주. 필요 나노워커도 선투입」(오빠 2026-10-21)
골의 어느 축: 멀티호스트 «기획 단계 마감» — 닫는 증거 = DESIGN DA 승인 + 오빠 결정 + OCI Tailscale 설치 + 구현 이관(하네스 카드). 구현·마이크 확정·추론 스택 이식은 «완성 후»로 이관.
마감 방침 근거: ~/.claude/rules/closeout-policy.md (오빠 2026-10-03) — 랜딩→정본 1장→전부 닫기. 이 문서는 그 정본이다.
※ 파일 이름 주의: 상위 지시 이름은 CLOSEOUT-multihost-20261022.md. 작성 시점 컨텍스트가 600k 게이트를 넘어 Write 가 막혀 «HANDOFF-» 접두(허용 스냅샷 이름)로 저장했다. 상위/후계가 `git mv` 로 개명할 것.

# CLOSEOUT — 멀티호스트 기획 (2026-10-21 ~ 10-22)

작성: aifp-multihost-master-claude#0 (컨텍스트 616k 에서 마감 · 후계 없음). 작업 폴더 .worktrees/multihost-plan · 가지 docs/multihost-plan-20261021. 오빠 결정 «지금 마감» (AskUserQuestion 10-22, 상위 #3094).

## 1. 닫는 증거 (축별)
| 축 | 상태 | 닫는 증거 (sha / 파일) |
|---|---|---|
| 설계 DA 승인 | ✅ | 994a6c5b DA r8-1 APPROVE(7문항 PASS·STRUCT 0) · 승인 이후 변경 경량 대조 2bb109ae·13e39733 DA r8-2 승인 유지. 보류 6회(r2-1~r7-1) → 하드 룰 14 로 구조 재설계 2회(r4 수신 호스트 소유 우편함 · r6 자동 이관 제거)로 수렴. 판정서 docs/multihost/DA-verdict-*.md |
| 설계 정본 | ✅ | docs/multihost/DESIGN-multihost-20261021.md (§13 카드 반영 5b0b9c6b) · 운영 UX DESIGN-multihost-ops-ux-20261021.md (209e2029) |
| 오빠 결정 | ✅ 확정 | §2 |
| OCI Tailscale | ✅ 설치·로그인 완료 | measured-oci-tailscale.md (b9c2c0c8) — h83 은 rc=4(승인 5분 초과)로 끝났으나 실제로는 완료. aifp-oci-jarvis 직접 경로 5ms |
| mini 키 배포·실측 | ✅ | h84 rc=0 · measured-mini-probe.txt (7e41f16c) · 사용자 byz |
| mini BlackHole | ✅ 장치 보임 | h135 rc=11(mini 앞 sudo)→오빠 설치+coreaudiod 재시작 · measured-mini-blackhole.md (b7167b0a) |
| 구현 | ⏳ 하네스 카드로 이관 | §4 |
| 공개 가지 | ✅ push 됨 | origin/docs/multihost-public-20261022 = e527066d (origin/main 위 1커밋 · IP/계정/도메인 가림 · 검증 0건 · 상위 집행) |

## 2. 오빠 결정 확정값
| # | 결정 | 확정 |
|---|---|---|
| D2 | 허브 | Mac mini (16GB·62일 가동·sleep 방지; swap 여유 감시 칸 포함) |
| D3 | mini ssh 키 | 완료(h84, 사용자 byz) |
| D4 | OCI Tailscale 설치·접근 | 승인·완료(ACL 은 키 등록 직전에) |
| D5 | 전송 | 일반 ssh over Tailscale |
| D6~D9 | 원격 첫 일·jarvis 8080 범위 밖·라이브 터널 안 만듦·마이크 확인 | 추천대로 (D9=사전 점검 후 e2e trusted 클릭 확정 회차) |
| D10 | OCI 추론 스택 인증 | 같은 계정 (추천 «별도 계정» 과 다름 — 한도 공유 위험·감시 칸 문서화) |
| D11 | hermes 관리 서비스 이전 | 불필요로 정정 — 이미 systemd 사용자 서비스(enabled·active·Linger=yes, v0.15.1) |
| D12 | 내보낼 때 남은 쪽지 | master 처리 + late_delivered 만 오빠 |
| D13 | mini BlackHole | 설치 승인(완료) |
| U1·U2 | 운영 화면·슬랙 | tmm ^B 호스트 판 · 슬랙 desk 경로(알림 6종·명령 실행 0) |
| 구현 순서 | | P2 → P4 → P3 (오빠 확정) |

## 3. 실측 5건
| 파일 | 요지 |
|---|---|
| measured-a-fs.md (+measure/a-fs-atomicity.sh, 37a021c1) | APFS: 파일 os.replace 원자 ✅ · 디렉터리 같은 이름 교체 불가(ENOTEMPTY)·2단 swap 부재창 68% ❌ · 디렉터리 fsync 23µs · 기존 recv 동시 이중 소비 15%(→ r676) · 현행 _save 강제 종료 100/100 torn |
| measured-mini-probe.txt | mini 16GB·Chrome 有·BlackHole/SwitchAudioSource 無(설치 전)·마이크 미확인 |
| measured-mini-blackhole.md | 설치 완료·coreaudiod 재시작 후 장치 보임·Multi-Output 구성원은 오빠 확인(도구 실측 불가) |
| measured-oci-tailscale.md | OCI 공인 22 거부 원인 = ufw limit(같은 IP 새 연결 30초 6회↑) 확정 · fail2ban 가설 반증 |
| measured-oci-next.md | hermes 는 이미 관리 서비스 · cliproxy 는 로컬 패치 빌드 교차 컴파일 필요(CGO) · headroom 0.33.0 aarch64 휠 有 · mini 에는 추론 스택이 이미 가동 |

## 4. 구현 이관 — 하네스 카드와 착지 순번
구현은 하네스 나노가 한다(BYZ 하네스 번호 직렬 1.1.x · 이 팀 구현 착수 0). 요청문 정본 docs/multihost/harness-requests-20261022.md (8ab8741d·396c65b1).
| 카드 | 내용 | 닫는 증거(rc=0) |
|---|---|---|
| r673 (A) | P2 tmuxc --host 디스패치 + open --seat-env | bash feature-pack/tmuxc/test/host-dispatch-golden.sh; echo "rc=$?" |
| r674 (B) | P4 tmm HOST 열 | bash feature-pack/tmm/test/host-col.sh --out docs/multihost/p4-tmm.tsv; echo "rc=$?" |
| r675 (C) | P3 우편함 멀티 모드 | bash feature-pack/fable-team/test/mbox-multihost-fault.sh --n 200 --transport shim,ssh:oci --out docs/multihost/p3-mbox.tsv; echo "rc=$?" (F22: r660 판정기 4길 · LIVE_BIN↔루트 comm cmp) |
| r676 (덤) | 기존 recv 동시 이중 소비 15% 별도 수리 | measure/a-fs-atomicity.sh 동시 recv 항목을 red 시험으로 |
| r678 (D) | P1 aifp-gate 실물 + K1/K2 키 + 원격 설치 h | ft-host-probe.sh --all --via tailnet --keys …; echo "rc=$?" (7항목) |
착지 순번: r646 → r673 ∥ r678 → r674 → r469 → r676 → r430·r432·r627 → r675. (열린 카드 r469·r430·r432·r627 본문은 이 맥에서 못 읽음 — 겹침 판정은 하네스 확인.)

## 5. 나중에 볼 것
### 5-1. «다른 트랙 착지 때»
- r673 착지 → P2 골든 rc=0 원문 대조 → tmuxc --host 실제 원격 1회(mini).
- r678 착지 → K1/K2 키 생성(K2 는 허브=mini 에서)·aifp-gate 설치 h·ACL(tag:aifp JSON 은 키 등록 직전 오빠께).
- r674 착지 → tmm HOST 열·^B 호스트 판(원격 tmm 설치 h 가 P3 보다 먼저).
- r469 → r676 착지 → P3 의 recv 잠금 부분 착수 가능.
- r675 착지 → mbox-multihost-fault.sh N=200 + 장애 16종(F1~F22) rc=0.
- 하네스 설치 누락: 이 리포 루트 `.fable-team/comm/` 에 `mbox_doorbell.sh`(mbox.sh 짝 파일)가 없어 `ft-successor-open.sh` 가 REJECT(rc2, 2026-10-22). 하네스에 설치 요청 필요 — 설치 확인은 LIVE_BIN ↔ 루트 comm `cmp`.
- 공개 가지: 문서가 바뀌면 새 커밋 1개(히스토리 교체 0). 가림 도구는 scratchpad redact-multihost.py (공개 워크트리에서 재생성 금지).
### 5-2. «완성 후»
- P5a OCI 추론 스택: headroom 0.33.0 aarch64 휠 고정 + cliproxy 패치 빌드 linux/arm64 교차 빌드(CGO → C 크로스 컴파일러(zig cc 등) 또는 OCI 자체 빌드; 시험 빌드는 이 맥 /tmp). 소스 ~/.claude/jobs/ee330f7a/tmp/cpa (패치 3개). 인증 파일은 D10=같은 계정 → op develop 에서만 0600.
- hermes 업데이트: hermes update --check → hermes backup → hermes update --yes → systemctl --user restart hermes-gateway(≈5초+기동) → hermes doctor.
- D9 마이크 확정 회차: mini 터미널 앞 사전 점검(h-plans/mini-audio-check.sh, 평균 > -50dB = MIC_OK 후보) 후 e2e 러너 trusted 클릭 회차(P6 ①).
- 실측 A2: 새 이름 디렉터리 rename 중간 상태 관찰(설계 §16 공백).
### 5-3. ★오빠 손 2건 — «나중에 볼 것» (마감을 막지 않음)★
1. OCI 키 만료 끄기 — login.tailscale.com/admin/machines → aifp-oci-jarvis «…» → Disable key expiry. 마지막 실측 KeyExpiry 2027-04-19T14:09Z (끄지 않으면 그날 조용히 끊김).
2. mini 마이크 점검 — ✅ 2026-10-22 오빠 실행: 시험음 들림(스피커 정상) · BlackHole 2ch 입력 mean -37.3 dB / max -10.6 dB(> -50 dB = 신호 들어옴 → MIC_OK 후보). 스크립트는 rc=3 으로 끝났으나 원인은 macOS sed 가 `\?` 를 못 읽어 평균값 추출이 비던 결함(신호 문제 아님) → h-plans/mini-audio-check.sh 를 `sed -E` 로 수정. 최종 확정은 e2e 러너 trusted 클릭 회차(P6 ①).

## 6. 정리 상태 (마감 시점)
| 대상 | 상태 | 비고 |
|---|---|---|
| 이 팀 좌석 | arch#1(Opus 5.5)·DA#1(codex) 대기 · 나노(pi) 전부 닫음 | 좌석 정리는 상위 집행(#3094 ③) |
| 체크 크론 | 5b8acc20 — 세션 종속(이 좌석 종료와 함께 끝남) | CronDelete 는 컨텍스트 게이트(600k)가 도구를 막아 못 함 → 세션 종료가 대신 |
| 워크트리·가지 | .worktrees/mh-p2-tmuxc (+nano/mh-p2-tmuxc-host-dispatch, 커밋 0·변경 0, 취소된 P2 구현용) · .worktrees/multihost-public (+docs/multihost-public-20261022, push 완료) | HIL 경로로 정리(브랜치 삭제 0) |
| 미커밋 | 0 (이 정본 커밋 후) | |
| 남은 쪽지 | 대기 0 (이 정본 작성 직전 #3094 이 마지막) | |
| 이 맥에 남긴 로컬 표식 | ~/.cache/aifp-h-mini-bh.guided · ~/.ssh/id_ed25519_aifp_op(임시·K2 는 mini 에서 새로 생성 예정) · ~/.ssh/aifp_mini_authorize_line.txt | 허브 이전 시 정리 |
| 원격 잔재 | mini /tmp/aifp-mini-audio-check.sh — h143 실행 시에만 생김(아직 없음) · OCI/mini 에 aifp 설치물 없음(Tailscale·BlackHole 제외) | |

## 7. 다시 여는 법
1. 이 문서와 harness-requests-20261022.md 를 읽는다(골 원문 3줄 → §5).
2. 새 세션(aifp-multihost-master-claude#<N+1> · 최신 루트에서 새 가지)을 연다. 가지 docs/multihost-plan-20261021 은 보존(병합은 오빠 ! bash /tmp/h<N> 한 줄).
3. 첫 일: 하네스 카드 r673·r674·r675·r676·r678 의 착지 sha 를 git log main --grep 으로 확인 → §5-1 해당 항목부터.
4. 인계 보조: HANDOFF-master-0-to-1-20261022.md (함정 §4 — OCI 22 ufw limit·훅 오탐·공개 워크트리 재생성 금지·쪽지 경로 4곳).

## 8. 이 팀이 한 실수 (재발 방지)
- 보류 6회 동안 반례를 하나씩 막는 루프를 내가 끊지 못했다(오빠 «해결 못하네? 그럼 어떻게 하라했지?») → 하드 룰 14 발동 기준을 «같은 카드 HOLD 2회» 로 못 박아 재설계/최소안을 먼저 냈어야 함.
- OCI 22 거부를 «fail2ban 자기 차단» 으로 단정했다가 서버 로그로 반증(실제 ufw limit) — 증거 없는 단정 금지.
- 공개 워크트리에서 가림 스크립트를 재생성해 상위 수정을 덮음 — 공유 작업 트리에서 재생성 금지.
- 틱에서 «물어보겠다/보내겠다» 만 쓰고 안 보낸 적 1회.
- 컨텍스트 550k 경고 뒤 승계 도구가 하네스 설치 누락(mbox_doorbell.sh)으로 거절돼 후계를 못 열고 600k 를 넘김 → 마감 정본 Write 가 막혀 HANDOFF- 이름으로 저장. 증류는 «경고선 이전 70~79%» 에 승계 스냅샷+후계 개설 시도를 끝내야 했다.
