Set-Location C:\Dev
$log = "C:\Dev\green_gate_log.txt"

"========================================" | Set-Content $log
" NeuroFlow Green Gate -- Stage 5" | Add-Content $log
" $(Get-Date)" | Add-Content $log
"========================================" | Add-Content $log

# ---- Step 1: dart pub get ----
"" | Add-Content $log
"[1/3] dart pub get..." | Add-Content $log
$out1 = & dart pub get 2>&1
$code1 = $LASTEXITCODE
$out1 | Add-Content $log
"STEP1 exit code: $code1" | Add-Content $log
if ($code1 -ne 0) {
    "FAILED: dart pub get" | Add-Content $log
    "GREEN GATE FAILED at step 1" | Add-Content $log
    exit 1
}

# ---- Clear stale dart processes and build cache before build_runner ----
"" | Add-Content $log
"[pre-2] Clearing stale dart processes and build cache..." | Add-Content $log
Get-Process -Name "dart" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2
if (Test-Path "C:\Dev\.dart_tool\build") {
    Remove-Item -Recurse -Force "C:\Dev\.dart_tool\build" -ErrorAction SilentlyContinue
    "  Build cache cleared." | Add-Content $log
}

# ---- Step 2: build_runner ----
"" | Add-Content $log
"[2/3] dart run build_runner build..." | Add-Content $log
$out2 = & dart run build_runner build 2>&1
$code2 = $LASTEXITCODE
$out2 | Add-Content $log
"STEP2 exit code: $code2" | Add-Content $log
if ($code2 -ne 0) {
    "FAILED: build_runner" | Add-Content $log
    "GREEN GATE FAILED at step 2" | Add-Content $log
    exit 1
}

# ---- Step 3: flutter build apk --debug (verifies Kotlin compilation) ----
"" | Add-Content $log
"[3/3] flutter build apk --debug..." | Add-Content $log
$out3 = & flutter build apk --debug 2>&1
$code3 = $LASTEXITCODE
$out3 | Add-Content $log
"STEP3 exit code: $code3" | Add-Content $log
if ($code3 -ne 0) {
    "FAILED: flutter build apk --debug" | Add-Content $log
    "GREEN GATE FAILED at step 3" | Add-Content $log
    exit 1
}

"" | Add-Content $log
"========================================" | Add-Content $log
" GREEN GATE PASSED" | Add-Content $log
"========================================" | Add-Content $log
