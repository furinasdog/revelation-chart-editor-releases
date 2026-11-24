param(
    [Parameter(Mandatory)][string]$Archive,
    [Parameter(Mandatory)][version]$Version,
    [Parameter(Mandatory)][string]$KeyFile,
    [Parameter(Mandatory)][string]$OutputDirectory,
    [version]$FromVersion,
    [string]$PatchTag
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$out = (New-Item -ItemType Directory -Force $OutputDirectory).FullName
$manifests = (New-Item -ItemType Directory -Force (Join-Path $PSScriptRoot 'manifests')).FullName
$crypto = [Security.Cryptography.RSA]::Create()
try {
    $plain = [Security.Cryptography.ProtectedData]::Unprotect([IO.File]::ReadAllBytes((Resolve-Path $KeyFile)), $null, 'CurrentUser')
    try { $crypto.FromXmlString([Text.Encoding]::UTF8.GetString($plain)) } finally { [Array]::Clear($plain) }
    if ($crypto.ToXmlString($false) -cne [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'publisher.xml'))) { throw 'Publisher key mismatch' }
    $old = @{}
    $patches = @()
    $delta = $null
    if ($FromVersion) {
        if ($PatchTag -notmatch '^(hub-)?v\d+\.\d+\.\d+$') { throw 'Invalid release tag' }
        $envelope = Get-Content -Raw -LiteralPath "$manifests/editor-v$FromVersion.signed.json" | ConvertFrom-Json
        $bytes = [Convert]::FromBase64String($envelope.payload)
        if (!$crypto.VerifyData($bytes,[Convert]::FromBase64String($envelope.signature),'SHA256',[Security.Cryptography.RSASignaturePadding]::Pkcs1)) {throw 'Invalid base manifest'}
        $previous = [Text.Encoding]::UTF8.GetString($bytes) | ConvertFrom-Json
        if ($previous.version -ne $FromVersion.ToString() -or $previous.product -ne 'editor-files') {throw 'Unexpected base manifest'}
        foreach ($f in $previous.files) { $old[$f.path]=$f.sha256 }
        $name="Revelation-Editor-v$FromVersion-to-v$Version.zip"
        $patchPath=Join-Path $out $name
        $delta=[IO.Compression.ZipFile]::Open($patchPath,'Create')
    }
    $package=Get-Item -LiteralPath $Archive
    $zip=[IO.Compression.ZipFile]::OpenRead($package.FullName)
    try {
        $files=@(foreach ($e in $zip.Entries) {
            if (!$e.Name) {continue}
            $stream=$e.Open()
            try { $hash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($stream)).ToLowerInvariant() } finally {$stream.Dispose()}
            if ($delta -and $old[$e.FullName] -ne $hash) {
                $part=$delta.CreateEntry($e.FullName,'Optimal').Open()
                $stream=$e.Open()
                try { $stream.CopyTo($part) } finally {$stream.Dispose();$part.Dispose()}
            }
            [ordered]@{path=$e.FullName;size=$e.Length;sha256=$hash}
        })
    } finally {$zip.Dispose();if ($delta) {$delta.Dispose()}}
    if ($FromVersion) {
        $patches=@(@{from=$FromVersion.ToString();tag=$PatchTag;size=(Get-Item $patchPath).Length;sha256=(Get-FileHash $patchPath).Hash.ToLowerInvariant()})
    }
    $index=@{schema=1;product='editor-files';version=$Version.ToString();archive=(Get-FileHash $package).Hash.ToLowerInvariant();files=$files;patches=$patches}
    $payload=[Text.Encoding]::UTF8.GetBytes(($index | ConvertTo-Json -Compress -Depth 7))
    $signature=$crypto.SignData($payload,'SHA256',[Security.Cryptography.RSASignaturePadding]::Pkcs1)
    $json=@{payload=[Convert]::ToBase64String($payload);signature=[Convert]::ToBase64String($signature)} | ConvertTo-Json -Compress
    [IO.File]::WriteAllText("$manifests/editor-v$Version.signed.json",$json)
    Write-Output "$Version · $($files.Count) files"
} finally {$crypto.Dispose()}
