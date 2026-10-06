function ConvertTo-ZarvotProfileConfig {
    param([string]$Text, [string]$SourceRoot, [string]$DestinationRoot)
    foreach ($match in [regex]::Matches($Text,
        '(?m)^(?:nand_directory|save_directory|sdmc_directory|load_directory|dump_directory|tas_directory)=([^\r\n]*)')) {
        $storage = $match.Groups[1].Value.Trim('"').Replace('\\', '\').Replace('/', '\')
        # Native default flags can leave these empty; the portable defaults are local.
        if ([string]::IsNullOrWhiteSpace($storage)) { continue }
        $resolved = [IO.Path]::GetFullPath($storage)
        if (-not $resolved.StartsWith($SourceRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
            throw 'Source config points outside its isolated test profile'
        }
    }
    $Text.Replace($SourceRoot.Replace('\', '\\'), $DestinationRoot.Replace('\', '\\')).
        Replace($SourceRoot.Replace('\', '/'), $DestinationRoot.Replace('\', '/')).Replace($SourceRoot, $DestinationRoot)
}
