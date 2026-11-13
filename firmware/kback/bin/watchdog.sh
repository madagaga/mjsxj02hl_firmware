#!/bin/sh

GATEWAY=${1:-"192.168.1.1"}

CHECK_INTERVAL=10   # seconds between two checks
STABLE_TIME=60      # seconds the application must stay up before its failures are forgotten

network_errors=0
application_errors=0
application_alive=0
while true; do
    # Network connection
    if ! ping -c 1 $GATEWAY &> /dev/null; then
        echo "Reconnecting to an Access Point..."
        killall udhcpc wpa_supplicant
        ifconfig wlan0 down
        ifconfig wlan0 up
        wpa_supplicant -B -D nl80211 -i wlan0 -c /etc/wpa_supplicant.conf
        udhcpc -b -i wlan0
        network_errors=$((network_errors+1))
    else
        network_errors=0
    fi
    # Main application
    if ! killall -0 mjsxj02hl &> /dev/null; then
        echo "Restarting main application..."
        mjsxj02hl &
        application_errors=$((application_errors+1))
        application_alive=0
    else
        # Being alive at one check proves nothing: an application that crashes a few
        # seconds after every restart is alive at most checks. Only a run of
        # STABLE_TIME seconds clears the failures, so a crash loop reaches the
        # reboot threshold below (which resets the kernel-side MPP state).
        application_alive=$((application_alive+CHECK_INTERVAL))
        if [ $application_alive -ge $STABLE_TIME ]; then
            application_errors=0
        fi
    fi
    # Reboot if there are many errors
    if [ $network_errors -ge 5 ] || [ $application_errors -ge 5 ]; then
        echo "Too many errors! Rebooting the device..."
        reboot
    fi
    sleep $CHECK_INTERVAL
done
