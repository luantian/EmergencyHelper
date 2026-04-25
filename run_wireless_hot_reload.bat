@echo off
setlocal

REM ====== Config (change if your phone IP changes) ======
set DEVICE_IP=192.168.2.7
set DEVICE_PORT=5555
set TARGET=%DEVICE_IP%:%DEVICE_PORT%

set ADB_EXE=%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe
set FLUTTER_EXE=%USERPROFILE%\development\flutter\bin\flutter.bat
set JAVA_HOME=%USERPROFILE%\development\jdk17

if not exist "%ADB_EXE%" (
  echo [ERROR] adb not found: %ADB_EXE%
  pause
  exit /b 1
)

if not exist "%FLUTTER_EXE%" (
  echo [ERROR] flutter not found: %FLUTTER_EXE%
  pause
  exit /b 1
)

if not exist "%JAVA_HOME%\bin\java.exe" (
  echo [ERROR] JDK17 not found: %JAVA_HOME%
  pause
  exit /b 1
)

set PATH=%JAVA_HOME%\bin;%USERPROFILE%\development\flutter\bin;%LOCALAPPDATA%\Android\Sdk\platform-tools;%PATH%

REM Always run from Flutter project root.
cd /d "%~dp0"

echo [INFO] Project: %cd%
echo [INFO] Connecting device: %TARGET%
"%ADB_EXE%" connect %TARGET%

echo [INFO] ADB devices:
"%ADB_EXE%" devices

echo [INFO] Starting Flutter debug with hot reload...
echo [TIP] In this window: press r = hot reload, R = hot restart, q = quit
call "%FLUTTER_EXE%" run -d %TARGET%

echo.
echo [INFO] Debug session ended.
pause

