# r810 증거
- 새 시험 test_doc_exempt_v65_roster_r810.sh = ALL PASS (ⓐ빨강→초록 ⓑⓒⓓⓔ ⓖ변이)
- 기존 test_doc_exempt_r725(고친 것: v65 픽스처 seats.json · 변이 사본에 ft_teamset.py 동봉) · guard_r741 · test_merge_land{,_equiv,_off_approval,_push_reason,_state_dir} = ALL PASS
- test_merge_land_deny_stale(1) · test_merge_land_pack_repo(4) FAIL = 원본 origin/main(73f097b3) 사본에서도 같은 건수(BASE-origin-main-*.out) → 이번 변경과 무관(옛 판 빨강 단계가 착지 뒤 썩음)
