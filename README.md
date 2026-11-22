# Music Desktop Skin · Ayudante

Ayudante gratis para el fondo **Music Desktop Skin** de Wallpaper Engine.
Activa las letras en vivo, el video de la canción, la lista de canciones y los controles de Spotify.

## Instalar (1 minuto, solo una vez)

1. **[Descargar MusicSkinHelper.zip](https://github.com/urielit1313-creator/music-desktop-skin-helper/releases/latest/download/MusicSkinHelper.zip)**
2. Clic derecho al archivo › **Extraer todo**.
3. Doble clic en **INSTALAR.bat**.
   Si Windows dice "Windows protegió su PC": **Más información › Ejecutar de todas formas**.
4. Listo. Se instala todo solo (incluso lo de los videos) y arranca con Windows.

## Qué hace

Corre en tu PC (solo en `localhost`) y le pasa al fondo lo que suena en Spotify.
Para los videos instala `yt-dlp` y `ffmpeg` con `winget`. No envía tus datos a ningún lado.
El código está aquí mismo para que lo revises.

## Quitarlo

Borra `%LOCALAPPDATA%\MusicSkin` y el acceso "MusicSkin Helper" de `shell:startup`.