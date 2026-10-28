# Native Windows D3D12 regression: the first main menu after a temporal mode
# (DLSS, TAA or FSR 2) is selected while its motion-vector shaders are not yet
# cached. Run from PowerShell on the Windows machine under test.
#
# Each mode gets a new profile (APPDATA is redirected for the game processes;
# the packages, the player's profile and driver settings are not modified):
#  1. seed: the previous release (-SeedPackage) opens the menu with the same
#     reported settings and mode, caching its own scene shaders;
#  2. measured: -Package opens the menu in that profile. Materials whose
#     generated code changed between the releases need new ordinary and
#     motion-vector shaders - the update in which 1.34.0 never presented
#     the menu. A process that does not report within -TimeoutSeconds is
#     killed and fails.
param(
    [Parameter(Mandatory=$true)][string]$Package,
    [Parameter(Mandatory=$true)][string]$SeedPackage,
    [Parameter(Mandatory=$true)][string]$OriginalGame,
    [ValidateSet('dlss','taa','fsr2','all')][string]$Mode = 'all',
    [string]$Output,
    [int]$TimeoutSeconds = 240
)
$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT') { throw 'This regression requires native Windows.' }
if (Test-Path 'HKCU:\Software\Wine') { throw 'Wine does not exercise native D3D12 shader compilation.' }
if ([string]::IsNullOrWhiteSpace($Output)) {
    $Output = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'CursedLands-d3d12-cold-start'
}
$packagePath = (Resolve-Path $Package).Path
$originalPath = (Resolve-Path $OriginalGame).Path
$exe = Join-Path $packagePath 'CursedLands.exe'
if (!(Test-Path $exe)) { throw 'Package must contain CursedLands.exe.' }
$seedPath = (Resolve-Path $SeedPackage).Path
if (!(Test-Path (Join-Path $seedPath 'CursedLands.exe'))) { throw 'SeedPackage must contain CursedLands.exe.' }
$fixture = Join-Path $PSScriptRoot 'tests/d3d12_cold_menu_start.gd'
if (!(Test-Path $fixture)) { throw 'Keep the tests directory beside this runner.' }
$run = Join-Path ([IO.Path]::GetFullPath($Output)) ([DateTime]::Now.ToString('yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Path $run | Out-Null
$modes = if ($Mode -eq 'all') { @('dlss','taa','fsr2') } else { @($Mode) }
# The reported High configuration (1.34.0 crash report, 2026-10-28), PT on.
$effects = @'
render_scale=4
q_aniso=4
q_shadows=2
q_shadow_fit=1
gfx_hd_textures=1
gfx_materials=1
gfx_sharp_units=1
gfx_detailed_heads=1
gfx_sky=1
gfx_far_view=1
gfx_terrain=1
gfx_wind=1
gfx_grass=1
gfx_biome_cover=1
gfx_vegetation_interaction=1
gfx_soft_ground=0
gfx_ground_contact=0
gfx_terrain_cliffs=1
gfx_terrain_surface=0
gfx_firelight=1
gfx_torch_glow=1
gfx_lava_light=1
gfx_foliage_light=1
gfx_volumetric=1
gfx_ssao=1
gfx_contact_shadows=1
gfx_bloom=1
gfx_depth_of_field=0
rt_shadows=0
rt_gi=0
q_rt_lighting=0
pt_mode=1
pt_accumulation=0
pt_target_fps=0
pt_sharc=1
pt_denoiser=0
pt_ray_reconstruction=1
pt_restir=1
pt_refraction=1
gfx_water=1
gfx_water_reflections=2
q_water_rt_quality=1
gfx_water_interaction=1
gfx_water_caustics=1
gfx_water_current=1
gfx_water_waves=1
gfx_waterfalls=1
gfx_ambient_wildlife=1
gfx_ambient_particles=1
gfx_clouds=3
gfx_cloud_shadows=1
gfx_cloud_reflections=1
gfx_weather_mist=1
gfx_weather_surfaces=1
gfx_heat_haze=1
gfx_soft_particles=1
gfx_lit_particles=1
gfx_severed_limbs=1
gfx_rain_puddles=1
'@
$temporal = @{
    dlss = "rtx_upscaling=4`nrtx_frame_generation=1`nq_aa=0"
    taa  = "rtx_upscaling=0`nrtx_frame_generation=0`nq_aa=4"
    fsr2 = "rtx_upscaling=0`nrtx_frame_generation=0`nq_aa=5"
}

function Invoke-Case([string]$case, [string]$phase, [string]$fixtureMode, [string]$options, [string]$runtime) {
    $profile = Join-Path $case 'appdata\Godot\app_userdata\Cursed Lands'
    New-Item -ItemType Directory -Force -Path $profile | Out-Null
    # Rewritten for each phase; the shader cache beside it is kept.
    @"
[options]
confine_mouse=0
show_fps=1
volume_sfx=0
volume_stream=0
volume_voice=0
auto_graphics=0
graphics_preset=0
renderer=1
display_mode=0
vsync=0
fps_limit=0
net_directory=0
net_upnp=0
net_lan=0
$effects
$options

[remake]
gfx=4
"@ | Set-Content -LiteralPath (Join-Path $profile 'settings.cfg') -Encoding ASCII
    $arguments = @('--rendering-method','forward_plus','--rendering-driver','d3d12','--windowed',
        '--resolution','1920x1080','--','--no-movies',('"--ei-path=' + $originalPath + '"'),
        ('"--tool=' + $fixture + '"'),('--cold-menu-mode=' + $fixtureMode))
    $stdout = Join-Path $case ($phase + '-stdout.log')
    $saved = $env:APPDATA
    $env:APPDATA = Join-Path $case 'appdata'
    $started = [DateTime]::UtcNow
    try {
        $process = Start-Process -FilePath (Join-Path $runtime 'CursedLands.exe') -ArgumentList $arguments -WorkingDirectory $runtime -PassThru `
            -RedirectStandardOutput $stdout -RedirectStandardError (Join-Path $case ($phase + '-stderr.log'))
    } finally { $env:APPDATA = $saved }
    $null = $process.Handle   # Windows PowerShell reports ExitCode only with a cached handle
    $hung = !$process.WaitForExit($TimeoutSeconds * 1000)
    if ($hung) { Stop-Process -Id $process.Id -Force; $process.WaitForExit() }
    $elapsed = ([DateTime]::UtcNow - $started).TotalSeconds
    $log = Get-Content -LiteralPath $stdout -Raw -ErrorAction SilentlyContinue
    if ($null -eq $log) { $log = '' }
    $lines = $log -split "`r?`n"
    $summary = @($lines | Where-Object { $_ -like 'D3D12_COLD_MENU *' })
    $errors = @($lines | Where-Object { $_ -match '^(SCRIPT ERROR:|FAIL\b)' })
    $data = $null
    if ($summary.Count -eq 1) { $data = $summary[0].Substring(16) | ConvertFrom-Json }
    $passed = !$hung -and $process.ExitCode -eq 0 -and $null -ne $data -and !$data.blocked -and
        $data.failures.Count -eq 0 -and $data.checks -ge 3 -and $errors.Count -eq 0
    return [ordered]@{ phase = $phase; passed = $passed; hung = $hung
        exit = $(if ($hung) { $null } else { $process.ExitCode }); elapsed_s = [math]::Round($elapsed, 1)
        summary = $data; errors = $errors }
}

$results = @()
foreach ($m in $modes) {
    $case = Join-Path $run $m
    $seed = Invoke-Case $case 'seed' 'seed' $temporal[$m] $seedPath
    $measured = if ($seed.passed) { Invoke-Case $case $m $m $temporal[$m] $packagePath } else { $null }
    $passed = $seed.passed -and $null -ne $measured -and $measured.passed -and $measured.summary.checks -ge 5
    $results += [ordered]@{ mode = $m; passed = $passed; seed = $seed; measured = $measured }
    $detail = if (!$seed.passed) { 'seed pass failed' } elseif ($measured.hung) { 'killed after timeout: no menu' } else {
        'menu {0} ms after process start' -f $measured.summary.process_to_menu_ms }
    Write-Output ("{0}: {1} ({2})" -f $m, $(if ($passed) { 'PASS' } else { 'FAIL' }), $detail)
}
$provenance = [ordered]@{
    platform = 'native Windows'; exe_sha256 = (Get-FileHash $exe).Hash
    seed_exe_sha256 = (Get-FileHash (Join-Path $seedPath 'CursedLands.exe')).Hash
    seed_pck_sha256 = (Get-FileHash (Join-Path $seedPath 'CursedLands.pck')).Hash
    pck_sha256 = (Get-FileHash (Join-Path $packagePath 'CursedLands.pck')).Hash
    fixture_sha256 = (Get-FileHash $fixture).Hash; timeout_s = $TimeoutSeconds
    windows = (Get-CimInstance Win32_OperatingSystem | Select-Object Caption,Version,BuildNumber)
    gpu = @(Get-CimInstance Win32_VideoController | Select-Object Name,DriverVersion)
    results = $results
}
$provenance | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $run 'results.json') -Encoding UTF8
if (@($results | Where-Object { !$_.passed }).Count -gt 0) { Write-Output "Failed; inspect $run"; exit 1 }
Write-Output "All cases passed: $run"
