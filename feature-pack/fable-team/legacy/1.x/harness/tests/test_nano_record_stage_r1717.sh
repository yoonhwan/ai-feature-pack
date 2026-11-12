#!/usr/bin/env bash
# test_nano_record_stage_r1717.sh — r1717 묶음 1 단계 사례 E1~E8(DA 보정 R1·R2·R3 + 자동 닫기 조건 ⓐ~ⓔ). 변이 대조(M7·M14·M15·M17·M18·M19) = test_nano_record_stage_mut_r1717.sh
#   E1 착지 줄만 있는 카드 · E2 남은 일(--left) · E3 확인 fetch 실패·닫기 요청 발신 실패 · E4 거절 뒤 rec 가 바뀌면 1회 다시 · E5 시험 rc≠0 · E6 세션 기록 쓰기 실패
#   E7 동시 landed · E8 ⓐ 역할 ⓑ 조상 재확인 ⓓ 실패 알림(가짜 닫기 도구) · ⓒⓔ «실» ft-nano-close.sh 사본을 ft_stall_scan auto_close 가 집행
#   세계 = _nano_record_r1717_fixture.sh · 사례 함수 = _nano_record_r1717_stage_cases.sh · 실 명부·실 우편함·실 tmux·네트워크 0 · sleep 0 · 자기 파일 재호출 0
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$HERE/_nano_record_r1717_fixture.sh"; . "$HERE/_nano_record_r1717_close_fixture.sh"
world; closebin; . "$HERE/_nano_record_r1717_stage_cases.sh"
step "사례 E1~E4"; run "E1 착지 줄만 있는 카드(R1)" e1; run "E2 남은 일(R1)" e2; run "E3 확인·발신 실패 뒤 이어 가기(R1)" e3; run "E4 거절 뒤 rec 바뀌면 1회 다시" e4
step "사례 E5~E8"; run "E5 시험 rc≠0" e5; run "E6 세션 기록 쓰기 실패(R2)" e6; run "E7 동시 landed(R3)" e7; run "E8 ⓐⓑⓓ 자동 닫기 조건" e8; run "E8 ⓒⓔ 실 닫기 사본 집행" e8r
finish
