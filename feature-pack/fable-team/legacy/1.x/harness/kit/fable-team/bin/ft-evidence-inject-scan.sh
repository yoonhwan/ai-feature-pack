#!/usr/bin/env bash
# ft-evidence-inject-scan.sh <파일|폴더>... — 증거 스크립트의 «측정 조작» 흔적을 훑어 보여 준다 (R63 ㉡ · 오빠 절대지침 2026-10-09)
#   임의 Redis 쓰기(제품 키 직접 주입) · 말풍선 DOM 주입(재생 하네스) 흔적을 줄 단위로 찾는다. ★차단 도구가 아니다 — 출력만★
#   패턴  ⓐ redis-cli + 같은 줄 상태 생성 동사   ⓑ 클라이언트 쓰기 호출(.hset( 등)   ⓒ /dev/bubble-replay
#         ⓓ appendChild · innerHTML= · dispatchEvent(   (★dispatchMouseEvent 는 안 맞는다 — trusted 클릭은 정상 경로★)
#            단 dispatchEvent(new [Keyboard]Event("input"|"change"|"keydown"…)) = 입력칸·키 UI 이벤트라 NOTE(기존 러너가 쓴다 — 말풍선 생성 아님)
#   허용  읽기·정리 동사(GET·SCAN·DEL·FLUSHDB 등)는 ⓐ 동사 목록에 없어 안 걸린다. ⓑ 가 isolated_redis 를 쓰는 파일 안이면 NOTE(격리 픽스처 — 별개).
#   출력  SUSPECT|NOTE <파일>:<줄> <ⓐ|ⓑ|ⓒ|ⓓ> <앞 80자>  +  INJECT-SCAN files=<N> suspect=<K> note=<J>
#   로그  SUSPECT 1개 이상이면 요약 줄을 <상태폴더>/inject-scan.log 에 시각과 함께 append (상태폴더 = env FT_INDEX_STATE_DIR 또는 <리포 루트>/.fable-team/state)
#   exit  0 = 훑음 끝(SUSPECT 유무 무관) · 1 = 인자 경로 없음(MISSING) · 2 = 인자 0
set -uo pipefail
[ $# -gt 0 ] || { echo "usage: $0 <파일|폴더>..." >&2; exit 2; }

VERBS='SET|SETEX|SETNX|MSET|HSET|HMSET|HSETNX|XADD|PUBLISH|LPUSH|RPUSH|SADD|ZADD|APPEND|INCR|INCRBY'
PAT_A="redis-cli.*[[:space:]'\"]($VERBS)([[:space:]'\"]|\$)"
PAT_B='\.(hset|hmset|xadd|publish|lpush|rpush|sadd|zadd)\('
PAT_C='/dev/bubble-replay'
PAT_D='appendChild|innerHTML[[:space:]]*=([^=]|$)|dispatchEvent\('
PAT_UI='dispatchEvent\(new (Keyboard)?Event\([\"'"'"'](input|change|keydown|keyup|keypress|focus|blur)[\"'"'"']'

files=(); missing=0
for a in "$@"; do
  if [ -d "$a" ]; then
    while IFS= read -r f; do files+=("$f"); done < <(find "$a" -type f \( -name '*.py' -o -name '*.sh' -o -name '*.js' -o -name '*.mjs' -o -name '*.ts' \) | sort)
  elif [ -f "$a" ]; then files+=("$a")
  else echo "MISSING $a"; missing=1
  fi
done

suspect=0; note=0
hit() { # <종류 SUSPECT|NOTE> <파일> <구분 ⓐ..ⓓ> <패턴> [제외 패턴]
  local kind="$1" f="$2" cat="$3" pat="$4" excl="${5:-^\$}" ln txt
  while IFS= read -r row; do
    [ -n "$row" ] || continue
    ln="${row%%:*}"; txt="${row#*:}"; txt="$(printf '%s' "$txt" | sed -e 's/^[[:space:]]*//' | cut -c1-80)"
    echo "$kind $f:$ln $cat $txt"
    if [ "$kind" = SUSPECT ]; then suspect=$((suspect+1)); else note=$((note+1)); fi
  done < <(grep -nIiE -- "$pat" "$f" 2>/dev/null | grep -viE -- "$excl")
}

for f in ${files[@]+"${files[@]}"}; do
  hit SUSPECT "$f" ⓐ "$PAT_A"
  if grep -qIi 'isolated_redis' "$f" 2>/dev/null; then hit NOTE "$f" ⓑ "$PAT_B"; else hit SUSPECT "$f" ⓑ "$PAT_B"; fi
  hit SUSPECT "$f" ⓒ "$PAT_C"
  hit SUSPECT "$f" ⓓ "$PAT_D" "$PAT_UI"
  hit NOTE "$f" ⓓ "$PAT_UI"
done

summary="INJECT-SCAN files=${#files[@]} suspect=$suspect note=$note"
echo "$summary"

if [ "$suspect" -gt 0 ]; then
  STATE="${FT_INDEX_STATE_DIR:-}"
  if [ -z "$STATE" ]; then
    ROOT="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null | sed 's|/\.git$||')"
    [ -n "$ROOT" ] && STATE="$ROOT/.fable-team/state"
  fi
  if [ -n "$STATE" ] && mkdir -p "$STATE" 2>/dev/null && printf '%s %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$summary" >> "$STATE/inject-scan.log" 2>/dev/null; then :
  else echo "WARN inject-scan.log 에 못 썼다 (상태폴더: ${STATE:-불명})" >&2; fi
fi

[ "$missing" = 0 ] && exit 0 || exit 1
