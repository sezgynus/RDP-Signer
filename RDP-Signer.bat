@echo off
setlocal EnableExtensions
title RDP Signer

:: ============================================================
:: ELEVATED INSTANCE MI?
:: ============================================================

if /I "%~1"=="--elevated" goto ELEVATED


:: ============================================================
:: RDP DOSYASI KONTROLU
:: ============================================================

if "%~1"=="" (
    echo.
    echo ==============================================
    echo                  RDP Signer
    echo ==============================================
    echo.
    echo Bir .rdp dosyasini bu dosyanin uzerine
    echo surukleyip birak.
    echo.
    pause
    exit /b 1
)

if /I not "%~x1"==".rdp" (
    echo.
    echo HATA: Suruklenen dosya bir .rdp dosyasi degil.
    echo.
    pause
    exit /b 1
)


:: ============================================================
:: RDP YOLUNU GECICI DOSYAYA KAYDET
:: ============================================================

set "ARGFILE=%TEMP%\RDP_Signer_Input_%RANDOM%_%RANDOM%.txt"

> "%ARGFILE%" echo %~f1


:: ============================================================
:: YONETICI OLARAK YENIDEN BASLAT
:: ============================================================

echo.
echo Yonetici yetkisi isteniyor...
echo.

set "SELF=%~f0"

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath 'cmd.exe' -ArgumentList '/k', ('""{0}"" --elevated ""{1}""' -f $env:SELF,$env:ARGFILE) -Verb RunAs"

if errorlevel 1 (
    echo.
    echo HATA: Yonetici yetkisi alinamadi.
    echo.
    pause
)

exit /b


:: ============================================================
:: YONETICI INSTANCE
:: ============================================================

:ELEVATED

if "%~2"=="" (
    echo.
    echo HATA: Gecici arguman dosyasi belirtilmedi.
    echo.
    pause
    exit /b 1
)

set "ARGFILE=%~2"

if not exist "%ARGFILE%" (
    echo.
    echo HATA: Gecici arguman dosyasi bulunamadi:
    echo %ARGFILE%
    echo.
    pause
    exit /b 1
)

set /p "RDP_INPUT="<"%ARGFILE%"

del "%ARGFILE%" >nul 2>&1

if not defined RDP_INPUT (
    echo.
    echo HATA: RDP dosya yolu okunamadi.
    echo.
    pause
    exit /b 1
)


:: ============================================================
:: ADMIN KONTROL
:: ============================================================

net session >nul 2>&1

if errorlevel 1 (
    echo.
    echo HATA: Program yonetici olarak calismiyor.
    echo.
    pause
    exit /b 1
)

echo.
echo Yonetici yetkisi : OK
echo.


:: ============================================================
:: POWERSHELL MARKERINI BUL
:: ============================================================

set "PSMARK1=###POWERSHELL_"
set "PSMARK2=START###"
set "PSLINE="

for /f "tokens=1 delims=:" %%A in ('findstr /n /c:"%PSMARK1%%PSMARK2%" "%~f0"') do (
    set "PSLINE=%%A"
)

if not defined PSLINE (
    echo.
    echo HATA: PowerShell bolumu bulunamadi.
    echo.
    pause
    exit /b 1
)


:: ============================================================
:: POWERSHELL BOLUMUNU GECICI PS1 DOSYASINA CIKAR
:: ============================================================

set "TEMP_PS=%TEMP%\RDP_Signer_%RANDOM%_%RANDOM%.ps1"

more +%PSLINE% "%~f0" > "%TEMP_PS%"

if not exist "%TEMP_PS%" (
    echo.
    echo HATA: Gecici PowerShell dosyasi olusturulamadi.
    echo.
    pause
    exit /b 1
)


:: ============================================================
:: POWERSHELL SCRIPTINI CALISTIR
:: ============================================================

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%TEMP_PS%" "%RDP_INPUT%"

set "ERR=%ERRORLEVEL%"

del "%TEMP_PS%" >nul 2>&1

echo.

if not "%ERR%"=="0" (
    echo Islem hata ile sonlandi. Hata kodu: %ERR%
) else (
    echo Islem tamamlandi.
)

echo.
pause
exit /b %ERR%


###POWERSHELL_START###
param(
    [Parameter(Mandatory = $true)]
    [string]$RdpFile
)

$ErrorActionPreference = "Stop"

try {

    # ========================================================
    # GENEL AYARLAR
    # ========================================================

    $UserName = $env:USERNAME
    $CertSubject = "CN=$UserName RDP"
    $CertDisplayName = "$UserName RDP"

    Write-Host ""
    Write-Host "==============================================" -ForegroundColor Cyan
    Write-Host "                 RDP Signer" -ForegroundColor Cyan
    Write-Host "==============================================" -ForegroundColor Cyan
    Write-Host ""


    # ========================================================
    # 1 - RDP DOSYASI
    # ========================================================

    if (-not (Test-Path -LiteralPath $RdpFile)) {
        throw "Dosya bulunamadi: $RdpFile"
    }

    if ([IO.Path]::GetExtension($RdpFile).ToLowerInvariant() -ne ".rdp") {
        throw "Suruklenen dosya bir .rdp dosyasi degil."
    }

    $RdpFile = (Resolve-Path -LiteralPath $RdpFile).Path

    Write-Host "[1/7] RDP dosyasi" -ForegroundColor Yellow
    Write-Host "      $RdpFile"
    Write-Host ""


    # ========================================================
    # 2 - SERTIFIKA BUL / OLUSTUR
    # ========================================================

    Write-Host "[2/7] Sertifika kontrol ediliyor..." -ForegroundColor Yellow

    $cert = Get-ChildItem Cert:\CurrentUser\My |
        Where-Object {
            $_.Subject -eq $CertSubject -and
            $_.HasPrivateKey -and
            $_.NotAfter -gt (Get-Date)
        } |
        Sort-Object NotBefore -Descending |
        Select-Object -First 1

    if (-not $cert) {

        Write-Host "      Sertifika bulunamadi, yeni sertifika olusturuluyor..."

        $cert = New-SelfSignedCertificate `
            -Type CodeSigningCert `
            -Subject $CertSubject `
            -FriendlyName $CertDisplayName `
            -CertStoreLocation "Cert:\CurrentUser\My" `
            -KeyExportPolicy Exportable `
            -HashAlgorithm SHA256

        Write-Host "      Yeni sertifika olusturuldu." -ForegroundColor Green
    }
    else {
        Write-Host "      Var olan sertifika kullaniliyor." -ForegroundColor Green
    }

    Write-Host "      Subject    : $($cert.Subject)"
    Write-Host "      Thumbprint : $($cert.Thumbprint)"
    Write-Host ""


    # ========================================================
    # 3 - TRUSTED PUBLISHER + ROOT
    # ========================================================

    Write-Host "[3/7] Sertifika guvenilir depolara ekleniyor..." -ForegroundColor Yellow

    $tp = New-Object System.Security.Cryptography.X509Certificates.X509Store(
        "TrustedPublisher",
        "CurrentUser"
    )

    $tp.Open("ReadWrite")

    if (-not ($tp.Certificates | Where-Object Thumbprint -eq $cert.Thumbprint)) {
        $tp.Add($cert)
    }

    $tp.Close()


    $root = New-Object System.Security.Cryptography.X509Certificates.X509Store(
        "Root",
        "CurrentUser"
    )

    $root.Open("ReadWrite")

    if (-not ($root.Certificates | Where-Object Thumbprint -eq $cert.Thumbprint)) {
        $root.Add($cert)
    }

    $root.Close()

    Write-Host "      TrustedPublisher : OK" -ForegroundColor Green
    Write-Host "      Root             : OK" -ForegroundColor Green
    Write-Host ""


    # ========================================================
    # 4 - SHA256 POLICY DEGERINI HESAPLA
    # ========================================================

    Write-Host "[4/7] SHA256 RDP Publisher policy hazirlaniyor..." -ForegroundColor Yellow

    $sha256 = [System.Security.Cryptography.SHA256]::Create()

    try {
        $sha256Bytes = $sha256.ComputeHash($cert.RawData)
    }
    finally {
        $sha256.Dispose()
    }

    $sha256Thumbprint = ($sha256Bytes | ForEach-Object {
        $_.ToString("X2")
    }) -join ""

    $policyThumbprint = "sha256:$sha256Thumbprint"

    Write-Host "      $policyThumbprint"
    Write-Host ""


    # ========================================================
    # 5 - RDP TRUSTED PUBLISHER POLICY
    # ========================================================

    Write-Host "[5/7] RDP Trusted Publisher policy ayarlaniyor..." -ForegroundColor Yellow

    $regPath = "HKLM\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services"

    $existing = $null

    $queryOutput = & reg.exe query `
        "$regPath" `
        /v TrustedCertThumbprints `
        2>$null

    if ($LASTEXITCODE -eq 0) {

        foreach ($line in $queryOutput) {

            if ($line -match "TrustedCertThumbprints\s+REG_SZ\s+(.+)$") {
                $existing = $matches[1].Trim()
                break
            }
        }
    }


    # ========================================================
    # MEVCUT DEGERLERI TEMIZLE
    #
    # Sadece gecerli:
    #
    # sha256: + 64 HEX
    #
    # kayitlarini alir.
    #
    # Boylece daha once olusan:
    #
    # sha256:AAAA...SHA1sha256:BBBB...
    #
    # gibi bozuk kayitlari da otomatik duzeltir.
    # ========================================================

    $policyEntries = @()

    if (-not [string]::IsNullOrWhiteSpace($existing)) {

        $matches = [regex]::Matches(
            $existing,
            '(?i)sha256:[0-9a-f]{64}'
        )

        foreach ($match in $matches) {

            $value = $match.Value.ToLowerInvariant()

            if ($policyEntries -notcontains $value) {
                $policyEntries += $value
            }
        }
    }


    # ========================================================
    # YENI HASH'I EKLE
    # ========================================================

    $currentPolicyValue = $policyThumbprint.ToLowerInvariant()

    if ($policyEntries -notcontains $currentPolicyValue) {
        $policyEntries += $currentPolicyValue
    }


    # ========================================================
    # VIRGULLE BIRLESTIR
    # ========================================================

    $newValue = $policyEntries -join ","


    Write-Host "      Yazilacak policy:" -ForegroundColor DarkYellow
    Write-Host "      $newValue"
    Write-Host ""


    # ========================================================
    # POLICY'YI REGISTRY'YE YAZ
    # ========================================================

    & reg.exe add `
        "$regPath" `
        /v TrustedCertThumbprints `
        /t REG_SZ `
        /d "$newValue" `
        /f

    if ($LASTEXITCODE -ne 0) {
        throw "TrustedCertThumbprints policy degeri yazilamadi."
    }


    # ========================================================
    # POLICY'YI GERI OKU
    # ========================================================

    $verifyOutput = & reg.exe query `
        "$regPath" `
        /v TrustedCertThumbprints `
        2>$null

    if ($LASTEXITCODE -ne 0) {
        throw "Policy yazildi ancak tekrar okunamadi."
    }

    $verifiedValue = $null

    foreach ($line in $verifyOutput) {

        if ($line -match "TrustedCertThumbprints\s+REG_SZ\s+(.+)$") {
            $verifiedValue = $matches[1].Trim()
            break
        }
    }

    if ([string]::IsNullOrWhiteSpace($verifiedValue)) {
        throw "TrustedCertThumbprints degeri dogrulanamadi."
    }

    $verifyEntries = @()

    $verifyMatches = [regex]::Matches(
        $verifiedValue,
        '(?i)sha256:[0-9a-f]{64}'
    )

    foreach ($match in $verifyMatches) {
        $verifyEntries += $match.Value.ToLowerInvariant()
    }

    if ($verifyEntries -notcontains $currentPolicyValue) {
        throw "Yeni SHA256 thumbprint policy icinde bulunamadi."
    }


    Write-Host "      Policy : OK" -ForegroundColor Green
    Write-Host ""
    Write-Host "      Registry degeri:"
    Write-Host "      $verifiedValue"
    Write-Host ""


    # ========================================================
    # GPUPDATE
    # ========================================================

    Write-Host "      Group Policy yenileniyor..." -ForegroundColor Yellow
    Write-Host ""

    & gpupdate.exe /force

    if ($LASTEXITCODE -ne 0) {
        throw "gpupdate /force hata verdi. ExitCode: $LASTEXITCODE"
    }

    Write-Host ""
    Write-Host "      gpupdate /force : OK" -ForegroundColor Green
    Write-Host ""


    # ========================================================
    # 6 - RDP DOSYASINI IMZALA
    # ========================================================

    Write-Host "[6/7] RDP dosyasi imzalaniyor..." -ForegroundColor Yellow

    $rdpSign = Join-Path $env:SystemRoot "System32\rdpsign.exe"

    if (-not (Test-Path $rdpSign)) {
        throw "rdpsign.exe bulunamadi."
    }

    & $rdpSign /sha256 $cert.Thumbprint /v $RdpFile

    if ($LASTEXITCODE -ne 0) {
        throw "rdpsign.exe hata verdi. ExitCode: $LASTEXITCODE"
    }

    Write-Host ""


    # ========================================================
    # 7 - IMZA KONTROLU
    # ========================================================

    Write-Host "[7/7] Imza kontrol ediliyor..." -ForegroundColor Yellow

    $content = Get-Content -LiteralPath $RdpFile -Raw

    $hasSignature = $content -match "(?m)^signature:s:"
    $hasSignscope = $content -match "(?m)^signscope:s:"

    if (-not $hasSignature -or -not $hasSignscope) {
        throw "RDP dosyasinda signature/signscope alanlari bulunamadi."
    }


    # ========================================================
    # BASARILI
    # ========================================================

    Write-Host ""
    Write-Host "==============================================" -ForegroundColor Green
    Write-Host "              ISLEM BASARILI" -ForegroundColor Green
    Write-Host "==============================================" -ForegroundColor Green
    Write-Host ""

    Write-Host "Yayimci       : $CertDisplayName"
    Write-Host "RDP Thumbprint: $($cert.Thumbprint)"
    Write-Host "Policy SHA256 : $policyThumbprint"
    Write-Host "Dosya         : $RdpFile"

    Write-Host ""
    Write-Host "Sertifika         : OK" -ForegroundColor Green
    Write-Host "Trusted Publisher : OK" -ForegroundColor Green
    Write-Host "SHA256 RDP Policy : OK" -ForegroundColor Green
    Write-Host "Group Policy      : OK" -ForegroundColor Green
    Write-Host "RDP Imzasi        : OK" -ForegroundColor Green
    Write-Host ""

    exit 0
}
catch {

    Write-Host ""
    Write-Host "==============================================" -ForegroundColor Red
    Write-Host "                    HATA" -ForegroundColor Red
    Write-Host "==============================================" -ForegroundColor Red
    Write-Host ""

    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host ""

    if ($_.InvocationInfo.PositionMessage) {
        Write-Host $_.InvocationInfo.PositionMessage -ForegroundColor DarkRed
        Write-Host ""
    }

    exit 1
}