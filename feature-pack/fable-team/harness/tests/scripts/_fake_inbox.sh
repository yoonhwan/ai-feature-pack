#!/usr/bin/env bash
# _fake_inbox.sh — ft-inbox.sh 스텁(미러 pytest 용): 인박스는 비어 있다. 닫는 사건(R49)은 tests/harness/test_question_board.sh 가 따로 시험한다.
case "${1:-}" in
  show) echo EMPTY ;;
  ingest) echo "SKIP seq=${2:-} 스텁" ;;
  *) exit 2 ;;
esac
