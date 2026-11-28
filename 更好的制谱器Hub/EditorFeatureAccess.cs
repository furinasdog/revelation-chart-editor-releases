using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace RevelationHub;

internal static class EditorFeatureAccess
{
    private const string Prefix = "REV-UNLOCK-1.";

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
        string path = Path.Combine(editorProfile, "official_access.json");
        try
        {
            if (!File.Exists(path) || new FileInfo(path).Length > 4096) return false;
            using var receipt = JsonDocument.Parse(File.ReadAllBytes(path));
            if (receipt.RootElement.ValueKind != JsonValueKind.Object ||
                !receipt.RootElement.TryGetProperty("agreement", out var agreement) || agreement.ValueKind != JsonValueKind.String ||
                !receipt.RootElement.TryGetProperty("unlock", out var unlock) || unlock.ValueKind != JsonValueKind.String)
                return false;
            string terms = StartupAgreements.Read("RevelationHub.license.user");
            if (!string.Equals(agreement.GetString(), Digest(terms), StringComparison.Ordinal)) return false;
            string token = unlock.GetString();
            if (token == null || token.Length != Prefix.Length + 512 || !token.StartsWith(Prefix, StringComparison.Ordinal) ||
                !GetCurrentHwProfile(out var hardware) || string.IsNullOrWhiteSpace(hardware.Guid))
                return false;
            byte[] signature = Convert.FromBase64String(token[Prefix.Length..]);
            if (signature.Length != 384) return false;
            string machine = "rev1-" + Digest("revelation-machine-code/v1|" + hardware.Guid);
            using var verifier = RSA.Create();
            verifier.ImportFromPem(StartupAgreements.Read("RevelationHub.license.feature-public-key"));
            return verifier.VerifyData(Encoding.UTF8.GetBytes("revelation-feature-unlock/v1|agent+audio|" + machine),
                signature, HashAlgorithmName.SHA256, RSASignaturePadding.Pkcs1);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or InvalidDataException or JsonException or FormatException
            or CryptographicException or ArgumentException)
        {
            return false;
        }
    }

    private static string Digest(string value) => Convert.ToHexStringLower(SHA256.HashData(Encoding.UTF8.GetBytes(value)));
}
