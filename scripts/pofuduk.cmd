@echo off
rem Pofuduk console demo with live weather (Windows).
rem Usage: scripts\pofuduk.cmd [il] [--stil samimi^|sakaci^|sakin] [--kisa] [--ses] [--soru "metin"]
rem Example: scripts\pofuduk.cmd Ankara --ses
call "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat" >nul || exit /b 1
rem UTF-8 console for Turkish text (after vcvars, which breaks under code page 65001).
chcp 65001 >nul
set "SDKROOT=%LOCALAPPDATA%\Programs\Swift\Platforms\6.4.2\Windows.platform\Developer\SDKs\Windows.sdk\"
set "PATH=%LOCALAPPDATA%\Programs\Swift\Toolchains\6.4.2+Asserts\usr\bin;%LOCALAPPDATA%\Programs\Swift\Runtimes\6.4.2\usr\bin;%PATH%"
set "POFUDUK_SPEAK_SCRIPT=%~dp0speak.ps1"
pushd "%~dp0..\PofudukCore"
swift build --product PofudukDemo -c release >nul 2>&1 || swift build --product PofudukDemo -c release
rem On Windows .build\release is not a symlink; ask SwiftPM for the real output folder.
for /f "delims=" %%i in ('swift build -c release --show-bin-path') do set "BIN=%%i"
"%BIN%\PofudukDemo.exe" %*
set ERR=%ERRORLEVEL%
popd
exit /b %ERR%
