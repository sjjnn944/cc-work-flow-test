# dev-setup: Windows 공통 유틸리티
# 사용법: . "$PSScriptRoot\_common.ps1"

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$script:LOG_PREFIX = "[dev-setup]"

function Write-Status {
    param(
        [ValidateSet("OK", "INSTALL", "SKIP", "FAIL", "CHECK")]
        [string]$Status,
        [string]$Message
    )
    $colors = @{ OK = "Green"; INSTALL = "Cyan"; SKIP = "Yellow"; FAIL = "Red"; CHECK = "Gray" }
    Write-Host "[$Status] " -ForegroundColor $colors[$Status] -NoNewline
    Write-Host $Message
}

function Test-CommandExists {
    param([string]$Command)
    $null -ne (Get-Command $Command -ErrorAction SilentlyContinue)
}

function Test-MinVersion {
    param(
        [string]$Command,
        [string]$VersionArg = "--version",
        [string]$MinVersion,
        [string]$VersionPattern = '(\d+\.\d+[\.\d]*)'
    )
    if (-not (Test-CommandExists $Command)) { return $false }
    try {
        $output = & $Command $VersionArg 2>&1 | Out-String
        if ($output -match $VersionPattern) {
            $current = [version]$Matches[1]
            $required = [version]$MinVersion
            return $current -ge $required
        }
    } catch {}
    return $false
}

function Install-WithWinget {
    param(
        [string]$PackageId,
        [string]$DisplayName
    )
    if (-not (Test-CommandExists "winget")) {
        Write-Status "FAIL" "winget을 사용할 수 없습니다"
        return $false
    }
    Write-Status "INSTALL" "$DisplayName 설치 중 (winget)..."
    try {
        winget install --id $PackageId --accept-source-agreements --accept-package-agreements --silent
        if ($LASTEXITCODE -eq 0) {
            Write-Status "OK" "$DisplayName 설치 완료"
            return $true
        }
    } catch {}
    Write-Status "FAIL" "$DisplayName 설치 실패"
    return $false
}

function Install-WithChoco {
    param(
        [string]$PackageName,
        [string]$DisplayName
    )
    if (-not (Test-CommandExists "choco")) {
        Write-Status "FAIL" "choco를 사용할 수 없습니다"
        return $false
    }
    Write-Status "INSTALL" "$DisplayName 설치 중 (choco)..."
    try {
        choco install $PackageName -y --no-progress
        if ($LASTEXITCODE -eq 0) {
            Write-Status "OK" "$DisplayName 설치 완료"
            return $true
        }
    } catch {}
    Write-Status "FAIL" "$DisplayName 설치 실패"
    return $false
}

function Add-ToPath {
    param([string]$Path)
    if ($env:PATH -notlike "*$Path*") {
        $env:PATH = "$Path;$env:PATH"
        [Environment]::SetEnvironmentVariable("PATH", "$Path;$([Environment]::GetEnvironmentVariable('PATH', 'User'))", "User")
        Write-Status "OK" "PATH에 추가: $Path"
    }
}

function Test-AdminPrivilege {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]$identity
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Request-AdminElevation {
    if (-not (Test-AdminPrivilege)) {
        Write-Status "CHECK" "관리자 권한이 필요합니다. 승격을 요청합니다..."
        $scriptPath = $MyInvocation.ScriptName
        $argList = "-ExecutionPolicy Bypass -File `"$scriptPath`" $($script:AllArgs -join ' ')"
        Start-Process powershell.exe -Verb RunAs -ArgumentList $argList -Wait
        exit $LASTEXITCODE
    }
}

function Refresh-PathEnv {
    $machinePath = [Environment]::GetEnvironmentVariable("PATH", "Machine")
    $userPath = [Environment]::GetEnvironmentVariable("PATH", "User")
    $env:PATH = "$userPath;$machinePath"
}

function Send-SettingChange {
    # WM_SETTINGCHANGE 브로드캐스트 — 새 터미널/Explorer가 환경변수 변경을 즉시 인식하도록 함
    if (-not ([System.Management.Automation.PSTypeName]'Win32.NativeMethods').Type) {
        Add-Type -Namespace Win32 -Name NativeMethods -MemberDefinition @'
[DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
public static extern IntPtr SendMessageTimeout(
    IntPtr hWnd, uint Msg, UIntPtr wParam, string lParam,
    uint fuFlags, uint uTimeout, out UIntPtr lpdwResult);
'@
    }
    $HWND_BROADCAST = [IntPtr]0xffff
    $WM_SETTINGCHANGE = 0x1a
    $SMTO_ABORTIFHUNG = 0x0002
    $result = [UIntPtr]::Zero
    [Win32.NativeMethods]::SendMessageTimeout(
        $HWND_BROADCAST, $WM_SETTINGCHANGE, [UIntPtr]::Zero,
        "Environment", $SMTO_ABORTIFHUNG, 5000, [ref]$result
    ) | Out-Null
}

# 전체 인수 저장
$script:AllArgs = $args

function Get-ProjectRoot {
    # --project-root 인수가 있으면 사용, 없으면 git root, 없으면 현재 디렉토리
    for ($i = 0; $i -lt $script:AllArgs.Count; $i++) {
        if ($script:AllArgs[$i] -eq "--project-root" -and $i + 1 -lt $script:AllArgs.Count) {
            return $script:AllArgs[$i + 1]
        }
    }
    try {
        $gitRoot = git rev-parse --show-toplevel 2>$null
        if ($gitRoot) { return $gitRoot }
    } catch {}
    return (Get-Location).Path
}

function Get-ThirdpartyDir {
    $root = Get-ProjectRoot
    $dir = Join-Path $root "thirdparty"
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    return $dir
}

function Test-BuildSample {
    param(
        [string]$Platform,          # "springboot", "cpp" 등
        [string]$SkillRoot          # 스킬 루트 경로
    )

    $sampleDir = Join-Path $SkillRoot "assets\samples\$Platform"
    if (-not (Test-Path $sampleDir)) {
        Write-Status "SKIP" "빌드 검증 샘플 없음: $Platform"
        return $true
    }

    $tempDir = Join-Path $env:TEMP "dev-setup-verify"
    try {
        # temp에 샘플 복사
        if (Test-Path $tempDir) { Remove-Item $tempDir -Recurse -Force }
        Copy-Item $sampleDir $tempDir -Recurse

        # 플랫폼별 빌드 명령 실행
        switch ($Platform) {
            "springboot" {
                Push-Location $tempDir
                try {
                    $sourceFile = "src\main\java\verify\BuildVerify.java"

                    if (Test-CommandExists "gradle") {
                        # --- Gradle 빌드 경로 ---
                        Write-Status "CHECK" "Gradle + JDK 17 빌드 테스트..."

                        & gradle wrapper --quiet 2>&1 | Out-Null
                        if ($LASTEXITCODE -ne 0) {
                            Write-Status "FAIL" "Gradle wrapper 생성 실패"
                            return $false
                        }

                        & .\gradlew.bat build --quiet 2>&1 | Out-Null
                        if ($LASTEXITCODE -ne 0) {
                            Write-Status "FAIL" "Gradle 빌드 실패"
                            return $false
                        }

                        $classPath = "build\classes\java\main"
                        if (-not (Test-Path $classPath)) {
                            Write-Status "FAIL" "빌드 출력 디렉토리 없음: $classPath"
                            return $false
                        }
                        Write-Status "OK" "Gradle 빌드 성공"

                    } elseif (Test-CommandExists "javac") {
                        # --- javac 직접 컴파일 fallback ---
                        Write-Status "CHECK" "javac + JDK 빌드 테스트 (Gradle 미설치, javac fallback)..."

                        # javac와 동일한 JDK의 java를 사용 (PATH 꼬임 방지)
                        $javacPath = (Get-Command javac).Source
                        $script:JavaExe = Join-Path (Split-Path $javacPath) "java.exe"
                        if (-not (Test-Path $script:JavaExe)) {
                            $script:JavaExe = "java"  # fallback to PATH
                        }

                        $outDir = "build\classes"
                        New-Item -ItemType Directory -Path $outDir -Force | Out-Null
                        & javac -d $outDir $sourceFile 2>&1 | Out-Null
                        if ($LASTEXITCODE -ne 0) {
                            Write-Status "FAIL" "javac 컴파일 실패"
                            return $false
                        }
                        $classPath = $outDir
                        Write-Status "OK" "javac 컴파일 성공"

                    } else {
                        Write-Status "FAIL" "gradle, javac 모두 찾을 수 없습니다"
                        return $false
                    }

                    # --- 공통: 실행 검증 ---
                    $javaCmd = if ($script:JavaExe) { $script:JavaExe } else { "java" }
                    $output = & $javaCmd -cp $classPath verify.BuildVerify 2>&1 | Out-String
                    if ($output -match "Build verification passed!") {
                        Write-Status "OK" "java -cp 실행 성공: `"Build verification passed!`""
                        return $true
                    } else {
                        Write-Status "FAIL" "빌드 결과 실행 실패: $output"
                        return $false
                    }
                } finally {
                    Pop-Location
                }
            }
            "cpp" {
                Write-Status "CHECK" "CMake + C++ 빌드 테스트..."

                Push-Location $tempDir
                try {
                    if (-not (Test-CommandExists "cmake")) {
                        Write-Status "FAIL" "cmake 명령을 찾을 수 없습니다"
                        return $false
                    }

                    # generator 결정: Ninja 우선, 없으면 기본(MSVC)
                    $buildDir = "build"
                    if (Test-CommandExists "ninja") {
                        $configResult = & cmake -S . -B $buildDir -G Ninja 2>&1 | Out-String
                    } else {
                        $configResult = & cmake -S . -B $buildDir 2>&1 | Out-String
                    }
                    if ($LASTEXITCODE -ne 0) {
                        Write-Status "FAIL" "CMake configure 실패: $configResult"
                        return $false
                    }
                    Write-Status "OK" "CMake configure 성공"

                    $buildResult = & cmake --build $buildDir 2>&1 | Out-String
                    if ($LASTEXITCODE -ne 0) {
                        Write-Status "FAIL" "CMake 빌드 실패: $buildResult"
                        return $false
                    }
                    Write-Status "OK" "CMake 빌드 성공"

                    # 실행 파일 찾기
                    $exe = Get-ChildItem -Path $buildDir -Recurse -Filter "build_verify*" -File |
                           Where-Object { $_.Extension -in '.exe', '' } |
                           Select-Object -First 1
                    if (-not $exe) {
                        Write-Status "FAIL" "빌드 결과 실행 파일을 찾을 수 없음"
                        return $false
                    }

                    $output = & $exe.FullName 2>&1 | Out-String
                    if ($output -match "Build verification passed!") {
                        Write-Status "OK" "실행 성공: `"Build verification passed!`""
                        return $true
                    } else {
                        Write-Status "FAIL" "빌드 결과 실행 실패: $output"
                        return $false
                    }
                } finally {
                    Pop-Location
                }
            }
            "driver" {
                Write-Status "CHECK" "WDK 드라이버 빌드 테스트 (MSBuild)..."

                # 1. vswhere로 VS 설치 경로 탐색
                $vsWhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
                if (-not (Test-Path $vsWhere)) {
                    Write-Status "FAIL" "vswhere 없음 — Visual Studio 미설치"
                    return $false
                }
                $vsPath = & $vsWhere -latest -products * -requires Microsoft.Component.MSBuild -property installationPath 2>$null
                if (-not $vsPath) {
                    Write-Status "FAIL" "MSBuild를 포함한 Visual Studio를 찾을 수 없습니다"
                    return $false
                }
                Write-Status "OK" "Visual Studio 감지: $vsPath"

                # 2. MSBuild.exe 경로 확인 (VS 2019/2022 모두 대응)
                $msbuild = & $vsWhere -latest -products * -requires Microsoft.Component.MSBuild -find "MSBuild\**\Bin\MSBuild.exe" 2>$null | Select-Object -First 1
                if (-not $msbuild -or -not (Test-Path $msbuild)) {
                    Write-Status "FAIL" "MSBuild.exe를 찾을 수 없습니다"
                    return $false
                }
                Write-Status "OK" "MSBuild 감지: $msbuild"

                # 3. WDK 설치 여부 확인 (km\ntddk.h 존재)
                $kitRoot = "${env:ProgramFiles(x86)}\Windows Kits\10"
                $incBase = Join-Path $kitRoot "Include"
                $wdkVer = $null
                if (Test-Path $incBase) {
                    $wdkVer = Get-ChildItem $incBase -Directory |
                              Where-Object { Test-Path (Join-Path $_.FullName "km\ntddk.h") } |
                              Sort-Object Name -Descending |
                              Select-Object -First 1
                }
                if (-not $wdkVer) {
                    Write-Status "FAIL" "WDK가 설치되어 있지 않습니다 (km\ntddk.h 없음)"
                    return $false
                }
                Write-Status "OK" "WDK 버전 감지: $($wdkVer.Name)"

                # 4. temp에 샘플 복사 (이미 상위에서 수행됨)
                # 5. MSBuild로 빌드
                $vcxproj = Join-Path $tempDir "build-verify.vcxproj"
                if (-not (Test-Path $vcxproj)) {
                    Write-Status "FAIL" "build-verify.vcxproj 샘플 파일 없음"
                    return $false
                }

                $wdkVerName = $wdkVer.Name
                $buildOutput = & $msbuild $vcxproj /p:Configuration=Release /p:Platform=x64 /p:WindowsTargetPlatformVersion=$wdkVerName /v:minimal 2>&1 | Out-String
                if ($LASTEXITCODE -ne 0) {
                    Write-Status "FAIL" "WDK 드라이버 MSBuild 실패:`n$buildOutput"
                    return $false
                }

                # 6. .sys 파일 생성 확인
                $sysFile = Join-Path $tempDir "build\build-verify.sys"
                if (Test-Path $sysFile) {
                    Write-Status "OK" "WDK 드라이버 빌드 성공 (build-verify.sys 생성)"
                    return $true
                } else {
                    Write-Status "FAIL" "빌드는 성공했으나 build-verify.sys 파일을 찾을 수 없음"
                    return $false
                }
            }
            default {
                Write-Status "SKIP" "빌드 검증 미지원 플랫폼: $Platform"
                return $true
            }
        }
    } catch {
        Write-Status "FAIL" "빌드 검증 중 오류: $_"
        return $false
    } finally {
        # temp 정리
        if (Test-Path $tempDir) {
            Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

# --check-only 인수 처리
$script:CheckOnly = $args -contains "--check-only"
