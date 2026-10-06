$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'scripts\zarvot-profile.ps1')
$sourceRoot = 'C:\fixture\before'
$destinationRoot = 'C:\fixture\after'
$text = @'
[Data%20Storage]
nand_directory=C:/fixture/before/user/nand
save_directory=C:\\fixture\\before\\user\\nand
dump_directory=
dump_directory\default=true
[Controls]
tas_enable=false
'@
$result = ConvertTo-ZarvotProfileConfig $text $sourceRoot $destinationRoot
if ($result.Contains('before') -or -not $result.Contains('C:/fixture/after/user/nand') -or
    -not $result.Contains('C:\\fixture\\after\\user\\nand') -or -not $result.Contains('tas_enable=false')) {
    throw 'Profile rebasing changed unrelated controls or retained source storage'
}
$rejected = $false
try { ConvertTo-ZarvotProfileConfig 'nand_directory=C:/fixture/outside' $sourceRoot $destinationRoot | Out-Null }
catch { $rejected = $true }
if (-not $rejected) { throw 'Foreign storage was accepted' }
'Profile rebasing checks passed'
