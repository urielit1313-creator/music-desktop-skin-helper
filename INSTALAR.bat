@echo off
chcp 65001 >nul
title Music Desktop Skin - Instalar ayudante
echo.
echo  Music Desktop Skin - instalando el ayudante (solo una vez)...
echo.
set "DEST=%LOCALAPPDATA%\MusicSkin\helper"
rem detiene un ayudante viejo si ya estaba corriendo
powershell -NoProfile -Command "Get-CimInstance Win32_Process -Filter \"Name='powershell.exe'\" | Where-Object { $_.CommandLine -like '*musicskin-helper.ps1*' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }"
rem copia el ayudante a una carpeta fija (asi puedes borrar la descarga)
if not exist "%DEST%" mkdir "%DEST%"
copy /y "%~dp0*.ps1" "%DEST%\" >nul
copy /y "%~dp0*.html" "%DEST%\" >nul
copy /y "%~dp0*.vbs" "%DEST%\" >nul
echo  [ok] Ayudante copiado
where winget >nul 2>nul
if errorlevel 1 (
  echo  [!] Este Windows no tiene winget: letras y controles si funcionan.
  echo      Para videos instala "App Installer" desde Microsoft Store y abre esto otra vez.
  goto start
)
call :tool yt-dlp yt-dlp.yt-dlp
call :tool ffmpeg Gyan.FFmpeg
:start
set "LNK=%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\MusicSkin Helper.lnk"
powershell -NoProfile -Command "$s=(New-Object -ComObject WScript.Shell).CreateShortcut($env:LNK); $s.TargetPath='wscript.exe'; $s.Arguments='\"' + $env:DEST + '\start-helper.vbs\"'; $s.WorkingDirectory=$env:DEST; $s.Save()"
wscript.exe "%DEST%\start-helper.vbs"
echo  [ok] Arranca solo con Windows
echo.
echo  Listo. Pon el fondo "Music Desktop Skin" y pon musica en Spotify.
echo.
pause
exit /b

:tool
where %1 >nul 2>nul && (echo  [ok] %1 ya estaba instalado & exit /b)
if exist "%LOCALAPPDATA%\Microsoft\WinGet\Links\%1.exe" (echo  [ok] %1 ya estaba instalado & exit /b)
echo  Instalando %1 (para los videos)... puede tardar un poco.
winget install --id %2 -e --silent --accept-package-agreements --accept-source-agreements --disable-interactivity >nul 2>nul
if errorlevel 1 (echo  [!] No se pudo instalar %1. Letras y controles si funcionan.) else (echo  [ok] %1 instalado)
exit /b