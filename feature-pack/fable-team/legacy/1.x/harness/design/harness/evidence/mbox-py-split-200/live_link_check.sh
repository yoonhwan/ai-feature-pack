C=$1; ORIG=$2
lay() {  # <real dir with py files> → root with .fable-team/comm links like live
  local T; T=$(mktemp -d); mkdir -p $T/root/.fable-team/comm $T/root/.claude/fable-team/bin; cd $T/root && git init -q
  cp $1/*.py $1/mbox.sh $1/mbox_doorbell.sh $T/root/.claude/fable-team/bin/
  for f in $T/root/.claude/fable-team/bin/*; do ln -s ../../.claude/fable-team/bin/$(basename $f) $T/root/.fable-team/comm/$(basename $f); done
  echo $T/root
}
N=$(mktemp -d); cp $C/mbox*.py $C/mbox.sh $C/mbox_doorbell.sh $N/
O=$(mktemp -d); cp $ORIG $O/mbox.py; cp $C/mbox.sh $C/mbox_doorbell.sh $O/
for tag in old new; do src=$O; [ $tag = new ] && src=$N
  R=$(lay $src); cd $R
  env -u FT_MBOX_DIR FT_SEATS_JSON=/nonexist TMPDIR=$R python3 .fable-team/comm/mbox.py send zz#1 me#1 "hello live" > o 2>&1; echo "$tag live-link send rc=$? $(sed 's/seq=[0-9]*/seq=N/' o | head -1 | cut -c1-60)"
  env -u FT_MBOX_DIR python3 .fable-team/comm/mbox.py recv zz#1 2>&1 | grep -c 'hello live' | sed "s/^/$tag recv_hit=/"
  ls .fable-team/comm/mailbox.jsonl >/dev/null 2>&1 && echo "$tag mailbox at root/.fable-team/comm OK"
  ls .claude/fable-team/bin/.fable-team 2>/dev/null && echo "$tag STRAY mailbox in bin!"
done
# 함정 실증: 진입점을 링크 없이 실제 폴더에서 직접 부르면(= 루트를 모듈 위치로 정하는 것과 같은 조건)
R=$(lay $N); cd $R; env -u FT_MBOX_DIR python3 .claude/fable-team/bin/mbox.py peek x > o 2>&1; echo "direct-real-path rc=$? $(head -1 o | cut -c1-60)"
