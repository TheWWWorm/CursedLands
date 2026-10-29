$ErrorActionPreference = "Stop"
$env:PYTHONUTF8 = "1"
$script = Join-Path $PSScriptRoot "tools/development.py"
if (Get-Command py -ErrorAction SilentlyContinue) {
    & py -3 $script @args
} else {
    & python $script @args
}
exit $LASTEXITCODE
