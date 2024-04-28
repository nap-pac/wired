#!/bin/bash

# |==========================|
# | Setup Script for Destiny |
# |    Prepared by Sean M    |
# |      Version 1.0.4       |
# | Last Updated: 2023-02-20 |
# |==========================|

curPhase=1
totalPhases=1

# Using phases to notify user of progress
logPhase() {
    echo "[$curPhase/$totalPhases]: $1"
    curPhase=$((curPhase+1))
}

# check if user would like to proceed
# read -p 'Would you like to proceed with the setup? [Y/N]: ' proceed
# if [ "$proceed" = "N" ] || [ "$proceed" = "n" ] || [ "$proceed" = "no" ] || [ "$proceed" = "No" ]; then
#     echo "Exiting..."
#     exit 1
# fi

# user must be root to run this script
if [ "$EUID" -ne 0 ]
  then echo "Please run as root"
  exit
fi

enableAutoLogin() {
    logPhase "Enabling auto login..."
    # check if set to root
    sudo sed -i 's/autologin-user=root/autologin-user=/g' /etc/lightdm/lightdm.conf
    # set to $USER
    sudo sed -i "s/autologin-user=/autologin-user=$USER/g" /etc/lightdm/lightdm.conf
    logPhase "Auto login enabled for user: $USER"
}

# install drivers
touchscreenDriverInstall() {
    # https://learn.adafruit.com/adafruit-pitft-28-inch-resistive-touchscreen-display-raspberry-pi/easy-install-2
    logPhase "Installing touchscreen drivers..."
    sudo pip3 install --upgrade adafruit-python-shell click
    git clone https://github.com/adafruit/Raspberry-Pi-Installer-Scripts.git
    sudo python3 Raspberry-Pi-Installer-Scripts/adafruit-pitft.py --display=28c --rotation=180 --install-type=fbcp --reboot=no
}

# uninstall touchscreen drivers
touchscreenDriverUninstall() {
    logPhase "Uninstalling touchscreen drivers..."
    # check if dir exists
    if [ -d "Raspberry-Pi-Installer-Scripts" ]; then
        sudo python3 Raspberry-Pi-Installer-Scripts/adafruit-pitft.py --install-type=uninstall --reboot=yes
    else 
        echo "Directory: 'Raspberry-Pi-Installer-Scripts' does not exist. Are touchscreen drivers installed?"
    fi
}

adapterInstallRTL8812BU() {
    logPhase "Installing DKMS..."
    sudo apt-get install dkms -y
    logPhase "Installing RTL8812BU drivers with DKMS..."
    sudo git clone "https://github.com/RinCat/RTL88x2BU-Linux-Driver.git" /usr/src/rtl88x2bu-git
    sudo sed -i 's/PACKAGE_VERSION="@PKGVER@"/PACKAGE_VERSION="git"/g' /usr/src/rtl88x2bu-git/dkms.conf
    sudo dkms add -m rtl88x2bu -v git
    sudo dkms autoinstall
    logPhase "DKMS status..."
    if sudo dkms status | grep -q "rtl88x2bu"; then
        echo "DKMS status... OK"
        echo "Rebooting..."
        sudo reboot
    else
        echo "DKMS status... FAIL"
        echo "Please check the output of 'sudo dkms status'"
        exit 1
    fi
}

# https://github.com/aircrack-ng/rtl8812au
# wireless adapter
adapterInstallRTL8812AU() {
    # check for /usr/src/$(uname -r) directory
    if [ -d "/usr/src/linux-headers-$(uname -r)" ]; then
        echo "Checking /usr/src/linux-headers-$(uname -r)... OK" 
    else 
        echo "Checking /usr/src/linux-headers-$(uname -r)... FAIL"
        echo "Please update kernel and install headers before running this"
        exit 1
    fi

    logPhase "Cloning RTL8812AU drivers..."
    git clone -b v5.6.4.2 https://github.com/aircrack-ng/rtl8812au.git
    cd rtl8812au
    sudo sed -i 's/CONFIG_PLATFORM_I386_PC = y/CONFIG_PLATFORM_I386_PC = n/g' Makefile
    sudo sed -i 's/CONFIG_PLATFORM_ARM_RPI = n/CONFIG_PLATFORM_ARM_RPI = y/g' Makefile
    # sudo sed -i 's/CONFIG_PLATFORM_ARM_RPI64 = n/CONFIG_PLATFORM_ARM_RPI64 = y/g' Makefile
    logPhase "Building RTL8812AU drivers..."
    make
    make install
    # sudo cp 88XXau.ko /lib/modules/$(uname -r)/kernel/drivers/net/wireless
    # sudo depmod -a
    # sudo modprobe -a 88XXau
    logPhase "Installing DKMS..."
    sudo apt-get install dkms -y
    logPhase "Installing RTL8812AU drivers with DKMS..."
    sudo make dkms_install
    cd ..

    logPhase "Configuring RTL8812AU drivers..."
    # create file in /etc/modprobe.d/88XXau.conf
    # check if file already exists
    if [ -f "/etc/modprobe.d/88XXau.conf" ]; then
        echo "File: /etc/modprobe.d/88XXau.conf already exists. Skipping..."
    else 
        echo "options 88XXau rtw_switch_usb_mode=0" | sudo tee /etc/modprobe.d/88XXau.conf
        echo "# (0: no switch 1: switch from usb2 to usb3 2: switch from usb3 to usb2)" | sudo tee -a /etc/modprobe.d/88XXau.conf
    fi
    # edit /etc/modules
    # check if 88XXau is already in file
    if grep -q "88XXau" "/etc/modules"; then
        echo "88XXau already in /etc/modules. Skipping..."
    else 
        echo "88XXau" | sudo tee -a /etc/modules
    fi 

    logPhase "Checking RTL8812AU drivers..."
    # check if driver is installed
    if [ -f "/lib/modules/$(uname -r)/kernel/drivers/net/wireless/88XXau.ko" ]; then
        echo "Checking /lib/modules/$(uname -r)/kernel/drivers/net/wireless/88XXau.ko... OK"
    else
        echo "Checking /lib/modules/$(uname -r)/kernel/drivers/net/wireless/88XXau.ko... FAIL"
        echo "Something went wrong. Please check the output above for errors."
        exit 1
    fi

    # dkms status check for 88XXau
    if dkms status | grep -q "88XXau"; then
        echo "Checking dkms status for 88XXau... OK"
    else
        echo "Checking dkms status for 88XXau... FAIL"
        echo "Something went wrong. Please check the output above for errors."
        exit 1
    fi

    logPhase "RTL8812AU drivers installed successfully! Rebooting..."
    sudo reboot

}

# kismet install - this is the one that I used with Pi 4 Model B+ Kernal 5.15.84-v7l+
kismetInstall() {
    logPhase "Adding Kismet repository..."
    wget -O - https://www.kismetwireless.net/repos/kismet-release.gpg.key | sudo apt-key add -
    echo 'deb https://www.kismetwireless.net/repos/apt/release/bullseye bullseye main' | sudo tee /etc/apt/sources.list.d/kismet.list
    sudo apt update
    logPhase "Installing Kismet..."
    sudo apt install kismet -y
    # yes to suid prompt
}

# if buster is installed then use this
kismetBusterInstall() {
    logPhase "Adding Kismet repository..."
    wget -O - https://www.kismetwireless.net/repos/kismet-release.gpg.key | sudo apt-key add -
    echo 'deb https://www.kismetwireless.net/repos/apt/git/buster buster main' | sudo tee /etc/apt/sources.list.d/kismet.list
    sudo apt update
    logPhase "Installing Kismet..."
    sudo apt install kismet -y
}

kismetPostInstall() {
    logPhase "Creating kismet logs directory..."
    sudo mkdir /home/$USER/kismet_logs
    sudo chown $USER:$USER /home/$USER/kismet_logs
    logPhase "Editing kismet config files..."
    # check if kismet_logging.conf already has log_prefix=/home/$USER/kismet_logs/
    if grep -q "log_prefix=/home/$USER/kismet_logs/" "/etc/kismet/kismet_logging.conf"; then
        echo "log_prefix=/home/$USER/kismet_logs/ already in /etc/kismet/kismet_logging.conf. Skipping..."
    else 
        sudo sed -i 's/log_prefix=.\//log_prefix=\/home\/'$USER'\/kismet_logs\//g' /etc/kismet/kismet_logging.conf
    fi
    # add source=wlan1:type=linuxwifi to the end of kismet.conf
    if grep -q "source=wlan1:type=linuxwifi" "/etc/kismet/kismet.conf"; then
        echo "source=wlan1:type=linuxwifi already in /etc/kismet/kismet.conf. Skipping..."
    else 
        echo "source=wlan1:type=linuxwifi" | sudo tee -a /etc/kismet/kismet.conf
    fi
    # add source=hci0:type=bluetooth to the end of kismet.conf
    # though this is not completely passive, as the bluetooth adapter will be in discoverable mode
    # if grep -q "source=hci0:type=bluetooth" "/etc/kismet/kismet.conf"; then
        # echo "source=hci0:type=bluetooth already in /etc/kismet/kismet.conf. Skipping..."
    # else 
        # echo "source=hci0:type=bluetooth" | sudo tee -a /etc/kismet/kismet.conf
    # fi
    # add gps to kismet.conf gps=gpsd:host=localhost,port=2947
    if grep -q "gps=gpsd:host=localhost,port=2947" "/etc/kismet/kismet.conf"; then
        echo "gps=gpsd:host=localhost,port=2947 already in /etc/kismet/kismet.conf. Skipping..."
    else 
        echo "gps=gpsd:host=localhost,port=2947" | sudo tee -a /etc/kismet/kismet.conf
    fi

    # add user to kismet group
    logPhase "Adding user to kismet group..."
    sudo usermod -aG kismet $USER
    logPhase "Kismet installed successfully! Rebooting..."
    sudo reboot
}

# install hackrf
hackrfInstall() {
    # version I used to develop the software is 2022.09.1
    hackRFVersion="2022.09.1"

    # checking hackrf version as updates may be available
    wget "https://api.github.com/repos/greatscottgadgets/hackrf/releases?per_page=1" -O hackrf.json -q
    hackRFVersionLatest=$(cat hackrf.json | grep tag_name | cut -d '"' -f 4 | cut -d 'v' -f 2)
    if [ "$hackRFVersionLatest" != "$hackRFVersion" ]; then
        echo "NOTE: There is a newer version of hackrf available: $hackRFVersionLatest (current version is $hackRFVersion)"
        read -p 'Would you like to install the latest version? [Y/N]: ' hackRFInstallLatest
        if [ "$hackRFInstallLatest" = "Y" ] || [ "$hackRFInstallLatest" = "y" ] || [ "$hackRFInstallLatest" = "yes" ] || [ "$hackRFInstallLatest" = "Yes" ]; then
            hackRFVersion=$hackRFVersionLatest
        fi
    fi

    # remove json file
    rm hackrf.json

    # check if directory already exists
    if [ -d "hackrf-$hackRFVersion" ]; then
        echo "Directory hackrf-$hackRFVersion already exists. Skipping..."
    else 
        logPhase "Purging old hackrf libraries..."
        sudo apt-get remove --purge libhackrf0 hackrf

        logPhase "Downloading hackrf tools version $hackRFVersion..."
        wget "https://github.com/greatscottgadgets/hackrf/releases/download/v$hackRFVersion/hackrf-$hackRFVersion.tar.xz"
        tar -xvf "hackrf-$hackRFVersion.tar.xz"
        cd "hackrf-$hackRFVersion/host"

        logPhase "Building hackrf tools..."
        mkdir build
        cd build
        cmake ..
        make

        logPhase "Installing hackrf tools..."
        sudo make install
        sudo ldconfig

        logPhase "Testing hackrf..."
        hackrf_info 
        
        cd ../../..
    fi
}

# install gps
gpsIntall() {
    logPhase "Installing GPS tools..."
    # https://wiki.52pi.com/index.php/EZ-0048
    sudo apt-get -y install gpsd gpsd-clients
    # edit /etc/default/gpsd
    # ask if USB or UART
    read -p 'Is your GPS connected via USB or SERIAL/UART? [U/S]: ' gpsConnection
    if [ "$gpsConnection" = "U" ] || [ "$gpsConnection" = "u" ] || [ "$gpsConnection" = "usb" ] || [ "$gpsConnection" = "USB" ]; then
        # if serial was previously set, remove it
        sudo sed -i 's/DEVICES="dev\/serial0"/DEVICES=""/g' /etc/default/gpsd
        # set usb
        sudo sed -i 's/DEVICES=""/DEVICES="dev\/ttyUSB0"/g' /etc/default/gpsd
    elif [ "$gpsConnection" = "S" ] || [ "$gpsConnection" = "s" ] || [ "$gpsConnection" = "serial" ] || [ "$gpsConnection" = "SERIAL" ]; then
        # set baud rate to 9600
        stty -F /dev/serial0 9600
        # if usb was previously set, remove it
        sudo sed -i 's/DEVICES="dev\/ttyUSB0"/DEVICES=""/g' /etc/default/gpsd
        # set serial
        sudo sed -i 's/DEVICES=""/DEVICES="dev\/serial0"/g' /etc/default/gpsd
    else
        echo "Invalid input. Skipping... (you can also manually edit /etc/default/gpsd)"
    fi
    
    # test using: gpsmon
    logPhase "GPS tools installed. To test, run 'gpsmon'"
}

btleHackRF() {
    logPhase "Cloning BTLE repository..."
    git clone https://github.com/JiaoXianjun/BTLE.git
    cd BTLE/host
    mkdir build
    cd build
    logPhase "Building BTLE..."
    cmake ..
    make
    logPhase "Installing BTLE..."
    # add ./btle-tools/src/btle_rx to path
    export PATH=$PATH:$(pwd)/btle-tools/src
    # add ./btle-tools/src/btle_rx to path permanently via bashrc
    sh -c "echo 'export PATH=\$PATH:$(pwd)/btle-tools/src' >> /home/$USER/.bashrc"
    cd ../../..
}

updateKernel() {
    logPhase "Updating apt repositories..."
    sudo apt-get update
    logPhase "Updating raspberry pi kernel..."
    sudo apt-get install --reinstall raspberrypi-bootloader raspberrypi-kernel
    logPhase "Installing kernel headers..."
    sudo apt-get install raspberrypi-kernel-headers
    logPhase "Kernel updated. Rebooting..."
    sudo reboot
}

crontabSetup() {
    logPhase "Setting up crontab..."
    (crontab -l 2>/dev/null; echo "@reboot sleep 15 && /home/$USER/dest/wlan1_to_mon.sh &") | crontab -
    (crontab -l 2>/dev/null; echo "@reboot sleep 30 && /usr/bin/kismet &") | crontab -
    # useful for testing over ssh, though normally you would ues the desktop setup for auto start main program
    # (crontab -l 2>/dev/null; echo "@reboot sleep 45 && /home/$USER/destiny.sh &") | crontab - 
    logPhase "Crontab setup complete."
    # crontab -r (to remove all)
}

desktopSetup() {
    logPhase "Setting up auto start for desktop..."
    # /etc/xdg/autostart/display.desktop
    sudo sh -c "echo '[Desktop Entry]' > /etc/xdg/autostart/display.desktop"
    sudo sh -c "echo 'Name=destiny' >> /etc/xdg/autostart/display.desktop"
    sudo sh -c "echo 'Exec=/home/$USER/destiny.sh' >> /etc/xdg/autostart/display.desktop"
    # setup destiny.sh
    # waiting at least 35 seconds to start main program to allow time for kismet to start
    sudo sh -c "echo '/bin/sh -c \"sleep 35 ; python3 /home/$USER/dest/dest_main.py\" &' >> /home/$USER/destiny.sh"
    # change permissions so user can run
    sudo chmod +x /home/$USER/destiny.sh
    logPhase "Desktop setup complete."
}

# selection menu
echo "Destiny Setup Script"
echo "Select an option:"
echo "[1] Update kernel"
echo "[2] Install all dependencies"
echo "[3] Install RTL8812AU driver"
echo "[4] Install RTL8812BU driver"
echo "[5] Install touchscreen driver"
echo "[6] Uninstall touchscreen driver"
echo "[7] Update hackrf tools"
echo "[8] Install GPS tools"
echo "[9] Install BTLE driver"
echo "[10] Install Kismet"
echo "[11] Finalise setup"
echo "[0] Exit"
read -p 'Enter a number: ' selection

if [ "$selection" = "1" ]; then

    totalPhases=4
    updateKernel

elif [ "$selection" = "2" ]; then

    totalPhases=5

    logPhase "Installing apt packages..."
    sudo apt-get install git python3-pip libatlas-base-dev build-essential libusb-1.0-0-dev libfftw3-dev cmake libopenblas-dev gfortran libelf-dev sqlite3 -y

    logPhase "Updating pip..."
    sudo pip3 install pip --upgrade

    # install python packages
    # note numpy is pinned to 1.23.
    # if other signal processing software is installed, like urh, it may use 1.19.5
    # versions 1.19.5 and 1.23 should still behave the same for most functions
    # 1.24 removes certain numpy apis, such as np.int which is known to cause issues
    logPhase "Installing system python packages..."
    sudo python3 -m pip install numpy==1.23 matplotlib==3.5.1
    
    logPhase "Installing python packages for Destiny..."
    python3 -m pip install pygame==2.1.2 pygame-menu==4.3.6

    # scipy is used for signal processing, though not needed for the main program
    # scipy has some issues so we need to add this to the bashrc
    LD_PRELOAD=/usr/lib/arm-linux-gnueabihf/libatomic.so.1.2.0

    logPhase "Updating ~/.bashrc..."
    echo $'\n#Destiny Setup Script\n\nexport LD_PRELOAD=/usr/lib/arm-linux-gnueabihf/libatomic.so.1.2.0' >> ~/.bashrc 
    # add to root bashrc as well
    sudo sh -c "echo '\n#Destiny Setup Script\n\nexport LD_PRELOAD=/usr/lib/arm-linux-gnueabihf/libatomic.so.1.2.0' >> /root/.bashrc"

elif [ "$selection" = "3" ]; then

    totalPhases=7
    adapterInstallRTL8812AU

elif [ "$selection" = "4" ]; then

    totalPhases=3
    adapterInstallRTL8812BU

elif [ "$selection" = "5" ]; then

    totalPhases=1
    touchscreenDriverInstall

elif [ "$selection" = "6" ]; then

    totalPhases=1
    touchscreenDriverUninstall

elif [ "$selection" = "7" ]; then

    totalPhases=5
    hackrfInstall

elif [ "$selection" = "8" ]; then

    totalPhases=2
    gpsIntall

elif [ "$selection" = "9" ]; then

    totalPhases=3
    btleHackRF

elif [ "$selection" = "10" ]; then

    totalPhases=6
    # check if running bullseye or buster
    if [ $(lsb_release -cs) = "bullseye" ]; then
        kismetInstallBullseye
    elif [ $(lsb_release -cs) = "buster" ]; then
        kismetInstallBuster
    else
        echo "Unsupported/unknown raspbian version"
        exit 1
    fi
    # run post install
    kismetPostInstall

elif [ "$selection" = "11" ]; then

    totalPhases=6
    enableAutoLogin
    crontabSetup
    desktopSetup

else

    echo "Invalid selection"
    exit 1

fi

echo "Complete!"
