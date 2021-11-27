#!/bin/bash
# composite USB device setup for OTG-enabled Pis like the Zero (and the 4!)
set -euo pipefail

# point to root of configfs. this should be the same on all systems, but...
CONFIGFS="/sys/kernel/config"

# name of the device subpath in configfs/usb_gadget
G_NAME="pi"

# USB vendor/product IDs to use
G_VID='0x1d6b' # Linux Foundation
G_PID='0x0104' # Multifunction Composite Gadget
G_REV='0x0100' # v1.0.0
G_USB='0x0200' # USB 2.0

# description strings
G_LANG=0x409 # English
G_MANUFACTURER="Raspberry Pi"
G_PRODUCT=$(cat /sys/firmware/devicetree/base/model | tr -d '\0')
G_SERIALNO=$(cat /sys/firmware/devicetree/base/serial-number | tr -d '\0')

# MAC addresses to use for host/device end of the virtual eth
# first byte must be even if you don't wanna be a dick
G_HOST_MAC="1a:55:89:a2:69:42"
G_DEV_MAC="1a:55:89:a2:69:41"

### end configuration, begin execution ###
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root"
   exit 1
fi

GADGET_ROOT="${CONFIGFS}/usb_gadget"
GADGET="${GADGET_ROOT}/${G_NAME}"

# load libcomposite and wait for it
modprobe libcomposite
while [[ ! -d ${GADGET_ROOT} ]]; do
    sleep 0.1
done

if [[ -d ${GADGET} ]]; then
    echo "Cleaning up existing gadget"
    cd "$GADGET"
    echo "Stopping getty"
    systemctl stop getty@ttyGS0.service
    echo "Removing config-level functions"
    find $GADGET/configs/*/* -maxdepth 0 -type l -exec rm {} \;
    echo "Removing config-level strings"
    find $GADGET/configs/*/strings/* -maxdepth 0 -type d -exec rmdir {} \;
    echo "Removing config-level OS descriptors"
    find $GADGET/os_desc/* -maxdepth 0 -type l -exec rm {} \;
    echo "Removing gadget-level functions"
    find $GADGET/functions/* -maxdepth 0 -type d -exec rmdir {} \;
    echo "Removing gadget-level strings"
    find $GADGET/strings/* -maxdepth 0 -type d -exec rmdir {} \;
    echo "Removing gadget-level configs"
    find $GADGET/configs/* -maxdepth 0 -type d -exec rmdir {} \;
    echo "Removing gadget"
    rmdir $GADGET
fi

echo "Creating gadget"
mkdir -p $GADGET
cd $GADGET

echo "Configuring device identifiers"
echo "$G_VID" > idVendor
echo "$G_PID" > idProduct
echo "$G_REV" > bcdDevice
echo "$G_USB" > bcdUSB
mkdir "strings/$G_LANG"
echo "$G_MANUFACTURER" > "strings/$G_LANG/manufacturer"
echo "$G_PRODUCT"      > "strings/$G_LANG/product"

echo "Configuring gadget as composite device"
# https://docs.microsoft.com/en-us/windows-hardware/drivers/usbcon/usb-common-class-generic-parent-driver
echo 0xEF > bDeviceClass
echo 0x02 > bDeviceSubClass
echo 0x01 > bDeviceProtocol

echo "Configuring OS descriptors"
# https://docs.microsoft.com/en-us/windows-hardware/drivers/usbcon/microsoft-os-2-0-descriptors-specification
echo 1       > os_desc/use
echo 0xcd    > os_desc/b_vendor_code
echo MSFT100 > os_desc/qw_sign

echo "Creating RNDIS function"
mkdir functions/rndis.usb0
echo $G_HOST_MAC > functions/rndis.usb0/host_addr
echo $G_DEV_MAC  > functions/rndis.usb0/dev_addr
# https://docs.microsoft.com/en-us/windows-hardware/drivers/usbcon/microsoft-os-1-0-descriptors-specification
echo 'RNDIS'   > functions/rndis.usb0/os_desc/interface.rndis/compatible_id
echo '5162001' > functions/rndis.usb0/os_desc/interface.rndis/sub_compatible_id

echo "Creating serial function"
mkdir functions/acm.usb0

echo "Creating gadget configuration"
mkdir configs/c.1
mkdir configs/c.1/strings/$G_LANG
echo "ACM+RNDIS" > configs/c.1/strings/$G_LANG/configuration
echo 500 > configs/c.1/MaxPower
echo 128 > configs/c.1/bmAttributes

ln -s functions/rndis.usb0 configs/c.1
ln -s functions/acm.usb0 configs/c.1
ln -s configs/c.1 os_desc/c.1

echo "Attaching gadget"
udevadm settle -t 5 || true
ls /sys/class/udc/ > UDC

echo "Starting getty"
systemctl start getty@ttyGS0.service

echo "Done!"
