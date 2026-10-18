"""시험용 tmux 클라이언트 — 진짜 pty 로 attach 해 «사람이 키를 친 것» 을 흉내 낸다(client_activity 가 갱신된다).
사용: python3 -I pty_client.py <tmux -L 소켓> <세션> <제어 폴더>
제어 폴더: READY(붙었다) · press(만들면 키 1개를 치고 지운다) · stop(만들면 끝). 40초 안에 stop 이 없어도 끝난다.
"""
import os
import pty
import select
import subprocess
import sys
import time

sock, session, ctl = sys.argv[1:4]
pid, fd = pty.fork()
if pid == 0:
    os.environ["TERM"] = "xterm"
    os.execvp("tmux", ["tmux", "-L", sock, "attach", "-t", session])


def drain() -> None:
    while select.select([fd], [], [], 0.05)[0]:
        try:
            os.read(fd, 4096)
        except OSError:
            return


drain()
open(os.path.join(ctl, "READY"), "w").close()
end = time.time() + 40
while time.time() < end and not os.path.exists(os.path.join(ctl, "stop")):
    drain()
    press = os.path.join(ctl, "press")
    if os.path.exists(press):
        os.write(fd, b"k")
        os.unlink(press)
    time.sleep(0.05)
subprocess.run(["tmux", "-L", sock, "detach-client", "-s", session], capture_output=True)
os.close(fd)
