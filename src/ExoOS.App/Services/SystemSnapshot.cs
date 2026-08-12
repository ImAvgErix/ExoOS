using System.Management;
using System.Runtime.InteropServices;
using Microsoft.Win32;

namespace ExoOS.Services;

/// <summary>Inventory stats for the plan screen (CPU / GPU / RAM / OS label).</summary>
public static class SystemSnapshot
{
    public static object GetSpecs()
    {
        return new
        {
            cpu = ReadCpuName(),
            gpu = ReadGpuName(),
            ram = $"{GetTotalRamGb():0.#} GB"
        };
    }

    public static string GetOsLabel()
    {
        try
        {
            using var k = Registry.LocalMachine.OpenSubKey(@"SOFTWARE\Microsoft\Windows NT\CurrentVersion");
            var product = k?.GetValue("ProductName") as string ?? "Windows";
            var display = k?.GetValue("DisplayVersion") as string;
            var build = k?.GetValue("CurrentBuildNumber") as string;
            if (!string.IsNullOrEmpty(display))
                return $"Windows 11 {display}";
            if (!string.IsNullOrEmpty(build))
                return $"{product} ({build})";
            return product;
        }
        catch
        {
            return "Windows";
        }
    }

    private static double GetTotalRamGb()
    {
        var status = new MEMORYSTATUSEX { dwLength = (uint)Marshal.SizeOf<MEMORYSTATUSEX>() };
        if (!GlobalMemoryStatusEx(ref status)) return 0;
        return status.ullTotalPhys / (1024.0 * 1024 * 1024);
    }

    private static string ReadCpuName()
    {
        try
        {
            using var k = Registry.LocalMachine.OpenSubKey(@"HARDWARE\DESCRIPTION\System\CentralProcessor\0");
            return (k?.GetValue("ProcessorNameString") as string)?.Trim() ?? "CPU";
        }
        catch { return "CPU"; }
    }

    private static string ReadGpuName()
    {
        try
        {
            using var searcher = new ManagementObjectSearcher("SELECT Name FROM Win32_VideoController");
            foreach (var o in searcher.Get())
            {
                var name = o["Name"]?.ToString();
                if (!string.IsNullOrWhiteSpace(name) && !name.Contains("Microsoft Basic", StringComparison.OrdinalIgnoreCase))
                    return name.Trim();
            }
        }
        catch { /* */ }
        return "GPU";
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Auto)]
    private struct MEMORYSTATUSEX
    {
        public uint dwLength;
        public uint dwMemoryLoad;
        public ulong ullTotalPhys;
        public ulong ullAvailPhys;
        public ulong ullTotalPageFile;
        public ulong ullAvailPageFile;
        public ulong ullTotalVirtual;
        public ulong ullAvailVirtual;
        public ulong ullAvailExtendedVirtual;
    }

    [DllImport("kernel32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    private static extern bool GlobalMemoryStatusEx(ref MEMORYSTATUSEX lpBuffer);
}
