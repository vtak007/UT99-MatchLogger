# build.ps1 - Rebuild MatchLogger.u from this repo's Source/, guarded and verified.
#
# Why this exists: the package is compiled from a *mirror* copy of Source/ at
# C:\UnrealTournament\MatchLogger\Classes, because ucc make requires the package
# folder to sit alongside System\ in the UT root. Doing that copy by hand lets the
# deployed binary drift from the tracked source (stale/uncommitted files getting
# baked in). This script makes the mirror a full, disposable copy of Source/ on
# every build, and refuses to build uncommitted source for a deploy.
#
# Usage (from the repo root):
#   pwsh ./build.ps1              # normal: requires clean Source/, builds, verifies
#   pwsh ./build.ps1 -AllowDirty  # build with uncommitted Source/ (local iteration only)
#   pwsh ./build.ps1 -DryRun      # run the guards + print the plan, no changes/build
#
# COMMIT-BEFORE-DEPLOY: anything you deploy to the VPS must come from a committed
# state. Normal (guarded) mode enforces that Source/ is clean. Use -AllowDirty only
# for throwaway local test builds you are NOT going to upload.

param(
    [switch]$AllowDirty,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

$repo    = $PSScriptRoot
$src     = Join-Path $repo 'Source'
$mirror  = 'C:\UnrealTournament\MatchLogger\Classes'
$system  = 'C:\UnrealTournament\System'
$ini     = Join-Path $system 'UnrealTournament.ini'
$pkg     = Join-Path $system 'MatchLogger.u'
$outCopy = Join-Path $repo 'MatchLogger_built.u'

function Fail($msg) { Write-Host "BUILD ABORTED: $msg" -ForegroundColor Red; exit 1 }

# --- Guard 1: UT client must be closed (it locks the .u -> silent no-op build) ---
if (Get-Process UnrealTournament -ErrorAction SilentlyContinue) {
    Fail "UnrealTournament.exe is running - it locks MatchLogger.u and the build silently no-ops. Close it and retry."
}

# --- Guard 2: the build ini must list the package ---
if (-not (Select-String -Path $ini -Pattern 'EditPackages=MatchLogger' -Quiet)) {
    Fail "EditPackages=MatchLogger not found in $ini. Add it as the LAST line under [Editor.EditorEngine], save, then re-run."
}

# --- Guard 3: commit-before-deploy - Source/ must be clean unless overridden ---
$dirty = git -C $repo status --porcelain -- Source
if ($dirty) {
    Write-Host "Uncommitted changes in Source/:" -ForegroundColor Yellow
    $dirty | ForEach-Object { Write-Host "  $_" }
    if (-not $AllowDirty -and -not $DryRun) {
        Fail "Commit Source/ before building a deploy artifact (or use -AllowDirty for a throwaway local build)."
    }
    if ($AllowDirty) { Write-Host "-AllowDirty set: building uncommitted source (do NOT deploy this)." -ForegroundColor Yellow }
}

# --- Plan ---
$toCopy = Get-ChildItem $src -Filter *.uc
if (-not $toCopy) { Fail "No .uc files found in $src." }
Write-Host "Repo:   $repo"
Write-Host "Mirror: $mirror  (wipe + copy $($toCopy.Count) .uc files)"

if ($DryRun) {
    Write-Host "-DryRun: guards passed. No files changed, no build run." -ForegroundColor Green
    exit 0
}

# --- 1. Fully re-sync mirror from Source/ (no stale files can survive) ---
if (-not (Test-Path $mirror)) { New-Item -ItemType Directory -Path $mirror -Force | Out-Null }
Get-ChildItem $mirror -Filter *.uc -ErrorAction SilentlyContinue | Remove-Item -Force
$toCopy | Copy-Item -Destination $mirror -Force
Write-Host "Mirror re-synced."

# --- 2. Delete old package (a pre-existing .u can make ucc report Success but no-op) ---
if (Test-Path $pkg) { Remove-Item $pkg -Force }

# --- 3. Build ---
# NOTE: plain "make", NOT "make -All". -All rebuilds every EditPackages entry, which would
# also recompile and overwrite SmartSB124.u and PersistentMute.u. Step 2 deleted
# MatchLogger.u, and plain "make" only builds packages whose .u is missing - so exactly
# this package gets built.
Push-Location $system
try { $log = & .\ucc.exe make 2>&1 } finally { Pop-Location }

$summary  = $log | Select-String -Pattern '^(Success|Failure)' | Select-Object -Last 1
$compiled = $log | Select-String -Pattern 'Compiling MatchLogger'

# --- 4. Verify a real recompile happened and succeeded ---
if (-not $compiled) { Fail "No 'Compiling ...' lines - ucc did not actually recompile (stale mirror or lock?)." }
if (-not (Test-Path $pkg)) { Fail "Build produced no MatchLogger.u." }
if (-not $summary -or $summary.Line -notmatch 'Success') {
    Fail "Build did not report Success: $($summary.Line)"
}
Write-Host $summary.Line -ForegroundColor Green

# --- 5. Copy the built package into the repo ---
Copy-Item $pkg $outCopy -Force
$hash = (Get-FileHash $outCopy -Algorithm MD5).Hash.ToLower()
Write-Host "OK: built + copied to MatchLogger_built.u  (md5 $hash)" -ForegroundColor Green
Write-Host "Deploy $pkg (with MatchLogger.int) to the server's System\ folder." -ForegroundColor Cyan
