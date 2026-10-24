# Run from PowerShell on the Windows machine being qualified. PresentMon is
# supplied separately: https://github.com/GameTechDev/PresentMon/releases
# No installed game, player profile or driver configuration is modified.
param(
    [Parameter(Mandatory=$true)][string]$Package,
    [Parameter(Mandatory=$true)][string]$OriginalGame,
    [Parameter(Mandatory=$true)][string]$PresentMon,
    [string]$Output
)
$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT') { throw 'This qualification requires native Windows.' }
if (Test-Path 'HKCU:\Software\Wine') { throw 'Wine cannot qualify native Windows pacing.' }
if ([string]::IsNullOrWhiteSpace($Output)) {
    $Output = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'CursedLands-native-dlss-results'
}
$packagePath = (Resolve-Path $Package).Path
$originalPath = (Resolve-Path $OriginalGame).Path
$monitorPath = (Resolve-Path $PresentMon).Path
$outputPath = [IO.Path]::GetFullPath($Output)
$packagePrefix = $packagePath.TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
if ($outputPath.Equals($packagePath, [StringComparison]::OrdinalIgnoreCase) -or
    $outputPath.StartsWith($packagePrefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Output must be outside Package to avoid copying the runtime into itself.'
}
$fixture = Join-Path $PSScriptRoot 'tests/rtx_frame_generation.gd'
if (!(Test-Path $fixture)) { throw 'Keep the tests directory beside this runner.' }
if (!(Test-Path (Join-Path $packagePath 'CursedLands.exe'))) { throw 'Package must contain CursedLands.exe.' }
$runId = [Guid]::NewGuid().ToString('N')
$destination = Join-Path $outputPath $runId
$runtime = Join-Path $destination 'runtime'
New-Item -ItemType Directory -Path $destination | Out-Null
Copy-Item -LiteralPath $packagePath -Destination $runtime -Recurse
$override = Join-Path $runtime 'override.cfg'
if (Test-Path $override) { throw 'The copied package already has an override.cfg; inspect it before qualification.' }
$profileName = 'CursedLands-PT-qualification-' + $runId
$profile = Join-Path ([Environment]::GetFolderPath('ApplicationData')) $profileName
New-Item -ItemType Directory -Path $profile | Out-Null
@"
[application]
config/use_custom_user_dir=true
config/custom_user_dir_name="$profileName"
"@ | Set-Content -LiteralPath $override -Encoding UTF8
@'
[options]
confine_mouse=0
show_fps=1
volume_sfx=0
volume_stream=0
volume_voice=0
auto_graphics=0
display_mode=0
vsync=0
rtx_upscaling=2
rtx_frame_generation=0
fsr_upscaling=0
fsr_frame_generation=0
net_directory=0
net_upnp=0
net_lan=0
'@ | Set-Content -LiteralPath (Join-Path $profile 'settings.cfg') -Encoding UTF8
$exe = Join-Path $runtime 'CursedLands.exe'
$arguments = @('--render-thread','safe','--audio-driver','Dummy','--max-fps','30',
    '--rendering-method','forward_plus','--rendering-driver','d3d12','--windowed',
    '--resolution','1280x720','--','--no-movies',
    ('"--ei-path=' + $originalPath + '"'),('"--tool=' + $fixture + '"'))
$application = $null
$capture = $null
try {
    $application = Start-Process -FilePath $exe -ArgumentList $arguments -WorkingDirectory $runtime -PassThru
    $captureArguments = @('--process_id',$application.Id,'--session_name',('CursedLands-' + $runId),
        '--output_file',('"' + (Join-Path $destination 'presentmon.csv') + '"'),
        '--date_time','--v2_metrics','--track_frame_type','--no_console_stats',
        '--timed','180','--terminate_after_timed','--terminate_on_proc_exit')
    $captureStart = @{
        FilePath = $monitorPath; ArgumentList = $captureArguments; PassThru = $true
        RedirectStandardOutput = (Join-Path $destination 'presentmon.log')
        RedirectStandardError = (Join-Path $destination 'presentmon-error.log')
    }
    $capture = Start-Process @captureStart
    if (!$application.WaitForExit(180000)) { throw 'The test exceeded its three-minute limit.' }
    $application.Refresh()
    if (!$capture.WaitForExit(15000)) { throw 'PresentMon did not finish its capture.' }
    New-Item -ItemType Directory -Path (Join-Path $destination 'profile') | Out-Null
    Copy-Item -Path (Join-Path $profile '*') -Destination (Join-Path $destination 'profile') -Recurse
    $metadata = [ordered]@{
        platform = 'native Windows'; profile = $profile; application_exit = $application.ExitCode
        presentmon_exit = $capture.ExitCode; presentmon_sha256 = (Get-FileHash $monitorPath).Hash
        exe_sha256 = (Get-FileHash $exe).Hash
        pck_sha256 = (Get-FileHash (Join-Path $runtime 'CursedLands.pck')).Hash
        fixture_sha256 = (Get-FileHash $fixture).Hash
        captured_at_utc = [DateTime]::UtcNow.ToString('o')
        time_zone = [TimeZoneInfo]::Local.Id
        utc_offset_minutes = [TimeZoneInfo]::Local.GetUtcOffset([DateTime]::Now).TotalMinutes
        windows = (Get-CimInstance Win32_OperatingSystem | Select-Object Caption,Version,BuildNumber)
        gpu = @(Get-CimInstance Win32_VideoController | Select-Object Name,DriverVersion,CurrentRefreshRate)
        pacing_review = 'Pending analysis of PresentMon display intervals and test phase timestamps.'
    }
    $metadata | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $destination 'provenance.json') -Encoding UTF8
    $result = Get-Content (Join-Path $profile 'dlss-framegen.json') -Raw | ConvertFrom-Json
    if ($application.ExitCode -ne 0 -or $result.blocked -or $result.failures.Count -gt 0) {
        throw "Runtime qualification failed; inspect $destination"
    }
    if ($capture.ExitCode -ne 0 -or !(Test-Path (Join-Path $destination 'presentmon.csv'))) {
        throw "PresentMon capture failed; inspect $destination"
    }
    Write-Output "Runtime checks passed. Pacing evidence is ready for review: $destination"
} finally {
    if ($capture -and !$capture.HasExited) { Stop-Process -Id $capture.Id }
    if ($application -and !$application.HasExited) { Stop-Process -Id $application.Id }
}
