#!/usr/bin/env bash
# test_nano_record_stage_mut_r1717.sh — r1717 단계 사례의 변이 대조: M7(카드 ref 확인 삭제 → E3) · M14(필수 3줄 판정을 착지 줄 하나로 → E1) · M15(잔여 판정 삭제 → E2)
#   M17(열쇠에서 rec 삭제 → E4) · M18(A11 role 검사 삭제 → E8 ⓐ) · M19(NEXT 앞 입력 확인 삭제 → E6) — 변이마다 bin 사본 1곳만 바꾸고(원본 불변) 같은 사례를 원본으로 1회 더(반대 결과).
#   사례 함수 = _nano_record_r1717_stage_cases.sh(사례 본 실행 = test_nano_record_stage_r1717.sh) · 실 명부·실 우편함·실 tmux·네트워크 0 · sleep 0 · 자기 파일 재호출 0
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$HERE/_nano_record_r1717_fixture.sh"; . "$HERE/_nano_record_r1717_close_fixture.sh"
world; closebin; . "$HERE/_nano_record_r1717_stage_cases.sh"
step "변이 M7·M14·M15·M17·M18·M19 (+원본 대조)"
mutbin m7 ft_nano_record_write.py '    return "DONE", verify(ctx, team, iroot, stem, add)   # r1717-mut:verify' '    return "DONE", lines[st + 1:en] + add'; mutcase M7 e3 7
mutbin m14 ft_nano_record_due.py '    miss = "".join(s for s, k in (("ⓢ", "s"), ("ⓛ", "l"), ("ⓒ", "c")) if not m[k])   # r1717-mut:three' '    miss = "" if m["l"] else "ⓛ"'; mutcase M14 e1 14
mutbin m15 ft_nano_record.py '    return t in ("", "없음") or all(' '    return True or all('; mutcase M15 e2 15
mutbin m17 ft_nano_record_auto.py ", f\"{tok.get('set', '')}|{tok.get('rec', '')}\"" ", tok.get('set', '')"; mutcase M17 e4 17
mutbin m18 ft_nano_record_auto.py '    if role != "nano":   # r1717-mut:autorole' '    if False:'; mutcase M18 e8 18
mutbin m19 ft_nano_record_write.py '    miss = [n for n, ok in (("세션 기록", path is not None and want.is_file()), ("닫기 요청 seq", seq_known(ctx, seq))) if not ok]   # r1717-mut:inputs' '    miss = []'; mutcase M19 e6 19
finish
