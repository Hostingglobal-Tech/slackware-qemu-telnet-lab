# 문제 해결 기록

이 문서는 실제 실험에서 막혔던 지점과 해결 방법을 정리한 것입니다.

## `ifconfig`에 `lo`만 보이고 `eth0`가 없음

처음에는 설치용으로 잘 부팅되는 커널을 사용했습니다. 이 커널은 하드디스크의 `/dev/hda1`로 들어가는 데는 안정적이었지만 NE2000 네트워크 드라이버가 없었습니다. 그래서 `ifconfig`를 실행하면 loopback인 `lo`만 보였습니다.

해결 방향은 Slackware의 `net144` 부트 커널을 사용하는 것이었습니다. `net144`는 NE2000을 포함하고 있어서 QEMU의 `ne2k_isa` 장치를 인식할 수 있습니다.

QEMU 장치 설정:

```powershell
-netdev user,id=n0,net=192.168.1.0/24,host=192.168.1.1,dns=8.8.8.8,hostfwd=tcp:127.0.0.1:2323-192.168.1.100:23
-device ne2k_isa,netdev=n0,iobase=0x300,irq=9
```

부트 프롬프트 입력:

```text
mount ether=9,0x300,eth0
```

성공하면 커널 로그에 다음과 비슷한 메시지가 보입니다.

```text
NE*000 ethercard probe at 0x300: ...
eth0: NE2000 found at 0x300, using IRQ 9.
```

## `net144`가 계속 root/install disk를 넣으라고 함

`net144`는 설치용 램디스크 흐름을 기본값으로 가지고 있습니다. 우리는 이미 설치된 `/dev/hda1`로 들어가야 했기 때문에 `mount` 라벨의 root 설정을 바꿨습니다.

원래 문자열:

```text
root=21c ramdisk=0
```

변경 문자열:

```text
root=301 ramdisk=0
```

`0x0301`은 Linux 1.x 계열에서 `/dev/hda1`을 뜻합니다. 이 변경은 `scripts/patch-net144-mount-hda1.ps1`로 수행합니다.

그런데 이 패치 후에도 `net144`는 다음 메시지를 한 번 더 표시합니다.

```text
Please remove the boot kernel disk from your floppy drive,
insert a root/install disk ... and then press ENTER to continue.
```

여기서는 실제로 플로피를 바꿀 필요 없이 ENTER를 한 번 더 누르면 `/dev/hda1` 설치 루트로 넘어갑니다. `run-slackware-qemu-net.ps1`는 이 ENTER까지 자동으로 보냅니다.

## `SIOCADDRT: Network is unreachable`

게이트웨이를 추가할 때 이 오류가 났습니다.

원인은 `default gw`를 추가하기 전에 직접 연결된 `192.168.1.0/24` 네트워크 라우트가 먼저 잡혀야 하기 때문입니다. 그래서 `rc.inet1`에서 순서를 다음처럼 고쳤습니다.

```sh
/sbin/ifconfig eth0 192.168.1.100 netmask 255.255.255.0 broadcast 192.168.1.255 up
/sbin/route add -net 192.168.1.0 netmask 255.255.255.0 eth0
/sbin/route add default gw 192.168.1.1 metric 1
```

## `route -n`에서 `/proc/net/route` 오류가 남

Linux 1.0.9와 당시 `route` 도구 조합에서는 `route -n` 출력이 `/proc/net/route`를 찾다가 실패할 수 있습니다.

이 오류만으로 네트워크 실패라고 판단하면 안 됩니다. 실제 검증은 다음이 더 확실했습니다.

```sh
ifconfig
ping -c 2 192.168.1.1
ping -c 2 8.8.8.8
```

검증된 결과:

- `eth0`가 표시됨
- `inet addr 192.168.1.100`
- `UP BROADCAST RUNNING`
- `192.168.1.1` ping 성공
- `8.8.8.8` ping 성공

## telnet 접속

QEMU 포워딩은 다음처럼 되어 있습니다.

```text
Windows host 127.0.0.1:2323 -> Slackware guest 192.168.1.100:23
```

Windows에서 접속:

```powershell
telnet 127.0.0.1 2323
```

또는 제공된 검증 스크립트:

```powershell
.\scripts\telnet-smoke-test.ps1 -HostName 127.0.0.1 -Port 2323 -Login root -Password root
```

실험에서는 다음까지 확인했습니다.

```text
darkstar login: root
Password:
Linux 1.0.9. (Posix).
# hostname
darkstar
# ifconfig
eth0 ... inet addr 192.168.1.100 ...
# echo telnet_ok >/root/telnet_test.txt
# cat /root/telnet_test.txt
telnet_ok
```

## 보안 참고

telnet은 암호화가 없습니다. 이 저장소의 설정은 1994년 리눅스 복원 실험과 로컬 레트로 랩을 위한 것입니다.

인터넷에 직접 노출하지 마세요. 기본 포워딩도 `127.0.0.1:2323`으로 로컬 호스트에만 묶어 둔 이유가 그것입니다.

