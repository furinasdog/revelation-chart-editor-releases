@echo off
"%~dp0tools\python\python.exe" -I -B "%~dp0runtime\cli.py" %*
exit /b %errorlevel%
