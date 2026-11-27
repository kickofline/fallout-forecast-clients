param(
    [string]$Godot = $env:GODOT3,
    [switch]$Test
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$project = Join-Path $repo 'clients/car'
$projectFile = Join-Path $project 'project.godot'
$dirty = & git -C $repo status --porcelain
if ($LASTEXITCODE -ne 0 -or $dirty) {
    throw "APK export requires a clean Git worktree. `n$($dirty -join "`n")"
}
if (-not $Godot) {
    throw 'Pass -Godot PATH or set GODOT3 to the Godot 3.6.3 executable.'
}
$Godot = (Get-Command $Godot -CommandType Application).Source
& python (Join-Path $repo 'tools/sync_assets.py')
if ($LASTEXITCODE -ne 0) {
    throw 'Car asset sync failed.'
}

$build = Join-Path $repo 'build'
New-Item -ItemType Directory -Force -Path $build | Out-Null
$preset = if ($Test) { 'Android Test' } else { 'Android Car' }
$filename = if ($Test) { 'fallout-car-test.apk' } else { 'fallout-car.apk' }
$target = Join-Path $build $filename
$staged = Join-Path $build "export-$PID-$filename"
$projectBytes = [IO.File]::ReadAllBytes($projectFile)
try {
    $arguments = "--path `"$project`" --no-window --export-debug `"$preset`" `"$staged`""
    $process = Start-Process -FilePath $Godot -ArgumentList $arguments -WindowStyle Hidden -Wait -PassThru
    if ($process.ExitCode -ne 0 -or !(Test-Path -LiteralPath $staged -PathType Leaf) -or
            (Get-Item -LiteralPath $staged).Length -eq 0) {
        throw "Godot failed to export $preset (exit $($process.ExitCode))."
    }
    Move-Item -LiteralPath $staged -Destination $target -Force
    if (Test-Path -LiteralPath "$staged.idsig") {
        Move-Item -LiteralPath "$staged.idsig" -Destination "$target.idsig" -Force
    } elseif (Test-Path -LiteralPath "$target.idsig") {
        Remove-Item -LiteralPath "$target.idsig"
    }
} finally {
    # Godot 3 can reorder keys when opening the project for an export.
    [IO.File]::WriteAllBytes($projectFile, $projectBytes)
    foreach ($file in @($staged, "$staged.idsig")) {
        if (Test-Path -LiteralPath $file) {
            Remove-Item -LiteralPath $file
        }
    }
}

Get-Item -LiteralPath $target | Select-Object FullName, Length, LastWriteTime
