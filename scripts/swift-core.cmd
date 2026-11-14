@echo off
rem Runs `swift <args>` for PofudukCore inside an MSVC x64 developer environment (Windows only).
rem Usage: scripts\swift-core.cmd build   |   scripts\swift-core.cmd test
set "PATH=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer;%PATH%"
call "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat" >nul || exit /b 1
set "SDKROOT=%LOCALAPPDATA%\Programs\Swift\Platforms\6.4.2\Windows.platform\Developer\SDKs\Windows.sdk\"
set "PATH=%LOCALAPPDATA%\Programs\Swift\Toolchains\6.4.2+Asserts\usr\bin;%LOCALAPPDATA%\Programs\Swift\Runtimes\6.4.2\usr\bin;%PATH%"
pushd "%~dp0..\PofudukCore"
swift %*
set ERR=%ERRORLEVEL%
popd
exit /b %ERR%
