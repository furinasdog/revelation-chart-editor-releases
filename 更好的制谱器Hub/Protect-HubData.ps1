#Requires -Version 7.4
param([Parameter(Mandatory)][string]$OutputDirectory)

$ErrorActionPreference = 'Stop'
$folder = (Resolve-Path -LiteralPath $OutputDirectory).Path
$buffer = [IO.MemoryStream]::new()
$zip = [IO.Compression.ZipArchive]::new($buffer, [IO.Compression.ZipArchiveMode]::Create, $true)
try {
    foreach ($row in [IO.File]::ReadLines((Join-Path $folder 'hub-data-files.txt'))) {
        $name, $path = $row.Split('|', 2)
        $entry = $zip.CreateEntry($name, [IO.Compression.CompressionLevel]::Optimal)
        $dest = $entry.Open()
        $source = [IO.File]::OpenRead($path)
        try { $source.CopyTo($dest) } finally { $source.Dispose(); $dest.Dispose() }
    }
} finally { $zip.Dispose() }

$plain = $buffer.ToArray()
$buffer.Dispose()
$key = [Security.Cryptography.RandomNumberGenerator]::GetBytes(32)
$nonce = [Security.Cryptography.RandomNumberGenerator]::GetBytes(12)
$tag = [byte[]]::new(16)
$cipher = [byte[]]::new($plain.Length)
$aes = [Security.Cryptography.AesGcm]::new($key, $tag.Length)
try {
    $aes.Encrypt($nonce, $plain, $cipher, $tag)
    [IO.File]::WriteAllBytes((Join-Path $folder 'hub-data.bin'), [byte[]]($nonce + $tag + $cipher))
    [IO.File]::WriteAllBytes((Join-Path $folder 'hub-data.key'), $key)
} finally {
    $aes.Dispose()
    [Array]::Clear($key)
    [Array]::Clear($plain)
}
