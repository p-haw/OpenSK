#!/usr/bin/env bash
set -e

# Check that rustup and pip3 are installed
check_command () {
  if ! which "$1" >/dev/null
  then
    echo "Missing $1 command.$2"
    exit 1
  fi
}
check_command virtualenv

SCRIPT_PATH="${0%/*}"
TARGET_PATH="${SCRIPT_PATH}/target/dfu"
TAB_PATH="${SCRIPT_PATH}/target/tab"
VENV_PATH="${SCRIPT_PATH}/target/venv"

# Init TARGET_PATH
[ -d "${TARGET_PATH}" ] && rm -rf "${TARGET_PATH}"
mkdir -p "${TARGET_PATH}"

# Init Virtualenv
if [ ! -f "${VENV_PATH}/bin/activate" ]
then
    virtualenv "${VENV_PATH}"
fi
. "${VENV_PATH}/bin/activate"

# Install nrfutil tool
pip install nrfutil -q
pip install intelhex -q

NRFUTIL="${VENV_PATH}/bin/nrfutil"
BIN2HEX="${VENV_PATH}/bin/bin2hex.py"
HEXMERGE="${VENV_PATH}/bin/hexmerge.py"

# Generate Tock OS and the OpenSK App
${SCRIPT_PATH}/deploy.py os --board nrf52840_dongle --build-only
${SCRIPT_PATH}/deploy.py app --opensk --build-only

# Generation hex files from bin
python $BIN2HEX --offset=0x01000 "${TAB_PATH}/nrf52840_dongle.bin" "${TARGET_PATH}/nrf52840_dongle.hex"
python $BIN2HEX --offset=0x30000 "${TAB_PATH}/padding.bin" "${TARGET_PATH}/padding.hex"
python $BIN2HEX --offset=0x40000 "${TAB_PATH}/cortex-m4.tbf" "${TARGET_PATH}/cortex-m4.hex"

# Merge hex files
python $HEXMERGE -o "${TARGET_PATH}/opensk.hex" "${TARGET_PATH}/nrf52840_dongle.hex" "${TARGET_PATH}/padding.hex" "${TARGET_PATH}/cortex-m4.hex"

# Create DFU packages
${NRFUTIL} pkg generate --hw-version 52 --sd-req 0x00 --application-version 1 --application "${TARGET_PATH}/opensk.hex" "${TARGET_PATH}/opensk.zip" > /dev/null
${NRFUTIL} pkg generate --hw-version 52 --sd-req 0x00 --application-version 1 --application "${TARGET_PATH}/nrf52840_dongle.hex" "${TARGET_PATH}/tock.zip" > /dev/null

# Insert the dongle, and make it go into dfu mode
echo "-----------------------------------------------------"
echo "Flash OpenSK: "
echo "-----------------------------------------------------"
echo "Please insert the dongle, make it go into DFU mode (long press on SW2)..."
read -n 1 -s -r -p "Press any key to continue"

# Flash OpenSK
sudo ${NRFUTIL} dfu usb-serial -pkg "${TARGET_PATH}/opensk.zip" -p /dev/ttyACM0

echo "-----------------------------------------------------"
echo "Flash TockOS: "
echo "-----------------------------------------------------"
echo "Please insert the dongle, make it go into DFU mode (long press on SW2)..."
read -n 1 -s -r -p "Press any key to continue"

# Flash TockOS
sudo ${NRFUTIL} dfu usb-serial -pkg "${TARGET_PATH}/tock.zip" -p /dev/ttyACM0
