@echo off
setlocal ENABLEDELAYEDEXPANSION

REM === Configuration (EDIT AS NEEDED) ===
set VM_USER=root
set VM_HOST=172.236.224.105
set VM_DEST_DIR=/root/oipms-backend
set ARCHIVE_NAME=oipms-backend.tgz
set REMOTE_SCRIPT=remote-deploy.sh

REM === Find backend directory ===
set SCRIPT_DIR=%~dp0
pushd "%SCRIPT_DIR%" >nul
set CANDIDATE1=%CD%\oipms-backend
set CANDIDATE2=%CD%
set LOCAL_BACKEND_DIR=

REM === Try candidate 1 ===
if exist "%CANDIDATE1%\server.js" (
  set LOCAL_BACKEND_DIR=%CANDIDATE1%
)

REM === Try candidate 2 ===
if "%LOCAL_BACKEND_DIR%"=="" if exist "%CANDIDATE2%\server.js" (
  set LOCAL_BACKEND_DIR=%CANDIDATE2%
)

if "%LOCAL_BACKEND_DIR%"=="" (
  echo [ERROR] Could not find server.js. Run this script from the repo root or from the oipms-backend directory.
  popd >nul
  exit /b 1
)
echo [DEBUG] Using backend directory: %LOCAL_BACKEND_DIR%
if not exist "%LOCAL_BACKEND_DIR%" (
  echo [ERROR] Backend dir missing: %LOCAL_BACKEND_DIR%
  popd >nul
  exit /b 1
)
dir "%LOCAL_BACKEND_DIR%"

REM === Confirm required local tools exist ===
where ssh >nul 2>nul || ( echo [ERROR] ssh not found in PATH. Install OpenSSH Client and retry. & popd & exit /b 1 )
where scp >nul 2>nul || ( echo [ERROR] scp not found in PATH. Install OpenSSH Client and retry. & popd & exit /b 1 )
where tar >nul 2>nul || ( echo [ERROR] tar not found in PATH. On Windows 10+, tar.exe should be present. & popd & exit /b 1 )

REM === Clean up any old local artifacts ===
if exist "%ARCHIVE_NAME%" del /f /q "%ARCHIVE_NAME%" >nul 2>nul
if exist "%REMOTE_SCRIPT%" del /f /q "%REMOTE_SCRIPT%" >nul 2>nul

REM === Create tar archive (excluding node_modules/.git) ===
echo [INFO] Creating archive %ARCHIVE_NAME% from %LOCAL_BACKEND_DIR% (excluding node_modules/.git)...
pushd "%LOCAL_BACKEND_DIR%" >nul
tar -czf "%CD%\..\%ARCHIVE_NAME%" --exclude=node_modules --exclude=.git .
if errorlevel 1 (
  popd >nul
  echo [ERROR] Failed to create archive. TAR error.
  popd >nul
  exit /b 1
)
popd >nul

REM === Generate the remote shell script (to be run only REMOTELY) ===
echo #!/bin/bash > %REMOTE_SCRIPT%
echo set -ex >> %REMOTE_SCRIPT%
echo sudo mkdir -p %VM_DEST_DIR% >> %REMOTE_SCRIPT%
echo sudo tar -xzf /root/%ARCHIVE_NAME% -C %VM_DEST_DIR% >> %REMOTE_SCRIPT%
echo cd %VM_DEST_DIR% >> %REMOTE_SCRIPT%
echo if command -v node >/dev/null 2^>^&1; then echo Node found; else echo Installing Node.js; sudo apt-get update -y && sudo apt-get install -y nodejs npm; fi >> %REMOTE_SCRIPT%
echo if command -v pm2 >/dev/null 2^>^&1; then echo PM2 found; else sudo npm i -g pm2; fi >> %REMOTE_SCRIPT%
echo if [ -f package-lock.json ]; then npm ci; else npm install; fi >> %REMOTE_SCRIPT%
echo PORT=8080 pm2 describe oipms-backend >/dev/null 2^>^&1 && pm2 restart oipms-backend --update-env || pm2 start server.js --name oipms-backend --time >> %REMOTE_SCRIPT%
echo pm2 save >/dev/null 2^>^&1 || true >> %REMOTE_SCRIPT%
echo echo Deployment complete. >> %REMOTE_SCRIPT%

REM === Show the generated script for debugging ===
echo ---------- remote-deploy.sh ----------
type %REMOTE_SCRIPT%
echo ---------------------------------------

REM === Convert CRLF to LF for Linux compatibility ===
powershell -Command "(Get-Content %REMOTE_SCRIPT%) | Set-Content -NoNewline -Encoding ASCII %REMOTE_SCRIPT%"

REM === Copy archive and deploy script to VM ===
echo [INFO] Copying archive and deploy script to %VM_USER%@%VM_HOST%
scp -o StrictHostKeyChecking=no "%ARCHIVE_NAME%" %VM_USER%@%VM_HOST%:/root/%ARCHIVE_NAME%
if errorlevel 1 (
  echo [ERROR] SCP upload of archive failed.
  del /f /q "%ARCHIVE_NAME%" >nul 2>nul
  del /f /q "%REMOTE_SCRIPT%" >nul 2>nul
  popd >nul
  exit /b 1
)
scp -o StrictHostKeyChecking=no "%REMOTE_SCRIPT%" %VM_USER%@%VM_HOST%:/root/%REMOTE_SCRIPT%
if errorlevel 1 (
  echo [ERROR] SCP upload of remote script failed.
  del /f /q "%ARCHIVE_NAME%" >nul 2>nul
  del /f /q "%REMOTE_SCRIPT%" >nul 2>nul
  popd >nul
  exit /b 1
)

REM === Execute ONLY ON REMOTE HOST by SSH ===
echo [INFO] Deploying on remote host ...
ssh -o StrictHostKeyChecking=no %VM_USER%@%VM_HOST% "bash /root/%REMOTE_SCRIPT%"
if errorlevel 1 (
  echo [ERROR] Remote deploy step failed.
  del /f /q "%ARCHIVE_NAME%" >nul 2>nul
  del /f /q "%REMOTE_SCRIPT%" >nul 2>nul
  popd >nul
  echo .
  echo Press any key to close this window...
  pause >nul
  exit /b 1
)

REM === Clean up local artifacts after complete ===
del /f /q "%ARCHIVE_NAME%" >nul 2>nul
del /f /q "%REMOTE_SCRIPT%" >nul 2>nul
popd >nul

echo [SUCCESS] Deployed and refreshed node modules on VM. Test: curl http://%VM_HOST%:8080/aerospike/health
echo.
echo Press any key to close this window...
pause >nul
endlocal
exit /b 0
