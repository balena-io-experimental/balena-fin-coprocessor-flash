#!/bin/bash

FW=$1
REV=$2

mux () {
    echo $1 > /sys/class/gpio/gpio41/value # Set I2C expander (SWD:1|UART:0)
}

get_device_id () {
    { BALENA_DEVICE_ID=$(curl -X GET "https://api.balena-cloud.com/v5/device?\$filter=uuid%20eq%20'$BALENA_DEVICE_UUID'" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $BALENA_API_KEY" | jq '.d[0].id'); } 2> /dev/null
}

update_var () {
    get_device_id
    curl -X POST \
    "https://api.balena-cloud.com/v5/device_environment_variable" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $BALENA_API_KEY" \
    --data '{
        "device": "'${BALENA_DEVICE_ID}'",
        "name": "FLASHED",
        "value": "'${1}'"
    }' \
    > /dev/null
}

# exit if already flashed
if [[ $FLASHED == "1" ]];
then
    echo "already flashed."
    exit 0
fi

# Makes sure we exit if lock fails.
set -e

echo "acquiring lockfile..."
exec {lock_fd}>/tmp/balena/updates.lock || exit 1
flock -n "$lock_fd" || { echo "ERROR: failed to acquire lockfile." >&2; rm -f /tmp/balena/updates.lock; exit 1; }

echo "opening screen terminal for flashing $FW to balenaFin v$REV"
case $REV in
  09)
    screen -dmS swd_program ftdi_eeprom --flash-eeprom firmware/v1-0-jtag.conf && sleep 1 && openocd -f /usr/share/openocd/scripts/board/balena-fin/balena-fin-v1-0
    ;;
  10)
    echo 41 > /sys/class/gpio/export || true
    echo "out" > /sys/class/gpio/gpio41/direction
    mux "1"
    screen -dmS swd_program openocd -f /usr/share/openocd/scripts/board/balena-fin/balena-fin-v1-1
    ;;
  *)
    echo "ERROR: unknown balenaFin revision" >&2
    flock -u "$lock_fd"; rm -f /tmp/balena/updates.lock
    exit 1
    ;;
esac

sleep 6
  { sleep 5; echo "reset halt"; echo "program firmware/bootloader.s37"; sleep 5; echo "reset halt"; echo "program firmware/$FW"; echo "reset run"; sleep 10; echo "exit"; echo -e '\x1dclose\x0d'; } | telnet localhost 4444
sleep 5

echo -e "flashing complete\n"
echo "releasing lockfile..."
flock -u "$lock_fd"; rm -f /tmp/balena/updates.lock
echo "closing the openocd process..."

# kill openocd session
kill $(ps aux | grep '[S]CREEN -dmS swd_program' | awk '{print $2}')

if [ $REV == 10 ]
then
    # mux "0"
    status=""
    while [[ $status != '"Idle"' ]]
    do
        { status=$(curl "${BALENA_SUPERVISOR_ADDRESS}/v1/device?apikey=${BALENA_SUPERVISOR_API_KEY}" | jq '.status'); } 2> /dev/null
        echo "supervisor is $status."
        sleep 5
    done

    # update device var to prevent reflashing
    update_var 1

    # reboot
    echo -e "\n rebooting device."
    curl -s -X POST "${BALENA_SUPERVISOR_ADDRESS}/v1/reboot?apikey=${BALENA_SUPERVISOR_API_KEY}" > /dev/null
fi

