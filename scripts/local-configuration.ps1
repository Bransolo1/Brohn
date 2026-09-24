# Shared, data-only installation configuration. Sourcing this file starts nothing.
function Resolve-BrohnConfiguredPath {
    param([object]$Value, [string]$Base, [string]$Kind, [string]$Label)
    if ($Value -isnot [string] -or [string]::IsNullOrWhiteSpace($Value) -or $Value.IndexOf([char]0) -ge 0) {
        throw "The local configuration needs a valid $Label path."
    }
    $resolved = if ([IO.Path]::IsPathRooted($Value)) { [IO.Path]::GetFullPath($Value) } else { [IO.Path]::GetFullPath((Join-Path $Base $Value)) }
    if ($Kind -and -not (Test-Path -LiteralPath $resolved -PathType $Kind)) { throw "The configured $Label was not found: $resolved" }
    return $resolved
}

function Read-BrohnLocalConfiguration {
    param([Parameter(Mandatory = $true)][string]$Path)
    $file = Get-Item -LiteralPath $Path -ErrorAction Stop
    if ($file.PSIsContainer -or $file.Length -gt 1048576) { throw 'Choose a local installation JSON file smaller than 1 MiB.' }
    $value = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
    $required = @('schema','rscript','r_library','publication_python','publication_manifest','portability_python','workspace','ports','scientific')
    $keys = @($value.PSObject.Properties.Name)
    if (@($required | Where-Object { $_ -notin $keys }).Count -or @($keys | Where-Object { $_ -notin ($required + @('checked_at','assets')) }).Count -or
        $value.schema -cne 'brohn-local-installation/1.0') { throw 'Unsupported or incomplete Brohn installation configuration.' }
    $base = $file.DirectoryName
    $resolved = [ordered]@{}
    foreach ($entry in @(@('rscript','Leaf'),@('r_library','Container'),@('publication_python','Leaf'),@('publication_manifest','Leaf'),@('portability_python','Leaf'),@('workspace',''))) {
        $resolved[$entry[0]] = Resolve-BrohnConfiguredPath $value.($entry[0]) $base $entry[1] $entry[0]
    }
    $portKeys = @($value.ports.PSObject.Properties.Name)
    if ($portKeys.Count -ne 2 -or 'researcher' -notin $portKeys -or 'participant' -notin $portKeys) { throw 'Configure exactly the researcher and participant ports.' }
    foreach ($key in @('researcher','participant')) {
        $number = $value.ports.$key
        if (($number -isnot [int] -and $number -isnot [long]) -or $number -lt 1024 -or $number -gt 65535) { throw 'Configured ports must be whole numbers between 1024 and 65535.' }
    }
    if ($value.ports.researcher -eq $value.ports.participant) { throw 'Researcher and participant ports must be distinct.' }
    if ($value.scientific -isnot [pscustomobject]) { throw 'Scientific profiles must be a JSON object of named executable paths.' }
    $profiles = @{}
    foreach ($property in $value.scientific.PSObject.Properties) {
        if ($property.Name -cnotin @('methods','acquisition','vision-audio','segmentation','facial-au')) { throw "Unknown scientific profile: $($property.Name)" }
        $profiles[$property.Name] = Resolve-BrohnConfiguredPath $property.Value $base 'Leaf' $property.Name
    }
    $assets = @{}
    if ('assets' -in $keys) {
        if ($value.assets -isnot [pscustomobject]) { throw 'Runtime assets must be a JSON object of named directory paths.' }
        foreach ($property in $value.assets.PSObject.Properties) {
            if ($property.Name -cnotin @('facial_models','facial_ffmpeg')) { throw "Unknown runtime asset: $($property.Name)" }
            $assets[$property.Name] = Resolve-BrohnConfiguredPath $property.Value $base 'Container' $property.Name
        }
    }
    if ($profiles.ContainsKey('facial-au') -and (-not $assets.ContainsKey('facial_models') -or -not $assets.ContainsKey('facial_ffmpeg'))) {
        throw 'The facial-au profile needs both facial_models and facial_ffmpeg directories in this configuration.'
    }
    $resolved['assets'] = $assets
    $resolved['ports'] = $value.ports
    $resolved['scientific'] = $profiles
    $resolved['configuration_path'] = $file.FullName
    return [pscustomobject]$resolved
}

function Get-BrohnConfiguredEnvironment {
    param([Parameter(Mandatory = $true)]$Configuration)
    $values = @{
        BROHN_PUBLICATION_PYTHON = $Configuration.publication_python
        BROHN_PUBLICATION_NATIVE_MANIFEST = $Configuration.publication_manifest
        BROHN_PYTHON = $Configuration.portability_python
    }
    foreach ($profile in $Configuration.scientific.Keys) {
        $values['BROHN_PYTHON_' + $profile.ToUpperInvariant().Replace('-','_')] = $Configuration.scientific[$profile]
    }
    $assetEnvironment = @{facial_models='BROHN_FACIAL_MODEL_DIR';facial_ffmpeg='BROHN_FACIAL_FFMPEG_DIR'}
    if ($Configuration.assets) {
        foreach ($asset in $Configuration.assets.Keys) { $values[$assetEnvironment[$asset]] = $Configuration.assets[$asset] }
    }
    return $values
}
