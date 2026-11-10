# h 묶음 — 앵커 A(계정별 요청 기록) 켜기 · 끄기·지우기 · 알림 설치 (r1571 · Issue byz#8209)

목적: cliproxy 가 어느 계정으로 요청을 보냈는지 계정별로 남겨 «계정 한도 도달 시각(앵커)» 을 직접 잰다.
기한: **2026-11-17 13:00 KST** 에 끝난다. 끝나면 지운다(오빠 Slack 1794294655.963939 «끝나면 지우는거 잊지않도록 처리»).
비밀 0: 쪽지·추출 결과·이 문서에 토큰·키 값을 적지 않는다. 계정은 이메일 그대로 쓴다(이미 auth 파일 이름).

★이 문서의 모든 단계는 h(사람 승인)다. 나노·좌석은 실행하지 않는다.★
★재기동 폴백 0 (DA R2): 켜기 h 안에서 cliproxy 를 restart·kill·launchctl kickstart 하지 않는다. 재적재가 확인되지 않으면 3키를 되돌리고 «A 보류 — 재적재 안 됨 · 재기동은 별도 판단» 1줄로 끝낸다.★

값 1곳(정본): 끝 시각 = `2026-11-17 13:00 KST`(= epoch 1794888000) · 상태 상한(logs-max-total-size-mb) = `1024`
— 스크립트 `feature-pack/fable-team/harness/bin/ft-anchor-a-request-log.sh` 상단 상수 2줄과 이 줄이 같은 값이다(다르면 카드 FAIL).

산출물(이 묶음)
| 파일 | 역할 |
|---|---|
| `feature-pack/fable-team/harness/bin/ft-anchor-a-request-log.sh` | 알림(끝 시각·24시간 반복·완료 표식) · 크기 경보(80%) · 전환 추출(하루 1회) |
| `feature-pack/fable-team/harness/bin/ft-anchor-a-request-log.plist` | launchd 템플릿(1시간 간격 1개) — 자리표시자 **6개**(`__SCRIPT__`·`__WORKTREE__`·`__COMM__`·`__SEATS__`·`__STATE__`·`__LOGS__`) 치환 후 설치(§3 2번) |
| `feature-pack/fable-team/harness/tests/test_anchor_a_request_log_r1571.sh` | 격리 시험(가짜 시계·로그·mbox·명부) |

---

## §0 사전 확인(쓰기 0)

1. `bash -n feature-pack/fable-team/harness/bin/ft-anchor-a-request-log.sh` → rc0
2. `bash feature-pack/fable-team/harness/tests/test_anchor_a_request_log_r1571.sh` → 마지막 줄 `PASS` (실 로그·실 우편함 접촉 0 — 격리 임시 폴더만 쓴다)
3. `plutil -lint feature-pack/fable-team/harness/bin/ft-anchor-a-request-log.plist` → OK
4. config 현재 값 확인(읽기만): 관리 API 또는 `~/.cli-proxy-api/config.yaml` 에서 `logging-to-file` · `debug` · `logs-max-total-size-mb` 3키.
   지금 값: `logging-to-file=false` · `debug=false` · `logs-max-total-size-mb=0`(상한 없음).
5. 수신자 확인: `.fable-team/seats-planner.json` 의 `_desk`(desk) · `_hil_route`(planner master). 둘 중 하나라도 비면 스크립트가 rc3 으로 멈춘다(다른 좌석으로 대신 보내지 않는다).

---

## §1 켜기 h (3키 · 재적재로만 · 재기동 0)

> 이 단계는 사람이 config 를 고친다. 나노·좌석은 config.yaml 을 쓰지 않는다.

1. **백업 1개**: `cp -p ~/.cli-proxy-api/config.yaml ~/.cli-proxy-api/config.yaml.bak-anchorA-$(date +%Y%m%d-%H%M%S)` → `ls -l` 로 1개 확인.
2. **3키만 바꾼다**(다른 키 0):
   - `logging-to-file=true`
   - `debug=true`
   - `logs-max-total-size-mb=1024`
3. **켜기 재적재 확인(기한 60초)**: 켜기 시각 이후에 쓰인 줄에서 다음 중 하나를 본다.
   - `log level changed from %s to %s (debug=true)` 줄(설정 감시 재적재 흔적), 또는
   - `~/.cli-proxy-api/logs/` 에 main 로그 파일이 새로 생김.
   ★이 조건은 «켜기 전용» 이다. 끝났을 때의 복구 확인은 §5 2번 조건(`debug=false` 줄)을 쓴다 — 섞으면 복구가 영원히 실패한다.★
4. **60초 안에 확인되지 않으면**: 같은 h 안에서 3키를 백업 값으로 되돌리고(`logging-to-file=false` · `debug=false` · `logs-max-total-size-mb=0`) 재적재를 다시 확인한다.
   → planner 에 «A 보류 — 재적재 안 됨 · 재기동은 별도 판단» 1줄. 이 h 안에서 restart·kill·launchctl 호출 0.
5. 확인되면 재적재 확인 시각을 적는다(다음 단계 관측 기한의 기준).

## §2 1건 관문 h (기한 30분 · 상수 1곳)

- **관측 기한 = 재적재 확인 시각 + 30분.** 증거는 «켜기 시각 뒤에 쓰인» `Use OAuth <계정> for model` 줄 1개다. 켜기 전 로그 줄 재사용 0.
- 결과는 4가지 중 하나다(어느 쪽이든 «복구 → 재적재 확인» 2단계를 건너뛰지 않는다).
  | 결과 | 뜻 | 조치 |
  |---|---|---|
  | ⓑ1 식별 있음 | 통과 | 켠 채 유지 · 끝 시각까지 둔다 |
  | ⓑ2 식별 없는 요청 줄만 있음 | 실패 | 3키 복구 → 재적재 확인 → planner «A 불가(사유)» |
  | ⓑ3 기한까지 새 요청 0 | 판정 불가 | 3키 복구 → 재적재 확인 → planner «A 불가(사유)» |
  | ⓑ4 관측 실패(로그 파일 못 읽음 등) · h 정상 중단 | 판정 불가 | 3키 복구 → 재적재 확인 → planner «A 불가(사유)» |
- 복구 확인이 실패하면 «A 불가 — 복구 확인 필요» 1줄 + 성공 처리 0(SIGKILL 같은 강제 종료 복구는 범위 밖).

## §3 알림 설치 h (launchd 1개 · 1시간 간격)

> 끄기를 잊지 않게 하는 장치다. 설치 뒤에는 손으로 알림을 보내지 않는다.

1. 스크립트를 라이브 bin 에 둔다(추적본 = 팩 PR, 라이브 = 설치 사본):
   `cp -p feature-pack/fable-team/harness/bin/ft-anchor-a-request-log.sh "$(cat <리포>/.fable-team/LIVE_BIN)/"` (경로는 설치 꼴에 따른다)
2. plist 치환 6개: `__SCRIPT__` = 라이브 스크립트 절대경로 · `__WORKTREE__` = 리포 공용 루트(작업 폴더 — launchd 는 cwd=/ 로 띄운다) · `__COMM__` = `<리포>/.fable-team/comm` · `__SEATS__` = `<리포>/.fable-team/seats-planner.json` · `__STATE__` = `~/.claude/fable-team/state/capacity` · `__LOGS__` = `~/.cli-proxy-api/logs` → `~/Library/LaunchAgents/com.byz.ft-anchor-a-request-log.plist`
   ★env 를 빼면 스크립트가 문맥을 못 풀어 rc3 으로 «알림 전에» 끝난다(DA R1). 자리표시자가 남은 plist 는 bootstrap 하지 않는다.★
3. `plutil -lint` → OK → `launchctl bootstrap gui/$UID <plist>` → `launchctl print gui/$UID/com.byz.ft-anchor-a-request-log` 에 `state = running`
4. 손 시험 2회(로그만): `cd / && bash <라이브 스크립트>` (= launchd 와 같은 cwd) → `/tmp/ft-anchor-a-request-log.log` 에 ERROR 0 · 상태 파일 `~/.claude/fable-team/state/capacity/anchor-a-alert.state` 생성. 로그 폴더가 비어 있어도 rc0 이어야 정상이다(추출 0행).
5. 이 시점부터 1시간마다: 끝 시각 전 = 조용, 끝 시각 뒤 = desk·planner 에 «끄기·지우기 h 실행 요청» 1통(24시간마다 반복), 로그 합계가 상한의 80% 이상이면 «크기 경보» 1통(같은 구간 반복 0).

## §4 전환 추출(자동 · 하루 1회 · 읽기만)

- 같은 스크립트가 하루 1회 `~/.claude/fable-team/state/capacity/anchor-a-transitions.tsv` 를 갱신한다. 형식 = `시각<TAB>이전 계정<TAB>다음 계정` 1행(fill-first 라 계정이 바뀐 첫 줄 = 한도 도달 시각).
- 로그는 읽기만 한다(수정·삭제 0). API key 이름은 `(api-key-id)` 로 가린다(비밀 0).
- 계산·상수 반영(앵커 값)은 aifp#3 몫이다. 이 도구는 «시각 표» 만 남긴다.

## §5 끄기·지우기 h (끝 시각 2026-11-17 13:00 뒤 · 순서 고정)

1. **추출 결과 인계 먼저**: `anchor-a-transitions.tsv` 를 aifp#3 에 넘겼는지 1줄 확인. 안 넘겼으면 지우기 전에 넘긴다.
2. **3키 복구**: `logging-to-file=false` · `debug=false` · `logs-max-total-size-mb=0` → **복구용 재적재 확인(기한 60초 · 조건은 켜기와 다르다)**: 복구 시각 뒤에 쓰인 `log level changed from %s to %s (debug=false)` 줄을 본다.
   ★켜기 확인 조건(`debug=true` 줄 · «새 main 로그 파일 생김»)을 재사용하지 않는다 — 끄면 debug 줄도 새 main 로그도 나오지 않아 영원히 실패한다(DA R3).★
   60초 안에 `debug=false` 재적재 줄이 없으면 «복구 확인 필요» 1줄 + 성공 처리 0(추측으로 넘기지 않는다).
   ★여기서 멈춘다 — 복구가 확인되지 않았으면 아래 3~6단계(관측기 종료 · 삭제 · 완료 표식 · plist 해제) 진행 0.★
3. **관측기 종료**(ⓔ′): 명령줄이 `~/.claude/fable-team/state/capacity/anchor-watch.py` 인 프로세스만 종료한다(pid 번호 고정 0 · 실행 직전 `ps` 로 명령줄 대조 · 11-10 관측 pid 97247 · `--snapshot --loop 10`) → 종료 확인 1줄.
4. **삭제 대상 = `~/.cli-proxy-api/logs/main*.log` 만**. 삭제 전 목록·크기 1줄 → 삭제 뒤 남은 수 0 확인.
   - 삭제 명령(글롭 넓히기 0): `ls -l ~/.cli-proxy-api/logs/main*.log` → `rm -f ~/.cli-proxy-api/logs/main*.log` · `ls ~/.cli-proxy-api/logs/main*.log 2>/dev/null | wc -l` → 0
   - glob 밖 0: `error-*` · `request-log-parts` · 인증 json 은 건드리지 않는다. 폴더 전체를 지우는 넓은 글롭 금지.
   - 별도 폴더의 `anchor-sampler.log` 1개도 삭제 대상이다 — 경로 고정 = `~/.claude/fable-team/state/capacity/anchor-sampler.log`(정본 · cliproxy logs 폴더 아님).
   - **보존(삭제 0) = `anchor-t0.json` · `anchor-watch.py` · `anchor-snapshots.jsonl`** — 이 셋은 지우지 않는다.
5. **완료 표식**: `~/.claude/fable-team/state/capacity/anchor-a-done` 빈 파일 생성 → 다음 1시간 실행에서 «앵커 A 해제» 1줄이 desk 에 가고 그 뒤 알림·경보 0.
6. **plist 해제 = 끄기 h 의 마지막 단계**: `launchctl bootout gui/$UID/com.byz.ft-anchor-a-request-log` → `~/Library/LaunchAgents/com.byz.ft-anchor-a-request-log.plist` 파일 제거(`~/.claude/fable-team/state/capacity` 의 상태·표식 파일은 남긴다 — 증거) → `launchctl print` 로 사라진 것 확인. 자동 bootout 은 없다(사람이 한다).
7. 끝 요약 1줄: 복구 확인 · 삭제 수 · 보존 3개 그대로 · 표식 · plist 해제.

## §6 값 반영 절차(ⓘ · aifp#3 · 이 카드는 절차 문구와 시험만)

- 측정으로 정한 값은 `~/.claude/fable-team/state/capacity/accounts.env`(현재) · `accounts.env.prev`(직전) **2슬롯에만** 둔다. 세 번째 파일(`.prev2` 등) 0.
- 갱신은 `cap-set.py` 만: `--show`(변경분 보기) · `--set KEY=V`(현재 → 직전 회전 뒤 갱신) · `--rotate`(수동 스냅샷). 직접 편집 0.
- 회전 대상 아님 = 증거·도구: `anchor-t0.json` · `anchor-snapshots.jsonl` · `anchor-watch.py` · `cap-set.py`.
- `ctx-plan` 은 **현재 1파일만** 읽는다(호출자가 `--inv-file`·`CTX_PLAN_CAP_FILE` 로 `accounts.env` 를 준다 · `.prev` 자동 읽기 0 · r1564 느슨한 연결).
- 값 계산·결정 = aifp#3. 이 카드는 문구와 시험(문서 문구 대조)만 갖는다.

## §7 이 묶음이 하지 않는 것

- config.yaml 직접 수정(§1·§5 의 사람 h 에서만) · 앵커 계산·상수 반영(aifp#3) · cliproxy 바이너리 변경 · 사용량 통계(`/v0/management/usage` 는 이 빌드 8.0.4 에서 404).
- 측정 조작(임의 Redis 쓰기 · 말풍선 DOM 주입) — 증거가 아니다.
