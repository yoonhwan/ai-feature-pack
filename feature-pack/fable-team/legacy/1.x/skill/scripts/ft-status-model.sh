#!/usr/bin/env bash
# ft-status-model.sh — 화면 텍스트(stdin)에서 마지막 모델 표기 1개를 «<이름> <숫자>» 로 출력 (r1057)
#   ⓐ 구형 상태줄  «  Model: Opus 5.5 · …»                    → «Opus 5.5»
#   ⓑ 신형 상태줄  «  ctx:?% | Opus 5.5 high | 세션명»        → «Opus 5.5» (effort 낱말 버림)
# 두 꼴이 다 있으면 화면에서 더 아래 줄을 쓴다. 못 찾으면 빈 출력 + rc0 (판정은 호출자 몫 —
# ft-tmux-spawn 은 빈 값을 fail-closed 로 죽인다).
# 시험 = feature-pack/fable-team/harness/tests/test_status_model_two_forms.sh
set -uo pipefail

exec awk '
{ line[NR] = $0 }
END {
  best_nr = 0; best = ""
  for (i = 1; i <= NR; i++) {
    s = line[i]
    # ⓐ 구형 «Model: <영문> <숫자.>» — 글자 «Model:» 가 있는 줄
    if (match(s, /Model:[[:space:]]*[A-Za-z]+[[:space:]]*[0-9][0-9.]*/)) {
      v = substr(s, RSTART, RLENGTH)
      sub(/.*Model:[[:space:]]*/, "", v)
      if (i >= best_nr) { best_nr = i; best = v }
    }
    # ⓑ 신형 «ctx:N% | <영문> <숫자.> [effort] | <세션>» — 줄 시작 고정(가운데 ctx: 는 안 읽는다)
    if (s ~ /^[[:space:]]*ctx:/) {
      n = split(s, f, "|")
      if (n >= 2) {
        g = f[2]; sub(/^[[:space:]]+/, "", g)
        if (match(g, /^[A-Za-z]+[[:space:]]+[0-9][0-9.]*/)) {
          if (i >= best_nr) { best_nr = i; best = substr(g, 1, RLENGTH) }
        }
      }
    }
  }
  if (best != "") print best
}'
