#!/usr/bin/env bash
# ft-proposal-register.sh — 폐기(R77 r1 · 판정 826). 조용한 통과 0: 호출하면 안내만 내고 rc 1.
#   제안서 → 제안 Issue 열기 = ft-proposal-open.sh <제안서.md> --apply · 오빠 인터뷰 판정 + 승인 = ft-proposal-approve.sh <M> --verdict N --interview <파일> --approve --apply
#   답 안 한 제안 Issue 찾기 = ft-proposal-inbox.sh. 정본 = 제안 Issue(라벨 proposal + approved).
echo "REJECT R77 r1: ft-proposal-register.sh 는 폐기됐다 — 제안서는 ft-proposal-open.sh <제안서.md> --apply 로 Issue 를 열고, 오빠 인터뷰 뒤 ft-proposal-approve.sh <M> --verdict N --interview <파일> --approve --apply 로 승인한다(판정 826)"
exit 1
