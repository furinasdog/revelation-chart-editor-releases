using System;
using System.Text.RegularExpressions;

namespace RevelationHub;

internal readonly record struct EditorVersion(Version Core, int? Beta) : IComparable<EditorVersion>
{
    private static readonly Regex Format = new(
        @"\A([0-9]{1,5}\.[0-9]{1,5}\.[0-9]{1,5})(?:-beta\.([1-9][0-9]{0,4}))?\z");

    internal static bool TryParse(string value, out EditorVersion version)
    {
        var match = Format.Match(value ?? "");
        version = default;
        if (!match.Success || !Version.TryParse(match.Groups[1].Value, out var core)) return false;
        var beta = match.Groups[2];
        version = new(core, beta.Success ? int.Parse(beta.Value) : null);
        return true;
    }

    internal static EditorVersion Parse(string value) => TryParse(value, out var version)
        ? version : throw new FormatException("制谱器版本号无效。");

    internal static bool IsBeta(string value) => TryParse(value, out var version) && version.Beta.HasValue;

    public int CompareTo(EditorVersion other)
    {
        int coreOrder = Core.CompareTo(other.Core);
        return coreOrder != 0 ? coreOrder : (Beta ?? int.MaxValue).CompareTo(other.Beta ?? int.MaxValue);
    }
}
