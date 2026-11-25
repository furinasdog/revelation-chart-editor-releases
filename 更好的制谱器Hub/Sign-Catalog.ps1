param(
    [Parameter(Mandatory)][string]$Archive,
    [Parameter(Mandatory)][version]$Version,
    [Parameter(Mandatory)][string]$KeyFile,
    [Parameter(Mandatory)][string]$Notes,
    [ValidateSet('editor','hub','cuda')][string]$Product='editor',
    [string]$DescriptorDirectory
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Security
$utf8 = New-Object System.Text.UTF8Encoding($false)
$publicPath = Join-Path $PSScriptRoot 'publisher.xml'
$isHub = $Product -eq 'hub'
$catalogPath = Join-Path $PSScriptRoot $(if ($isHub) { 'hub-update.signed.json' } else { 'catalog.signed.json' })
$source = Get-Item -LiteralPath $Archive
$expected = if ($isHub) { "Revelation-Hub-v$Version-x64.msi" } else { "Revelation-Editor-v$Version-Windows-x64.zip" }
if ($Product -eq 'cuda') {
    if (-not $DescriptorDirectory) { throw 'Specify the staged editor directory for its CUDA descriptor.' }
    $catalogPath = Join-Path $DescriptorDirectory 'cuda-addon.signed.json'
    $expected = "Revelation-Editor-v$Version-CUDA-Windows-x64.zip"
}
if ($source.Name -cne $expected) { throw 'Unexpected asset name' }
$crypto = New-Object Security.Cryptography.RSACryptoServiceProvider(3072)
$crypto.PersistKeyInCsp = $false
try {
    if (Test-Path -LiteralPath $KeyFile) {
        $plain = [Security.Cryptography.ProtectedData]::Unprotect([IO.File]::ReadAllBytes($KeyFile),$null,'CurrentUser')
        $crypto.FromXmlString($utf8.GetString($plain))
        [Array]::Clear($plain,0,$plain.Length)
    } elseif (Test-Path -LiteralPath $publicPath) { throw 'The original signing key is required' }
    else {
        $plain = $utf8.GetBytes($crypto.ToXmlString($true))
        $sealed = [Security.Cryptography.ProtectedData]::Protect($plain,$null,'CurrentUser')
        [Array]::Clear($plain,0,$plain.Length)
        [IO.File]::WriteAllBytes($KeyFile,$sealed)
    }
    $public = $crypto.ToXmlString($false)
    if ((Test-Path -LiteralPath $publicPath) -and [IO.File]::ReadAllText($publicPath) -cne $public) { throw 'Publisher key mismatch' }
    $records = @()
    if ($Product -ne 'cuda' -and (Test-Path -LiteralPath $catalogPath)) {
        $old = [IO.File]::ReadAllText($catalogPath) | ConvertFrom-Json
        $bytes = [Convert]::FromBase64String($old.payload)
        if (!$crypto.VerifyData($bytes,'SHA256',[Convert]::FromBase64String($old.signature))) { throw 'Invalid existing catalog' }
        $records = @(($utf8.GetString($bytes) | ConvertFrom-Json).releases | Where-Object { $_.version -ne $Version.ToString() })
    }
    $record = [ordered]@{version=$Version.ToString(); size=$source.Length; sha256=(Get-FileHash -LiteralPath $source.FullName).Hash.ToLowerInvariant(); notes=$Notes; date=[DateTime]::UtcNow.ToString('yyyy-MM-dd')}
    $payload = $utf8.GetBytes((ConvertTo-Json -InputObject @{schema=1;product=$Product;releases=@($record)+$records} -Depth 5 -Compress))
    $sig = $crypto.SignData($payload,'SHA256')
    [IO.File]::WriteAllText($publicPath,$public,$utf8)
    [IO.File]::WriteAllText($catalogPath,(ConvertTo-Json -InputObject @{payload=[Convert]::ToBase64String($payload); signature=[Convert]::ToBase64String($sig)} -Compress),$utf8)
} finally { $crypto.Dispose() }
