[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$TasDirectory,
    [Parameter(Mandatory)][string]$ConfigPath,
    [string]$Buttons = 'NONE',
    [ValidateRange(1, 36000)][int]$Frames = 30,
    [ValidateRange(1, 100)][int]$Pulses = 1,
    [ValidateRange(1, 36000)][int]$GapFrames = 90,
    [ValidateRange(-32767, 32767)][int]$LeftX = 0,
    [ValidateRange(-32767, 32767)][int]$LeftY = 0,
    [ValidateRange(-32767, 32767)][int]$RightX = 0,
    [ValidateRange(-32767, 32767)][int]$RightY = 0,
    [int]$Port = 9742
)

# Uses the emulator's own TAS input API, rather than OS key injection.
# TAS must already be enabled and this directory selected in its settings.
$ErrorActionPreference = 'Stop'
function Invoke-EmulatorTool([string]$Name, [hashtable]$Arguments = @{}) {
    $response = & "$PSScriptRoot/zarvot-rpc.ps1" -Tool $Name -Port $Port `
        -ArgumentsJson ($Arguments | ConvertTo-Json -Compress) -TimeoutSeconds 10
    if ($response.result.isError) { throw ($response.result | ConvertTo-Json -Depth 10) }
    $block = $response.result.content | Where-Object type -eq text | Select-Object -First 1
    if (-not $block) { throw "No text result for $Name" }
    return ($block.text | ConvertFrom-Json)
}
$allowed = 'NONE|KEY_A|KEY_B|KEY_X|KEY_Y|KEY_LSTICK|KEY_RSTICK|KEY_L|KEY_R|KEY_PLUS|KEY_MINUS|KEY_DLEFT|KEY_DUP|KEY_DRIGHT|KEY_DDOWN|KEY_SL|KEY_SR|KEY_ZL|KEY_ZR'
foreach ($button in $Buttons.Split(';')) {
    if ($button -notmatch "^(?:$allowed)$") { throw "Unsupported TAS button: $button" }
}
$directory = (Resolve-Path -LiteralPath $TasDirectory).Path
$config = Get-Content -LiteralPath $ConfigPath -Raw
if ($config -notmatch '(?m)^tas_enable=true\s*$') { throw 'Enable TAS in the emulator and save its settings first' }
if ($config -match '(?m)^tas_loop=true\s*$') { throw 'Disable TAS looping before using this tool' }
$selected = [regex]::Match($config, '(?m)^tas_directory=(.*)$').Groups[1].Value.Trim().Trim('"')
if (-not $selected -or [IO.Path]::GetFullPath($selected) -ne $directory) {
    throw 'The emulator config selects a different TAS directory; no fixture was modified'
}
$state = Invoke-EmulatorTool get_emulator_state
if (-not $state.game_running) { throw 'A game must be running' }
if ($state.tas_running -or $state.tas_recording) { throw 'Stop existing TAS playback/recording first' }
$fixture = Join-Path $directory 'script0-1.txt'
if (Test-Path -LiteralPath $fixture) { Copy-Item -LiteralPath $fixture -Destination "$fixture.previous" -Force }
$lines = [Collections.Generic.List[string]]::new()
if ($Pulses*$Frames+($Pulses-1)*$GapFrames+30 -gt 36000) { throw 'Fixture exceeds 36000 input ticks' }
for ($pulse = 0; $pulse -lt $Pulses; $pulse++) {
    for ($i = 0; $i -lt $Frames; $i++) { $lines.Add("$($lines.Count) $Buttons $LeftX;$LeftY $RightX;$RightY") }
    if ($pulse -lt $Pulses-1) {
        for ($i = 0; $i -lt $GapFrames; $i++) { $lines.Add("$($lines.Count) NONE 0;0 0;0") }
    }
}
# Neutral input after the held command releases all buttons/sticks.
for ($i = 0; $i -lt 30; $i++) { $lines.Add("$($lines.Count) NONE 0;0 0;0") }
[IO.File]::WriteAllLines($fixture, $lines, [Text.UTF8Encoding]::new($false))
Invoke-EmulatorTool trigger_ui_action @{action='tas_reset'} | Out-Null
# Reset reloads asynchronously in the input thread; verify before starting.
$loaded = $false
for ($attempt = 0; $attempt -lt 20; $attempt++) {
    Start-Sleep -Milliseconds 100
    $state = Invoke-EmulatorTool get_emulator_state
    if ($state.tas_frame -eq 0 -and $state.tas_total_frames -eq $lines.Count) { $loaded = $true; break }
}
if (-not $loaded) { throw 'Fixture did not load; verify TAS enable and directory settings' }
$generation = $state.tas_completion_generation
Invoke-EmulatorTool trigger_ui_action @{action='tas_start_stop'} | Out-Null
[pscustomobject]@{ Frames=$lines.Count; Buttons=$Buttons; CompletionGenerationBefore=$generation; Fixture=$fixture }
