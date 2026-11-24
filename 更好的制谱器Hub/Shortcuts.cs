using Microsoft.Win32;
using System;
using System.IO;
using System.Runtime.InteropServices;

namespace RevelationHub;

internal static class Shortcuts
{
    private const string Settings = @"Software\RevelationHub";
    private const string LinkName = "更好的制谱器 Hub.lnk";
    internal static string InstalledExecutable
    {
        get
        {
            using var key = Registry.CurrentUser.OpenSubKey(Settings);
            string directory = key?.GetValue("InstallDir") as string ??
                Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Programs", "RevelationHub");
            return Path.Combine(directory, "RevelationHub.exe");
        }
    }

    internal static void Set(bool? start, bool? desktop)
    {
        using var settings = Registry.CurrentUser.CreateSubKey(Settings);
        bool startMenu = start ?? (int)settings.GetValue("StartMenuShortcut", 1) != 0;
        bool desktopIcon = desktop ?? (int)settings.GetValue("DesktopShortcut", 0) != 0;
        string executable = Environment.ProcessPath;
        WriteLink(Environment.GetFolderPath(Environment.SpecialFolder.Programs), executable, startMenu);
        WriteLink(Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory), executable, desktopIcon);
        settings.SetValue("StartMenuShortcut", startMenu ? 1 : 0, RegistryValueKind.DWord);
        settings.SetValue("DesktopShortcut", desktopIcon ? 1 : 0, RegistryValueKind.DWord);
    }

    internal static void WriteLink(string directory, string executable, bool enabled)
    {
        string path = Path.Combine(directory, LinkName);
        if (!enabled && !File.Exists(path)) return;
        Directory.CreateDirectory(directory);
        dynamic shell = Activator.CreateInstance(Type.GetTypeFromProgID("WScript.Shell", true));
        try
        {
            dynamic link = shell.CreateShortcut(path);
            try
            {
                if (enabled)
                {
                    link.TargetPath = executable;
                    link.WorkingDirectory = Path.GetDirectoryName(executable);
                    link.IconLocation = executable + ",0";
                    link.Description = "更好的制谱器 Hub";
                    link.Save();
                }
                else if (string.Equals((string)link.TargetPath, executable, StringComparison.OrdinalIgnoreCase)) File.Delete(path);
            }
            finally { Marshal.FinalReleaseComObject(link); }
        }
        finally { Marshal.FinalReleaseComObject(shell); }
    }
}
