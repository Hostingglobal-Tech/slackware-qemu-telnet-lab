$ErrorActionPreference = "Stop"

# Windows-host QEMU path.
$QemuExe = "C:\Program Files\qemu\qemu-system-i386.exe"

# Change this to your local Slackware lab directory.
$BaseDir = "D:\WSL\RETRO\Slackware-2.0.0"

# These two files are intentionally not included in this repository.
# - net144-mount-hda1.flp is created from an original Slackware net144.flp
#   by scripts/patch-net144-mount-hda1.ps1.
# - slackware-installed-hda1-flat.vmdk is a flat/raw disk image. It can come
#   from a VMware experiment, but QEMU loads it here as format=raw, not as a
#   VMware descriptor VMDK.
$BootFloppy = Join-Path $BaseDir "floppy\net144-mount-hda1.flp"
$DiskImage = Join-Path $BaseDir "vm\slackware-installed-hda1-flat.vmdk"

# QEMU user-mode NAT network. This is a guest-internal static address, not a
# bridged physical LAN address. Use TAP/bridge if you need real LAN presence.
$GuestIp = "192.168.1.100"
$GuestNet = "192.168.1.0/24"
$GuestGateway = "192.168.1.1"
$GuestDns = "8.8.8.8"
$HostTelnetPort = 2323
$MonitorPort = 45454

# NE2000 ISA settings used by the Slackware 2.0.0 net144 kernel.
$Ne2kIoBase = "0x300"
$Ne2kIrq = 9

$Title = "Slackware Linux 2.0.0 (1994) - installed hda1 + eth0"

foreach ($Path in @($QemuExe, $BootFloppy, $DiskImage)) {
  if (-not (Test-Path $Path)) {
    throw "Required file not found: $Path"
  }
}

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

Start-Process -FilePath $QemuExe -ArgumentList ($QemuArgs -join " ") -WorkingDirectory $BaseDir

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
    Start-Sleep -Milliseconds 35
  }
}

$Client = $null
$Stream = $null
for ($i = 0; $i -lt 60; $i++) {
  try {
    $Client = New-Object Net.Sockets.TcpClient
    $Client.Connect("127.0.0.1", $MonitorPort)
    $Stream = $Client.GetStream()
    break
  } catch {
    if ($Client) { $Client.Close() }
    Start-Sleep -Milliseconds 500
  }
}

if ($Stream) {
  Start-Sleep -Seconds 2

  # The patched net144 "mount" label already contains root=301 ramdisk=0.
  # We add only the NE2000 probe hint here.
  Send-QemuText -Stream $Stream -Text "mount ether=$Ne2kIrq,$Ne2kIoBase,eth0"
  Send-QemuMonitorLine -Stream $Stream -Line "sendkey ret"

  # net144 still asks for a root/install disk. ENTER continues into /dev/hda1.
  Start-Sleep -Seconds 10
  Send-QemuMonitorLine -Stream $Stream -Line "sendkey ret"

  $Stream.Close()
  $Client.Close()

  Write-Host "Slackware installed /dev/hda1 network boot started."
  Write-Host "eth0 target: $GuestIp / 255.255.255.0"
  Write-Host "gateway: $GuestGateway, dns: $GuestDns"
  Write-Host "host telnet forward: 127.0.0.1:$HostTelnetPort -> $GuestIp`:23"
} else {
  Write-Warning "QEMU started, but monitor connection failed."
  Write-Warning "At boot: type 'mount ether=$Ne2kIrq,$Ne2kIoBase,eth0', then press ENTER at the root/install prompt."
}

Write-Host "Floppy A: $BootFloppy"
Write-Host "Disk: $DiskImage"
