param(
    [ValidateRange(1, 65535)]
    [int]$Port,
    [switch]$Editor,
    [string]$GameExe
)

$ErrorActionPreference = 'Stop'
$projectRoot = $PSScriptRoot
$envRoot = if ($GameExe) { Split-Path -Parent (Resolve-Path -LiteralPath $GameExe).Path } else { $projectRoot }
$envPath = Join-Path $envRoot '.env'
if (Test-Path -LiteralPath $envPath -PathType Leaf) {
    foreach ($line in Get-Content -LiteralPath $envPath) {
        if ($line -match '^\s*(?<name>[A-Z][A-Z0-9_]*)\s*=\s*(?<value>.*)$') {
            $name = $Matches.name
            if ($name -notin @('WORKSHOP_PROVIDER','WORKSHOP_MODEL','SPELLCHECK_PROVIDER','SPELLCHECK_MODEL','SPELLCHECK_OLLAMA_PORT','OPENROUTER_API_KEY','GEMINI_API_KEY','GROQ_API_KEY')) { continue }
            if (Test-Path "Env:$name") { continue }
            $value = $Matches.value.Trim()
            if ($value.Length -ge 2 -and (($value[0] -eq '"' -and $value[-1] -eq '"') -or ($value[0] -eq "'" -and $value[-1] -eq "'"))) {
                $value = $value.Substring(1, $value.Length - 2)
            }
            [Environment]::SetEnvironmentVariable($name, $value, 'Process')
        }
    }
}
if (-not $PSBoundParameters.ContainsKey('Port')) {
    $Port = 11435
    if ($env:SPELLCHECK_OLLAMA_PORT) {
        $parsedPort = 0
        if (-not [int]::TryParse($env:SPELLCHECK_OLLAMA_PORT, [ref]$parsedPort) -or $parsedPort -lt 1 -or $parsedPort -gt 65535) {
            throw 'SPELLCHECK_OLLAMA_PORT must be between 1 and 65535.'
        }
        $Port = $parsedPort
    }
}
$serverUrl = "http://127.0.0.1:$Port"
$env:OLLAMA_HOST = "127.0.0.1:$Port"
$env:SPELLCHECK_OLLAMA_PORT = "$Port"
$provider = if ($env:SPELLCHECK_PROVIDER) { $env:SPELLCHECK_PROVIDER } else { 'ollama' }
$model = if ($env:SPELLCHECK_MODEL) { $env:SPELLCHECK_MODEL } else { 'gemma3:4b' }
$localOllama = Join-Path $projectRoot '.godot\spellcheck-ollama\bin\ollama.exe'
$localModels = Join-Path $projectRoot '.godot\spellcheck-ollama\models'
$localGodot = Join-Path $projectRoot '.godot\spellcheck-engine\Godot_v4.7.2-stable_win64_console.exe'

if ($provider -eq 'ollama') {
    try {
        if (Test-Path -LiteralPath $localOllama) {
            $ollama = $localOllama
        } else {
            $ollamaCommand = Get-Command ollama -ErrorAction SilentlyContinue
            if (-not $ollamaCommand) { throw 'Ollama was not found. Install Ollama or add it to PATH.' }
            $ollama = $ollamaCommand.Source
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

        if (-not ($models.models | Where-Object { $_.name -eq $model })) {
            Write-Host "Downloading $model..."
            & $ollama pull $model
            if ($LASTEXITCODE -ne 0) { throw 'Could not download the selected Ollama model.' }
        }
    } catch {
        Write-Warning ('Ollama setup failed. You can still use the workshop and previously unlocked spells. ' + $_.Exception.Message)
    }
}

if ($GameExe) {
    & (Resolve-Path -LiteralPath $GameExe).Path
} else {
    if (Test-Path -LiteralPath $localGodot) {
        $godot = $localGodot
    } else {
        $godotCommand = Get-Command godot -ErrorAction Stop
        $godot = $godotCommand.Source
    }
    if ($Editor) {
        & $godot --path $projectRoot --editor
    } else {
        & $godot --path $projectRoot
    }
}
if ($LASTEXITCODE -ne 0) { throw "Godot exited with code $LASTEXITCODE." }
