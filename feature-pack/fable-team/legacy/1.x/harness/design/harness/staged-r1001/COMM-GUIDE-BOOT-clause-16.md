# staged-r1001 — COMM-GUIDE-BOOT 16 «체크 크론» 줄 끝 1구 (R1001)

설치는 master 집행(라이브 BOOT 에 cp 전 `ft-version.sh check` 의 BOOT sha 대조 · 선복사 규칙). 이 폴더 파일은 «한 구절»만 담는다.

## 더하는 위치
`~/.claude/skills/tmuxc/COMM-GUIDE-BOOT.md` 16번 줄(`16. **체크 크론 = 부팅 보고 직후**…`) 맨 끝, 마지막 문장 `받는 오케는 그 칸이 비면 그 턴에 되묻는다.` 바로 뒤에 아래 구를 이어 붙인다.

## 추가 구 (글자 그대로)
` ★틱마다 «한 일 정리» 1통을 보낸다 — `{mbox} send <보고처> <나> "[정리] <한 일 3줄 이내>"`(팀장의 보고처 = master · master·planner 의 보고처 = 오케). 이 쪽지가 팀장 심박이고, 심박이 15분(주기 10분 + 여유 5) 끊기면 `ft-stall-scan` 이 그 팀에 `[멈춤]` 1통만 낸다(팀장 좌석의 b·d 경보는 그동안 0) — 그래서 이 한 통을 빠뜨리면 그 팀이 «멈춤» 으로 읽힌다.`

## 전문 매핑표 갱신 1줄
`| §1.1 mbox 명령·규약 | 119–155 | | O(4): 명령 5종 · notify 규칙 · READ 인용 · ★심박 `[정리]` 1통은 §16★ |`

## 검증
- 시험: `tests/test_stall_scan_lead_heartbeat_r1001.sh` rc0 (ⓐ~ⓗ 18 passed · 회귀 37/7/6/12 passed · 변이 2종 FAIL · kit 짝 cmp0).
- 짝 사본: `feature-pack/fable-team/harness/bin/` = `feature-pack/fable-team/harness/kit/fable-team/bin/` cmp 0 (`ft_stall_scan.py` · `ft_stall_detect.py`).
