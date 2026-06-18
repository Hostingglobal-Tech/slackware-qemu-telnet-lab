param(
  [string]$HostName = "127.0.0.1",
  [int]$Port = 2323,
  [string]$Login = "root",
  [string]$Password = "root"
)

$ProgressPreference = "SilentlyContinue"
$ErrorActionPreference = "Stop"

$Client = New-Object Net.Sockets.TcpClient
$Client.Connect($HostName, $Port)
$Stream = $Client.GetStream()
$Stream.ReadTimeout = 500

function Send-Bytes([byte[]]$Bytes) {
  $Stream.Write($Bytes, 0, $Bytes.Length)
  $Stream.Flush()
}

function Send-Line([string]$Line) {
  Send-Bytes ([Text.Encoding]::ASCII.GetBytes($Line + "`r`n"))
}

function Read-Telnet([int]$Seconds) {
  $Deadline = (Get-Date).AddSeconds($Seconds)
  $Out = New-Object System.Text.StringBuilder

  while ((Get-Date) -lt $Deadline) {
    if (-not $Stream.DataAvailable) {
      Start-Sleep -Milliseconds 100
      continue
    }

    $Buffer = New-Object byte[] 4096
    $N = $Stream.Read($Buffer, 0, $Buffer.Length)
    $I = 0

    while ($I -lt $N) {
      $Byte = $Buffer[$I]
      if ($Byte -eq 255 -and ($I + 1) -lt $N) {
        $Command = $Buffer[$I + 1]
        if (($Command -eq 251 -or $Command -eq 252 -or $Command -eq 253 -or $Command -eq 254) -and ($I + 2) -lt $N) {
          $Option = $Buffer[$I + 2]
          if ($Command -eq 251) {
            Send-Bytes ([byte[]](255, 253, $Option))
          } elseif ($Command -eq 253) {
            Send-Bytes ([byte[]](255, 252, $Option))
          }
          $I += 3
          continue
        }
        $I += 2
        continue
      }

      if ($Byte -ge 32 -or $Byte -eq 10 -or $Byte -eq 13 -or $Byte -eq 9) {
        [void]$Out.Append([char]$Byte)
      }
      $I++
    }
  }

  $Out.ToString()
}

function Step([string]$Label, [string]$Line, [int]$WaitSeconds = 3) {
  Write-Host "--- $Label ---"
  if ($Line -ne "") {
    Send-Line $Line
  }
  Write-Host (Read-Telnet $WaitSeconds)
}

Step "banner" "" 4
Step "login" $Login 2
Step "password" $Password 5
Step "hostname" "hostname" 3
Step "pwd" "pwd" 3
Step "ifconfig" "ifconfig" 5
Step "write file" "echo telnet_ok >/root/telnet_test.txt" 3
Step "read file" "cat /root/telnet_test.txt" 3
Step "exit" "exit" 1

$Stream.Close()
$Client.Close()
