#!/bin/bash

#**************************************************************************************************
# WebPageTest agent installation script for Debian-based systems.
# Tested with Ubuntu 18.04+ and Raspbian Buster+
# For headless operation options can be specified in the environment before launching the script:
#**************************************************************************************************
# bash <(curl -s https://raw.githubusercontent.com/HTTPArchive/wptagent-install/master/debian.sh)
#

#**************************************************************************************************
# Configure Defaults
#**************************************************************************************************

set -eu
: ${WPT_KEY:=''}

#**************************************************************************************************
# Prompt for options
#**************************************************************************************************

# Prompt for the configuration options
echo "Installing and configuring WebPageTest agent..."
echo

# Pre-prompt for the sudo authorization so it doesn't prompt later
sudo date

# Make sure sudo doesn't prompt for a password
echo "${USER} ALL=(ALL:ALL) NOPASSWD:ALL" | sudo tee "/etc/sudoers.d/wptagent"

cd ~
until sudo apt -y update
do
    sleep 1
done

# system config
until sudo apt -y install git screen watchdog curl wget apt-transport-https xserver-xorg-video-dummy gnupg2
do
    sleep 1
done

until sudo DEBIAN_FRONTEND=noninteractive apt -yq -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" dist-upgrade
do
    sleep 1
done

#**************************************************************************************************
# Agent code
#**************************************************************************************************

cd ~
rm -rf wptagent
until git clone --branch=haprod https://github.com/HTTPArchive/wptagent.git
do
    sleep 1
done

#**************************************************************************************************
# Custom metrics
#**************************************************************************************************
git clone https://github.com/HTTPArchive/custom-metrics.git
mkdir ~/wptagent/custom
mkdir ~/wptagent/custom/metrics
cp ~/custom-metrics/dist/*.js ~/wptagent/custom/metrics/

#**************************************************************************************************
# OS Packages
#**************************************************************************************************

# Node JS
curl -sL https://deb.nodesource.com/setup_16.x | sudo -E bash -

# Agent dependencies
echo ttf-mscorefonts-installer msttcorefonts/accepted-mscorefonts-eula select true | sudo debconf-set-selections
until sudo apt -y install python python3 python3-pip python3-ujson \
        imagemagick dbus-x11 traceroute software-properties-common psmisc libnss3-tools iproute2 net-tools openvpn \
        libtiff5-dev libjpeg-dev zlib1g-dev libfreetype6-dev liblcms2-dev libwebp-dev tcl8.6-dev tk8.6-dev python3-tk \
        python3-dev libavutil-dev libmp3lame-dev libx264-dev yasm autoconf automake build-essential libass-dev libfreetype6-dev libtheora-dev \
        libtool libvorbis-dev pkg-config texi2html libtext-unidecode-perl python3-numpy python3-scipy \
        adb ethtool nodejs cmake git-core libsdl2-dev libva-dev libvdpau-dev libxcb1-dev libxcb-shm0-dev libxcb-xfixes0-dev texinfo wget \
        ttf-mscorefonts-installer fonts-noto fonts-roboto fonts-open-sans ffmpeg
do
    sleep 1
done

sudo dbus-uuidgen --ensure
sudo fc-cache -f -v

# Lighthouse
until sudo npm install -g lighthouse
do
    sleep 1
done
sudo npm update -g

#**************************************************************************************************
# Python Modules
#**************************************************************************************************
until sudo pip3 install dnspython monotonic pillow psutil requests tornado wsaccel brotli fonttools selenium future usbmuxwrapper
do
    sleep 1
done

#**************************************************************************************************
# Browser Install
#**************************************************************************************************
wget -q -O - https://dl.google.com/linux/linux_signing_key.pub | sudo apt-key add -
sudo sh -c 'echo "deb http://dl.google.com/linux/chrome/deb/ stable main" >> /etc/apt/sources.list.d/google.list'
until sudo apt -y update
do
    sleep 1
done
until sudo apt -yq install google-chrome-stable
do
    sleep 1
done

#**************************************************************************************************
# OS Config
#**************************************************************************************************

# Disable the built-in automatic updates
sudo apt -y remove unattended-upgrades

# Clean-up apt
sudo apt -y autoremove

# Minimize the space for systemd journals
sudo mkdir --mode=755 /etc/systemd/journald.conf.d || true
echo 'SystemMaxUse=1M' | sudo tee /etc/systemd/journald.conf.d/wptagent.conf
sudo systemctl restart systemd-journald

# Reboot when out of memory
cat << _SYSCTL_ | sudo tee /etc/sysctl.d/60-wptagent-dedicated.conf
vm.panic_on_oom = 1
kernel.panic = 10
net.ipv4.tcp_syn_retries = 4
_SYSCTL_

# disable IPv6
cat << _SYSCTL_NO_IPV6_ | sudo tee /etc/sysctl.d/60-wptagent-no-ipv6.conf
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
_SYSCTL_NO_IPV6_

cat << _LIMITS_ | sudo tee /etc/security/limits.d/wptagent.conf
# Limits increased for wptagent
* soft nofile 250000
* hard nofile 300000
_LIMITS_

# configure watchdog
cd ~
echo "test-binary = $PWD/wptagent/alive3.sh" | sudo tee -a /etc/watchdog.conf

#**************************************************************************************************
# Startup Script
#**************************************************************************************************
echo '#!/bin/sh' > ~/startup.sh
echo "PATH=$PWD/bin:$PWD/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games:/usr/local/games:/snap/bin" >> ~/startup.sh
echo 'sudo DEBIAN_FRONTEND=noninteractive apt update -yq' >> ~/startup.sh
echo 'sudo DEBIAN_FRONTEND=noninteractive apt install ca-certificates -yq' >> ~/startup.sh
echo 'cd ~' >> ~/startup.sh
echo 'if [ -e first.run ]' >> ~/startup.sh
echo 'then' >> ~/startup.sh
echo '    screen -dmS init ~/firstrun.sh' >> ~/startup.sh
echo 'else' >> ~/startup.sh
echo '    screen -dmS agent ~/agent.sh' >> ~/startup.sh
echo 'fi' >> ~/startup.sh
echo 'sudo service watchdog restart' >> ~/startup.sh
chmod +x ~/startup.sh

#**************************************************************************************************
# First-run Script (reboot the first time after starting if ~/first.run file exists)
#**************************************************************************************************
echo '#!/bin/sh' > ~/firstrun.sh
echo 'cd ~' >> ~/firstrun.sh
echo 'until sudo apt -y update' >> ~/firstrun.sh
echo 'do' >> ~/firstrun.sh
echo '    sleep 1' >> ~/firstrun.sh
echo 'done' >> ~/firstrun.sh
echo 'until sudo DEBIAN_FRONTEND=noninteractive apt install ca-certificates -yq' >> ~/firstrun.sh
echo 'do' >> ~/firstrun.sh
echo '    sleep 1' >> ~/firstrun.sh
echo 'done' >> ~/firstrun.sh
echo 'until sudo DEBIAN_FRONTEND=noninteractive apt -yq -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" dist-upgrade' >> ~/firstrun.sh
echo 'do' >> ~/firstrun.sh
echo '    sleep 1' >> ~/firstrun.sh
echo 'done' >> ~/firstrun.sh
echo 'rm ~/first.run' >> ~/firstrun.sh
echo 'sudo reboot' >> ~/firstrun.sh
chmod +x ~/firstrun.sh

#**************************************************************************************************
# Agent Script
#**************************************************************************************************

# build the agent script
KEY_OPTION=''
if [ $WPT_KEY != '' ]; then
  KEY_OPTION="--key $WPT_KEY"
fi
echo '#!/bin/sh' > ~/agent.sh

echo 'export DEBIAN_FRONTEND=noninteractive' >> ~/agent.sh
echo 'cd ~/wptagent' >> ~/agent.sh

# Wait for networking to become available and update the package list
echo 'sleep 10' >> ~/agent.sh

# Browser Certificates
echo 'echo "Updating browser certificates"' >> ~/agent.sh
echo 'wget -q -O - https://dl.google.com/linux/linux_signing_key.pub | sudo apt-key add -' >> ~/agent.sh

# OS Update
echo 'until sudo apt -y update' >> ~/agent.sh
echo 'do' >> ~/agent.sh
echo '    sleep 1' >> ~/agent.sh
echo 'done' >> ~/agent.sh
echo 'echo "Updating OS"' >> ~/agent.sh
echo 'until sudo DEBIAN_FRONTEND=noninteractive apt -yq -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" dist-upgrade' >> ~/agent.sh
echo 'do' >> ~/agent.sh
echo '    sudo apt -f install' >> ~/agent.sh
echo '    sleep 1' >> ~/agent.sh
echo 'done' >> ~/agent.sh

# Lighthouse Update
echo 'sudo npm i -g lighthouse' >> ~/agent.sh

# Dummy X display
echo 'export DISPLAY=:1' >> ~/agent.sh
echo 'Xorg -noreset +extension GLX +extension RANDR +extension RENDER -logfile /dev/null -config ./misc/xorg.conf :1 &' >> ~/agent.sh

echo 'for i in `seq 1 24`' >> ~/agent.sh
echo 'do' >> ~/agent.sh

# Update the custom metrics
echo "    cd ~/custom-metrics" >> ~/agent.sh
echo "    git pull origin main" >> ~/agent.sh
echo "    rm -rf ~/wptagent/custom/metrics" >> ~/agent.sh
echo "    mkdir ~/wptagent/custom/metrics" >> ~/agent.sh
echo "    cp ~/custom-metrics/dist/*.js ~/wptagent/custom/metrics/" >> ~/agent.sh

# Update the agent
echo "    cd ~/wptagent" >> ~/agent.sh
echo "    git pull origin haprod" >> ~/agent.sh

# Agent invocation
echo "    python3 wptagent.py -vvvv --server \"https://webpagetest.httparchive.org/work/\" --location \"California,California2\" $KEY_OPTION --exit 60 --alive /tmp/wptagent" >> ~/agent.sh

echo '    echo "Exited, restarting"' >> ~/agent.sh
echo '    sleep 10' >> ~/agent.sh
echo 'done' >> ~/agent.sh

# OS Update (again, just before reboot)
echo 'until sudo apt -y update' >> ~/agent.sh
echo 'do' >> ~/agent.sh
echo '    sleep 1' >> ~/agent.sh
echo 'done' >> ~/agent.sh
echo 'echo "Updating OS"' >> ~/agent.sh
echo 'until sudo DEBIAN_FRONTEND=noninteractive apt -yq -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" dist-upgrade' >> ~/agent.sh
echo 'do' >> ~/agent.sh
echo '    sudo apt -f install' >> ~/agent.sh
echo '    sleep 1' >> ~/agent.sh
echo 'done' >> ~/agent.sh

echo 'sudo apt -y autoremove' >> ~/agent.sh
echo 'sudo apt clean' >> ~/agent.sh
echo 'sudo reboot' >> ~/agent.sh

chmod +x ~/agent.sh

#**************************************************************************************************
# Finish
#**************************************************************************************************

# Overwrite the existing user crontab
echo "@reboot ${PWD}/startup.sh" | crontab -

# Allow X to be started within the screen session
sudo sed -i 's/allowed_users=console/allowed_users=anybody/g' /etc/X11/Xwrapper.config || true
sudo systemctl set-default multi-user

echo
echo "Install is complete.  Please reboot the system to start testing (sudo reboot)"
