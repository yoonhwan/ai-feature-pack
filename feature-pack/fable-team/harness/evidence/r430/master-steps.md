# r430 master-steps — `ft-inbox mark` 가 큐에 없는 쪽지를 우편함 파일에서 찾아 적재 뒤 표시 (집행 순서 · master)

카드 `design/harness/indices/진행/r430-inbox-mark-finds-seq-in-rotated-mailbox.md` · 나노 byz-harness-nano-r430-inbox-mark-finds-seq-in-rotated-mai#0

## 가지 1
| 리포 | 가지 | 내용 |
|---|---|---|
| ai-feature-pack | `nano/r430-inbox-mark-finds-seq-in-rotated-mai` (워크트리 `.worktrees/nano-r430-inbox-mark` · base ed8e118e) | `kit/fable-team/bin/ft_inbox_core.py`(find_seq) · `kit/fable-team/bin/ft-inbox.py`(locate 적재·MARKED 줄) · `harness/bin/` 짝 cmp0 · 새 `harness/tests/test_inbox_mark_rotated.sh` · CHANGES 1절 · manifest 1.1.23 |

## 순서
1. 팩 PR → main 착지(master). 착지 전 `bash feature-pack/fable-team/harness/tests/test_inbox_mark_rotated.sh` rc0(23 PASS) · `test_inbox.sh` rc0. 판 1.1.23 이 다른 가지와 겹치면 착지 순번대로 master 조정.
2. 설치: `bash feature-pack/fable-team/harness/install.sh --apply --project <BYZ 공용 루트>` → `cmp <팩>/harness/kit/fable-team/bin/ft-inbox.py "$(head -1 <루트>/.fable-team/LIVE_BIN)/ft-inbox.py"` rc0 (ft_inbox_core.py 도 같다). 되돌림 = 옛 판 LIVE_BIN.
3. 실사건 1(설치 뒤 · planner 좌석 또는 master 손): `FT_SEAT=byz-planner-master-claude#<현역> bash <루트>/.fable-team/bin/ft-inbox.sh mark 110726 처리 "r430 실사건"` → 기대 출력
   `INGEST seq=110726 queue=byz-planner-master-claude cls=⑤ group=g-e7b3b2fb92` · `OK byz-planner-master-claude.jsonl seq=110726` · `MARKED seq=110726 file=mailbox.log.jsonl`
   (나노 사전 관측 = 임시 루트에 실 우편함 3파일 심링크 + planner 큐 사본: 옛 코드 `REJECT 대상 못 찾음(좌석 byz-planner-master-claude#74): ['110726']` rc1 · 같은 seq `ingest` rc0 → 원인 = 큐 적재 빠짐)
4. 착지 뒤 arch 손: BOOT 4 mbox 절 «mark 는 큐에 없으면 우편함 파일(회전본 포함)에서 찾아 적재(r430)» 반 줄.

## 편차(카드 대비)
- 카드 가정 «mark 가 mailbox.jsonl 만 본다» 는 실측과 다름 — `mail_files()` 는 이미 3파일(+회전본 숫자 순)을 보고, mark 는 좌석 큐만 봤다. 그래서 고침 = «큐에 없으면 우편함에서 찾아 적재 뒤 표시»(조회 순서는 카드 그대로).
- 고친 파일은 `ft-mbox.py` 가 아니라 `ft_inbox_core.py`·`ft-inbox.py`(키트 2 파일 · 카드 «≤2» 안).
- locate 는 mark·report 공통이라 report 도 같은 적재를 탄다(같은 구멍).
- `ft-inbox.py` 200줄(한도 200).

## 관측 거리(실사건 때)
- send 때 적재가 왜 빠졌나: 키트 `ft-mbox.sh inbox_ingest` 는 실패를 `2>/dev/null` + `WARN` 만 남긴다 · room·v65 master 가 쓴 경로(comm/mbox.sh 인지 키트인지)와 그 시각 WARN 을 같이 본다 — 필요하면 새 카드.
- 기존 시험 `test_mbox_guard.sh`(25 FAIL)·`test_mbox_lineage.sh`(10)·`test_mbox_v2_guard.sh`(12) 는 origin/main ed8e118e 에서도 같은 수로 실패(이 가지 무관 · 나노 실측) — 고침 단위 필요.

press 필요: 없음(단위 시험만).
