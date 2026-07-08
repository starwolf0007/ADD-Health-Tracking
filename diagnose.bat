@echo off
cd /d C:\Dev
echo Running dart pub get (NOT flutter) with no redirection...
dart pub get
echo.
echo ERRORLEVEL after dart pub get: %ERRORLEVEL%
echo.
echo Now running build_runner...
dart run build_runner build --delete-conflicting-outputs
echo.
echo ERRORLEVEL after build_runner: %ERRORLEVEL%
echo.
echo Now running flutter analyze...
flutter analyze
echo.
echo ERRORLEVEL after flutter analyze: %ERRORLEVEL%
echo.
echo ALL STEPS COMPLETE
pause
