[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ConfigPath,
    [Parameter(Mandatory)][string]$EmulatorPath,
    [Parameter(Mandatory)][string]$Scene,
    [Parameter(Mandatory)][string]$OutputPath,
    [ValidateRange(5, 3600)][int]$Seconds = 60,
    [ValidateRange(0, 60)][int]$CountdownSeconds = 10,
    [string]$Notes = '',
    [int]$Port = 9742,
    [switch]$IncludeGpuCounters
)

# Records a manual playtest. Never sends input, pauses, or changes settings.
$ErrorActionPreference = 'Stop'
$settingsNames = @('cpu_backend', 'cpu_accuracy', 'use_multi_core', 'backend',
    'resolution_setup', 'gpu_accuracy', 'use_disk_shader_cache',
    'use_asynchronous_gpu_emulation', 'use_asynchronous_shaders',
    'use_speed_limit', 'speed_limit', 'use_docked_mode', 'volume')
function Read-Settings {
    $settings = [ordered]@{}
    foreach ($line in Get-Content -LiteralPath $ConfigPath) {
        if ($line -match '^([^=]+)=(.*)$' -and $settingsNames -contains $Matches[1]) {
            $settings[$Matches[1]] = $Matches[2]
        }
    }
    return $settings
}
Resolve-Path -LiteralPath $EmulatorPath -ErrorAction Stop | Out-Null
$configHash = (Get-FileHash -LiteralPath $ConfigPath -Algorithm SHA256).Hash.ToLowerInvariant()
$settingsBefore = Read-Settings
Write-Host "Recording starts in $CountdownSeconds seconds. Resume gameplay and keep it visible and foreground."
if ($CountdownSeconds) { Start-Sleep -Seconds $CountdownSeconds }
$response = & "$PSScriptRoot/zarvot-rpc.ps1" -Tool get_emulator_state -Port $Port -TimeoutSeconds 5
if ($response.result.isError) { throw ($response.result | ConvertTo-Json -Depth 10) }
$block = $response.result.content | Where-Object type -eq text | Select-Object -First 1
if (-not $block) { throw 'Emulator returned no state' }
$state = $block.text | ConvertFrom-Json
if (-not $state.game_running -or -not $state.emulation_thread_running) {
    throw 'Resume gameplay before recording. No benchmark was written.'
}
if ($state.tas_running -or $state.tas_recording) {
    throw 'Stop TAS playback/recording before a manual playtest. No controller state was changed.'
}
& "$PSScriptRoot/zarvot-sample.ps1" -Scene $Scene -OutputPath $OutputPath `
    -EmulatorPath $EmulatorPath -Seconds $Seconds -Port $Port -IncludeGpuCounters:$IncludeGpuCounters
$result = Get-Content -LiteralPath $OutputPath -Raw | ConvertFrom-Json
$result | Add-Member -NotePropertyName InputMethod -NotePropertyValue 'Manual user playtest; recorder sends no controller input'
$result | Add-Member -NotePropertyName OperatorNotes -NotePropertyValue $Notes
$result | Add-Member -NotePropertyName ConfigSha256Before -NotePropertyValue $configHash
$result | Add-Member -NotePropertyName ConfigSha256After -NotePropertyValue ((Get-FileHash -LiteralPath $ConfigPath -Algorithm SHA256).Hash.ToLowerInvariant())
$result | Add-Member -NotePropertyName SavedSettingsBefore -NotePropertyValue $settingsBefore
$result | Add-Member -NotePropertyName SavedSettingsAfter -NotePropertyValue (Read-Settings)
$result | Add-Member -NotePropertyName SettingsLimit -NotePropertyValue 'Saved profile entries; in-memory settings and focus are not continuously verified'
[IO.File]::WriteAllText([IO.Path]::GetFullPath($OutputPath), ($result | ConvertTo-Json -Depth 12), [Text.UTF8Encoding]::new($false))
Write-Host "Recording saved to $OutputPath"
