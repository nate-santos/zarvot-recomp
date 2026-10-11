# Run the real launcher with tiny synthetic files and StageOnly. Never starts a game.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$fixtureBase = Join-Path $root ('build\launcher-tests\' + [Guid]::NewGuid().ToString('N'))
$global:ZarvotLaunchTestProcesses = @()
$script:checks = 0
function Get-Process {
    [CmdletBinding()]
    param([string[]]$Name, [int]$Id)
    if ($PSBoundParameters.ContainsKey('Id')) {
        $global:ZarvotLaunchTestProcesses | Where-Object Id -eq $Id
    } else { $global:ZarvotLaunchTestProcesses }
}
function Start-Process { throw 'The staging tests must never start a process' }
function Write-Json($Path, $Value) {
    [IO.Directory]::CreateDirectory((Split-Path -Parent $Path)) | Out-Null
    [IO.File]::WriteAllText($Path, ($Value | ConvertTo-Json -Depth 10), [Text.UTF8Encoding]::new($false))
}
function Hash($Path) { (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() }
function New-Fixture {
    $base = Join-Path $fixtureBase ([Guid]::NewGuid().ToString('N').Substring(0,8))
    [IO.Directory]::CreateDirectory((Join-Path $base 'scripts')) | Out-Null
    foreach ($name in @('start-zarvot-recomp.ps1','zarvot-profile.ps1')) {
        Copy-Item -LiteralPath (Join-Path $root "scripts\$name") -Destination (Join-Path $base 'scripts')
    }
    $rom = Join-Path $base 'zarvot.fixture'
    [IO.File]::WriteAllText($rom, 'synthetic test; no game data')
    $modules = @()
    $index = 0
    foreach ($name in @('rtld','sdk','subsdk0','main')) {
        ++$index
        $modules += [ordered]@{
            name=$name; build_id=('{0:x64}' -f $index)
            text_vaddr=0; text_size=(4096*$index); rodata_vaddr=(4096*$index)
            rodata_size=512; data_vaddr=(4096*$index+512); data_size=128
        }
    }
    $manifest = [ordered]@{
        version=2; image_abi=6; image_features=7; source_exefs_sha256=('a'*64)
        total_modules=4; total_blocks_analyzed=1; modules=$modules
    }
    $baselineManifest = Join-Path $base 'generated\zarvot\out\Zarvot - Hybrid AOT + JIT\aot_cache\aot_manifest.json'
    Write-Json $baselineManifest $manifest
    $candidateManifest = Join-Path $base 'generated\zarvot-fp32-outline\out\candidate\aot_cache\aot_manifest.json'
    $manifest.total_blocks_analyzed = 2 # changed generated build, same guest game
    Write-Json $candidateManifest $manifest
    foreach ($target in @('zarvot','zarvot-fp32-outline')) {
        $built = @()
        foreach ($name in @('rtld','sdk','subsdk0','main')) {
            $imageName = if ($name -eq 'main') { 'recompiled_image.dll' } else { "recompiled_$name.dll" }
            $image = Join-Path $base "build\recomp\$target\$name\$imageName"
            [IO.Directory]::CreateDirectory((Split-Path -Parent $image)) | Out-Null
            [IO.File]::WriteAllText($image, "synthetic $target $name")
            $built += [ordered]@{name=$name; state='complete'; bytes=(Get-Item $image).Length; sha256=(Hash $image)}
        }
        $selectedManifest = if ($target -eq 'zarvot') { $baselineManifest } else { $candidateManifest }
        Write-Json (Join-Path $base "build\recomp\$target\build-status.json") ([ordered]@{
            target=$target; state='complete'; image_abi=6; image_features=7
            export_manifest_sha256=(Hash $selectedManifest); modules=$built
        })
    }
    $previous = Join-Path $base 'build\zarvot-runs\baseline-run'
    $fixtureHost = Join-Path $base 'build\suyu\bin'
    foreach ($hostDir in @($previous,$fixtureHost)) {
        [IO.Directory]::CreateDirectory((Join-Path $hostDir 'user\keys')) | Out-Null
        [IO.File]::WriteAllText((Join-Path $hostDir 'suyu-cmd.exe'), "synthetic host $hostDir")
        [IO.File]::WriteAllText((Join-Path $hostDir 'host-dependency.dll'), 'synthetic dependency')
        [IO.File]::WriteAllText((Join-Path $hostDir 'user\keys\prod.keys'), 'synthetic key fixture')
    }
    foreach ($dir in @('config','nand','cache')) {
        [IO.Directory]::CreateDirectory((Join-Path $previous "user\$dir")) | Out-Null
    }
    $save = Join-Path $previous 'user\nand\save.fixture'
    [IO.File]::WriteAllText($save, 'synthetic saved progress')
    [IO.File]::WriteAllText((Join-Path $previous 'user\cache\cache.fixture'), 'synthetic cache')
    $config = "[Core]`nuse_speed_limit=true`nspeed_limit=100`n[Controls]`ntas_enable=false`n[Data%20Storage]`nnand_directory=" +
        ($previous.Replace('\','/') + "/user/nand`nsave_directory=" + $previous.Replace('\','/') + '/user/nand')
    [IO.File]::WriteAllText((Join-Path $previous 'user\config\sdl-config.ini'), $config)
    Copy-Item -LiteralPath $baselineManifest -Destination (Join-Path $previous 'aot_manifest.json')
    $baselineBuild = Get-Content (Join-Path $base 'build\recomp\zarvot\build-status.json') -Raw | ConvertFrom-Json
    Write-Json (Join-Path $previous 'launch.json') ([ordered]@{
        state='started'; run_root=$previous; pid=123456; process_started_utc='2026-10-01T01:00:00Z'
        host_sha256=(Hash (Join-Path $previous 'suyu-cmd.exe')); image_abi=6; image_features=7
        export_manifest_sha256=(Hash $baselineManifest); modules=$baselineBuild.modules
    })
    $global:ZarvotLaunchTestProcesses = @()
    [pscustomobject]@{Root=$base; Rom=$rom; Previous=$previous; Host=$fixtureHost; Save=$save
        CandidateManifest=$candidateManifest; BaselineManifest=$baselineManifest}
}
function Invoke-Fixture($Fixture, [hashtable]$Options) {
    $parameters = @{Rom=$Fixture.Rom; StageOnly=$true}
    foreach ($key in $Options.Keys) { $parameters[$key] = $Options[$key] }
    & (Join-Path $Fixture.Root 'scripts\start-zarvot-recomp.ps1') @parameters
}
function Candidate-Options($Fixture) {
    @{Target='zarvot-fp32-outline'; Package='out\candidate'; ProfileFromRun=$Fixture.Previous; AllowSameGameProfileReuse=$true}
}
function Save-CandidateManifest($Fixture, $Manifest) {
    Write-Json $Fixture.CandidateManifest $Manifest
    $path = Join-Path $Fixture.Root 'build\recomp\zarvot-fp32-outline\build-status.json'
    $build = Get-Content $path -Raw | ConvertFrom-Json
    $build.export_manifest_sha256 = Hash $Fixture.CandidateManifest
    Write-Json $path $build
}
function Reject($Name, [scriptblock]$Action, $Message) {
    $rejected = $false
    try { & $Action | Out-Null }
    catch {
        if ($_.Exception.Message -notmatch $Message) { throw "$Name rejected unexpectedly: $($_.Exception.Message)" }
        $rejected = $true
    }
    if (-not $rejected) { throw "Accepted invalid case: $Name" }
    ++$script:checks
}
try {
    $fixture = New-Fixture
    $before = Hash $fixture.Save
    $oldConfig = [IO.File]::ReadAllText((Join-Path $fixture.Previous 'user\config\sdl-config.ini'))
    $same = Invoke-Fixture $fixture @{HostRoot=$fixture.Previous; ProfileFromRun=$fixture.Previous}
    $record = Get-Content (Join-Path $same.RunRoot 'launch.json') -Raw | ConvertFrom-Json
    if ($same.State -ne 'staged' -or $record.profile_reuse_mode -ne 'same-build' -or
        $record.host_sha256 -ne (Hash (Join-Path $fixture.Previous 'suyu-cmd.exe'))) {
        throw 'An explicit baseline host/profile was not staged with its strict identities'
    }
    ++$script:checks

    $candidate = Invoke-Fixture $fixture (Candidate-Options $fixture)
    $record = Get-Content (Join-Path $candidate.RunRoot 'launch.json') -Raw | ConvertFrom-Json
    $clonedSave = Join-Path $candidate.RunRoot 'user\nand\save.fixture'
    $newConfig = [IO.File]::ReadAllText((Join-Path $candidate.RunRoot 'user\config\sdl-config.ini'))
    if ($record.target -ne 'zarvot-fp32-outline' -or $record.package -ne 'out\candidate' -or
        $record.profile_reuse_mode -ne 'same-game-cross-build' -or
        $record.export_manifest_sha256 -ne (Hash $fixture.CandidateManifest) -or
        $record.profile_source_manifest_sha256 -ne (Hash $fixture.BaselineManifest) -or
        $record.host_sha256 -ne (Hash (Join-Path $fixture.Host 'suyu-cmd.exe')) -or
        (Hash $clonedSave) -ne $before -or $newConfig.Contains($fixture.Previous.Replace('\','/')) -or
        -not $newConfig.Contains($candidate.RunRoot.Replace('\','/')) -or
        -not $newConfig.Contains('speed_limit=100') -or -not $newConfig.Contains('tas_enable=false')) {
        throw 'Candidate selection or isolated save/config copying failed'
    }
    [IO.File]::AppendAllText($clonedSave, ' changed only in clone')
    if ((Hash $fixture.Save) -ne $before -or
        [IO.File]::ReadAllText((Join-Path $fixture.Previous 'user\config\sdl-config.ini')) -ne $oldConfig) {
        throw 'Staging or changing the clone modified the source saved profile'
    }
    foreach ($module in $record.modules) {
        $name = if ($module.name -eq 'main') { 'recompiled_image.dll' } else { "recompiled_$($module.name).dll" }
        if ((Hash (Join-Path $candidate.RunRoot $name)) -ne $module.sha256) { throw 'Staged mixed compiled images' }
    }
    ++$script:checks

    $options = Candidate-Options $fixture
    $options.Remove('AllowSameGameProfileReuse')
    Reject 'default cross-build reuse' { Invoke-Fixture $fixture $options } 'runtime/export identity'
    Reject 'default changed host' { Invoke-Fixture $fixture @{ProfileFromRun=$fixture.Previous} } 'runtime/export identity'
    $fixture = New-Fixture
    $manifest = Get-Content $fixture.BaselineManifest -Raw | ConvertFrom-Json
    Save-CandidateManifest $fixture $manifest
    Reject 'default changed compiled DLLs' {
        Invoke-Fixture $fixture @{Target='zarvot-fp32-outline'; Package='out\candidate'; HostRoot=$fixture.Previous; ProfileFromRun=$fixture.Previous}
    } 'different compiled module set'

    foreach ($field in @('source_exefs_sha256','build_id','text_vaddr','text_size','rodata_vaddr','rodata_size','data_vaddr','data_size')) {
        $fixture = New-Fixture
        $manifest = Get-Content $fixture.CandidateManifest -Raw | ConvertFrom-Json
        if ($field -eq 'source_exefs_sha256') { $manifest.source_exefs_sha256 = 'b'*64 }
        elseif ($field -eq 'build_id') { $manifest.modules[0].build_id = 'b'*64 }
        else { $manifest.modules[0].$field++ }
        Save-CandidateManifest $fixture $manifest
        Reject "different guest $field" { Invoke-Fixture $fixture (Candidate-Options $fixture) } 'Cross-build profile reuse'
    }
    foreach ($field in @('source_exefs_sha256','text_size')) {
        $fixture = New-Fixture
        $manifest = Get-Content $fixture.CandidateManifest -Raw | ConvertFrom-Json
        if ($field -eq 'source_exefs_sha256') { $manifest.PSObject.Properties.Remove($field) }
        else { $manifest.modules[0].PSObject.Properties.Remove($field) }
        Save-CandidateManifest $fixture $manifest
        Reject "missing guest $field" { Invoke-Fixture $fixture (Candidate-Options $fixture) } 'Cross-build profile reuse'
    }
    $fixture = New-Fixture
    [IO.File]::AppendAllText((Join-Path $fixture.Previous 'aot_manifest.json'), ' ')
    Reject 'tampered source manifest' { Invoke-Fixture $fixture (Candidate-Options $fixture) } 'manifest does not match'
    $fixture = New-Fixture
    $path = Join-Path $fixture.Previous 'launch.json'
    $launch = Get-Content $path -Raw | ConvertFrom-Json
    $launch.image_features = 0
    Write-Json $path $launch
    Reject 'source feature mismatch' { Invoke-Fixture $fixture (Candidate-Options $fixture) } 'feature identity'
    $fixture = New-Fixture
    $global:ZarvotLaunchTestProcesses = @([pscustomobject]@{
        Id=123456; Path=(Join-Path $fixture.Previous 'suyu-cmd.exe'); StartTime=([DateTime]'2026-10-01T01:00:00Z')
    })
    Reject 'active source PID' { Invoke-Fixture $fixture (Candidate-Options $fixture) } 'Close the source test session'
    $global:ZarvotLaunchTestProcesses[0].Id = 123457
    Reject 'manually restarted source profile' { Invoke-Fixture $fixture (Candidate-Options $fixture) } 'Close the source test session'
    $global:ZarvotLaunchTestProcesses = @([pscustomobject]@{
        Id=123456; Path=(Join-Path $fixture.Host 'unrelated.exe'); StartTime=([DateTime]'2026-10-02T01:00:00Z')
    })
    Invoke-Fixture $fixture (Candidate-Options $fixture) | Out-Null
    ++$script:checks # a reused PID with a different lifetime cannot make the old run live
    $fixture = New-Fixture
    $path = Join-Path $fixture.Previous 'launch.json'
    $launch = Get-Content $path -Raw | ConvertFrom-Json
    $launch.PSObject.Properties.Remove('process_started_utc')
    Write-Json $path $launch
    Reject 'missing source process identity' { Invoke-Fixture $fixture (Candidate-Options $fixture) } 'recorded process identity'
    $fixture = New-Fixture
    Reject 'package traversal' { Invoke-Fixture $fixture @{Package='..\..\other'} } 'Package resolved outside'
    Reject 'target traversal' { Invoke-Fixture $fixture @{Target='..\other'} } 'Target'
    Reject 'foreign host root' { Invoke-Fixture $fixture @{HostRoot=$fixtureBase} } 'HostRoot must stay'
    Reject 'unscoped reuse flag' { Invoke-Fixture $fixture @{AllowSameGameProfileReuse=$true} } 'explicit ProfileFromRun'
    [IO.File]::WriteAllText((Join-Path $fixture.Previous 'user\config\sdl-config.ini'), 'nand_directory=C:/outside-profile')
    Reject 'foreign profile storage' { Invoke-Fixture $fixture (Candidate-Options $fixture) } 'outside its isolated test profile'
    $fixture = New-Fixture
    [IO.File]::AppendAllText((Join-Path $fixture.Root 'build\recomp\zarvot-fp32-outline\main\recompiled_image.dll'), ' tampered')
    Reject 'selected DLL identity' { Invoke-Fixture $fixture (Candidate-Options $fixture) } 'Compiled image identity'
    "Launcher staging/isolation and identity rejection checks passed: $script:checks"
} finally {
    Remove-Variable -Scope Global -Name ZarvotLaunchTestProcesses -ErrorAction SilentlyContinue
}
