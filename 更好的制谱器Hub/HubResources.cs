using System;
using System.Collections.Generic;
using System.IO;
using System.IO.Compression;
using System.Security.Cryptography;

namespace RevelationHub;

internal static class HubResources
{
    private static readonly Lazy<Dictionary<string, byte[]>> Sealed = new(ReadSealed);

    internal static Stream Open(string name)
    {
        var plain = typeof(HubResources).Assembly.GetManifestResourceStream(name);
        if (plain != null) return plain;
        return Sealed.Value.TryGetValue(name, out var bytes) ? new MemoryStream(bytes, false) : null;
    }

    private static Dictionary<string, byte[]> ReadSealed()
    {
        var files = new Dictionary<string, byte[]>(StringComparer.Ordinal);
        var assembly = typeof(HubResources).Assembly;
        using var payload = assembly.GetManifestResourceStream("RevelationHub.protected-data");
        if (payload == null) return files;
        using var material = assembly.GetManifestResourceStream("RevelationHub.package-key")
            ?? throw new InvalidDataException("缺少内置资源密钥。");
        byte[] key = new byte[32];
        material.ReadExactly(key);
        byte[] encrypted = new byte[checked((int)payload.Length)];
        payload.ReadExactly(encrypted);
        if (encrypted.Length < 28) throw new InvalidDataException("内置资源包损坏。");
        byte[] clear = new byte[encrypted.Length - 28];
        try
        {
            using var aes = new AesGcm(key, 16);
            aes.Decrypt(encrypted.AsSpan(0, 12), encrypted.AsSpan(28), encrypted.AsSpan(12, 16), clear);
            using var archive = new ZipArchive(new MemoryStream(clear, false));
            foreach (var entry in archive.Entries)
            {
                using var stream = entry.Open();
                var data = new byte[checked((int)entry.Length)];
                stream.ReadExactly(data);
                files.Add(entry.FullName, data);
            }
            return files;
        }
        finally
        {
            CryptographicOperations.ZeroMemory(key);
            CryptographicOperations.ZeroMemory(clear);
        }
    }
}
