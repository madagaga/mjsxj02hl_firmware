# mjsxj02hl_firmware

[![Donate](https://img.shields.io/badge/donate-YooMoney-blueviolet.svg)](https://yoomoney.ru/to/4100110221014297)

Build tools for mjsxj02hl firmware

**Attention! This firmware is no longer supported by the author. We recommend using [OpenIPC](https://github.com/OpenIPC/device-mjsxj02hl).**

## Preparation

1. Install dependencies:

```bash
sudo apt install git cmake lib32z1 lib32stdc++6 u-boot-tools dbus python3-pip dos2unix
pip3 install click
```

2. Install Hi3518Ev300 toolchain:

```bash
tar -zxf arm-himix100-linux.tgz
cd arm-himix100-linux
sudo ./arm-himix100-linux.install
sudo mkdir -p /opt/hisi-linux/x86-arm/arm-himix100-linux/target/usr/app/lib
sudo chmod 777 /opt/hisi-linux/x86-arm/arm-himix100-linux/target/usr/app/lib
gnome-session-quit
```

## Usage

Clone the repository:

```bash
git clone https://github.com/kasitoru/mjsxj02hl_firmware
cd mjsxj02hl_firmware
```

### Build firmware:
```bash
make FIRMWARE_VER=x.y.z
```

### Remote access services (FTP, Telnet, SSH)

Which remote access services start at boot is stored in `/configs/services.conf` (`ftp=1`, `telnet=1`, `ssh=1`; a missing file or a missing/invalid line means "enabled"). `init_app.sh` calls `services.sh apply`; the same script manages the services at run time:

```bash
services.sh status                  # one line per service: <name> enabled=<0|1> running=<0|1> available=<0|1>
services.sh set ssh 0               # save in services.conf AND stop now (set <name> 1 = save and start)
services.sh enable|disable <name>   # services.conf only
services.sh start|stop <name>       # now only, services.conf unchanged
```

Turning off (or stopping) the last remote shell access (telnet and ssh) is refused unless `--force` is added. Existing sessions are not closed when a service is stopped.

SSH is [Dropbear](https://matt.ucc.asn.au/dropbear/) (static, one multi-call binary `dropbearmulti` with `dropbear`, `dropbearkey` and `scp` links, ed25519 only, no port forwarding). Log in with `root` / `toor` (the password set by `init_app.sh`, change it with `passwd`) or with a key listed in `/configs/dropbear/authorized_keys`. The host key is generated at the first start in `/configs/dropbear/`.

```bash
ssh root@<camera-ip>
scp -O file root@<camera-ip>:/mnt/mmc/    # -O: legacy scp protocol, needed with OpenSSH >= 9 (Dropbear has no sftp-server)
```
### Unpack image:
```bash
make FIRMWARE_FILE=image.bin FIRMWARE_DIR=unpkg unpack
```

or (defaults input file `demo_hlc6.bin` and output directory `temp/firmware`):

```bash
make unpack
```

### Pack image:
```bash
make FIRMWARE_DIR=unpkg FIRMWARE_FILE=image.bin pack
```

or (defaults input directory `temp/firmware` and output file `demo_hlc6.bin`):

```bash
make pack
```
