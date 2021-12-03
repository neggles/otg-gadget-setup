#!/usr/bin/env bash
# copies the setup script into place and sets up systemd unit
# config:
SCRIPTNAME=${1:-'gadget-setup'}
PREFIX="/usr/local"
UNITNAME="gadget.service"

### processing
set -e

function sedPath {
    SED_PATH=$((echo $1|sed -r 's/([\$\.\*\/\[\\^])/\\\1/g'|sed 's/[]]/\[]]/g')>&1)
} #Escape path for use with sed

# calculate source and dst paths
SRCFILE="./src/${SCRIPTNAME}"
DSTFILE="${PREFIX}/bin/gadget-setup"
# same for systemd unit
SRCUNIT="./src/${UNITNAME}"
DSTUNIT="/etc/systemd/system/${UNITNAME}"

if [[ -f $SRCFILE ]]; then
    echo "Copying $SRCFILE to $DSTFILE and setting permissions"
    sudo cp "$SRCFILE" "$DSTFILE"
    sudo chmod a+x "$DSTFILE"
else
    echo "Error: unable to find $SRCFILE - bailing out..."
    exit 1
fi

if [[ -f $SRCUNIT ]]; then
    echo "Copying systemd unit from $SRCUNIT to $DSTUNIT and reloading systemd"
    sudo cp "$SRCUNIT" "$DSTUNIT"
    sedPath "${DSTFILE}"
    sudo sed -i "s/ExecStart=/ExecStart=$SED_PATH/" "$DSTUNIT"
    sudo systemctl daemon-reload
    echo "Enabling systemd unit..."
    sudo systemctl enable $UNITNAME
else
    echo "Error: unable to find $SRCUNIT - bailing out..."
    exit 1
fi

echo "Done! Start the service with ` systemctl start $UNITNAME ` to enable, or it will start automatically on boot."
exit 0
