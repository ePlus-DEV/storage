@echo off
REM ============================================================
REM  © Copyright ePlus.DEV
REM  Task: Build Docker image (Windows Containers - GCP Lab)
REM ============================================================

REM --- Get PROJECT_ID from GCE metadata ---
for /f "usebackq delims=" %%i in (`powershell -NoProfile -Command ^
 "(Invoke-RestMethod -Headers @{ 'Metadata-Flavor'='Google' } ^
 -Uri 'http://metadata.google.internal/computeMetadata/v1/project/project-id')"`) do (
  set PROJECT_ID=%%i
)

REM --- Define image name ---
set IMAGE=gcr.io/%PROJECT_ID%/iis-site-windows

echo.
echo ===============================================
echo   Building Docker image
echo   %IMAGE%
echo ===============================================
echo.

REM --- Go to app directory ---
cd /d C:\my-windows-app

REM --- Build Docker image (ONLY command required) ---
docker build -t %IMAGE% .

echo.
echo DONE. If no error above, the task is PASSED.
echo.

pause