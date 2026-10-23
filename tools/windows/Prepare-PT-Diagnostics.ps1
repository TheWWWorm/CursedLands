# Requires the diagnostic candidate compiled with the custom user directory
# "Cursed Lands PT Diagnostics". Bundle these launchers beside CursedLands.exe.
[CmdletBinding()]
param([switch]$GpuValidation)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$utf8 = New-Object System.Text.UTF8Encoding($false)
$language = [Globalization.CultureInfo]::CurrentUICulture.TwoLetterISOLanguageName
$text = @{
    en = @{
        missing_game = 'CursedLands.exe was not found beside the diagnostic launchers.'
        missing_appdata = 'The Windows application-data directory is unavailable.'
        linked_profile = 'The diagnostic profile contains a linked path. Use a separate local diagnostic profile: {0}'
        start = 'Starting PT diagnostics. Logs: {0}'
        finish = 'Game exit code: {0}. Logs: {1}'
        failed = 'PT diagnostics could not finish: {0}'
    }
    ru = @{
        missing_game = 'Файл CursedLands.exe не найден рядом со средствами запуска диагностики.'
        missing_appdata = 'Папка данных приложений Windows недоступна.'
        linked_profile = 'Профиль диагностики содержит ссылку на другую папку или файл. Используйте отдельный локальный профиль: {0}'
        start = 'Запуск диагностики трассировки путей. Журналы: {0}'
        finish = 'Код завершения игры: {0}. Журналы: {1}'
        failed = 'Не удалось завершить диагностику трассировки путей: {0}'
    }
    de = @{
        missing_game = 'CursedLands.exe wurde neben den Diagnose-Startern nicht gefunden.'
        missing_appdata = 'Der Windows-Ordner für Anwendungsdaten ist nicht verfügbar.'
        linked_profile = 'Das Diagnoseprofil enthält einen verknüpften Pfad. Verwende ein separates lokales Diagnoseprofil: {0}'
        start = 'Pathtracing-Diagnose wird gestartet. Protokolle: {0}'
        finish = 'Beendigungscode des Spiels: {0}. Protokolle: {1}'
        failed = 'Die Pathtracing-Diagnose konnte nicht abgeschlossen werden: {0}'
    }
}
if (-not $text.ContainsKey($language)) { $language = 'en' }

function Assert-UnlinkedPath([string]$Path) {
    if ((Test-Path -LiteralPath $Path) -and
        ((Get-Item -LiteralPath $Path -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw ($text[$language].linked_profile -f $Path)
    }
}

function Copy-MissingDirectory([string]$Source, [string]$Destination) {
    Assert-UnlinkedPath $Source
    Assert-UnlinkedPath $Destination
    [void][IO.Directory]::CreateDirectory($Destination)
    foreach ($item in Get-ChildItem -LiteralPath $Source -Force) {
        Assert-UnlinkedPath $item.FullName
        $target = Join-Path $Destination $item.Name
        Assert-UnlinkedPath $target
        if ($item.PSIsContainer) {
            Copy-MissingDirectory $item.FullName $target
        } elseif (-not (Test-Path -LiteralPath $target)) {
            [IO.File]::Copy($item.FullName, $target, $false)
        }
    }
}

function Resolve-CopiedGameDataPaths([string]$Path, [string]$NormalProfile) {
    # A copied user://import-* reference still belongs to the normal profile.
    # Replace only game-data roots in the freshly copied settings file; the
    # imported assets stay in place and all other configuration stays intact.
    $normalPrefix = [IO.Path]::GetFullPath($NormalProfile).Replace('\', '/').TrimEnd('/') + '/'
    $normalPrefix = $normalPrefix.Replace('"', '\"')
    $result = New-Object 'System.Collections.Generic.List[string]'
    $section = ''
    $changed = $false
    foreach ($line in [IO.File]::ReadAllLines($Path)) {
        if ($line -match '^\s*\[([^\]]+)\]\s*(?:;.*)?$') {
            $section = $Matches[1]
        } elseif (($section -ceq 'game' -or $section -ceq 'games') -and
            ($line -cmatch '^(\s*([^=]+?)\s*=\s*)"user://((?:[^"\\]|\\.)*)"(\s*(?:;.*)?)$') -and
            ($section -ceq 'games' -or $Matches[2].Trim() -ceq 'root')) {
            $line = $Matches[1] + '"' + $normalPrefix + $Matches[3] + '"' + $Matches[4]
            $changed = $true
        }
        $result.Add($line)
    }
    if ($changed) { [IO.File]::WriteAllLines($Path, $result.ToArray(), $utf8) }
}

function Set-DiagnosticOptions([string]$Path, [System.Collections.IDictionary]$Values) {
    Assert-UnlinkedPath $Path
    $lines = @()
    if (Test-Path -LiteralPath $Path) { $lines = [IO.File]::ReadAllLines($Path) }
    $result = New-Object 'System.Collections.Generic.List[string]'
    $inOptions = $false
    $inserted = $false
    foreach ($line in $lines) {
        if ($line -match '^\s*\[([^\]]+)\]\s*(?:;.*)?$') {
            $inOptions = $Matches[1] -ceq 'options'
            $result.Add($line)
            if ($inOptions -and -not $inserted) {
                foreach ($key in $Values.Keys) { $result.Add($key + '=' + $Values[$key]) }
                $inserted = $true
            }
        } elseif ($inOptions -and ($line -match '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=') -and $Values.Contains($Matches[1])) {
            # Replace only controlled keys, including any duplicate entries.
        } else {
            $result.Add($line)
        }
    }
    if (-not $inserted) {
        $result.Add('')
        $result.Add('[options]')
        foreach ($key in $Values.Keys) { $result.Add($key + '=' + $Values[$key]) }
    }
    [IO.File]::WriteAllLines($Path, $result.ToArray(), $utf8)
}

$exitCode = 1
$runDirectory = $null
$profileLock = $null
$gameProcess = $null
try {
    $gameDirectory = $PSScriptRoot
    $executable = Join-Path $gameDirectory 'CursedLands.exe'
    if (-not (Test-Path -LiteralPath $executable -PathType Leaf)) {
        throw $text[$language].missing_game
    }
    $runName = (Get-Date -Format 'yyyyMMdd-HHmmss-fff') + '-' + $PID
    $runDirectory = Join-Path (Join-Path $gameDirectory 'diagnostics') $runName
    [void][IO.Directory]::CreateDirectory($runDirectory)
    if ([string]::IsNullOrWhiteSpace($env:APPDATA)) { throw $text[$language].missing_appdata }
    $normalProfile = Join-Path $env:APPDATA 'Godot\app_userdata\Cursed Lands'
    $diagnosticProfile = Join-Path $env:APPDATA 'Cursed Lands PT Diagnostics'
    Assert-UnlinkedPath $diagnosticProfile
    [void][IO.Directory]::CreateDirectory($diagnosticProfile)
    $lockPath = Join-Path $diagnosticProfile '.pt-diagnostics-launch.lock'
    Assert-UnlinkedPath $lockPath
    $profileLock = [IO.File]::Open($lockPath, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    $marker = Join-Path $diagnosticProfile '.pt-diagnostics-profile-v1'
    Assert-UnlinkedPath $marker
    $initialize = -not (Test-Path -LiteralPath $marker)
    $settings = Join-Path $diagnosticProfile 'settings.cfg'
    foreach ($name in @('settings.cfg', 'mod_settings.json', 'keyboard.ini', 'saves', 'mods')) {
        Assert-UnlinkedPath (Join-Path $diagnosticProfile $name)
    }
    if ($initialize) {
        foreach ($name in @('settings.cfg', 'mod_settings.json', 'keyboard.ini')) {
            $sourceFile = Join-Path $normalProfile $name
            $targetFile = Join-Path $diagnosticProfile $name
            Assert-UnlinkedPath $sourceFile
            if ((Test-Path -LiteralPath $sourceFile -PathType Leaf) -and -not (Test-Path -LiteralPath $targetFile)) {
                [IO.File]::Copy($sourceFile, $targetFile, $false)
                if ($name -ceq 'settings.cfg') { Resolve-CopiedGameDataPaths $targetFile $normalProfile }
            }
        }
        foreach ($name in @('saves', 'mods')) {
            $sourceDirectory = Join-Path $normalProfile $name
            if (Test-Path -LiteralPath $sourceDirectory -PathType Container) {
                Copy-MissingDirectory $sourceDirectory (Join-Path $diagnosticProfile $name)
            }
        }
    }
    $options = [ordered]@{
        confine_mouse = 0
        show_fps = 1
        volume_sfx = 0
        volume_stream = 0
        volume_voice = 0
        autosave = 0
    }
    if ($initialize) {
        $options['pt_mode'] = 1
        $options['q_rt_lighting'] = 0
    }
    Set-DiagnosticOptions $settings $options
    if ($initialize) { [IO.File]::WriteAllText($marker, [DateTime]::UtcNow.ToString('o'), $utf8) }

    $metadata = [ordered]@{
        started_utc = [DateTime]::UtcNow.ToString('o')
        diagnostic_profile = $diagnosticProfile
        profile_initialized = $initialize
        initial_pt_defaults = 'pt_mode=1; q_rt_lighting=0 (two bounces; Low)'
        gpu_validation = [bool]$GpuValidation
        forced_options = $options
    }
    [IO.File]::WriteAllText((Join-Path $runDirectory 'launch.json'), ($metadata | ConvertTo-Json -Depth 4), $utf8)
    try {
        $gpus = @(Get-CimInstance -ClassName Win32_VideoController -OperationTimeoutSec 5 | Select-Object Name, DriverVersion)
        [IO.File]::WriteAllText((Join-Path $runDirectory 'gpu-drivers.json'), (ConvertTo-Json -InputObject $gpus), $utf8)
    } catch {
        [IO.File]::WriteAllText((Join-Path $runDirectory 'gpu-query-error.txt'), $_.Exception.Message, $utf8)
    }

    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $executable
    $startInfo.WorkingDirectory = $gameDirectory
    $startInfo.UseShellExecute = $false
    $startInfo.Arguments = '--rendering-method forward_plus --rendering-driver d3d12 --render-thread safe --audio-driver Dummy --log-file "' + (Join-Path $runDirectory 'godot.log') + '"'
    $startInfo.EnvironmentVariables['EI_D3D12_DIAGNOSTICS'] = '1'
    if ($GpuValidation) {
        $startInfo.EnvironmentVariables['EI_D3D12_GPU_VALIDATION'] = '1'
    } else {
        # Standard diagnostics must not inherit an accidental GBV opt-in.
        $startInfo.EnvironmentVariables.Remove('EI_D3D12_GPU_VALIDATION')
    }
    Write-Host ($text[$language].start -f $runDirectory)
    $gameProcess = [Diagnostics.Process]::Start($startInfo)
    $gameProcess.WaitForExit()
    $exitCode = $gameProcess.ExitCode
    [IO.File]::WriteAllText((Join-Path $runDirectory 'exit-code.txt'), [string]$exitCode, $utf8)
    Write-Host ($text[$language].finish -f $exitCode, $runDirectory)
} catch {
    $failure = $text[$language].failed -f $_.Exception.Message
    Write-Host $failure -ForegroundColor Red
    if ($runDirectory -and [IO.Directory]::Exists($runDirectory)) {
        try { [IO.File]::WriteAllText((Join-Path $runDirectory 'launcher-error.txt'), $failure, $utf8) } catch { }
    }
} finally {
    if ($gameProcess) { $gameProcess.Dispose() }
    if ($profileLock) { $profileLock.Dispose() }
}
exit $exitCode
