param(
  [string]$OutputDir = "$env:TEMP\slackware-qemu-monitor-frames",
  [int]$DurationSeconds = 76,
  [int]$Fps = 6,
  [int]$BootSendDelaySeconds = 2,
  [int]$RootDiskContinueDelaySeconds = 12,
  [int]$LoginDelaySeconds = 36
)

$ProgressPreference = "SilentlyContinue"
$ErrorActionPreference = "Stop"

$QemuExe = "C:\Program Files\qemu\qemu-system-i386.exe"
$BaseDir = "D:\WSL\RETRO\Slackware-2.0.0"
$BootFloppy = Join-Path $BaseDir "floppy\net144-mount-hda1.flp"
$DiskImage = Join-Path $BaseDir "vm\slackware-installed-hda1-flat.vmdk"

$GuestIp = "192.168.1.100"
$GuestNet = "192.168.1.0/24"
$GuestGateway = "192.168.1.1"
$GuestDns = "8.8.8.8"
$HostTelnetPort = 2323
$MonitorPort = 45454
$Ne2kIoBase = "0x300"
$Ne2kIrq = 9
$Title = "Slackware Linux 2.0.0 QEMU boot capture"

foreach ($Path in @($QemuExe, $BootFloppy, $DiskImage)) {
  if (-not (Test-Path $Path)) {
    throw "Required file not found: $Path"
  }
}

if (Test-Path $OutputDir) {
  Remove-Item -Recurse -Force $OutputDir
}
New-Item -ItemType Directory -Path $OutputDir | Out-Null

Get-Process -Name qemu-system-i386 -ErrorAction SilentlyContinue | Stop-Process -Force

$QemuArgs = @(
  "-name", "`"$Title`"",
  "-M", "pc",
  "-m", "32",
  "-boot", "a",
  "-drive", "`"file=$BootFloppy,format=raw,if=floppy,index=0,media=disk`"",
  "-drive", "`"file=$DiskImage,format=raw,if=ide,index=0,media=disk`"",
  "-monitor", "telnet:127.0.0.1:$MonitorPort,server,nowait",
  "-netdev", "user,id=n0,net=$GuestNet,host=$GuestGateway,dns=$GuestDns,hostfwd=tcp:127.0.0.1:$HostTelnetPort-$GuestIp`:23",
  "-device", "ne2k_isa,netdev=n0,iobase=$Ne2kIoBase,irq=$Ne2kIrq",
  "-rtc", "base=localtime"
)

$Qemu = Start-Process -FilePath $QemuExe -ArgumentList ($QemuArgs -join " ") -WorkingDirectory $BaseDir -PassThru

function Send-QemuMonitorLine {
  param(
    [Parameter(Mandatory = $true)][System.Net.Sockets.NetworkStream]$Stream,
    [Parameter(Mandatory = $true)][string]$Line
  )
  $Bytes = [Text.Encoding]::ASCII.GetBytes("$Line`n")
  $Stream.Write($Bytes, 0, $Bytes.Length)
  $Stream.Flush()
}

function Send-QemuText {
  param(
    [Parameter(Mandatory = $true)][System.Net.Sockets.NetworkStream]$Stream,
    [Parameter(Mandatory = $true)][string]$Text
  )

  $KeyMap = @{
    " " = "spc"
    "," = "comma"
    "." = "dot"
    "/" = "slash"
    "-" = "minus"
    "=" = "equal"
  }

  foreach ($Char in $Text.ToCharArray()) {
    $Key = [string]$Char
    if ($KeyMap.ContainsKey($Key)) {
      $Key = $KeyMap[$Key]
    }
    Send-QemuMonitorLine -Stream $Stream -Line "sendkey $Key"
    Start-Sleep -Milliseconds 25
  }
}

$Client = $null
$Stream = $null
for ($i = 0; $i -lt 80; $i++) {
  try {
    $Client = New-Object Net.Sockets.TcpClient
    $Client.Connect("127.0.0.1", $MonitorPort)
    $Stream = $Client.GetStream()
    break
  } catch {
    if ($Client) { $Client.Close() }
    Start-Sleep -Milliseconds 250
  }
}

if (-not $Stream) {
  throw "QEMU monitor connection failed."
}

$TotalFrames = [Math]::Max(1, $DurationSeconds * $Fps)
$DelayMs = [Math]::Max(20, [int](1000 / $Fps))
$BootFrame = [Math]::Max(0, $BootSendDelaySeconds * $Fps)
$ContinueFrame = [Math]::Max($BootFrame + 1, $RootDiskContinueDelaySeconds * $Fps)
$LoginFrame = [Math]::Max($ContinueFrame + 1, $LoginDelaySeconds * $Fps)
$PasswordFrame = $LoginFrame + (2 * $Fps)
$IfconfigFrame = $PasswordFrame + (3 * $Fps)
$MountProcFrame = $IfconfigFrame + (7 * $Fps)
$PsFrame = $MountProcFrame + (5 * $Fps)
$InetdConfFrame = $PsFrame + (8 * $Fps)

for ($i = 0; $i -lt $TotalFrames; $i++) {
  if ($i -eq $BootFrame) {
    Send-QemuText -Stream $Stream -Text "mount ether=$Ne2kIrq,$Ne2kIoBase,eth0"
    Send-QemuMonitorLine -Stream $Stream -Line "sendkey ret"
  }

  if ($i -eq $ContinueFrame) {
    Send-QemuMonitorLine -Stream $Stream -Line "sendkey ret"
  }

  if ($i -eq $LoginFrame) {
    Send-QemuText -Stream $Stream -Text "root"
    Send-QemuMonitorLine -Stream $Stream -Line "sendkey ret"
  }

  if ($i -eq $PasswordFrame) {
    Send-QemuText -Stream $Stream -Text "root"
    Send-QemuMonitorLine -Stream $Stream -Line "sendkey ret"
  }

  if ($i -eq $IfconfigFrame) {
    Send-QemuText -Stream $Stream -Text "ifconfig"
    Send-QemuMonitorLine -Stream $Stream -Line "sendkey ret"
  }

  if ($i -eq $MountProcFrame) {
    Send-QemuText -Stream $Stream -Text "mount -t proc proc /proc"
    Send-QemuMonitorLine -Stream $Stream -Line "sendkey ret"
  }

  if ($i -eq $PsFrame) {
    Send-QemuText -Stream $Stream -Text "ps ax"
    Send-QemuMonitorLine -Stream $Stream -Line "sendkey ret"
  }

  if ($i -eq $InetdConfFrame) {
    Send-QemuText -Stream $Stream -Text "grep telnet /etc/inetd.conf"
    Send-QemuMonitorLine -Stream $Stream -Line "sendkey ret"
  }

  $FramePath = (Join-Path $OutputDir ("frame_{0:D4}.ppm" -f $i)).Replace("\", "/")
  Send-QemuMonitorLine -Stream $Stream -Line "screendump $FramePath"
  Start-Sleep -Milliseconds $DelayMs
}

$Stream.Close()
$Client.Close()

Write-Host "Frames: $OutputDir"
Write-Host "QEMU PID: $($Qemu.Id)"
Write-Host "Captured only QEMU VGA output; no telnet session is appended."
