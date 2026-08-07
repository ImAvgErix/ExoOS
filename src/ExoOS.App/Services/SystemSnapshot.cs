using System.Diagnostics;
using System.IO;
using System.Management;
using System.Net.NetworkInformation;
using System.Runtime.InteropServices;
using Microsoft.Win32;

namespace ExoOS.Services;

/// <summary>Lightweight live + inventory stats for the Exo-style home dashboard.</summary>
public static class SystemSnapshot
{
    private static PerformanceCounter? _cpu;
    private static long _prevRecv;
    private static long _prevSent;
    private static DateTime _prevNet = DateTime.UtcNow;
    private static double _downMbps;
    private static double _upMbps;

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

    public static object GetLive()
    {
        var mem = GetMemory();
        SampleNet();
        var disk = GetDisk();
        return new
        {
            cpuPercent = SampleCpu(),
            gpuPercent = 0, // no vendor GPU meter without NVAPI; label still shows GPU name
            memoryPercent = mem.percent,
            diskPercent = disk.percent,
            memorySecondary = mem.secondary,
            diskSecondary = disk.secondary,
            netDownMbps = _downMbps,
            netUpMbps = _upMbps,
            netLink = GetLink()
        };
    }

    private static float SampleCpu()
    {
        try
        {
            _cpu ??= new PerformanceCounter("Processor", "% Processor Time", "_Total");
            _ = _cpu.NextValue();
            Thread.Sleep(80);
            return Math.Clamp(_cpu.NextValue(), 0, 100);
        }
        catch
        {
            return 0;
        }
    }

    private static (float percent, string secondary) GetMemory()
    {
        var status = new MEMORYSTATUSEX { dwLength = (uint)Marshal.SizeOf<MEMORYSTATUSEX>() };
        if (!GlobalMemoryStatusEx(ref status) || status.ullTotalPhys == 0)
            return (0, "—");
        var used = status.ullTotalPhys - status.ullAvailPhys;
        var pct = (float)(used * 100.0 / status.ullTotalPhys);
        var usedGb = used / (1024.0 * 1024 * 1024);
        var totalGb = status.ullTotalPhys / (1024.0 * 1024 * 1024);
        return (pct, $"{usedGb:0.#} / {totalGb:0.#} GB");
    }

    private static (float percent, string secondary) GetDisk()
    {
        try
        {
            var drive = new DriveInfo(Path.GetPathRoot(Environment.SystemDirectory) ?? "C:\\");
            if (!drive.IsReady) return (0, "—");
            var used = drive.TotalSize - drive.AvailableFreeSpace;
            var pct = (float)(used * 100.0 / drive.TotalSize);
            return (pct, $"{used / (1024.0 * 1024 * 1024):0.#} GB used");
        }
        catch
        {
            return (0, "—");
        }
    }

    private static void SampleNet()
    {
        try
        {
            long recv = 0, sent = 0;
            foreach (var n in NetworkInterface.GetAllNetworkInterfaces())
            {
                if (n.OperationalStatus != OperationalStatus.Up) continue;
                if (n.NetworkInterfaceType is NetworkInterfaceType.Loopback or NetworkInterfaceType.Tunnel)
                    continue;
                var s = n.GetIPv4Statistics();
                recv += s.BytesReceived;
                sent += s.BytesSent;
            }
            var now = DateTime.UtcNow;
            var dt = (now - _prevNet).TotalSeconds;
            if (dt > 0.2 && _prevRecv > 0)
            {
                _downMbps = Math.Max(0, (recv - _prevRecv) * 8.0 / dt / 1_000_000);
                _upMbps = Math.Max(0, (sent - _prevSent) * 8.0 / dt / 1_000_000);
            }
            _prevRecv = recv;
            _prevSent = sent;
            _prevNet = now;
        }
        catch { /* */ }
    }

    private static string GetLink()
    {
        try
        {
            foreach (var n in NetworkInterface.GetAllNetworkInterfaces())
            {
                if (n.OperationalStatus != OperationalStatus.Up) continue;
                if (n.NetworkInterfaceType is NetworkInterfaceType.Loopback or NetworkInterfaceType.Tunnel)
                    continue;
                var speed = n.Speed;
                if (speed <= 0) continue;
                if (speed >= 1_000_000_000) return $"{speed / 1_000_000_000} Gbps · {n.Name}";
                return $"{speed / 1_000_000} Mbps · {n.Name}";
            }
        }
        catch { /* */ }
        return "—";
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
