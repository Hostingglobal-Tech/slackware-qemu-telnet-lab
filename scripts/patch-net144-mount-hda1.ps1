$ErrorActionPreference = "Stop"

param(
  [Parameter(Mandatory = $true)]
  [string]$InputFloppy,

  [Parameter(Mandatory = $true)]
  [string]$OutputFloppy
)

if (-not (Test-Path $InputFloppy)) {
  throw "Input floppy not found: $InputFloppy"
}

$Data = [IO.File]::ReadAllBytes($InputFloppy)
$From = [Text.Encoding]::ASCII.GetBytes("root=21c ramdisk=0")
$To = [Text.Encoding]::ASCII.GetBytes("root=301 ramdisk=0")

if ($From.Length -ne $To.Length) {
  throw "Patch strings must have the same length."
}

$Found = -1
for ($i = 0; $i -le $Data.Length - $From.Length; $i++) {
  $Match = $true
  for ($j = 0; $j -lt $From.Length; $j++) {
    if ($Data[$i + $j] -ne $From[$j]) {
      $Match = $false
      break
    }
  }
  if ($Match) {
    $Found = $i
    break
  }
}

if ($Found -lt 0) {
  throw "Could not find 'root=21c ramdisk=0'. The input image may not be Slackware net144.flp."
}

for ($j = 0; $j -lt $To.Length; $j++) {
  $Data[$Found + $j] = $To[$j]
}

$OutDir = Split-Path -Parent $OutputFloppy
if ($OutDir -and -not (Test-Path $OutDir)) {
  New-Item -ItemType Directory -Path $OutDir | Out-Null
}

[IO.File]::WriteAllBytes($OutputFloppy, $Data)
Write-Host "Patched LILO mount label:"
Write-Host "  root=21c ramdisk=0 -> root=301 ramdisk=0"
Write-Host "Output: $OutputFloppy"

