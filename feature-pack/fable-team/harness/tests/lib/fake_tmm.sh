#!/usr/bin/env bash
# fake_tmm.sh — `tmm ls <팀 접두>`(살아 있는 좌석 목록) 시험용 대역 (r975 r4 · arch 162 판단 4).
#   왜: r975 r4 부터 ft-nano-spawn.sh 의 «보고(회신) 대상» 은 명부 파일이 아니라 «지금 살아 있는 좌석 목록»(tmm ls) 이 정한다.
#       시험이 실 tmm 을 부르면 «실 좌석 목록» 이 새어 들어와 판정이 환경에 따라 흔들린다(오늘 실측: test_nano_team_env 가 실 좌석을 읽었다).
#   사용: . "$HERE/lib/fake_tmm.sh"
#         fake_tmm "$T/fake" <좌석 이름…>      # 스텁을 PATH 맨 앞 폴더에 만들고, 그 좌석들만 «살아 있다» 로 답하게 한다
#   스텁은 인자를 무시하고 목록 파일을 그대로 낸다(실 tmm 의 형식: `<라벨> ● <이름> <상태> …`).
#   목록을 바꾸고 싶으면 같은 폴더에 다시 호출한다(파일을 새로 쓴다).
fake_tmm() {  # <PATH 맨 앞 폴더> <이름…>
  local dir="${1:?fake_tmm: 폴더 필요}"; shift
  mkdir -p "$dir" || return 1
  : > "$dir/tmm.lst"
  local n
  for n in "$@"; do printf 'harne ● %s IDLE  fabl5·hi 09~14  0m harness-ops\n' "$n" >> "$dir/tmm.lst"; done
  printf '#!/usr/bin/env bash\n# r975 r4 시험 대역 — 살아 있는 좌석 목록(tmm ls)\ncat "%s/tmm.lst" 2>/dev/null\n' "$dir" > "$dir/tmm"
  chmod +x "$dir/tmm"
}
