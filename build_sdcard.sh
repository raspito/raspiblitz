#!/bin/bash
#########################################################################
# Build your SD card image based on:
# Raspbian Buster Desktop (2020-02-13)
# https://www.raspberrypi.org/downloads/raspbian/
# SHA256: a82ed4139dfad31c3167e60e943bcbe28c404d1858f4713efe5530c08a419f50
##########################################################################
# setup fresh SD card with image above - login per SSH and run this script:
##########################################################################

echo ""
echo "*****************************************"
echo "* RASPIBLITZ SD CARD IMAGE SETUP v1.5   *"
echo "*****************************************"
echo ""

# 1st optional parameter is the BRANCH to get code from when
# provisioning sd card with raspiblitz assets/scripts later on
echo "*** CHECK INPUT PARAMETERS ***"
wantedBranch="$1"
if [ ${#wantedBranch} -eq 0 ]; then
  wantedBranch="master"
fi
echo "will use code from branch --> '${wantedBranch}'"

# 2nd optional parameter is the GITHUB-USERNAME to get code from when
# provisioning sd card with raspiblitz assets/scripts later on
# if 2nd parameter is used - 1st is mandatory
echo "*** CHECK INPUT PARAMETERS ***"
githubUser="$2"
if [ ${#githubUser} -eq 0 ]; then
  githubUser="rootzoll"
fi
echo "will use code from user --> '${githubUser}'"

sleep 3

echo ""
echo "*** CHECK BASE IMAGE ***"

# armv7=32Bit , armv8=64Bit
echo "Detect CPU architecture ..."
isARM=$(uname -m | grep -c 'arm')
isAARCH64=$(uname -m | grep -c 'aarch64')
isX86_64=$(uname -m | grep -c 'x86_64')
isX86_32=$(uname -m | grep -c 'i386\|i486\|i586\|i686\|i786')
if [ ${isARM} -eq 0 ] && [ ${isAARCH64} -eq 0 ] && [ ${isX86_64} -eq 0 ] && [ ${isX86_32} -eq 0 ] ; then
  echo "!!! FAIL !!!"
  echo "Can only build on ARM, aarch64, x86_64 or i386 not on:"
  uname -m
  exit 1
else
 echo "OK running on $(uname -m) architecture."
fi

# keep in mind that DietPi for Raspberry is also a stripped down Raspbian
echo "Detect Base Image ..."
baseImage="?"
isDietPi=$(uname -n | grep -c 'DietPi')
isRaspbian=$(cat /etc/os-release 2>/dev/null | grep -c 'Raspbian')
isArmbian=$(cat /etc/os-release 2>/dev/null | grep -c 'Debian')
isUbuntu=$(cat /etc/os-release 2>/dev/null | grep -c 'Ubuntu')
isNvidia=$(uname -a | grep -c 'tegra')
if [ ${isRaspbian} -gt 0 ]; then
  baseImage="raspbian"
fi
if [ ${isArmbian} -gt 0 ]; then
  baseImage="armbian"
fi
if [ ${isUbuntu} -gt 0 ]; then
baseImage="ubuntu"
fi
if [ ${isDietPi} -gt 0 ]; then
  baseImage="dietpi"
fi
if [ "${baseImage}" = "?" ]; then
  cat /etc/os-release 2>/dev/null
  echo "!!! FAIL !!!"
  echo "Base Image cannot be detected or is not supported."
  exit 1
else
  echo "OK running ${baseImage}"
fi

if [ "${baseImage}" = "raspbian" ] || [ "${baseImage}" = "dietpi" ] ; then
  # fixing locales for build
  # https://github.com/rootzoll/raspiblitz/issues/138
  # https://daker.me/2014/10/how-to-fix-perl-warning-setting-locale-failed-in-raspbian.html
  # https://stackoverflow.com/questions/38188762/generate-all-locales-in-a-docker-image
  echo ""
  echo "*** FIXING LOCALES FOR BUILD ***"

  sudo sed -i "s/^# en_US.UTF-8 UTF-8.*/en_US.UTF-8 UTF-8/g" /etc/locale.gen
  sudo sed -i "s/^# en_US ISO-8859-1.*/en_US ISO-8859-1/g" /etc/locale.gen
  sudo locale-gen
  export LANGUAGE=en_US.UTF-8
  export LANG=en_US.UTF-8
  export LC_ALL=en_US.UTF-8

  # https://github.com/rootzoll/raspiblitz/issues/684
  sudo sed -i "s/^    SendEnv LANG LC.*/#   SendEnv LANG LC_*/g" /etc/ssh/ssh_config

  # remove unneccesary files
  sudo rm -rf /home/pi/MagPi
fi

# remove some (big) packages that are not needed
sudo apt-get remove -y --purge libreoffice* oracle-java* chromium-browser nuscratch scratch sonic-pi minecraft-pi plymouth python2
sudo apt-get clean
sudo apt-get -y autoremove

# make sure /usr/bin/python exists (and calls Python3.7 in Debian Buster)
sudo update-alternatives --install /usr/bin/python python /usr/bin/python3.7 1

# update debian
echo ""
echo "*** UPDATE DEBIAN ***"
sudo apt-get update -y
sudo apt-get upgrade -f -y

echo ""
echo "*** PREPARE ${baseImage} ***"

# special prepare when DietPi
if [ "${baseImage}" = "dietpi" ]; then
  echo "renaming dietpi user to pi"
  sudo usermod -l pi dietpi
fi

# special prepare when Raspbian
if [ "${baseImage}" = "raspbian" ]; then
  # do memory split (16MB)
  sudo raspi-config nonint do_memory_split 16
  # set to wait until network is available on boot (0 seems to yes)
  sudo raspi-config nonint do_boot_wait 0
  # set WIFI country so boot does not block
  sudo raspi-config nonint do_wifi_country US
  # see https://github.com/rootzoll/raspiblitz/issues/428#issuecomment-472822840
  echo "max_usb_current=1" | sudo tee -a /boot/config.txt
  # run fsck on sd boot partition on every startup to prevent "maintenance login" screen
  # see: https://github.com/rootzoll/raspiblitz/issues/782#issuecomment-564981630
  # use command to check last fsck check: sudo tune2fs -l /dev/mmcblk0p2
  sudo tune2fs -c 1 /dev/mmcblk0p2
  # see https://github.com/rootzoll/raspiblitz/issues/1053#issuecomment-600878695
  sudo sed -i 's/^/fsck.mode=force fsck.repair=yes /g' /boot/cmdline.txt
fi

# special prepare when Ubuntu or Armbian
if [ "${baseImage}" = "ubuntu" ] || [ "${baseImage}" = "armbian" ]; then
  # make user pi and add to sudo
  sudo adduser --disabled-password --gecos "" pi
  sudo adduser pi sudo
fi

# special prepare when Nvidia Jetson Nano
if [ ${isNvidia} -eq 1 ] ; then
  # disable GUI on boot
  sudo systemctl set-default multi-user.target
fi

echo ""
echo "*** CONFIG ***"
# based on https://github.com/Stadicus/guides/blob/master/raspibolt/raspibolt_20_pi.md#raspi-config

# set new default passwort for root user
echo "root:raspiblitz" | sudo chpasswd
echo "pi:raspiblitz" | sudo chpasswd

if [ "${baseImage}" = "raspbian" ]; then
  # set Raspi to boot up automatically with user pi (for the LCD)
  # https://www.raspberrypi.org/forums/viewtopic.php?t=21632
  sudo raspi-config nonint do_boot_behaviour B2
  sudo bash -c "echo '[Service]' >> /etc/systemd/system/getty@tty1.service.d/autologin.conf"
  sudo bash -c "echo 'ExecStart=' >> /etc/systemd/system/getty@tty1.service.d/autologin.conf"
  sudo bash -c "echo 'ExecStart=-/sbin/agetty --autologin pi --noclear %I 38400 linux' >> /etc/systemd/system/getty@tty1.service.d/autologin.conf"
fi

if [ "${baseImage}" = "dietpi" ]; then
  # set DietPi to boot up automatically with user pi (for the LCD)
  # requires AUTO_SETUP_AUTOSTART_TARGET_INDEX=7 in the dietpi.txt
  # /DietPi/dietpi/dietpi-autostart overwrites /etc/systemd/system/getty@tty1.service.d/dietpi-autologin.conf on reboot
  sudo sed -i 's/agetty --autologin root %I $TERM/agetty --autologin pi --noclear %I 38400 linux/' /DietPi/dietpi/dietpi-autostart
fi

if [ "${baseImage}" = "ubuntu" ] || [ "${baseImage}" = "armbian" ]; then
  sudo bash -c "echo '[Service]' >> /lib/systemd/system/getty@.service"
  sudo bash -c "echo 'ExecStart=' >> /lib/systemd/system/getty@.service"
  sudo bash -c "echo 'ExecStart=-/sbin/agetty --autologin pi --noclear %I 38400 linux' >> /lib/systemd/system/getty@.service"
fi

# change log rotates
# see https://github.com/rootzoll/raspiblitz/issues/394#issuecomment-471535483
echo "/var/log/syslog" >> ./rsyslog
echo "{" >> ./rsyslog
echo "	rotate 7" >> ./rsyslog
echo "	daily" >> ./rsyslog
echo "	missingok" >> ./rsyslog
echo "	notifempty" >> ./rsyslog
echo "	delaycompress" >> ./rsyslog
echo "	compress" >> ./rsyslog
echo "	postrotate" >> ./rsyslog
echo "		invoke-rc.d rsyslog rotate > /dev/null" >> ./rsyslog
echo "	endscript" >> ./rsyslog
echo "}" >> ./rsyslog
echo "" >> ./rsyslog
echo "/var/log/mail.info" >> ./rsyslog
echo "/var/log/mail.warn" >> ./rsyslog
echo "/var/log/mail.err" >> ./rsyslog
echo "/var/log/mail.log" >> ./rsyslog
echo "/var/log/daemon.log" >> ./rsyslog
echo "{" >> ./rsyslog
echo "        rotate 4" >> ./rsyslog
echo "        size=100M" >> ./rsyslog
echo "        missingok" >> ./rsyslog
echo "        notifempty" >> ./rsyslog
echo "        compress" >> ./rsyslog
echo "        delaycompress" >> ./rsyslog
echo "        sharedscripts" >> ./rsyslog
echo "        postrotate" >> ./rsyslog
echo "                invoke-rc.d rsyslog rotate > /dev/null" >> ./rsyslog
echo "        endscript" >> ./rsyslog
echo "}" >> ./rsyslog
echo "" >> ./rsyslog
echo "/var/log/kern.log" >> ./rsyslog
echo "/var/log/auth.log" >> ./rsyslog
echo "{" >> ./rsyslog
echo "        rotate 4" >> ./rsyslog
echo "        size=100M" >> ./rsyslog
echo "        missingok" >> ./rsyslog
echo "        notifempty" >> ./rsyslog
echo "        compress" >> ./rsyslog
echo "        delaycompress" >> ./rsyslog
echo "        sharedscripts" >> ./rsyslog
echo "        postrotate" >> ./rsyslog
echo "                invoke-rc.d rsyslog rotate > /dev/null" >> ./rsyslog
echo "        endscript" >> ./rsyslog
echo "}" >> ./rsyslog
echo "" >> ./rsyslog
echo "/var/log/user.log" >> ./rsyslog
echo "/var/log/lpr.log" >> ./rsyslog
echo "/var/log/cron.log" >> ./rsyslog
echo "/var/log/debug" >> ./rsyslog
echo "/var/log/messages" >> ./rsyslog
echo "{" >> ./rsyslog
echo "	rotate 4" >> ./rsyslog
echo "	weekly" >> ./rsyslog
echo "	missingok" >> ./rsyslog
echo "	notifempty" >> ./rsyslog
echo "	compress" >> ./rsyslog
echo "	delaycompress" >> ./rsyslog
echo "	sharedscripts" >> ./rsyslog
echo "	postrotate" >> ./rsyslog
echo "		invoke-rc.d rsyslog rotate > /dev/null" >> ./rsyslog
echo "	endscript" >> ./rsyslog
echo "}" >> ./rsyslog
sudo mv ./rsyslog /etc/logrotate.d/rsyslog
sudo chown root:root /etc/logrotate.d/rsyslog
sudo service rsyslog restart

echo ""
echo "*** SOFTWARE UPDATE ***"
# based on https://github.com/Stadicus/guides/blob/master/raspibolt/raspibolt_20_pi.md#software-update

# installs like on RaspiBolt
sudo apt-get install -y htop git curl bash-completion vim jq dphys-swapfile bsdmainutils

# installs bandwidth monitoring for future statistics
sudo apt-get install -y vnstat

# prepare for BTRFS data drive raid
sudo apt-get install -y btrfs-tools

# prepare for ssh reverse tunneling
sudo apt-get install -y autossh

# prepare for display graphics mode
# see https://github.com/rootzoll/raspiblitz/pull/334
sudo apt-get install -y fbi

# prepare for powertest
sudo apt install -y sysbench

# check for dependencies on DietPi, Ubuntu, Armbian
sudo apt install -y build-essential
if [ "${baseImage}" = "armbian" ]; then
  # add armbian config
  sudo apt --fix-broken install -y
  sudo apt install armbian-config -y
  # dependencies for Armbian Buster minimal kernel 5.4
  sudo apt install -y python3-venv python3-dev python3-wheel
fi

# rsync is needed to copy from HDD
sudo apt install -y rsync
# install ifconfig
sudo apt install -y net-tools
#to display hex codes
sudo apt install -y xxd
# setuptools needed for Nyx
sudo pip install setuptools
# netcat for 00infoBlitz.sh
sudo apt install -y netcat
# install OpenSSH client + server
sudo apt install -y openssh-client
sudo apt install -y openssh-sftp-server
# install killall, fuser
sudo apt-get install -y psmisc

sudo apt-get clean
sudo apt-get -y autoremove

echo ""
echo "*** ADDING MAIN USER admin ***"
# based on https://github.com/Stadicus/guides/blob/master/raspibolt/raspibolt_20_pi.md#adding-main-user-admin
# using the default password 'raspiblitz'

sudo adduser --disabled-password --gecos "" admin
echo "admin:raspiblitz" | sudo chpasswd
sudo adduser admin sudo
sudo chsh admin -s /bin/bash

# configure sudo for usage without password entry
echo '%sudo ALL=(ALL) NOPASSWD:ALL' | sudo EDITOR='tee -a' visudo

echo ""
echo "*** ADDING SERVICE USER bitcoin"
# based on https://github.com/Stadicus/guides/blob/master/raspibolt/raspibolt_20_pi.md#adding-the-service-user-bitcoin

# create user and set default password for user
sudo adduser --disabled-password --gecos "" bitcoin
echo "bitcoin:raspiblitz" | sudo chpasswd

echo ""
echo "*** ADDING GROUPS FOR CREDENTIALS STORE ***"
# access to credentials (e.g. macaroon files) in a central location is managed with unix groups and permissions
sudo /usr/sbin/groupadd --force --gid 9700 lndadmin
sudo /usr/sbin/groupadd --force --gid 9701 lndinvoice
sudo /usr/sbin/groupadd --force --gid 9702 lndreadonly

echo ""
echo "*** SWAP FILE ***"
# based on https://github.com/Stadicus/guides/blob/master/raspibolt/raspibolt_20_pi.md#moving-the-swap-file
# but just deactivating and deleting old (will be created alter when user adds HDD)

sudo dphys-swapfile swapoff
sudo dphys-swapfile uninstall

echo ""
echo "*** INCREASE OPEN FILE LIMIT ***"
# based on https://github.com/Stadicus/guides/blob/master/raspibolt/raspibolt_20_pi.md#increase-your-open-files-limit

sudo sed --in-place -i "56s/.*/*    soft nofile 128000/" /etc/security/limits.conf
sudo bash -c "echo '*    hard nofile 128000' >> /etc/security/limits.conf"
sudo bash -c "echo 'root soft nofile 128000' >> /etc/security/limits.conf"
sudo bash -c "echo 'root hard nofile 128000' >> /etc/security/limits.conf"
sudo bash -c "echo '# End of file' >> /etc/security/limits.conf"

sudo sed --in-place -i "23s/.*/session required pam_limits.so/" /etc/pam.d/common-session

sudo sed --in-place -i "25s/.*/session required pam_limits.so/" /etc/pam.d/common-session-noninteractive
sudo bash -c "echo '# end of pam-auth-update config' >> /etc/pam.d/common-session-noninteractive"

# "*** BITCOIN ***"
# based on https://github.com/Stadicus/guides/blob/master/raspibolt/raspibolt_30_bitcoin.md#installation

echo ""
echo "*** PREPARING BITCOIN & Co ***"

# set version (change if update is available)
# https://bitcoincore.org/en/download/
bitcoinVersion="0.19.1"

# needed to check code signing
laanwjPGP="01EA5486DE18A882D4C2684590C8019E36C2E964"

# prepare directories
sudo rm -rf /home/admin/download
sudo -u admin mkdir /home/admin/download
cd /home/admin/download

# download, check and import signer key
sudo -u admin wget https://bitcoin.org/laanwj-releases.asc
if [ ! -f "./laanwj-releases.asc" ]
then
  echo "!!! FAIL !!! Download laanwj-releases.asc not success."
  exit 1
fi
gpg ./laanwj-releases.asc
fingerprint=$(gpg ./laanwj-releases.asc 2>/dev/null | grep "${laanwjPGP}" -c)
if [ ${fingerprint} -lt 1 ]; then
  echo ""
  echo "!!! BUILD WARNING --> Bitcoin PGP author not as expected"
  echo "Should contain laanwjPGP: ${laanwjPGP}"
  echo "PRESS ENTER to TAKE THE RISK if you think all is OK"
  read key
fi
gpg --import ./laanwj-releases.asc

# download signed binary sha256 hash sum file and check
sudo -u admin wget https://bitcoin.org/bin/bitcoin-core-${bitcoinVersion}/SHA256SUMS.asc
verifyResult=$(gpg --verify SHA256SUMS.asc 2>&1)
goodSignature=$(echo ${verifyResult} | grep 'Good signature' -c)
echo "goodSignature(${goodSignature})"
correctKey=$(echo ${verifyResult} |  grep "using RSA key ${laanwjPGP: -16}" -c)
echo "correctKey(${correctKey})"
if [ ${correctKey} -lt 1 ] || [ ${goodSignature} -lt 1 ]; then
  echo ""
  echo "!!! BUILD FAILED --> PGP Verify not OK / signatute(${goodSignature}) verify(${correctKey})"
  exit 1
else
  echo ""
  echo "****************************************"
  echo "OK --> BITCOIN MANIFEST IS CORRECT"
  echo "****************************************"
  echo ""
fi

# get the sha256 value for the corresponding platform from signed hash sum file
if [ ${isARM} -eq 1 ] ; then
  bitcoinOSversion="arm-linux-gnueabihf"
fi
if [ ${isAARCH64} -eq 1 ] ; then
  bitcoinOSversion="aarch64-linux-gnu"
fi
if [ ${isX86_64} -eq 1 ] ; then
  bitcoinOSversion="x86_64-linux-gnu"
fi
if [ ${isX86_32} -eq 1 ] ; then
  bitcoinOSversion="i686-pc-linux-gnu"
fi
bitcoinSHA256=$(grep -i "$bitcoinOSversion" SHA256SUMS.asc | cut -d " " -f1)

echo ""
echo "*** BITCOIN v${bitcoinVersion} for ${bitcoinOSversion} ***"

# download resources
binaryName="bitcoin-${bitcoinVersion}-${bitcoinOSversion}.tar.gz"
sudo -u admin wget https://bitcoin.org/bin/bitcoin-core-${bitcoinVersion}/${binaryName}
if [ ! -f "./${binaryName}" ]
then
    echo "!!! FAIL !!! Download BITCOIN BINARY not success."
    exit 1
fi

# check binary checksum test
binaryChecksum=$(sha256sum ${binaryName} | cut -d " " -f1)
if [ "${binaryChecksum}" != "${bitcoinSHA256}" ]; then
  echo "!!! FAIL !!! Downloaded BITCOIN BINARY not matching SHA256 checksum: ${bitcoinSHA256}"
  exit 1
else
  echo ""
  echo "****************************************"
  echo "OK --> VERIFIED BITCOIN CHECKSUM CORRECT"
  echo "****************************************"
  echo ""
fi

# install
sudo -u admin tar -xvf ${binaryName}
sudo install -m 0755 -o root -g root -t /usr/local/bin/ bitcoin-${bitcoinVersion}/bin/*
sleep 3
installed=$(sudo -u admin bitcoind --version | grep "${bitcoinVersion}" -c)
if [ ${installed} -lt 1 ]; then
  echo ""
  echo "!!! BUILD FAILED --> Was not able to install bitcoind version(${bitcoinVersion})"
  exit 1
fi

# "*** LND ***"
## based on https://github.com/Stadicus/guides/blob/master/raspibolt/raspibolt_40_lnd.md#lightning-lnd
## see LND releases: https://github.com/lightningnetwork/lnd/releases
lndVersion="0.9.2-beta"

# olaoluwa
PGPpkeys="https://keybase.io/roasbeef/pgp_keys.asc"
PGPcheck="9769140D255C759B1EB77B46A96387A57CAAE94D"
# bitconner
#PGPpkeys="https://keybase.io/bitconner/pgp_keys.asc"
#PGPcheck="9C8D61868A7C492003B2744EE7D737B67FA592C7"
# Joost Jager
#PGPpkeys="https://keybase.io/joostjager/pgp_keys.asc"
#PGPcheck="D146D0F68939436268FA9A130E26BB61B76C4D3A"

# get LND resources
cd /home/admin/download

# download lnd binary checksum manifest
sudo -u admin wget -N https://github.com/lightningnetwork/lnd/releases/download/v${lndVersion}/manifest-v${lndVersion}.txt

# check if checksums are signed by lnd dev team
sudo -u admin wget -N https://github.com/lightningnetwork/lnd/releases/download/v${lndVersion}/manifest-v${lndVersion}.txt.sig
sudo -u admin wget -N -O "pgp_keys.asc" ${PGPpkeys}
gpg ./pgp_keys.asc
fingerprint=$(sudo gpg "pgp_keys.asc" 2>/dev/null | grep "${PGPcheck}" -c)
if [ ${fingerprint} -lt 1 ]; then
  echo ""
  echo "!!! BUILD WARNING --> LND PGP author not as expected"
  echo "Should contain PGP: ${PGPcheck}"
  echo "PRESS ENTER to TAKE THE RISK if you think all is OK"
  read key
fi
gpg --import ./pgp_keys.asc
sleep 3
verifyResult=$(gpg --verify manifest-v${lndVersion}.txt.sig 2>&1)
goodSignature=$(echo ${verifyResult} | grep 'Good signature' -c)
echo "goodSignature(${goodSignature})"
correctKey=$(echo ${verifyResult} | tr -d " \t\n\r" | grep "${GPGcheck}" -c)
echo "correctKey(${correctKey})"
if [ ${correctKey} -lt 1 ] || [ ${goodSignature} -lt 1 ]; then
  echo ""
  echo "!!! BUILD FAILED --> LND PGP Verify not OK / signature(${goodSignature}) verify(${correctKey})"
  exit 1
else
  echo ""
  echo "****************************************"
  echo "OK --> SIGNATURE LND MANIFEST IS CORRECT"
  echo "****************************************"
  echo ""
fi

# get the lndSHA256 for the corresponding platform from manifest file
if [ ${isARM} -eq 1 ] ; then
  lndOSversion="armv7"
  lndSHA256=$(grep -i "linux-$lndOSversion" manifest-v$lndVersion.txt | cut -d " " -f1)
fi
if [ ${isAARCH64} -eq 1 ] ; then
  lndOSversion="arm64"
  lndSHA256=$(grep -i "linux-$lndOSversion" manifest-v$lndVersion.txt | cut -d " " -f1)
fi
if [ ${isX86_64} -eq 1 ] ; then
  lndOSversion="amd64"
  lndSHA256=$(grep -i "linux-$lndOSversion" manifest-v$lndVersion.txt | cut -d " " -f1)
fi
if [ ${isX86_32} -eq 1 ] ; then
  lndOSversion="386"
  lndSHA256=$(grep -i "linux-$lndOSversion" manifest-v$lndVersion.txt | cut -d " " -f1)
fi

echo ""
echo "*** LND v${lndVersion} for ${lndOSversion} ***"
echo "SHA256 hash: $lndSHA256"
echo ""

# get LND binary
binaryName="lnd-linux-${lndOSversion}-v${lndVersion}.tar.gz"
sudo -u admin wget -N https://github.com/lightningnetwork/lnd/releases/download/v${lndVersion}/${binaryName}

# check binary was not manipulated (checksum test)
binaryChecksum=$(sha256sum ${binaryName} | cut -d " " -f1)
if [ "${binaryChecksum}" != "${lndSHA256}" ]; then
  echo "!!! FAIL !!! Downloaded LND BINARY not matching SHA256 checksum: ${lndSHA256}"
  exit 1
else
  echo ""
  echo "****************************************"
  echo "OK --> VERIFIED LND CHECKSUM IS CORRECT"
  echo "****************************************"
  echo ""
fi

# install
sudo -u admin tar -xzf ${binaryName}
sudo install -m 0755 -o root -g root -t /usr/local/bin lnd-linux-${lndOSversion}-v${lndVersion}/*
sleep 3
installed=$(sudo -u admin lnd --version)
if [ ${#installed} -eq 0 ]; then
  echo ""
  echo "!!! BUILD FAILED --> Was not able to install LND"
  exit 1
fi

# prepare python for lnd api use
# https://dev.lightning.community/guides/python-grpc/

echo ""
echo "*** LND API for Python ***"
sudo chown -R admin /home/admin

# This Python3 virtualenv includes the site-packages because access to the PyQt5
# libs - which are installed system-wide (via apt-get) - is needed for TouchUI.
sudo -u admin bash -c "cd; python3 -m venv --system-site-packages python3-env-lnd"
sudo -u admin bash -c "/home/admin/python3-env-lnd/bin/python3 -m pip install grpcio grpcio-tools googleapis-common-protos pathlib2"
echo ""

echo ""
echo "*** RASPIBLITZ EXTRAS ***"

# for setup schell scripts
sudo apt-get -y install dialog bc

# enable copy of blockchain from 2nd HDD formatted with exFAT
sudo apt-get -y install exfat-fuse

# for blockchain torrent download
sudo apt-get -y install transmission-cli
sudo apt-get -y install rtorrent
sudo apt-get -y install cpulimit

# for background downloading
sudo apt-get -y install screen

# for multiple (detachable/background) sessions when using SSH
# https://github.com/rootzoll/raspiblitz/issues/990
sudo apt-get -y install tmux

# optimization for torrent download
sudo bash -c "echo 'net.core.rmem_max = 4194304' >> /etc/sysctl.conf"
sudo bash -c "echo 'net.core.wmem_max = 1048576' >> /etc/sysctl.conf"

# install a command-line fuzzy finder (https://github.com/junegunn/fzf)
sudo apt-get -y install fzf
sudo bash -c "echo 'source /usr/share/doc/fzf/examples/key-bindings.bash' >> /home/admin/.bashrc"

# *** SHELL SCRIPTS AND ASSETS

# move files from gitclone
cd /home/admin/
sudo -u admin git clone -b ${wantedBranch} https://github.com/${githubUser}/raspiblitz.git
sudo -u admin cp /home/admin/raspiblitz/home.admin/*.* /home/admin
sudo -u admin cp /home/admin/raspiblitz/home.admin/.tmux.conf /home/admin
sudo -u admin chmod +x *.sh
sudo -u admin cp -r /home/admin/raspiblitz/home.admin/assets /home/admin/
sudo -u admin cp -r /home/admin/raspiblitz/home.admin/config.scripts /home/admin/
sudo -u admin chmod +x /home/admin/config.scripts/*.sh

# make sure lndlibs are patched for compatibility for both Python2 and Python3
if ! grep -Fxq "from __future__ import absolute_import" /home/admin/config.scripts/lndlibs/rpc_pb2_grpc.py; then
  sed -i -E '1 a from __future__ import absolute_import' /home/admin/config.scripts/lndlibs/rpc_pb2_grpc.py
fi

if ! grep -Eq "^from . import.*" /home/admin/config.scripts/lndlibs/rpc_pb2_grpc.py; then
  sed -i -E 's/^(import.*_pb2)/from . \1/' /home/admin/config.scripts/lndlibs/rpc_pb2_grpc.py
fi

# add /sbin to path for all
sudo bash -c "echo 'PATH=\$PATH:/sbin' >> /etc/profile"

# bash autostart for admin
sudo bash -c "echo '# shortcut commands' >> /home/admin/.bashrc"
sudo bash -c "echo 'source /home/admin/_commands.sh' >> /home/admin/.bashrc"
sudo bash -c "echo '# automatically start main menu for admin unless' >> /home/admin/.bashrc"
sudo bash -c "echo '# when running in a tmux session' >> /home/admin/.bashrc"
sudo bash -c "echo 'if [ -z \"\$TMUX\" ]; then' >> /home/admin/.bashrc"
sudo bash -c "echo '    ./00raspiblitz.sh' >> /home/admin/.bashrc"
sudo bash -c "echo 'fi' >> /home/admin/.bashrc"

if [ "${baseImage}" = "raspbian" ] || [ "${baseImage}" = "armbian" ] || [ "${baseImage}" = "ubuntu" ]; then
  # bash autostart for pi
  # run as exec to dont allow easy physical access by keyboard
  # see https://github.com/rootzoll/raspiblitz/issues/54
  sudo bash -c 'echo "# automatic start the LCD info loop" >> /home/pi/.bashrc'
  sudo bash -c 'echo "SCRIPT=/home/admin/00infoLCD.sh" >> /home/pi/.bashrc'
  sudo bash -c 'echo "# replace shell with script => logout when exiting script" >> /home/pi/.bashrc'
  sudo bash -c 'echo "exec \$SCRIPT" >> /home/pi/.bashrc'
fi

if [ "${baseImage}" = "dietpi" ]; then
  # bash autostart for dietpi
  sudo bash -c 'echo "# automatic start the LCD info loop" >> /home/dietpi/.bashrc'
  sudo bash -c 'echo "SCRIPT=/home/admin/00infoLCD.sh" >> /home/dietpi/.bashrc'
  sudo bash -c 'echo "# replace shell with script => logout when exiting script" >> /home/dietpi/.bashrc'
  sudo bash -c 'echo "exec \$SCRIPT" >> /home/dietpi/.bashrc'
fi

echo ""
echo "*** HARDENING ***"
# based on https://stadicus.github.io/RaspiBolt/raspibolt_21_security.html

# fail2ban (no config required)
#### sudo apt-get install -y --no-install-recommends python3-systemd fail2ban

if [ "${baseImage}" = "raspbian" ]; then
  echo ""
  echo "*** DISABLE BLUETOOTH ***"

  # disable bluetooth module
  sudo sh -c "echo 'dtoverlay=pi3-disable-bt' >> /boot/config.txt"
  sudo sh -c "echo 'dtoverlay=disable-bt' >> /boot/config.txt"

  # remove bluetooth services
  sudo systemctl disable bluetooth.service
  sudo systemctl disable hciuart.service

  # remove bluetooth packages
  sudo apt remove -y --purge pi-bluetooth bluez bluez-firmware
fi

# *** BOOTSTRAP ***
# see background README for details
echo ""
echo "*** RASPI BOOSTRAP SERVICE ***"
sudo chmod +x /home/admin/_bootstrap.sh
sudo cp ./assets/bootstrap.service /etc/systemd/system/bootstrap.service
sudo systemctl enable bootstrap

# *** BACKGROUND ***
echo ""
echo "*** RASPI BACKGROUND SERVICE ***"
sudo chmod +x /home/admin/_background.sh
sudo cp ./assets/background.service /etc/systemd/system/background.service
sudo systemctl enable background

# *** TOR Prepare ***
echo "*** Prepare TOR source+keys ***"
sudo /home/admin/config.scripts/internet.tor.sh prepare
echo ""

# *** RASPIBLITZ LCD DRIVER (do last - because makes a reboot) ***
# based on https://www.elegoo.com/tutorial/Elegoo%203.5%20inch%20Touch%20Screen%20User%20Manual%20V1.00.2017.10.09.zip
#echo "*** LCD DRIVER ***"
#
#echo "--> Downloading LCD Driver from Github"
#cd /home/admin/
#sudo -u admin git clone https://github.com/goodtft/LCD-show.git
#sudo -u admin chmod -R 755 LCD-show
#sudo -u admin chown -R admin:admin LCD-show
#cd LCD-show/
# set comit hard to old version - that seemed to run better
#
#sudo -u admin git reset --hard ce52014

# install xinput calibrator package
#  echo "--> install xinput calibrator package"
#sudo dpkg -i xinput-calibrator_0.7.5-1_armhf.deb

# make dietpi preparations
#if [ "${baseImage}" = "dietpi" ]; then
#  echo "--> dietpi preparations"
#  sudo rm -rf /etc/X11/xorg.conf.d/40-libinput.conf
#  sudo mkdir /etc/X11/xorg.conf.d
#  sudo cp ./usr/tft35a-overlay.dtb /boot/overlays/
#  sudo cp ./usr/tft35a-overlay.dtb /boot/overlays/tft35a.dtbo
#  sudo cp -rf ./usr/99-calibration.conf-35  /etc/X11/xorg.conf.d/99-calibration.conf
#  sudo cp -rf ./usr/99-fbturbo.conf  /usr/share/X11/xorg.conf.d/
#  sudo cp ./usr/cmdline.txt /DietPi/
#  sudo cp ./usr/inittab /etc/
#  sudo cp ./boot/config-35.txt /DietPi/config.txt
  # make LCD screen rotation correct
#  sudo sed -i "s/dtoverlay=tft35a/dtoverlay=tft35a:rotate=270/" /DietPi/config.txt
# fi

# *** RASPIBLITZ IMAGE READY ***
echo ""
echo "**********************************************"
echo "SD CARD BUILD DONE"
echo "**********************************************"
echo ""
echo "Your SD Card Image for RaspiBlitz is almost ready."
echo "Last step is to install LCD drivers. This will reboot your Pi when done."
echo ""
echo "Take the chance & look thru the output above if you can spot any errror."
echo ""
echo "After final reboot - your SD Card Image is ready."
echo ""
echo "IMPORTANT IF WANT TO MAKE A RELEASE IMAGE FROM THIS BUILD:"
echo "login once after reboot without external HDD/SSD and run 'XXprepareRelease.sh'"
echo "REMEMBER for login now use --> user:admin password:raspiblitz"
echo ""

# activate LCD and trigger reboot
# dont do this on dietpi to allow for automatic build
#if [ "${baseImage}" != "dietpi" ]; then
#  sudo chmod +x -R /home/admin/LCD-show
#  cd /home/admin/LCD-show/
#  sudo apt-mark hold raspberrypi-bootloader
#  sudo ./LCD35-show
#fi
