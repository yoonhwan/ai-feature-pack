C=$1; ORIG=$2; OUT=$3
run() { local src=$1 B; B=$(mktemp -d); local RL=$B/relay; echo "body" > $B/f.txt
  for sc in "send zz#1 me#1 hello" "send zz#2 me#1 hello" "send zz#3 me#1 hello" "send 'bad name' me#1 x" "relay zz#1 me#1 $B/f.txt 요약" "peek zz#1" "recv zz#1" "recv zz#1 --all" "recv nobody#1" "send zz#1 me#1 쪽지 #1601 회신" "bogus" ""; do
    eval "set -- $sc"; FT_MBOX_DIR=$B FT_MBOX_RELAY_DIR=$RL python3 $src "$@" > $B/o 2> $B/e; rc=$?
    echo "## [$sc] rc=$rc"; cat $B/o $B/e | sed -E "s#$B#<B>#g; s/[0-9]{8}T[0-9]{6}/TS/g; s/[0-9]{4}-[0-9]{2}-[0-9]{2}[T ][0-9:.+]+/TS/g"
  done; echo "## files"; (cd $B && ls -a | sort; cat mailbox.log.jsonl | python3 -c 'import sys,json;[print(sorted(json.loads(l).keys())) for l in sys.stdin]' | sort | uniq -c; python3 -c 'import json;print(sorted({k for r in json.load(open(".mbox-guard.json")) for k in r}))') | sed -E "s/[0-9]{8}T[0-9]{6}/TS/g"; }
run $ORIG > $OUT.old; run $C/mbox.py > $OUT.new
diff $OUT.old $OUT.new && echo "SCEN_SAME $(grep -c '^## \[' $OUT.old)"
