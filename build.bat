@echo off
chcp 65001 >nul
setlocal
cd /d "%~dp0"
echo ============================================
echo   Dota Draft Assistant — сборка приложения
echo ============================================
echo.

rem --- 1. .NET 8 SDK -----------------------------------------------------
where dotnet >nul 2>nul
if errorlevel 1 goto :install_dotnet
dotnet --list-sdks | findstr /b "8." >nul
if errorlevel 1 goto :install_dotnet
goto :have_dotnet

:install_dotnet
echo [1/3] .NET 8 SDK не найден — устанавливаю через winget...
winget install --id Microsoft.DotNet.SDK.8 -e --accept-source-agreements --accept-package-agreements
if errorlevel 1 (
    echo.
    echo Не удалось установить автоматически.
    echo Скачайте .NET 8 SDK вручную: https://dotnet.microsoft.com/download/dotnet/8.0
    echo После установки запустите build.bat ещё раз.
    pause
    exit /b 1
)
echo.
echo .NET установлен. ЗАКРОЙТЕ это окно и запустите build.bat ещё раз
echo (нужно, чтобы Windows подхватила новый путь к dotnet).
pause
exit /b 0

:have_dotnet
echo [1/3] .NET 8 SDK найден.

rem --- 2. Данные героев и патча ------------------------------------------
if exist data\heroes\heroes.json (
    echo [2/3] Данные героев уже скачаны. Чтобы обновить патч — удалите папку data\patch и запустите снова.
) else (
    echo [2/3] Скачиваю героев, портреты и статистику патча ^(около 3 минут^)...
    dotnet run --project tools\DataTool -c Release -- fetch --out data
    if errorlevel 1 goto :fail
)
if not exist data\patch\meta.json (
    dotnet run --project tools\DataTool -c Release -- fetch --out data
    if errorlevel 1 goto :fail
)

rem --- 3. Один exe -------------------------------------------------------
echo [3/3] Собираю DotaDraftAssistant.exe...
if exist release rmdir /s /q release
dotnet publish src\Presentation\DraftAssistant.Overlay.csproj -c Release -r win-x64 --self-contained true ^
    -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -p:DebugType=none -o release
if errorlevel 1 goto :fail

xcopy /E /I /Y /Q data release\data >nul
copy /Y gsi\gamestate_integration_draftassistant.cfg release\ >nul

echo.
echo ============================================
echo   ГОТОВО: release\DotaDraftAssistant.exe
echo   Папку release можно переносить куда угодно.
echo ============================================
explorer release
pause
exit /b 0

:fail
echo.
echo ОШИБКА. Скопируйте текст выше и отправьте его в чат — исправлю.
pause
exit /b 1
