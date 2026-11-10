#!/usr/bin/env bash
# ft-resource-du-lib.sh — ft-resource-watch.sh 가 source 하는 증분 du 측정 함수(r534). 단독 실행 0.
#   감시자 전역을 쓴다: STATE · DISK_TSV · DU_CACHE · DU_LOCK · DU_CAP · PER_TICK · SPLIT_MAX · run_capped. 읽기·기록만(지우기 0 — 지우는 건 자기 임시 파일·캐시 줄·죽은 pid 의 스캔 잠금뿐).
#   du_line · du_lock 은 R323 감시자 본문에서 옮겨 왔다(r522 병합 뒤 감시자 줄 수 ≤245 · 동작 변경 0).
TAB="$(printf '\t')"; NL='
'
du_line() { # now name path
  local now="$1" name="$2" p="$3" raw rc
  if [ ! -e "$p" ]; then printf '%s\t%s\t0\n' "$now" "$name" >> "$DISK_TSV"; return; fi
  raw=$(run_capped du -sk "$p"); rc=$?
  if [ "$rc" = 124 ]; then printf '%s\t%s\tTIMEOUT\n' "$now" "$name" >> "$DISK_TSV"; return; fi
  printf '%s\t%s\t%s\n' "$now" "$name" "$(printf '%s' "$raw" | awk 'END{print $1+0}')" >> "$DISK_TSV"
}
du_lock() { # 스냅샷 전체에 잠금 1개 — rc0 = 잡음 · rc1 = 다른 살아 있는 스캔이 있음. 죽은 pid 의 잠금은 회수.
  local hp
  mkdir "$DU_LOCK" 2>/dev/null || {
    hp="$(cat "$DU_LOCK/pid" 2>/dev/null)"
    if [ -n "$hp" ] && ! kill -0 "$hp" 2>/dev/null; then rm -r -f "$DU_LOCK"; mkdir "$DU_LOCK" 2>/dev/null || return 1; else return 1; fi
  }
  echo $$ > "$DU_LOCK/pid"
}
# r534: 큰 폴더(워크트리 443개 등)를 통째 du 1회로 재면 7초 상한에 매번 걸린다(10-17 뒤 worktrees.total TIMEOUT 393회) → 1단계 단위로 나눠 틱마다 몇 개씩.
#   캐시 du-cache.tsv 줄 = ts · <pfx>:<rel> · kb · 직전 ts · 직전 kb · 표식(빈 값 | stale = 상한 넘김·옛 값 보존·합 제외 | split = 다음 틱부터 그 아래 1단계로 · 깊이 SPLIT_MAX) + 바퀴 시작 줄 ts · <pfx>#round
_inc_walk() { # base rel depth splits [find 조건…] — 출력 «U|S<TAB>rel<TAB>mtime<TAB>d|f» (S = 나눔 표식 폴더 · 그 아래로 내려감)
  local base="$1" rel="$2" d="$3" sp="$4" m k p r; shift 4
  find "$base${rel:+/$rel}" -mindepth 1 -maxdepth 1 "$@" -exec stat -f '%m%t%HT%t%N' {} + 2>/dev/null | while IFS="$TAB" read -r m k p; do
    r="${rel:+$rel/}${p##*/}"; [ "$k" = Directory ] && k=d || k=f
    case "$NL$sp$NL" in *"$NL$r$NL"*) if [ "$k" = d ] && [ "$d" -lt "$SPLIT_MAX" ]; then printf 'S\t%s\t%s\td\n' "$r" "$m"; _inc_walk "$base" "$r" $((d+1)) "$sp"; continue; fi;; esac
    printf 'U\t%s\t%s\t%s\n' "$r" "$m" "$k"
  done
}
_inc_plan() { # pfx now — stdin = 단위 목록 · 출력 = 잴 순번(캐시 없음 → 잰 뒤 바뀜(2시간 안 mtime) → 캐시 오래된 순)
  awk -F'\t' -v p="$1:" -v now="$2" -v c="$DU_CACHE" '
    FILENAME==c { if (index($2,p)==1) ts[substr($2,length(p)+1)]=$1; next }
    $1=="U" { r=$2; m=$3+0
      if (!(r in ts)) printf "0\t%d\t%s\n", -m, r
      else if (m>=now-7200 && m>ts[r]+0) printf "1\t%d\t%s\n", -m, r
      else printf "2\t%d\t%s\n", ts[r], r }' "$DU_CACHE" - | sort -t "$TAB" -k1,1n -k2,2n | cut -f3-
}
_inc_merge() { # pfx now units res — 출력 «C<TAB>새 캐시 줄»(다른 칸 줄 그대로) · «F<TAB>폴더<TAB>kb<TAB>앎» · «N<TAB>합|PARTIAL 합<TAB>앎/전체» · «W<TAB>1»(한 바퀴 끝)
  awk -F'\t' -v OFS='\t' -v p="$1:" -v rk="$1#round" -v now="$2" -v smax="$SPLIT_MAX" -v c="$DU_CACHE" -v uf="$3" '
    function tp(r) { sub(/\/.*/, "", r); return r }
    function dep(r) { return gsub(/\//, "/", r) }
    function put(t, r, k, pt, pk, f) { print "C", t, p r, k, pt, pk, f; fts[r]=t; fkb[r]=k; ffl[r]=f }
    FILENAME==c { if ($2==rk) { rs=$1; next }
      if (index($2,p)==1) { r=substr($2,length(p)+1); L[r]=$0; ts[r]=$1; kb[r]=$3; pts[r]=$4; pkb[r]=$5; fl[r]=$6 }
      else if (!(p=="wt:" && $2=="worktrees.total")) print "C", $0   # 옛 통째 합 캐시 줄은 버림
      next }
    FILENAME==uf { top[tp($2)]=1; if ($1=="S") { if ($2 in L) print "C", L[$2] } else { nu++; U[nu]=$2; ty[$2]=$4 }; next }
    { R[$1]=$2 }
    END { if (rs=="") rs=now; done=1
      for (t in top) ok[t]=1
      for (i=1;i<=nu;i++) { r=U[i]; t=tp(r)
        if (r in R && R[r]=="TIMEOUT") {
          if (ty[r]=="d" && dep(r)<smax) { print "C", now, p r, "-", "", "", "split"; ok[t]=0; done=0; continue }
          put(now, r, kb[r], "", "", "stale") }
        else if (r in R) { fresh=(kb[r] ~ /^[0-9]+$/ && fl[r]==""); put(now, r, R[r], fresh?ts[r]:"", fresh?kb[r]:"", "") }
        else if (r in L) { fts[r]=ts[r]; fkb[r]=kb[r]; ffl[r]=fl[r]; print "C", L[r] }
        else { ok[t]=0; done=0; continue }
        if (ffl[r]!="" || fkb[r] !~ /^[0-9]+$/) ok[t]=0; else sum[t]+=fkb[r]
        if (fts[r]+0 < rs+0) done=0 }
      for (t in top) { m++; if (ok[t]) { k++; s+=sum[t] } print "F", t, sum[t]+0, ok[t] }
      if (done && m>0) { print "W", 1; rs=now }
      print "C", rs, rk
      print "N", (k==m ? s+0 : "PARTIAL " s+0), (k+0) "/" (m+0) }' "$DU_CACHE" "$3" "$4"
}
# r534: 폴더 dir 을 1단계 단위로 증분 측정 — 한 틱 PER_TICK 개 · 각 DU_CAP 초 · 마감 dl(SECONDS) 안에서만(마감으로 끊긴 du 는 표기 0 · 다음 틱 다시).
#   넘긴 단위 = «<pfx>:<rel> TIMEOUT» 1줄 + 폴더면 split · 아니면 stale. 기록 = «<name> <합>»(전부 앎) | «<name> PARTIAL <앎 합>» + «<known> <앎>/<전체>» — 부분 합·옛 값을 새 숫자처럼 쓰지 않는다.
#   wt 는 한 바퀴(모든 단위를 바퀴 시작 뒤 한 번씩) 끝난 틱에 «wt.top <이름> <KB>» 상위 5.
inc_group() { # now name known_name pfx dir dl
  local now="$1" name="$2" kn="$3" pfx="$4" dir="$5" dl="$6" uf rf rel raw rc cap n=0 out
  if [ ! -d "$dir" ]; then printf '%s\t%s\t0\n%s\t%s\t0/0\n' "$now" "$name" "$now" "$kn" >> "$DISK_TSV"; return; fi
  uf="$STATE/.inc-units.$$"; rf="$STATE/.inc-res.$$"; : > "$rf"
  _inc_walk "$dir" "" 0 "$(awk -F'\t' -v p="$pfx:" 'index($2,p)==1 && $6=="split"{print substr($2,length(p)+1)}' "$DU_CACHE")" -type d > "$uf"
  while IFS= read -r rel; do
    [ -n "$rel" ] && [ "$n" -lt "$PER_TICK" ] || break
    cap=$((dl-SECONDS)); [ "$cap" -ge 1 ] || break; [ "$cap" -le "$DU_CAP" ] || cap="$DU_CAP"
    raw="$(DU_CAP="$cap" run_capped du -sk "$dir/$rel")"; rc=$?
    if [ "$rc" = 124 ]; then
      [ "$cap" -lt "$DU_CAP" ] && break
      printf '%s\tTIMEOUT\n' "$rel" >> "$rf"; printf '%s\t%s:%s\tTIMEOUT\n' "$now" "$pfx" "$rel" >> "$DISK_TSV"
    else printf '%s\t%s\n' "$rel" "$(printf '%s' "$raw" | awk 'END{print $1+0}')" >> "$rf"; fi
    n=$((n+1))
  done <<EOF
$(_inc_plan "$pfx" "$now" < "$uf")
EOF
  out="$(_inc_merge "$pfx" "$now" "$uf" "$rf")"; rm -f "$uf" "$rf"
  printf '%s\n' "$out" | sed -n "s/^C$TAB//p" > "$DU_CACHE.tmp.$$" && mv "$DU_CACHE.tmp.$$" "$DU_CACHE"
  printf '%s\n' "$out" | awk -F'\t' -v now="$now" -v nm="$name" -v kn="$kn" '$1=="N"{print now"\t"nm"\t"$2; print now"\t"kn"\t"$3}' >> "$DISK_TSV"
  [ "$pfx" = wt ] && printf '%s\n' "$out" | grep -q "^W${TAB}1" && printf '%s\n' "$out" | awk -F'\t' '$1=="F" && $4==1 {print $3"\t"$2}' \
    | sort -rn | head -5 | awk -F'\t' -v now="$now" '{print now"\twt.top\t"$2" "$1}' >> "$DISK_TSV"
  return 0
}
