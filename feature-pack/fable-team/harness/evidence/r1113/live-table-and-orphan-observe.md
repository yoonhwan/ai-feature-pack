# r1113 실측 — 조회 표 1장 + 실제 고아 1건 관찰(신호 0)

- 시각: 2026-10-29 16:40:05 KST · 명령은 읽기 전용(--table · --orphans --dry-run) · kill 0 · 실 kill 은 master 승인 뒤

## `FT_ROOT=<BYZ> bash bin/ft-child-watch.sh --table` (위 15줄)

```
좌석	역할	유휴분	자식MB	무거운MB	자식수	top3	조치
byz-ops-master-claude#71	master	0	961	496	7	git:258,bd.real:237	-
byz-feature-nano-f-presentation-mode-press#0	nano	0	603	236	3	pyright-langserver:235	-
byz-planner-master-claude#165	master	0	576	0	7	-	-
byz-v65-master-claude#253	master	0	541	0	9	-	-
byz-v65-nano-m7-port-path-827-facade-double-deadline#0	nano	3	511	152	2	pyright-langserver:151	-
byz-planner-desk-claude#79	desk	0	501	0	2	-	-
byz-planner-arch-claude#27	arch	0	481	0	2	-	-
byz-harness-nano-r1116-mailbox-key-by-role-not-session-nu#0	nano	0	474	45	10	pyright-langserver:44	-
byz-feature-arch-claude#65	arch	0	458	0	2	-	-
byz-feature-master-claude#50	master	0	456	0	2	-	-
byz-harness-master-claude#132	master	0	451	0	2	-	-
byz-lecture-master-claude#28	master	0	431	0	2	-	-
byz-graphics-master-claude#38	master	0	428	0	2	-	-
byz-lecture-arch-claude#7	arch	0	426	0	4	-	-
byz-planner-nano-r-sinbo-meeting-base-20261029#0	nano	1	411	0	1	-	-
```

## `bash bin/ft-seat-quiesce.sh --orphans --dry-run`

```
quiesce-cand pid=48384 name=probe rss=77MB
QUIESCED orphans mode=orphans before=77 after=77 term=0 kill=0 left=0 dry-run
남은 대상 0
```

## 고아 후보 ps (관찰)

```
48384     1 01:57  79072 /Users/yoonhwan/.local/bin/probe lsp start -f
```
