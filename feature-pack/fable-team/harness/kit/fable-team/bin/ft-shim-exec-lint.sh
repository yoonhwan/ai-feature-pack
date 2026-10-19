#!/usr/bin/env bash
# ft-shim-exec-lint.sh — «shim 은 exec 만 — 인터프리터에 넘기지 않는다» 린트 (r484). 읽기 전용.
#   워크트리 `.fable-team/bin/*` 는 r413 뒤 bash shim(1행 `#!/usr/bin/env bash` · exec 로 LIVE_BIN 진짜 도구를 부름)이다.
#   그 자리를 python3/bash/sh 에 «파일로» 넘기면 .py shim 은 python 이 bash 를 읽어 SyntaxError(뉴스 틱 ⑥ 1.1.37~38 실측).
#   도구는 자기 폴더($HERE = LIVE_BIN) 의 형제를 부른다(r459 자리 규칙).
#   사용: ft-shim-exec-lint.sh [<bin 폴더>]   기본 = 이 파일 폴더
#         위반 0 = `OK 0건` rc0 · 있으면 줄마다 `REJECT <파일>:<줄> 인터프리터가 shim 을 읽는다 — $HERE/<도구> 로` rc1 · 폴더 없음 rc2
set -uo pipefail
DIR="${1:-$(cd "$(dirname "$0")" && pwd)}"
[ -d "$DIR" ] || { echo "ERROR: 폴더 없음 — $DIR" >&2; exit 2; }
PAT='(python3|bash|sh)[[:space:]]+"?\$\{?[A-Za-z_][A-Za-z0-9_]*\}?/\.fable-team/bin/'
n=0
while IFS= read -r hit; do
  f="${hit%%:*}"; rest="${hit#*:}"; ln="${rest%%:*}"; body="${rest#*:}"
  case "$(printf '%s' "$body" | sed 's/^[[:space:]]*//')" in '#'*) continue;; esac
  tool="$(printf '%s' "$body" | grep -oE '/\.fable-team/bin/[^"[:space:]]+' | head -1)"; tool="${tool##*/}"
  echo "REJECT $(basename "$f"):$ln 인터프리터가 shim 을 읽는다 — \$HERE/${tool:-<파일>} 로"
  n=$((n+1))
done < <(find "$DIR" -maxdepth 1 -type f ! -name '*.bak*' -print0 | sort -z | xargs -0 grep -nIE "$PAT" /dev/null 2>/dev/null)
[ "$n" = 0 ] && { echo "OK 0건"; exit 0; }
exit 1
