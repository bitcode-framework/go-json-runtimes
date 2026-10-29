# go-json installer for Windows.
#
#   irm https://raw.githubusercontent.com/bitcode-framework/go-json-runtimes/main/install.ps1 | iex
#
# Downloads a prebuilt binary from GitHub Releases. Go is NOT required.
# If no prebuilt binary matches your platform, the script falls back to
# `go install` when a Go toolchain is available.
#
# Parameters:
#   -Version   release to install (default: latest), e.g. v0.1.0
#   -BinDir    install directory (default: %LOCALAPPDATA%\go-json\bin)
#   -Lite      install go-json-lite (no script runtimes) instead

[CmdletBinding()]
param(
    [string]$Version = 'latest',
    [string]$BinDir,
    [switch]$Lite
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$Repo   = 'bitcode-framework/go-json-runtimes'
$Binary = if ($Lite) { 'go-json-lite' } else { 'go-json' }

# Base URL for release downloads. Override for mirrors or local testing.
$BaseUrl = if ($env:GO_JSON_BASE_URL) {
    $env:GO_JSON_BASE_URL.TrimEnd('/')
} else {
    "https://github.com/$Repo/releases/download"
}

function Write-Info($Message) { Write-Host "  $Message" }
function Write-Warn($Message) { Write-Host "  warning: $Message" -ForegroundColor Yellow }

# --- detect platform -------------------------------------------------------

$arch = switch ($env:PROCESSOR_ARCHITECTURE) {
    'AMD64' { 'amd64' }
    'ARM64' { 'arm64' }
    'x86'   { throw '32-bit Windows is not supported. Install the amd64 build manually.' }
    default { throw "unsupported architecture: $env:PROCESSOR_ARCHITECTURE" }
}

if (-not $BinDir) {
    $BinDir = Join-Path $env:LOCALAPPDATA 'go-json\bin'
}

# --- resolve version -------------------------------------------------------

if ($Version -eq 'latest') {
    $latest = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases/latest" `
        -Headers @{ 'User-Agent' = 'go-json-installer' }
    $Version = $latest.tag_name
    if (-not $Version) {
        throw 'could not determine the latest release; pass -Version explicitly'
    }
}

if (-not $Version.StartsWith('v')) { $Version = "v$Version" }

Write-Info "platform: windows/$arch"
Write-Info "version:  $Version"

$asset = "$Binary-windows-$arch.exe"
$url   = "$BaseUrl/$Version/$asset"

# --- download --------------------------------------------------------------

$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("go-json-" + [guid]::NewGuid())
New-Item -ItemType Directory -Force -Path $tmp | Out-Null

try {
    Write-Info "downloading $asset"
    $downloaded = $false
    try {
        Invoke-WebRequest -Uri $url -OutFile (Join-Path $tmp $asset) -UseBasicParsing
        $downloaded = $true
    }
    catch {
        Write-Warn "no prebuilt binary for windows/$arch at $Version"

        $go = Get-Command go -ErrorAction SilentlyContinue
        if ($go) {
            Write-Info "Go found, building from source"
            $env:GOBIN = $tmp
            $pkg = if ($Lite) {
                "github.com/bitcode-framework/go-json/cmd/go-json-lite@$Version"
            } else {
                "github.com/$Repo/cmd/go-json@$Version"
            }
            & go install $pkg
            if ($LASTEXITCODE -ne 0) { throw "go install failed for $pkg" }

            $built = Join-Path $tmp "$Binary.exe"
            if (-not (Test-Path $built)) { throw "expected $built after go install" }
            Move-Item -Force $built (Join-Path $tmp $asset)
            $downloaded = $true
        }
        else {
            throw @"
no prebuilt binary and no Go toolchain found.
  Install Go from https://go.dev/dl/ and re-run, or pick a supported platform.
"@
        }
    }

    if (-not $downloaded) { throw 'download failed' }

    # Verify the checksum when the release ships one.
    try {
        $sumFile = Join-Path $tmp "$asset.sha256"
        Invoke-WebRequest -Uri "$url.sha256" -OutFile $sumFile -UseBasicParsing
        $expected = ((Get-Content $sumFile -Raw) -split '\s+')[0].ToLower()
        $actual   = (Get-FileHash -Path (Join-Path $tmp $asset) -Algorithm SHA256).Hash.ToLower()
        if ($expected -ne $actual) {
            throw "checksum mismatch for ${asset}`n  expected: $expected`n  actual:   $actual"
        }
        Write-Info 'checksum verified'
    }
    catch [System.Net.WebException] {
        # No checksum published; nothing to verify.
    }

    # --- install -----------------------------------------------------------

    New-Item -ItemType Directory -Force -Path $BinDir | Out-Null
    $target = Join-Path $BinDir "$Binary.exe"

    if (Test-Path $target) {
        Write-Info "replacing existing $target"
    }

    Move-Item -Force (Join-Path $tmp $asset) $target
    Write-Info "installed to $target"

    # --- PATH --------------------------------------------------------------

    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    $entries  = @($userPath -split ';' | Where-Object { $_ })
    if ($entries -notcontains $BinDir) {
        $newPath = (@($entries) + $BinDir) -join ';'
        [Environment]::SetEnvironmentVariable('Path', $newPath, 'User')
        $env:Path = "$env:Path;$BinDir"
        Write-Info "added $BinDir to your user PATH (restart your terminal to pick it up)"
    }

    # --- verify ------------------------------------------------------------

    & $target version
    if ($LASTEXITCODE -ne 0) {
        Write-Warn "installed, but '$Binary version' did not run cleanly"
    }

    Write-Host ''
    Write-Host '  Done. Try it:' -ForegroundColor Green
    Write-Host ''
    Write-Host "    $Binary run program.json"
    Write-Host ''
}
finally {
    Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}
