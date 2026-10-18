# 반송 지시 r1 — R87 LOOM 터널 launchd 설치 도구 (DA HOLD #73139 · arch#27 판정 · 2026-10-10)

골 원문:
> 내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
> 하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
> 메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.
골의 축: C(업그레이드·반영) — #1213 구현 교정.

대상: 가지 `nano/r87-loom-tunnel-launchd` f655d4daf9 · `scripts/harness-install/loom-tunnel/install.sh` · plist 틀 · 시험. 같은 가지에 커밋, push 금지.

## 원칙 (설계 판정)
«옛 터널을 끊는 것»은 «새 터널이 DB 까지 확인된 뒤»에만 한다. 순서를 바꾼다: 새 launchd 터널은 옛 터널이 쥔 38309 와 충돌하므로, ①사전검증(비대화 인증·호스트키)을 옛 터널이 살아 있는 동안 «다른 빈 포트»로 끝낸 뒤 ②옛 pid 종료 → launchd 기동 → 38309 LISTEN + `select 1` 확인, ③실패면 복구.

## 필수 교정 6
1. **사전검증(③ · install 91→93)**: 옛 pid 종료 «전»에 같은 명령을 비대화 옵션(`-o BatchMode=yes` · gcloud `--quiet` · `--strict-host-key-checking=yes` 등 실제 쓰는 값)으로 38301~38399 빈 포트에 1회 열어 `select 1` 성공 → 그 pid 만 종료. 실패면 옛 터널 손대지 않고 REJECT(전환 0).
2. **same_command 정확 대조(② · 31~32)**: 부분 문자열 금지. 옛 pid 의 실제 argv 에서 VM 이름·`--account`·`--zone`·`-L 38309:10.2.0.10:5432` 를 토큰 단위로 «정확히» 대조(접미사 `-unrelated`·다른 계정·다른 지역 = REJECT). TERM 직전 그 pid 의 argv·시작 시각을 다시 읽어 같을 때만 TERM.
3. **외부 호출 상한(① · 59~62)**: secret 조회·psql·`select 1` 전부 1회 7초 + 재시도 1회(`timeout 7` 등) — 멈춤으로 롤백에 못 닿는 경로 0.
4. **전환 실패 전 경로 복구(① · 77~81)**: TERM 뒤 어느 단계든 실패하면 복구. `launchctl bootout` 결과를 검사(실패도 기록) · 복구 성공 판정 = 38309 LISTEN 의 소유 pid 가 «복구로 띄운 그 pid» ∧ `select 1` 성공(아무 pid 의 LISTEN 은 성공 아님).
5. **복구 소유권(④ · 79~80)**: `nohup` 만으로는 호출 세션의 SID/PGID 를 물려받는다(DA 재현). 복구 터널도 세션 밖 감독자 소유로 — launchd 일회성 job(`launchctl submit` 또는 별도 label 의 1회 plist) 또는 `setsid` + 부모 1 확인. 복구 뒤 ppid=1 ∧ 호출자와 SID 다름을 확인해 출력.
6. **시험 추가**: 위 1~5 각 실패 경로를 가짜 ps/launchctl/gcloud/psql 로 재현 — 사전검증 실패 → 옛 pid TERM 0 · 접미사·계정·지역 다른 프로세스 → REJECT · 외부 호출 멈춤 스텁 → 7초 상한 뒤 복구 도달 · bootout 실패 기록 · 복구 성공 판정이 «다른 pid LISTEN» 이면 실패 · 복구 프로세스 SID ≠ 호출자. 기존 시험 전부 PASS.

## 완료 조건
`bash tests/harness/test_loom_tunnel_install.sh` rc=0 · `bash -n` · 증거 줄 `세트: <40hex> · 시험: bash tests/harness/test_loom_tunnel_install.sh rc=0 · 이슈: #1213` → DA 2차(같은 범위 · 마지막 1회 · bounded).
