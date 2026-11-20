param(
    [ValidateRange(1, 65535)]
    [int]$Port = 11435
)

$ErrorActionPreference = 'Stop'
$projectRoot = $PSScriptRoot
$serverUrl = "http://127.0.0.1:$Port"
$env:OLLAMA_HOST = "127.0.0.1:$Port"
$env:SPELLCHECK_OLLAMA_PORT = "$Port"
$localOllama = Join-Path $projectRoot '.godot\spellcheck-ollama\bin\ollama.exe'
$localModels = Join-Path $projectRoot '.godot\spellcheck-ollama\models'
$localGodot = Join-Path $projectRoot '.godot\spellcheck-engine\Godot_v4.7.2-stable_win64_console.exe'

if (Test-Path -LiteralPath $localOllama) {
    $ollama = $localOllama
} else {
    $ollamaCommand = Get-Command ollama -ErrorAction SilentlyContinue
    if (-not $ollamaCommand) { throw 'Ollama was not found. Install Ollama or add it to PATH.' }
    $ollama = $ollamaCommand.Source
}
if (Test-Path -LiteralPath $localGodot) {
    $godot = $localGodot
} else {
    $godotCommand = Get-Command godot -ErrorAction SilentlyContinue
    if (-not $godotCommand) { throw 'Godot was not found. Install Godot 4.7 or add it to PATH.' }
    $godot = $godotCommand.Source
}

try {
    $models = Invoke-RestMethod -Uri "$serverUrl/api/tags" -TimeoutSec 2
} catch {
    $models = $null
}
if ($null -eq $models) {
    if (Test-Path -LiteralPath $localModels) { $env:OLLAMA_MODELS = $localModels }
    Write-Host "Starting Ollama on $serverUrl..."
    $server = Start-Process -FilePath $ollama -ArgumentList 'serve' -WindowStyle Hidden -PassThru
    for ($attempt = 0; $attempt -lt 40; $attempt++) {
        Start-Sleep -Milliseconds 500
        try {
            $models = Invoke-RestMethod -Uri "$serverUrl/api/tags" -TimeoutSec 2
            break
        } catch {
            if ($server.HasExited) { break }
        }
    }
    if ($null -eq $models) { throw "Ollama could not start on $serverUrl. Check whether the port is in use." }
}

if (-not ($models.models | Where-Object { $_.name -eq 'gemma3:4b' })) {
    Write-Host 'Downloading Gemma 3 4B...'
    & $ollama pull gemma3:4b
    if ($LASTEXITCODE -ne 0) { throw 'Could not download Gemma 3 4B.' }
}

Write-Host "Starting Spellcheck with Gemma on $serverUrl..."
& $godot --path $projectRoot 'res://spellcheck/sandbox.tscn'
if ($LASTEXITCODE -ne 0) { throw "Godot exited with code $LASTEXITCODE." }
