@echo off
setlocal EnableDelayedExpansion
title  Dope Wars: Re-Up  -  Installer
color 0A

rem ---------------------------------------------------------------
rem  Guard: people double-click the .bat INSIDE the zip preview.
rem  Explorer extracts only the .bat to a temp dir, so adb.exe is
rem  missing. Catch it and say exactly what to do.
rem ---------------------------------------------------------------
if not exist "%~dp0adb.exe" goto notunzipped
if not exist "%~dp0dopewars-reup.apk" goto notunzipped

echo(
echo   ============================================
echo      DOPE WARS: RE-UP   one-click installer
echo   ============================================
echo(
echo   Step 1: On your Android phone, turn on USB debugging.
echo           (Settings ^> About phone ^> tap "Build number" 7 times,
echo            then Settings ^> System ^> Developer options ^> USB debugging)
echo   Step 2: Plug the phone into this PC with a USB cable.
echo   Step 3: When the phone asks "Allow USB debugging?", tap ALLOW.
echo(
echo   Waiting for your phone to connect...

"%~dp0adb.exe" start-server >nul 2>&1
set "LASTMSG="

:waitloop
set "COUNT=0"
set "STATE="
for /f "skip=1 tokens=1,2" %%A in ('call "%~dp0adb.exe" devices 2^>nul') do (
  if not "%%B"=="" (
    set /a COUNT+=1
    set "STATE=%%B"
  )
)

if "!COUNT!"=="0" (
  if not "!LASTMSG!"=="none" (
    echo(
    echo   ...still looking. Check that the cable is plugged in at both ends.
    echo   Some cables are charge-only -- if nothing happens, try another cable
    echo   or another USB port.
    set "LASTMSG=none"
  )
  timeout /t 2 >nul
  goto waitloop
)

if !COUNT! GTR 1 (
  if not "!LASTMSG!"=="many" (
    echo(
    echo   More than one Android device is connected. Unplug the others
    echo   (and close any phone emulators^) so I know which one gets the game.
    set "LASTMSG=many"
  )
  timeout /t 2 >nul
  goto waitloop
)

if "!STATE!"=="unauthorized" (
  if not "!LASTMSG!"=="auth" (
    echo(
    echo   ^>^>^> LOOK AT YOUR PHONE ^<^<^<
    echo   There is a popup asking "Allow USB debugging?" -- tap ALLOW.
    echo   (If you tapped Deny, unplug and replug the cable to get it again.^)
    set "LASTMSG=auth"
  )
  timeout /t 2 >nul
  goto waitloop
)

if "!STATE!"=="offline" (
  if not "!LASTMSG!"=="off" (
    echo(
    echo   The phone shows as "offline". Unplug the USB cable, plug it back
    echo   in, and unlock the phone's screen.
    set "LASTMSG=off"
  )
  timeout /t 2 >nul
  goto waitloop
)

if not "!STATE!"=="device" (
  timeout /t 2 >nul
  goto waitloop
)

echo(
echo   Phone connected. Installing Dope Wars: Re-Up...
echo   (If the phone asks anything, just tap YES / ALLOW / INSTALL.)
echo(

set "LOG=%TEMP%\dwreup-install.log"
"%~dp0adb.exe" install -r "%~dp0dopewars-reup.apk" >"%LOG%" 2>&1
findstr /i /c:"Success" "%LOG%" >nul && goto success

rem ---------------- failure triage ----------------
findstr /i /c:"INSTALL_FAILED_UPDATE_INCOMPATIBLE" /c:"signatures do not match" "%LOG%" >nul && goto sigclash
findstr /i /c:"INSTALL_FAILED_VERSION_DOWNGRADE" "%LOG%" >nul && goto downgrade
findstr /i /c:"INSTALL_FAILED_NO_MATCHING_ABIS" "%LOG%" >nul && goto wrongcpu
findstr /i /c:"INSTALL_FAILED_INSUFFICIENT_STORAGE" "%LOG%" >nul && goto nospace
findstr /i /c:"INSTALL_CANCELED_BY_USER" /c:"USER_RESTRICTED" "%LOG%" >nul && goto phonesaidno

echo   Hmm, the install did not finish. Here is what the phone said:
echo   ------------------------------------------------------------
type "%LOG%"
echo   ------------------------------------------------------------
echo   Try: unplug/replug the phone, make sure it is unlocked, then run
echo   this installer again. Still stuck? Open an issue on GitHub and
echo   paste the text above.
goto end

:sigclash
echo   Your phone has an OLD copy of Dope Wars installed with a different
echo   signature (probably an early test build^). Android will not update
echo   across signatures, so the old copy has to come off first.
echo(
echo   NOTE: this removes that old copy and its LOCAL save data.
echo   (Online progress lives on the server and is safe.^)
echo(
set "ANSWER="
set /p ANSWER=  Type YES to remove the old copy and install fresh:
if /i not "!ANSWER!"=="YES" (
  echo   Okay, nothing was changed. Run me again if you change your mind.
  goto end
)
echo   Removing old copy...
"%~dp0adb.exe" uninstall com.dopewarsreup.app >nul 2>&1
echo   Installing fresh...
"%~dp0adb.exe" install "%~dp0dopewars-reup.apk" >"%LOG%" 2>&1
findstr /i /c:"Success" "%LOG%" >nul && goto success
echo   Still failed. Here is what the phone said:
type "%LOG%"
goto end

:downgrade
echo   Your phone already has a NEWER version of Dope Wars: Re-Up on it.
echo   Nothing to do -- you are ahead of this installer. If you really want
echo   to go back to this older build, uninstall the game on the phone
echo   first, then run me again.
goto end

:wrongcpu
echo   Sorry -- this phone's processor is not supported. The game needs a
echo   64-bit ARM phone (arm64), which is every mainstream Android phone
echo   from about 2015 on. Very old or x86 devices will not work.
goto end

:nospace
echo   The phone is out of storage space. Free up ~200 MB on the phone
echo   (Settings ^> Storage^), then run me again.
goto end

:phonesaidno
echo   The phone blocked the install. If it asked "Allow from this source?"
echo   or showed an install prompt, tap ALLOW / INSTALL and run me again.
echo   On work/school-managed phones, the administrator may block sideloads.
goto end

:success
echo   ============================================
echo    DONE!  Dope Wars: Re-Up is on your phone.
echo    You can unplug the cable and start playing.
echo   ============================================
echo(
echo   Tip: you can turn USB debugging back OFF now if you want
echo   (Settings ^> System ^> Developer options^).
goto end

:notunzipped
echo(
echo   Almost! You are running this from INSIDE the ZIP file.
echo(
echo   1. Close this window.
echo   2. Right-click the downloaded ZIP  -^>  "Extract All..."
echo   3. Open the NEW folder it created and double-click
echo      "Install DopeWars.bat" in there.
echo(

:end
echo(
pause
endlocal
