@echo off
rem Starts or stops contained_droid. Double-click it, or put a shortcut to it
rem on the desktop. Also usable as: contained_droid.bat start | stop
setlocal
cd /d "%~dp0"
title contained_droid

if /i "%~1"=="start" goto start
if /i "%~1"=="stop" goto stop

:menu
echo.
echo   contained_droid
echo   ---------------
echo   [1] Start and open the desktop in the browser
echo   [2] Stop  (docker compose down - Android and settings are kept)
echo   [3] Show status and recent log
echo   [Q] Quit
echo.
choice /c 123Q /n /m "  Choose 1, 2, 3 or Q: "
if errorlevel 4 exit /b 0
if errorlevel 3 goto status
if errorlevel 2 goto stop
goto start

:start
call :need_docker
if errorlevel 1 goto done
echo.
echo Starting the container...
docker compose up -d
if errorlevel 1 goto failed
echo Waiting for the desktop...
set tries=0
:wait_desktop
curl -s -o nul http://localhost:6080/
if not errorlevel 1 goto open
set /a tries+=1
if %tries% geq 60 goto failed
timeout /t 2 /nobreak >nul
goto wait_desktop
:open
start "" http://localhost:6080
echo.
echo The desktop is open in your browser. Android needs about a minute to boot.
goto done

:stop
echo.
echo Stopping the container...
docker compose down
goto done

:status
echo.
docker compose ps
echo.
docker compose logs --tail 25
goto done

:failed
echo.
echo Something went wrong. Recent log:
docker compose logs --tail 25
goto done

:done
if not "%~1"=="" exit /b
echo.
pause
goto menu

:need_docker
docker info >nul 2>&1
if not errorlevel 1 exit /b 0
echo.
echo Docker is not running. Starting Docker Desktop, this can take a minute...
if exist "%ProgramFiles%\Docker\Docker\Docker Desktop.exe" start "" "%ProgramFiles%\Docker\Docker\Docker Desktop.exe"
set dtries=0
:wait_docker
timeout /t 3 /nobreak >nul
docker info >nul 2>&1
if not errorlevel 1 exit /b 0
set /a dtries+=1
if %dtries% lss 60 goto wait_docker
echo Docker did not start. Start Docker Desktop yourself and try again.
exit /b 1
