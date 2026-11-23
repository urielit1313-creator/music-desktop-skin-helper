@echo off
chcp 65001 >nul
title Music Desktop Skin - Instalador del ayudante
cls
echo.
echo  ============================================================
echo    MUSIC DESKTOP SKIN  -  Instalador del ayudante
echo  ============================================================
echo.
echo   Esto se hace UNA sola vez. Se va a instalar:
echo.
echo    1. El ayudante de Music Desktop Skin
echo       Conecta el fondo con tu Spotify: letras, lista,
echo       controles y la cancion que suena.
echo    2. yt-dlp  (programa gratuito y conocido)
echo       Busca el video oficial de cada cancion en calidad HD.
echo    3. FFmpeg  (programa gratuito y conocido)
echo       Hace que los videos se vean nitidos y sin franjas negras.
echo.
echo   Todo se queda en tu PC. No se envian tus datos a ningun lado.
echo   No cierres esta ventana hasta que diga LISTO.
echo.
echo  ------------------------------------------------------------
echo.

rem --- si se abrio desde dentro del zip sin extraer, los demas archivos no estan aqui
if not exist "%~dp0musicskin-helper.ps1" (
  echo   [!] Primero tienes que EXTRAER el zip.
  echo.
  echo       Cierra esta ventana. Ve a Descargas, clic derecho a
  echo       MusicSkinHelper.zip  ^>  Extraer todo  ^>  Extraer.
  echo       Luego abre INSTALAR.bat desde la carpeta extraida.
  echo.
  pause
  exit /b 1
)

set "DEST=%LOCALAPPDATA%\MusicSkin\helper"

echo   [1/4] Instalando el ayudante...
powershell -NoProfile -Command "Get-CimInstance Win32_Process -Filter \"Name='powershell.exe'\" | Where-Object { $_.ProcessId -ne $PID -and $_.CommandLine -like '*-File*musicskin-helper.ps1*' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }" >nul 2>nul
if not exist "%DEST%" mkdir "%DEST%"
copy /y "%~dp0*.ps1" "%DEST%\" >nul
copy /y "%~dp0*.html" "%DEST%\" >nul
copy /y "%~dp0*.vbs" "%DEST%\" >nul
if not exist "%DEST%\musicskin-helper.ps1" (
  echo         [!] No se pudo copiar. Vuelve a extraer el zip e intenta otra vez.
  pause
  exit /b 1
)
echo         OK

where winget >nul 2>nul
if errorlevel 1 (
  echo   [2/4] Video HD: yt-dlp ^(descarga directa^)
  call :ytdlp_direct
  echo   [3/4] [!] Tu Windows no tiene "winget" ^(para instalar FFmpeg^).
  echo         Letras, lista, controles y videos SI funcionan.
  goto start
)
echo   [2/4] Video HD: yt-dlp
call :tool yt-dlp yt-dlp.yt-dlp
echo   [3/4] Video nitido: FFmpeg  ^(puede tardar 1-2 minutos^)
call :tool ffmpeg Gyan.FFmpeg

:start
echo   [4/4] Encendiendo el ayudante y haciendo que arranque con Windows...
set "LNK=%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\MusicSkin Helper.lnk"
powershell -NoProfile -Command "$s=(New-Object -ComObject WScript.Shell).CreateShortcut($env:LNK); $s.TargetPath='wscript.exe'; $s.Arguments='\"' + $env:DEST + '\start-helper.vbs\"'; $s.WorkingDirectory=$env:DEST; $s.Save()" >nul 2>nul
wscript.exe "%DEST%\start-helper.vbs"
powershell -NoProfile -Command "for($i=0;$i -lt 30;$i++){ try { if((Invoke-RestMethod http://localhost:47800/status -TimeoutSec 2).ok){ exit 0 } } catch {}; Start-Sleep 1 }; exit 1" >nul 2>nul
if errorlevel 1 (
  echo         [!] El ayudante no respondio. Reinicia la PC: arranca solo al encender.
) else (
  echo         OK, el ayudante ya esta funcionando.
)

rem --- el ayudante lee la app de Spotify para PC (no la pagina web)
set "SPOT="
if exist "%APPDATA%\Spotify\Spotify.exe" set "SPOT=1"
powershell -NoProfile -Command "if(Get-AppxPackage SpotifyAB.SpotifyMusic){exit 0}else{exit 1}" >nul 2>nul && set "SPOT=1"
echo.
echo  ============================================================
echo    LISTO. Ya puedes cerrar esta ventana.
echo  ============================================================
echo.
echo   - Pon el fondo "Music Desktop Skin" en Wallpaper Engine.
echo   - Abre Spotify y pon una cancion: en segundos salen la letra,
echo     los colores y el video.
if not defined SPOT (
  echo.
  echo   [!] No encontre la app de Spotify para PC. Instalala desde
  echo       spotify.com/download o Microsoft Store. La pagina web
  echo       de Spotify no funciona con el fondo.
)
echo.
echo   Ya puedes borrar el zip y esta carpeta: el ayudante quedo
echo   instalado en tu PC y arranca solo con Windows.
echo.
pause
exit /b

:tool
where %1 >nul 2>nul && (echo         OK ^(ya estaba instalado^) & exit /b)
if exist "%LOCALAPPDATA%\Microsoft\WinGet\Links\%1.exe" (echo         OK ^(ya estaba instalado^) & exit /b)
if exist "%LOCALAPPDATA%\MusicSkin\bin\%1.exe" (echo         OK ^(ya estaba instalado^) & exit /b)
powershell -NoProfile -Command "if(Get-ChildItem \"$env:LOCALAPPDATA\Microsoft\WinGet\Packages\" -Recurse -Filter '%1.exe' -EA SilentlyContinue | Select-Object -First 1){exit 0}else{exit 1}" >nul 2>nul && (echo         OK ^(ya estaba instalado^) & exit /b)
winget install --id %2 -e --silent --accept-package-agreements --accept-source-agreements --disable-interactivity >nul 2>nul
if exist "%LOCALAPPDATA%\Microsoft\WinGet\Links\%1.exe" (echo         OK, instalado & exit /b)
where %1 >nul 2>nul && (echo         OK, instalado & exit /b)
if exist "%ProgramFiles%\WinGet\Links\%1.exe" (echo         OK, instalado & exit /b)
powershell -NoProfile -Command "if(Get-ChildItem \"$env:LOCALAPPDATA\Microsoft\WinGet\Packages\" -Recurse -Filter '%1.exe' -EA SilentlyContinue | Select-Object -First 1){exit 0}else{exit 1}" >nul 2>nul && (echo         OK, instalado & exit /b)
if /i "%1"=="yt-dlp" goto ytdlp_direct
echo         [!] No se pudo instalar. Letras, lista y controles SI funcionan.
echo             Revisa tu internet y vuelve a abrir INSTALAR.bat para los videos.
exit /b

:ytdlp_direct
if exist "%LOCALAPPDATA%\MusicSkin\bin\yt-dlp.exe" (echo         OK ^(ya estaba instalado^) & exit /b)
if not exist "%LOCALAPPDATA%\MusicSkin\bin" mkdir "%LOCALAPPDATA%\MusicSkin\bin"
powershell -NoProfile -Command "[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -UseBasicParsing 'https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe' -OutFile \"$env:LOCALAPPDATA\MusicSkin\bin\yt-dlp.exe\" -TimeoutSec 45" >nul 2>nul
if exist "%LOCALAPPDATA%\MusicSkin\bin\yt-dlp.exe" (echo         OK, instalado & exit /b)
echo         [!] No se pudo instalar yt-dlp. Revisa tu internet y vuelve a abrir INSTALAR.bat.
exit /b