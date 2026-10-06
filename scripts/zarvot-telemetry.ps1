# Parse independent UI and coverage sources; absent or torn telemetry is unknown.
function ConvertFrom-ZarvotWindowTitle {
    param([string]$Title)
    $result = [ordered]@{ jit_transitions = $null; shaders_building = $null; fps = $null }
    if ($Title -match '(?:^|\|)\s*JIT transitions:\s*(\d+)\s*(?:\||$)') {
        $result.jit_transitions = [uint64]$Matches[1]
    }
    if ($Title -match '(?:^|\|)\s*Building (\d+) shaders?\s*(?:\||$)') {
        $result.shaders_building = [int]$Matches[1]
    }
    if ($Title -match '(?:^|\|)\s*(\d+(?:\.\d+)?) FPS\s*\(') {
        $result.fps = [double]::Parse($Matches[1], [Globalization.CultureInfo]::InvariantCulture)
    }
    [pscustomobject]$result
}

function ConvertFrom-ZarvotCoverage {
    param([string]$Text)
    $result = [ordered]@{
        report_complete = $false
        static_blocks = $null
        jit_transitions = $null
        lookup_misses = $null
        unhandled_opcodes = $null
        unresolved_import_traps = $null
    }
    if (-not $Text.StartsWith('=== RECOMP EXECUTION COVERAGE ===') -or
        -not $Text.TrimEnd().EndsWith('=== END RECOMP EXECUTION COVERAGE ===') -or
        [regex]::Matches($Text, '=== RECOMP EXECUTION COVERAGE ===').Count -ne 1 -or
        [regex]::Matches($Text, '=== END RECOMP EXECUTION COVERAGE ===').Count -ne 1) {
        return [pscustomobject]$result
    }
    if ($Text -notmatch 'static blocks executed\s*:\s*(\d+)') { return [pscustomobject]$result }
    $blocks = [uint64]$Matches[1]
    if ($Text -notmatch 'static -> JIT\s*:\s*(\d+) \((\d+) lookup miss, (\d+) unimplemented opcode\)') {
        return [pscustomobject]$result
    }
    $jit = [uint64]$Matches[1]
    $miss = [uint64]$Matches[2]
    $unhandled = [uint64]$Matches[3]
    if ([decimal]$jit -ne ([decimal]$miss + [decimal]$unhandled) -or
        $Text -notmatch 'unresolved import traps\s*:\s*(\d+)') {
        return [pscustomobject]$result
    }
    $result.report_complete = $true
    $result.static_blocks = $blocks
    $result.jit_transitions = $jit
    $result.lookup_misses = $miss
    $result.unhandled_opcodes = $unhandled
    $result.unresolved_import_traps = [uint64]$Matches[1]
    [pscustomobject]$result
}
