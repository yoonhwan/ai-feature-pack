@echo off
chcp 65001 >nul
cd /d "%~dp0"

set PY=
where python >nul 2>nul && set PY=python
if not defined PY where py >nul 2>nul && set PY=py

if not defined PY (
  echo.
  echo   [알림] 파이썬(Python 3)이 설치되어 있지 않습니다.
  echo   https://www.python.org/downloads/ 에서 설치할 때
  echo   "Add Python to PATH" 를 꼭 체크한 뒤 이 파일을 다시 실행해 주세요.
  echo.
  pause
  exit /b 1
)

echo.
echo   ▶ 데일리 트렌드 뷰어를 시작합니다...
echo   ▶ 잠시 후 브라우저에서 http://localhost:8778 이 열립니다.
echo   ▶ 종료하려면 이 창을 닫으세요.
echo.

start "" http://localhost:8778
%PY% server.py
pause
