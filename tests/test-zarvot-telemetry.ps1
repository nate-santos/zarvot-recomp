# Synthetic fixtures only: protect the distinction between absence and zero.
$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'scripts\zarvot-telemetry.ps1')
function Assert-Equal($Actual, $Expected, $Name) {
    if ($Actual -ne $Expected) { throw "$Name expected '$Expected', got '$Actual'" }
}
$title = ConvertFrom-ZarvotWindowTitle 'Fixture | suyu Hybrid JIT + AOT | 6.2 FPS (160.0 ms) | Building 6 shaders | JIT transitions: 0 | F12 Controls'
Assert-Equal $title.jit_transitions 0 'Separate shader count from JIT count'
Assert-Equal $title.shaders_building 6 'Shader count'
Assert-Equal $title.fps 6.2 'FPS'
$title = ConvertFrom-ZarvotWindowTitle 'Fixture | suyu Hybrid JIT + AOT | JIT transitions: 6 | F12 Controls'
Assert-Equal $title.jit_transitions 6 'Nonzero UI transition'
$title = ConvertFrom-ZarvotWindowTitle 'Fixture | Building 6 shaders | F12 Controls'
Assert-Equal $title.jit_transitions $null 'Missing UI count stays unknown'
$text = @'
=== RECOMP EXECUTION COVERAGE ===
  static blocks executed : 9007199254741009
  static -> JIT          : 6 (4 lookup miss, 2 unimplemented opcode)
  unresolved import traps: 1
=== END RECOMP EXECUTION COVERAGE ===
'@
$coverage = ConvertFrom-ZarvotCoverage $text
Assert-Equal $coverage.report_complete $true 'Complete report'
Assert-Equal $coverage.static_blocks ([uint64]'9007199254741009') 'Counter precision'
Assert-Equal $coverage.jit_transitions 6 'File count'
Assert-Equal $coverage.lookup_misses 4 'Miss count'
Assert-Equal $coverage.unhandled_opcodes 2 'Opcode count'
Assert-Equal $coverage.unresolved_import_traps 1 'Import count'
foreach ($partial in @('', $text.Replace('=== END RECOMP EXECUTION COVERAGE ===', ''),
                       ($text + "`n" + $text),
                       $text.Replace('  unresolved import traps: 1', ''),
                       $text.Replace('6 (4 lookup miss', '7 (4 lookup miss'))) {
    $coverage = ConvertFrom-ZarvotCoverage $partial
    Assert-Equal $coverage.report_complete $false 'Absent/torn/inconsistent report'
    Assert-Equal $coverage.jit_transitions $null 'Incomplete count stays unknown'
}
'Telemetry parser checks passed'
