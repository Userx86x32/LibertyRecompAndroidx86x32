@echo off
rem LibertyRecomp test helper for Windows: changes the game's settings files
rem on the phone over adb. Put it in the platform-tools folder (next to
rem adb.exe), open Command Prompt there and run, for example:  lrtest check
rem Run "lrtest" alone for the list of commands.
setlocal EnableDelayedExpansion
set "PKG=com.libertyrecomp"
set "F=/sdcard/Android/data/%PKG%/files"
set "ADB=adb"
if exist "%~dp0adb.exe" set "ADB="%~dp0adb.exe""
rem If "adb devices" lists the phone twice, run first:  set LR_SERIAL=<one entry>
if defined LR_SERIAL set "ADB=%ADB% -s %LR_SERIAL%"

set "CMD=%~1"
if "%CMD%"=="" goto help
for %%c in (check backup restore stop play restart baseline shadow1 shadow2 drivers driver turnip system gmem nogmem shaderon shaderoff lastlaunch) do (
  if /i "%CMD%"=="%%c" goto %%c
)
echo Unknown command "%CMD%".
goto help

:help
echo.
echo   lrtest check        phone connected? power saving, battery, current settings
echo   lrtest backup       copy saves and settings files to a new lr-backup-N folder
echo   lrtest restore DIR  put saves from DIR (an lr-backup-N folder) back on the phone
echo   lrtest stop / play / restart   close the game / start it / both
echo.
echo   lrtest baseline     test step 1: bundled Turnip, no env.txt, test lines removed
echo   lrtest shadow1      shadow range 1.0 (if step 1 is clearly below 60)
echo   lrtest shadow2      shadow range 2.0 (the S24+ default) again
echo   lrtest drivers      list imported drivers (import them on the launcher first)
echo   lrtest driver NAME  test step 3: use the imported driver NAME
echo   lrtest turnip       back to the bundled Turnip driver
echo   lrtest gmem         test step 4: create env.txt with TU_DEBUG=
echo   lrtest nogmem       undo step 4: delete env.txt
echo   lrtest system       test step 5: the phone's own Qualcomm driver
echo   lrtest shaderon     step 5 extra: draw the shader skipped under Turnip
echo   lrtest shaderoff    undo shaderon (always do this before going back to Turnip)
echo   lrtest lastlaunch   copy last_launch.txt from the phone into this folder
echo.
echo   Changes apply the next time the game starts: run "lrtest restart" after them.
goto end

:needphone
%ADB% get-state >nul 2>&1
if errorlevel 1 (
  echo No phone found. Check the cable or wireless debugging, then run: %ADB% devices
  exit /b 1
)
exit /b 0

:needargs
call :needphone || exit /b 1
%ADB% shell "test -f %F%/args.txt" >nul 2>&1
if errorlevel 1 (
  echo args.txt is not on the phone yet: start the game once, close it, then try again.
  exit /b 1
)
exit /b 0

:check
call :needphone || goto end
echo == CPU limits (kHz; the last value should be about 3340800-3398400, else turn power saving off)
%ADB% shell "cat /sys/devices/system/cpu/cpufreq/policy*/scaling_max_freq"
echo == Battery (temperature in tenths of a degree C: 350 = 35.0 C)
%ADB% shell "dumpsys battery | grep -E 'level|temperature|powered: true'"
echo == driver.txt (which Vulkan driver)
%ADB% shell "cat %F%/driver.txt 2>/dev/null || echo '(no file: bundled Turnip)'"
echo == env.txt (driver environment)
%ADB% shell "cat %F%/env.txt 2>/dev/null || echo '(no file: the app default TU_DEBUG=sysmem)'"
echo == Test lines in args.txt
%ADB% shell "grep -E '^--gta4_(shadow_distance_scale|native_skip_pixel_shaders)=' %F%/args.txt 2>/dev/null || echo '(none)'"
goto end

:backup
call :needphone || goto end
set N=1
:backup_next
if exist "lr-backup-!N!" (
  set /a N+=1
  goto backup_next
)
set "B=lr-backup-!N!"
mkdir "!B!"
echo Copying into !B! ...
%ADB% pull "%F%/LibertyRecomp/saves" "!B!"
for %%f in (args.txt env.txt driver.txt last_launch.txt) do %ADB% pull "%F%/%%f" "!B!\%%f" >nul 2>&1
%ADB% pull "%F%/LibertyRecomp/native.toml" "!B!\native.toml" >nul 2>&1
echo.
echo Saves copied:
dir /b /s "!B!\saves"
echo.
echo Check that the list above shows your save files before you uninstall anything.
goto end

:restore
call :needphone || goto end
if "%~2"=="" (
  echo Usage: lrtest restore lr-backup-N
  goto end
)
if not exist "%~2\saves" (
  echo "%~2\saves" not found.
  goto end
)
echo Close the game first; restoring overwrites saves with the same names.
%ADB% shell am force-stop %PKG%
%ADB% shell "mkdir -p %F%/LibertyRecomp"
%ADB% push "%~2\saves" "%F%/LibertyRecomp/"
goto end

:stop
call :needphone || goto end
%ADB% shell am force-stop %PKG%
echo Game closed.
goto end

:play
call :needphone || goto end
%ADB% shell am start -n %PKG%/.LauncherActivity --ez play true >nul
echo Game starting.
goto end

:restart
call :needphone || goto end
%ADB% shell am force-stop %PKG%
%ADB% shell am start -n %PKG%/.LauncherActivity --ez play true >nul
echo Game restarted.
goto end

:baseline
call :needargs || goto end
%ADB% shell am force-stop %PKG%
%ADB% shell "echo turnip > %F%/driver.txt; rm -f %F%/env.txt"
%ADB% shell "sed -i '/^--gta4_native_skip_pixel_shaders=/d' %F%/args.txt"
echo Baseline: bundled Turnip, no env.txt, no shader line. Shadow range left as it is
echo (run "lrtest shadow2" for the S24+ default). Now: lrtest restart
goto end

:shadow1
call :needargs || goto end
%ADB% shell "sed -i '/^--gta4_shadow_distance_scale=/d' %F%/args.txt; printf '%%s\n' '--gta4_shadow_distance_scale=1.0' >> %F%/args.txt"
echo Shadow range 1.0. Now: lrtest restart
goto end

:shadow2
call :needargs || goto end
%ADB% shell "sed -i '/^--gta4_shadow_distance_scale=/d' %F%/args.txt; printf '%%s\n' '--gta4_shadow_distance_scale=2.0' >> %F%/args.txt"
echo Shadow range 2.0. Now: lrtest restart
goto end

:drivers
call :needphone || goto end
echo Imported drivers (names for "lrtest driver NAME"):
%ADB% shell "ls %F%/drivers 2>/dev/null || echo '(none: use Import driver (.zip) on the launcher first)'"
goto end

:driver
call :needphone || goto end
if "%~2"=="" (
  echo Usage: lrtest driver NAME   ^(run "lrtest drivers" for the names^)
  goto end
)
%ADB% shell "test -d %F%/drivers/%~2" >nul 2>&1
if errorlevel 1 (
  echo No imported driver named "%~2". Run "lrtest drivers" for the names.
  goto end
)
%ADB% shell am force-stop %PKG%
%ADB% shell "echo custom:%~2 > %F%/driver.txt"
echo Driver: %~2. Now: lrtest restart
goto end

:turnip
call :needphone || goto end
%ADB% shell am force-stop %PKG%
%ADB% shell "echo turnip > %F%/driver.txt"
echo Driver: bundled Turnip. Now: lrtest restart
goto end

:system
call :needphone || goto end
%ADB% shell am force-stop %PKG%
%ADB% shell "echo system > %F%/driver.txt; rm -f %F%/env.txt"
echo Driver: the phone's own Qualcomm driver (env.txt removed). Now: lrtest restart
goto end

:gmem
call :needphone || goto end
%ADB% shell am force-stop %PKG%
%ADB% shell "printf '%%s\n' '# Let Turnip choose tiled (GMEM) or direct rendering per pass.' 'TU_DEBUG=' > %F%/env.txt"
echo env.txt written (TU_DEBUG= : Turnip chooses per pass). Now: lrtest restart
goto end

:nogmem
call :needphone || goto end
%ADB% shell am force-stop %PKG%
%ADB% shell "rm -f %F%/env.txt"
echo env.txt removed (back to the app default, direct rendering). Now: lrtest restart
goto end

:shaderon
call :needargs || goto end
%ADB% shell "cat %F%/driver.txt 2>/dev/null" | findstr /b /c:"system" >nul
if errorlevel 1 (
  echo Refused: this shader hangs the GPU under Turnip. Run "lrtest system" first.
  goto end
)
%ADB% shell am force-stop %PKG%
%ADB% shell "sed -i '/^--gta4_native_skip_pixel_shaders=/d' %F%/args.txt; printf '%%s\n' '--gta4_native_skip_pixel_shaders=' >> %F%/args.txt"
echo Skipped shader now drawn. If the screen freezes: lrtest shaderoff. Now: lrtest restart
goto end

:shaderoff
call :needargs || goto end
%ADB% shell am force-stop %PKG%
%ADB% shell "sed -i '/^--gta4_native_skip_pixel_shaders=/d' %F%/args.txt"
echo Shader line removed (the default skip applies again). Now: lrtest restart
goto end

:lastlaunch
call :needphone || goto end
%ADB% pull "%F%/last_launch.txt" last_launch.txt
goto end

:end
endlocal
