@echo off
setlocal enabledelayedexpansion

title CyberTrials - Synthrace Compatibility Patch

:: Define paths
set "CYBERPUNK_EXE=%~dp0bin\x64\Cyberpunk2077.exe"
set "LOGIC_LUA=%~dp0bin\x64\plugins\cyber_engine_tweaks\mods\CyberTrials\modules\utils\raceLogic.lua"
set "INIT_LUA=%~dp0bin\x64\plugins\cyber_engine_tweaks\mods\CyberTrials\init.lua"
set "LOGIC_BACKUP=%LOGIC_LUA%.backup"
set "INIT_BACKUP=%INIT_LUA%.backup"

:: Check if Cyberpunk 2077 is installed
if not exist "%CYBERPUNK_EXE%" (
	color 4F
	echo.
	echo ========================================
	echo        ERROR: Wrong Directory
	echo ========================================
	echo.
	echo This script must be executed in the
	echo Cyberpunk 2077 installation folder.
	echo.
	echo Please move this script to the main
	echo Cyberpunk 2077 directory and run it
	echo from there.
	echo.
	echo ========================================
	pause
	exit /b 1
)

:: Check if CyberTrials mod is installed
if not exist "%LOGIC_LUA%" (
	color 4F
	echo.
	echo ========================================
	echo     ERROR: CyberTrials Mod Not Found
	echo ========================================
	echo.
	echo The CyberTrials mod was not found.
	echo.
	echo Expected at:
	echo %LOGIC_LUA%
	echo.
	echo Please install the CyberTrials mod and
	echo run this script again.
	echo.
	echo ========================================
	pause
	exit /b 1
)

if not exist "%INIT_LUA%" (
	color 4F
	echo.
	echo ========================================
	echo     ERROR: init.lua Not Found
	echo ========================================
	echo.
	echo The CyberTrials init.lua was not found.
	echo.
	echo Expected at:
	echo %INIT_LUA%
	echo.
	echo Please install the CyberTrials mod and
	echo run this script again.
	echo.
	echo ========================================
	pause
	exit /b 1
)

:: Check if backup exists - if yes, restore it
if exist "%LOGIC_BACKUP%" (
	echo Backup files detected. Restoring original files...
	copy /Y "%LOGIC_BACKUP%" "%LOGIC_LUA%" >nul 2>&1
	if %errorlevel% neq 0 (
		color 4F
		echo.
		echo ========================================
		echo      ERROR: Restore Failed
		echo ========================================
		echo.
		echo Could not restore the raceLogic.lua backup.
		echo Please check your permissions.
		echo.
		echo ========================================
		pause
		exit /b 1
	)
	if exist "%INIT_BACKUP%" (
		copy /Y "%INIT_BACKUP%" "%INIT_LUA%" >nul 2>&1
		if %errorlevel% neq 0 (
			color 4F
			echo.
			echo ========================================
			echo      ERROR: Restore Failed
			echo ========================================
			echo.
			echo Could not restore the init.lua backup.
			echo Please check your permissions.
			echo.
			echo ========================================
			pause
			exit /b 1
		)
		del "%INIT_BACKUP%" >nul 2>&1
	)
	del "%LOGIC_BACKUP%" >nul 2>&1
	color 1F
	echo.
	echo ========================================
	echo       Successfully Restored!
	echo ========================================
	echo.
	echo The original files have been restored.
	echo The patch has been removed.
	echo.
	echo You can run this script again to re-apply
	echo the patch.
	echo.
	echo ========================================
	pause
	exit /b 0
)

:: Call PowerShell section
powershell -NoProfile -ExecutionPolicy Bypass -Command "$raceLogicPath='%LOGIC_LUA%'; $initLuaPath='%INIT_LUA%'; $backupPath='%LOGIC_BACKUP%'; $initBackupPath='%INIT_BACKUP%'; try { $content = Get-Content -Path $raceLogicPath -Raw -Encoding UTF8; if ($content -match ';raceLogic\.hudController:OnForwardVehicleRaceUIEvent\(getRaceEnd\(raceLogic\.finish\)\)') { Write-Host 'Files are already patched.'; exit 2; }; Write-Host 'Creating backups...'; Copy-Item -Path $raceLogicPath -Destination $backupPath -Force; Copy-Item -Path $initLuaPath -Destination $initBackupPath -Force; Write-Host 'Patching raceLogic.lua...'; $lines = Get-Content -Path $raceLogicPath -Encoding UTF8; $patchedLines = @(); foreach ($line in $lines) { $trimmedLine = $line.TrimStart(); if ($trimmedLine -match '^raceLogic\.hudController:EndRace\(\)') { $patchedLines += $line + '; raceLogic.hudController:OnForwardVehicleRaceUIEvent(getRaceEnd(raceLogic.finish))'; } elseif ($trimmedLine -match '^raceLogic\.hudController:StartRace\(\)') { $patchedLines += $line + '; raceLogic.hudController:OnForwardVehicleRaceUIEvent(getRaceStart(raceLogic.finish))'; } else { $patchedLines += $line; }; }; $patchedLines | Set-Content -Path $raceLogicPath -Encoding UTF8; Write-Host 'Patching init.lua...'; $initContent = Get-Content -Path $initLuaPath -Encoding UTF8; $initPatched = $initContent -replace 'raceActive = false,', 'raceActive = false, raceLogicHook = raceLogic, userHook = user, isPatched = true,'; $initPatched | Set-Content -Path $initLuaPath -Encoding UTF8; Write-Host 'Patching completed successfully.'; exit 0; } catch { Write-Host ('ERROR: ' + $_.Exception.Message) -ForegroundColor Red; exit 1; }"

set RESULT=%errorlevel%

if %RESULT% equ 0 (
	color 0A
	echo.
	echo ========================================
	echo       Successfully Patched!
	echo ========================================
	echo.
	echo The raceLogic.lua and init.lua have been
	echo successfully patched.
	echo.
	echo Backups of the original files were created:
	echo %LOGIC_BACKUP%
	echo %INIT_BACKUP%
	echo.
	echo You can now start Cyberpunk 2077.
	echo.
	echo ========================================
) else if %RESULT% equ 2 (
	color 0A
	echo.
	echo ========================================
	echo         Already Patched
	echo ========================================
	echo.
	echo The files have already been patched.
	echo No further changes are necessary.
	echo.
	echo ========================================
) else (
	color 4F
	echo.
	echo ========================================
	echo      ERROR: Patching Failed
	echo ========================================
	echo.
	echo Could not patch the files.
	echo Please check the error messages above.
	echo.
	echo ========================================
)

pause
exit /b %RESULT%