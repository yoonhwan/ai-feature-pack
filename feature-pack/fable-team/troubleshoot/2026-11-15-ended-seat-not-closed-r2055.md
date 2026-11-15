# 사고 기록 — 끝난 좌석이 일주일 동안 안 닫혔다 (r2055 · 보정 3 · r2065)

- 날짜: 2026-11-15 · 기록: aifp-ft-arch-pi#15(aifp 5297 · planner#322 배분 5296)
- 오빠 원문: «닫힘감지 닫기 제대로 아키해서 다시는 안나오게 · 일주일 해결 안 됨»(Slack 1794730232.295539) · «끝난 좌석 자동정리 완전 정상화 일반화. 신규케이스 대응되도록»(Slack 1794730277.871759)
- 설계 정본: `feature-pack/fable-team/design/DESIGN-r2055-seat-settle-one-path.md` · 계약: `feature-pack/fable-team/ft2/contracts/keeper-settle/`
- 이 기록의 증상·원인 문장은 설계 §1·§3b 에서 옮겼다. 설치 시각은 `~/.claude/fable-team/ft2/install-log.jsonl` 에서 읽었다.

## 1. 증상

| 증상 | 실사건(설계 §1) |
|---|---|
| 끝난 나노가 «착지 줄 없음» 으로 계속 HELD | knowledge 오사카 loom 1335분 · harness r1721·r1742·r1746·r1749 · v65 conn-1 |
| 팀 걸친 카드가 «카드 후보 0» 으로 HELD | knowledge conn-2·3·4·6(카드 = design/teams/v65 · 팀 행 = design/teams/knowledge) |
| 접수 칸이 안 풀림 | harness 남은 일 8/8 · r1968·r1973 은 세션 0 인데 owner 가 남아 반환 거부 |
| 정지 신호가 두 벌 | keeper 가 ALL_STOP 을 안 읽어 `<팀>-tick/PAUSED` 13개로 대신함 |
| HELD 가 드러나지 않음 | harness HELD 로그 하루 12,184줄 · 통보 0(설계 §3b) |

같은 날 조건 18① 표본에서도 같은 꼴이 났다. 착지 도구가 카드 «- 착지:» 줄을 쓰지 않아 keeper 가 닫지 못했고, arch 좌석이 그 줄을 손으로 보완한 뒤에야 complete 했다(착지부터 complete 까지 harness 37분 · planner 27분 · BYZ `checker/r1771-cond18-1-20261113` @3f1e997f19 장부).

## 2. 원인

- 한 줄: «세션을 닫아도 되나» 를 «착지했나» 로 대신 물었다.
- 착지는 사람·DA·try-auto·HIL 이 끼는 긴 사슬이다. 그 사이 끝난 나노는 세션을 쥔 채 칸을 막았다.
- 카드·PR·장부 중 하나만 어긋나도 판정이 «판정 불가» 가 됐고, 그 판정 불가는 HELD 1줄로 끝났다.
- 원인마다 땜질(noland 목록 · 짝 표 손 채우기 · PAUSED 파일)을 일주일 반복했다. 새 꼴이 나올 때마다 다시 HELD 가 됐다(설계 §9 버린 안 ⓧ).

| 원인 | 그때 코드(설계 §1 · 읽은 판 ft2 2.0.60) |
|---|---|
| 세션 닫기가 착지에 묶임 | `keeper_close.py` close = 착지 조상일 때만 kill · 아니면 HELD |
| 카드를 못 찾으면 «끝남» 판정 불가 | `keeper_land.py` landing = 짝 표 → 팀 폴더만 |
| 칸 = 장부 기준 · 세션 생사와 무관 | `record.py` remaining = done·returned 만 뺌 · owner 가 있으면 반환 거부 |
| 정지 신호 두 벌 | `keeper.py` _round = SKIP_TEAMS 만 봄 |

## 3. 고침

| 고침 | 팩 sha · PR | 바꾼 것 |
|---|---|---|
| settle 한 길 | d88ef381161e9f68546055a2cbe380f5658d41ef · PR 1246 | 좌석마다 판정 1개(LANDED·PARKED·WORKING·UNKNOWN) · HELD 판정 폐지 · core `park` 동사 · work 단위 `capacity` 셈 · `resolve_card` 3단계 · ALL_STOP 판독 |
| 보정 3 | 77511fccb4e384dd00eb28cb5ae9f1718a036ee8 · PR 1249 | `accept_only` 가 work 문자열인 접수만 봄(dict·None work 에서 TypeError) |
| r2065 | 4b0567c307624ec9faa98522a49b8c4b970f619b · PR 1250 | 1.x `ft_launchd_llm_gate.py`(bin · kit 두 사본): 기준선의 같은 (경로·줄) 결합을 집합으로 읽음 |

고침 뒤 달라지는 것(계약 `CONTRACT.md`):

- 세션은 «일이 끝났고 남길 것이 안전하면» 닫는다. 착지는 일의 상태로만 따로 센다.
- 못 채운 판정은 `UNKNOWN` + [긴급] 1줄로 드러난다. 조용한 HELD 는 없다.
- 쉼(parked) work 는 의무 장부에는 남고 용량에서만 빠진다.

## 4. 설치 경과 (install-log · UTC)

| 시각 | 행 | 뜻 |
|---|---|---|
| 12:20:11Z | install 2.0.61 rc0 | r2055 settle 을 실은 판 |
| — | 2.0.61 postcheck FAIL rc8 | 원인 = `accept_only` 의 dict work TypeError(77511fcc 커밋 글) |
| 12:24:14Z | rollback 2.0.60 rc1 | 되돌림 거절 — 원인 = launchd LLM 판정기가 기준선 같은 열쇠의 마지막 줄만 봄(4b0567c3 커밋 글) |
| 12:29:23Z | rollback 2.0.60 rc0 | 되돌림 성공 |
| 12:55:36Z | install 2.0.62 rc0 | 설치본 `adapters/pi/keeper_settle.py` 가 팩 origin/main(77511fcc 포함)과 같음(`cmp` 로 확인 · 2026-11-15 23:4x) |

- [확인 필요: 12:24 되돌림 거절이 12:29 에 어떻게 풀렸는지 — r2065 착지(13:05Z)보다 앞이다. install-log 에는 사유 칸이 없다]
- [확인 필요: 설치 뒤 실사건 관측(끝난 나노 0석 · 새로 끝난 나노가 손 없이 닫힘) 값 — 이 기록을 쓸 때 읽지 않았다 · master 몫]

## 5. 다음에 같은 증상이 보이면

1. keeper 원장 `.fable-team/state/ft2-keeper/<날짜>.jsonl` 에서 그 좌석의 판정 줄과 사유 코드를 읽는다.
2. `UNKNOWN` 이면 사유 코드의 «다음 수» 를 따른다(계약 §3 · `keeper_settle.py` `NEXT` 표).
3. 판정 줄이 없는 `byz-*` 세션이 있으면 그것이 결함이다. 계약 §1 «좌석마다 바퀴당 정확히 1개» 위반으로 올린다.
4. 자동 닫기가 남긴 세션을 손으로 닫는 일은 planner master·desk 몫이다 → `~/.claude/guides/hil.md` «수동 닫기 지원 표준승인»(판정 4180).
5. 원인마다 땜질하지 않는다. 새 꼴은 settle 의 근거 칸이나 사유 코드로 넣는다.

근거: 설계 §0·§1·§3b·§9 · 팩 d88ef381·77511fcc·4b0567c3 커밋 글 · install-log 2.0.60~2.0.62 행 · BYZ checker/r1771-cond18-1-20261113 @3f1e997f19
