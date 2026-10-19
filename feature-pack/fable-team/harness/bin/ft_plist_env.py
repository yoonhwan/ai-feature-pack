#!/usr/bin/env python3
"""ft_plist_env.py — 설치기가 관리하는 launchd plist 를 키트 템플릿에서 렌더한다 (r426 · 미러 FT_ROOT 없이 7시간 47분 정지 사건).
관리 대상 = MANAGED(라벨 → 키트 harness/kit/ 기준 템플릿). 값: __ROOT__ = 프로젝트 루트 · __INBOX_BIN__ = <LIVE_BIN>/ft-inbox.sh ·
__MAILBOX__ = <루트>/.fable-team/comm/mailbox.log.jsonl · __HOME__ · 나머지(__PY__·__PROJECT__·__SEAT__·__CHANNEL__·__MENTION__·__REPO__)는
설치된 plist 에서 그대로 옮긴다(머신별 설정 보존 — 처음 설치는 slack-mirror/install.sh 소관).
사용: ft_plist_env.py list                                              → «라벨<TAB>템플릿» 줄
      ft_plist_env.py render <라벨> <템플릿> <설치 plist> <루트> <LIVE_BIN> <HOME> → stdout 렌더본
종료: 0 · 2 usage · 3 ERROR(루트·LIVE_BIN·설치값 없음 · 자리표시 잔재 · plist 해석 실패 — 조용한 통과 0 · #0 RULE). 쓰기 0."""
import os
import plistlib
import re
import sys
from xml.parsers.expat import ExpatError
from xml.sax.saxutils import escape

MANAGED = {"com.hermes.byz-mbox-slack-mirror": "slack-mirror/com.hermes.byz-mbox-slack-mirror.plist.template"}
FLAGS = {"__PROJECT__": "--project", "__SEAT__": "--seat", "__CHANNEL__": "--channel", "__MENTION__": "--mention", "__REPO__": "--repo"}


class RenderError(Exception):
    pass


def plist_path(home, label):
    return os.path.join(home, "Library", "LaunchAgents", label + ".plist")


def load(path):
    try:
        with open(path, "rb") as fh:
            return plistlib.load(fh)
    except (OSError, ValueError, ExpatError) as e:
        raise RenderError("plist 해석 실패: %s (%s)" % (path, e))


def installed_values(path):
    """설치된 plist 의 ProgramArguments 에서 머신별 값을 옮긴다 — 하나라도 없으면 RenderError."""
    args = load(path).get("ProgramArguments") or []
    if not args:
        raise RenderError("설치된 plist 에 ProgramArguments 없음: %s" % path)
    vals = {"__PY__": args[0]}
    for key, flag in FLAGS.items():
        i = args.index(flag) if flag in args else -1
        if i < 0 or i + 1 >= len(args):
            raise RenderError("설치된 plist 에 %s 값 없음: %s" % (flag, path))
        vals[key] = args[i + 1]
    return vals


def render(template, installed, root, live_bin, home):
    """템플릿 본문 → 렌더본 문자열. 렌더본의 EnvironmentVariables.FT_ROOT = root 까지 확인한다."""
    if not os.path.isdir(os.path.join(root, ".fable-team")):
        raise RenderError("프로젝트 루트 없음(.fable-team 없음): %s" % root)
    if not os.path.isdir(os.path.join(root, ".git")):  # r457: 워크트리(.git 파일)·git 밖 = launchd 가 볼 루트가 아니다
        why = "워크트리" if os.path.isfile(os.path.join(root, ".git")) else ".git 없음"
        raise RenderError("루트가 git 공용 루트 아님(%s): %s" % (why, root))
    inbox = os.path.join(live_bin, "ft-inbox.sh")
    if not os.path.isabs(live_bin) or not os.path.isfile(inbox):
        raise RenderError("LIVE_BIN 에 ft-inbox.sh 없음: %s" % inbox)
    vals = installed_values(installed)
    vals.update({"__ROOT__": root, "__HOME__": home, "__INBOX_BIN__": inbox,
                 "__MAILBOX__": os.path.join(root, ".fable-team", "comm", "mailbox.log.jsonl")})
    out = template
    for key, val in vals.items():
        out = out.replace(key, escape(val))
    left = sorted(set(re.findall(r"__[A-Z_]+__", out)))
    if left:
        raise RenderError("자리표시 잔재: %s" % " ".join(left))
    try:
        env = plistlib.loads(out.encode("utf-8")).get("EnvironmentVariables") or {}
    except (ValueError, ExpatError) as e:
        raise RenderError("렌더본 plist 해석 실패: %s" % e)
    if env.get("FT_ROOT") != root:
        raise RenderError("렌더본 FT_ROOT(%r) ≠ 루트 — 템플릿에 FT_ROOT 키가 있어야 한다" % env.get("FT_ROOT"))
    return out


def main(argv):
    if argv == ["list"]:
        print("\n".join("%s\t%s" % kv for kv in sorted(MANAGED.items())))
        return 0
    if len(argv) != 7 or argv[0] != "render":
        print("usage: ft_plist_env.py list | render <라벨> <템플릿> <설치 plist> <루트> <LIVE_BIN> <HOME>", file=sys.stderr)
        return 2
    label, tpl, installed, root, live_bin, home = argv[1:]
    try:
        if label not in MANAGED:
            raise RenderError("관리 대상 라벨 아님: %s" % label)
        with open(tpl, encoding="utf-8") as fh:
            sys.stdout.write(render(fh.read(), installed, root, live_bin, home))
    except (RenderError, OSError) as e:
        print("ERROR %s" % e)
        return 3
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
