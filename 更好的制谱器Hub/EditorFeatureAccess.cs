using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace RevelationHub;

internal static class EditorFeatureAccess
{
    internal const string AgreementReceipt = "official_access.json";
    internal const string UnlockReceipt = "official_unlock_v2.json";
    private const string Prefix = "REV-UNLOCK-2.";

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Ansi)]
    private struct HardwareProfile
    {
        internal int DockInfo;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 39)] internal string Guid;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 80)] internal string Name;
    }

    // Match Godot's Windows OS.get_unique_id() when validating the editor receipt.
    [DllImport("advapi32.dll", EntryPoint = "GetCurrentHwProfileA", ExactSpelling = true, CharSet = CharSet.Ansi)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetCurrentHwProfile(out HardwareProfile profile);

    internal static bool Enabled(string editorProfile)
    {
        try
        {
            using var proof = ReadJson(Path.Combine(editorProfile, UnlockReceipt), 1024);
            if (proof?.RootElement.ValueKind != JsonValueKind.String) return false;
            string token = proof.RootElement.GetString();
            if (token == null || token.Length != Prefix.Length + 684 || !token.StartsWith(Prefix, StringComparison.Ordinal))
                return false;
            using var receipt = ReadJson(Path.Combine(editorProfile, AgreementReceipt), 4096);
            if (receipt?.RootElement.ValueKind != JsonValueKind.Object ||
                !receipt.RootElement.TryGetProperty("agreement", out var agreement) || agreement.ValueKind != JsonValueKind.String)
                return false;
            string terms = StartupAgreements.Read("RevelationHub.license.user");
            if (!string.Equals(agreement.GetString(), Digest(terms), StringComparison.Ordinal)) return false;
            if (!GetCurrentHwProfile(out var hardware) || string.IsNullOrWhiteSpace(hardware.Guid))
                return false;
            string encoded = token[Prefix.Length..];
            byte[] signature = Convert.FromBase64String(encoded);
            if (signature.Length != 512 || Convert.ToBase64String(signature) != encoded) return false;
            string machine = "rev1-" + Digest("revelation-machine-code/v1|" + hardware.Guid);
            using var verifier = RSA.Create();
            verifier.ImportFromPem(StartupAgreements.Read("RevelationHub.license.feature-public-key"));
            return verifier.KeySize == 4096 && verifier.VerifyData(Encoding.UTF8.GetBytes("revelation-feature-unlock/v2|agent+audio|" + machine),
                signature, HashAlgorithmName.SHA256, RSASignaturePadding.Pkcs1);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or InvalidDataException or JsonException or FormatException
            or CryptographicException or ArgumentException)
        {
            return false;
        }
    }

    private static JsonDocument ReadJson(string path, int limit)
    {
        using var stream = File.Open(path, FileMode.Open, FileAccess.Read, FileShare.Read | FileShare.Delete);
        long size = stream.Length;
        if (size <= 0 || size > limit) return null;
        var bytes = new byte[(int)size];
        stream.ReadExactly(bytes);
        return JsonDocument.Parse(bytes);
    }

    private static string Digest(string value) => Convert.ToHexStringLower(SHA256.HashData(Encoding.UTF8.GetBytes(value)));
}
