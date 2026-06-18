param(
  [string]$OutputDir = "$env:TEMP\slackware-qemu-boot-frames",
  [int]$DurationSeconds = 34,
  [int]$Fps = 3,
  [int]$WindowX = 40,
  [int]$WindowY = 40,
  [int]$WindowWidth = 900,
  [int]$WindowHeight = 620
)

$ProgressPreference = "SilentlyContinue"
$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RunScript = Join-Path $ScriptDir "run-slackware-qemu-net.ps1"

if (-not (Test-Path $RunScript)) {
  throw "Run script not found: $RunScript"
}

if (Test-Path $OutputDir) {
  Remove-Item -Recurse -Force $OutputDir
}
New-Item -ItemType Directory -Path $OutputDir | Out-Null

Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class Win32Window {
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, UInt32 uFlags);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
  public static readonly IntPtr HWND_TOPMOST = new IntPtr(-1);
  public static readonly IntPtr HWND_NOTOPMOST = new IntPtr(-2);
}
public struct RECT {
  public int Left;
  public int Top;
  public int Right;
  public int Bottom;
}
"@

Get-Process -Name qemu-system-i386 -ErrorAction SilentlyContinue | Stop-Process -Force

$Runner = Start-Process -FilePath "powershell.exe" `
  -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$RunScript`"") `
  -WindowStyle Hidden `
  -PassThru

$Qemu = $null
for ($i = 0; $i -lt 80; $i++) {
  $Qemu = Get-Process -Name qemu-system-i386 -ErrorAction SilentlyContinue |
    Where-Object { $_.MainWindowHandle -ne 0 } |
    Select-Object -First 1
  if ($Qemu) { break }
  Start-Sleep -Milliseconds 250
}

if (-not $Qemu) {
  throw "QEMU window was not found."
}

[void][Win32Window]::ShowWindow($Qemu.MainWindowHandle, 1)
[void][Win32Window]::SetWindowPos($Qemu.MainWindowHandle, [Win32Window]::HWND_TOPMOST, $WindowX, $WindowY, $WindowWidth, $WindowHeight, 0x0040)
[void][Win32Window]::SetForegroundWindow($Qemu.MainWindowHandle)
Start-Sleep -Milliseconds 500

$FrameCount = [Math]::Max(1, $DurationSeconds * $Fps)
$DelayMs = [Math]::Max(20, [int](1000 / $Fps))

for ($i = 0; $i -lt $FrameCount; $i++) {
  $Rect = New-Object RECT
  [void][Win32Window]::GetWindowRect($Qemu.MainWindowHandle, [ref]$Rect)
  $Width = [Math]::Max(1, $Rect.Right - $Rect.Left)
  $Height = [Math]::Max(1, $Rect.Bottom - $Rect.Top)

  $Bitmap = New-Object System.Drawing.Bitmap $Width, $Height
  $Graphics = [System.Drawing.Graphics]::FromImage($Bitmap)
  $Graphics.CopyFromScreen($Rect.Left, $Rect.Top, 0, 0, $Bitmap.Size)
  $Path = Join-Path $OutputDir ("frame_{0:D4}.png" -f $i)
  $Bitmap.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
  $Graphics.Dispose()
  $Bitmap.Dispose()

  Start-Sleep -Milliseconds $DelayMs
}

[void][Win32Window]::SetWindowPos($Qemu.MainWindowHandle, [Win32Window]::HWND_NOTOPMOST, $WindowX, $WindowY, $WindowWidth, $WindowHeight, 0x0040)

Write-Host "Frames: $OutputDir"
Write-Host "Runner PID: $($Runner.Id)"
