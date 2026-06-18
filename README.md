# Slackware 2.0.0 QEMU Telnet Lab

1994년 Slackware Linux 2.0.0을 Windows 호스트의 QEMU에서 부팅하고, `eth0`에 정적 IP를 넣은 뒤 telnet으로 접속해서 작업할 수 있게 만든 실험 저장소입니다.

핵심 목표는 단순합니다.

- QEMU에서 Slackware 2.0.0을 부팅한다.
- `ifconfig`에서 `lo`만 보이는 상태를 고쳐 `eth0`를 잡는다.
- 게스트 IP를 `192.168.1.100/24`로 고정한다.
- 게이트웨이 `192.168.1.1`, DNS `8.8.8.8`을 사용한다.
- Windows 호스트에서 `127.0.0.1:2323`으로 telnet 접속한다.

## 현재 검증된 결과

실험 환경에서 다음까지 확인했습니다.

```text
eth0      Link encap UNSPEC
          inet addr 192.168.1.100  Bcast 192.168.1.255  Mask 255.255.255.0
          UP BROADCAST RUNNING  MTU 1500  Metric 1
```

게스트에서 통신 확인:

```text
ping -c 2 192.168.1.1
2 packets transmitted, 2 packets received, 0% packet loss

ping -c 2 8.8.8.8
2 packets transmitted, 2 packets received, 0% packet loss
```

telnet 작업 확인:

```text
darkstar login: root
Password:
Linux 1.0.9. (Posix).
# hostname
darkstar
# pwd
/root
# echo telnet_ok >/root/telnet_test.txt
# cat /root/telnet_test.txt
telnet_ok
```

## 저장소에 포함하지 않는 것

이 저장소에는 다음 파일을 포함하지 않습니다.

- Slackware 원본 플로피 이미지
- 설치된 하드디스크 이미지
- VMDK, ISO, raw disk 이미지
- 개인 PC 경로에 맞춘 로컬 결과물

이유는 간단합니다. 오래된 배포판 이미지라도 라이선스와 재배포 범위를 분리해서 보는 것이 안전하고, 디스크 이미지는 용량도 큽니다.

대신 이 저장소에는 다음을 넣었습니다.

- Windows QEMU 실행 스크립트
- `net144.flp` 패치 스크립트
- 게스트의 `/etc/rc.d/rc.inet1` 정적 IP 설정 예시
- telnet 접속 검증 스크립트
- 실제 삽질 기록과 문제 해결 문서

## 전체 구조

```text
scripts/
  patch-net144-mount-hda1.ps1   net144.flp의 mount 라벨을 /dev/hda1용으로 패치
  run-slackware-qemu-net.ps1    Windows QEMU 실행 및 자동 부팅 입력
  run-slackware-qemu-net.cmd    더블클릭 실행용 wrapper
  telnet-smoke-test.ps1         telnet 로그인과 기본 명령 검증

guest/
  etc/rc.d/rc.inet1             Slackware 게스트용 정적 IP 설정 예시
  etc/resolv.conf               DNS 설정 예시

docs/
  TROUBLESHOOTING.md            실제 문제와 해결 과정
```

## 준비물

Windows 호스트 기준입니다.

1. QEMU for Windows
2. Slackware 2.0.0 원본 부트 이미지
3. 설치 완료된 Slackware 2.0.0 하드디스크 이미지
4. PowerShell

예시 경로:

```text
D:\WSL\RETRO\Slackware-2.0.0
  floppy\
    net144.flp
    net144-mount-hda1.flp
  vm\
    slackware-installed-hda1-flat.vmdk
```

여기서 `slackware-installed-hda1-flat.vmdk`는 이름은 `.vmdk`지만, 이 실험에서는 QEMU가 `format=raw`로 읽습니다.

즉 VMware descriptor VMDK 파일을 QEMU가 그대로 해석하는 구조가 아닙니다. VMware 실험 과정에서 만든 flat/raw 디스크 내용을 QEMU에 IDE 하드디스크처럼 붙인 것입니다.

QEMU 실행 스크립트의 해당 부분:

```powershell
-drive "file=$DiskImage,format=raw,if=ide,index=0,media=disk"
```

만약 일반 VMware descriptor VMDK를 쓰고 싶다면 QEMU에서 `format=vmdk`로 읽는 방법도 있지만, 이 저장소의 검증 경로는 flat/raw 디스크 이미지입니다.

`scripts/run-slackware-qemu-net.ps1`의 `$BaseDir`, `$BootFloppy`, `$DiskImage` 값을 본인 환경에 맞게 바꾸면 됩니다.

## 1. net144.flp 패치

Slackware의 `net144.flp`는 NE2000 네트워크 커널을 포함합니다. 이 커널 덕분에 QEMU의 `ne2k_isa` 장치를 `eth0`로 잡을 수 있었습니다.

문제는 원래 `net144.flp`가 설치용 램디스크 흐름이라는 점입니다. 우리는 설치된 `/dev/hda1`로 바로 들어가야 하므로 `mount` 라벨의 root 값을 바꿉니다.

패치 실행:

```powershell
.\scripts\patch-net144-mount-hda1.ps1 `
  -InputFloppy "D:\WSL\RETRO\Slackware-2.0.0\floppy\net144.flp" `
  -OutputFloppy "D:\WSL\RETRO\Slackware-2.0.0\floppy\net144-mount-hda1.flp"
```

패치 내용:

```text
root=21c ramdisk=0
```

을 다음으로 바꿉니다.

```text
root=301 ramdisk=0
```

`0x0301`은 오래된 Linux 장치 번호 체계에서 `/dev/hda1`입니다.

## 2. QEMU에서 NE2000 NIC 붙이기

QEMU 실행 스크립트의 핵심은 이 부분입니다.

```powershell
-netdev user,id=n0,net=192.168.1.0/24,host=192.168.1.1,dns=8.8.8.8,hostfwd=tcp:127.0.0.1:2323-192.168.1.100:23
-device ne2k_isa,netdev=n0,iobase=0x300,irq=9
```

의미:

- 게스트 내부 네트워크: `192.168.1.0/24`
- QEMU 게이트웨이: `192.168.1.1`
- 게스트 IP: `192.168.1.100`
- DNS: `8.8.8.8`
- Windows telnet 접속 포트: `127.0.0.1:2323`
- Slackware 쪽 telnet 포트: `192.168.1.100:23`
- NIC 모델: NE2000 ISA
- I/O base: `0x300`
- IRQ: `9`

중요한 점이 있습니다. 이 방식은 QEMU user-mode NAT입니다.

즉 `192.168.1.100`은 QEMU 내부 NAT 네트워크의 게스트 IP입니다. 물리 LAN에 직접 `192.168.1.100` 장비가 나타나는 구조는 아닙니다. 물리 LAN에 직접 붙이고 싶다면 TAP/bridge 구성이 필요합니다.

## 3. 부트 프롬프트 자동 입력

부팅할 때 `net144`의 `boot:` 프롬프트에 다음을 입력해야 합니다.

```text
mount ether=9,0x300,eth0
```

뜻:

- `mount`: 우리가 패치한 LILO 라벨
- `ether=9,0x300,eth0`: NE2000 카드를 IRQ 9, I/O `0x300`, 인터페이스 `eth0`로 강제 탐색

`run-slackware-qemu-net.ps1`는 QEMU monitor에 접속해서 이 키 입력을 자동으로 보냅니다.

또 `net144`는 패치 후에도 다음과 같은 메시지를 한 번 더 띄웁니다.

```text
Please remove the boot kernel disk from your floppy drive,
insert a root/install disk ... and then press ENTER to continue.
```

여기서 실제로 디스크를 바꾸지 않아도 됩니다. ENTER만 누르면 설치된 `/dev/hda1` 루트로 들어갑니다. 이 ENTER도 스크립트에서 자동으로 보냅니다.

## 4. 게스트 안에서 정적 IP 설정

Slackware 게스트의 `/etc/rc.d/rc.inet1`을 이 저장소의 예시처럼 설정합니다.

핵심 설정값:

```sh
IPADDR="192.168.1.100"
NETMASK="255.255.255.0"
NETWORK="192.168.1.0"
BROADCAST="192.168.1.255"
GATEWAY="192.168.1.1"
```

핵심 실행 순서:

```sh
/sbin/ifconfig eth0 $IPADDR netmask $NETMASK broadcast $BROADCAST up
/sbin/route add -net $NETWORK netmask $NETMASK eth0
/sbin/route add default gw $GATEWAY metric 1
```

게이트웨이를 먼저 넣으면 다음 오류가 날 수 있습니다.

```text
SIOCADDRT: Network is unreachable
```

그래서 반드시 `eth0` 설정, 직접 연결된 네트워크 route, default gateway 순서로 넣는 것이 좋습니다.

DNS는 `/etc/resolv.conf`에 넣습니다.

```text
nameserver 8.8.8.8
```

### 디스크에 한 번에 패치하기

수동으로 게스트 안에서 파일을 편집하지 않으려면 WSL/Linux에서 설치된 flat/raw 디스크 이미지를 마운트해 한 번에 패치할 수 있습니다.

```bash
sudo ./scripts/patch-installed-hda1-guest.sh \
  /mnt/d/WSL/RETRO/Slackware-2.0.0/vm/slackware-installed-hda1-flat.vmdk
```

이 스크립트가 하는 일:

- `/etc/rc.d/rc.inet1`에 `eth0=192.168.1.100/24` 설정
- `/etc/resolv.conf`에 `nameserver 8.8.8.8` 설정
- `/etc/inetd.conf`에서 `in.telnetd` 활성화
- `/etc/services`에 `telnet 23/tcp` 확인
- `/etc/securetty`에 `ttyp0~ttyp9` 추가
- root 비밀번호 해시 설정

기본 root 비밀번호는 레트로 랩 편의상 `root`입니다. 다른 비밀번호를 쓰려면 DES crypt 해시를 만들어 환경변수로 넘깁니다.

```bash
ROOT_PASSWORD_HASH="$(perl -le 'print crypt("my-password", "xy")')" \
sudo -E ./scripts/patch-installed-hda1-guest.sh \
  /mnt/d/WSL/RETRO/Slackware-2.0.0/vm/slackware-installed-hda1-flat.vmdk
```

패치 스크립트는 원본 파일을 게스트 파일시스템 안에 `*.before-qemu-telnet-lab` 이름으로 한 번 백업합니다.

## 5. 실행

PowerShell에서:

```powershell
.\scripts\run-slackware-qemu-net.ps1
```

또는 Windows에서:

```text
scripts\run-slackware-qemu-net.cmd
```

## 6. telnet 접속

QEMU가 뜬 뒤 Windows 호스트에서 접속합니다.

```powershell
telnet 127.0.0.1 2323
```

검증 스크립트:

```powershell
.\scripts\telnet-smoke-test.ps1 -HostName 127.0.0.1 -Port 2323 -Login root -Password root
```

실험 환경에서는 root 비밀번호를 `root`로 설정했습니다. 공개 인터넷에 절대 노출하지 마세요. telnet은 암호화가 없습니다. 이 구성은 레트로 OS 복원 실험용입니다.

## 우리가 실제로 고친 것

처음에는 단순히 QEMU에서 Slackware가 부팅되면 끝날 줄 알았습니다. 실제로는 다음 문제가 순서대로 터졌습니다.

1. 안정적으로 부팅되는 커널은 `eth0`를 못 잡고 `lo`만 보였습니다.
2. `net144` 커널은 NE2000을 잡았지만 설치용 램디스크 흐름이라 `/dev/hda1`로 바로 들어가지 못했습니다.
3. `root=21c ramdisk=0`을 `root=301 ramdisk=0`으로 바꿔 `/dev/hda1`를 선택하게 했습니다.
4. 부트 프롬프트에 `ether=9,0x300,eth0`를 자동 입력했습니다.
5. `net144`가 여전히 root/install disk를 넣으라고 묻는 단계에서 ENTER를 한 번 더 자동 입력하게 했습니다.
6. 게스트의 `rc.inet1`에서 오래된 `/proc/net/dev` 감지 조건을 제거했습니다.
7. `eth0` 설정 후 바로 default gateway를 넣으면 실패해서, `192.168.1.0/24` route를 먼저 추가하도록 바꿨습니다.
8. `route -n`은 구형 환경에서 `/proc/net/route`를 못 찾아 실패할 수 있어, 실제 검증은 `ifconfig`와 ping으로 했습니다.
9. telnet 접속을 위해 QEMU hostfwd를 열고, 게스트의 telnet login 흐름까지 확인했습니다.

결과적으로 QEMU 콘솔이 아니라 telnet으로 접속해서 작업할 수 있는 상태까지 만들었습니다.

## 라이선스

이 저장소의 스크립트와 문서는 MIT 라이선스로 공개합니다.

Slackware 원본 이미지와 패키지는 이 저장소에 포함하지 않으며, 각 원저작권과 배포 조건을 따릅니다.
