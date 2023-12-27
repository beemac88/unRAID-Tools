#!/bin/bash
# unraid_array_fan.sh v0.6
# v0.1: By xamindar: First try at it.
# v0.2: Made a small change so the fan speed on low doesn't fluctuate every time the script is run.
# v0.3: It will now enable fan speed change before trying to change it. I missed 
#        it at first because pwmconfig was doing it for me while I was testing the fan.
# v0.4: Corrected temp reading to "Temperature_Celsius" as my new Seagate drive
#        was returning two numbers with just "Temperature".
# v0.5: By Pauven:  Added linear PWM logic to slowly ramp speed when fan is between HIGH and OFF.
# v0.6: By kmwoley: Added fan start speed. Added logging, suppressed unless fan speed is changed.
# v0.7: By beemac88: Tailored for my specific unRAID setup with one SATA SSD (sdb), 8 drives active, and three array fans.
# A simple script to check for the highest hard disk temperatures in an array
# or backplane and then set the fan to an apropriate speed. Fan needs to be connected
# to motherboard with pwm support, not array.
# DEPENDS ON:grep,awk,smartctl,hdparm

### VARIABLES FOR USER TO SET ###
# Amount of drives in the array. Make sure it matches the amount you filled out below.
NUM_OF_DRIVES=8

# unRAID drives that are in the array/backplane of the fan we need to control
HD[1]=/dev/sdc
HD[2]=/dev/sdd
HD[3]=/dev/sde
HD[4]=/dev/sdf
HD[5]=/dev/sdg
HD[6]=/dev/sdh
HD[7]=/dev/sdi
HD[8]=/dev/sdj
#HD[9]=/dev/sdk
#HD[10]=/dev/sdk
#HD[11]=/dev/sdl
#HD[12]=/dev/sdm
#HD[13]=/dev/sdn
#HD[14]=/dev/sdo
#HD[15]=/dev/sdp
#HD[16]=/dev/sdq
#HD[17]=/dev/sdr
#HD[18]=/dev/sds
#HD[19]=/dev/sdt
#HD[20]=/dev/sdu
#HD[21]=/dev/sdv
#HD[22]=/dev/sdw
#HD[23]=/dev/sdx
#HD[24]=/dev/sdy

# Temperatures to change fan speed at
# Any temp between OFF and HIGH will cause fan to run on low speed setting 
FAN_OFF_TEMP=28     # Anything this number and below - fan is off
FAN_HIGH_TEMP=42    # Anything this number or above - fan is high speed

# Fan speed settings. Run pwmconfig (part of the lm_sensors package) to determine 
# what numbers you want to use for your fan pwm settings. Should not need to
# change the OFF variable, only the LOW and maybe also HIGH to what you desire.
# The START variable controls the speed to get the fan spinning from 0 
# (Default: 255 to be safe).
# Any real number between 0 and 255.
#
FAN_OFF_PWM=0
FAN_LOW_PWM=27
FAN_START_PWM=255
FAN_HIGH_PWM=255

# Fan device. Depends on your system. pwmconfig can help with finding this out. 
# pwm1 is usually the cpu fan. You can "cat /sys/class/hwmon/hwmon0/device/fan1_input"
# or fan2_input and so on to see the current rpm of the fan. If 0 then fan is off or 
# there is no fan connected or motherboard can't read rpm of fan.
# ARRAY_FAN=/sys/class/hwmon/hwmon1/device/pwm2
ARRAY_FAN=/sys/class/hwmon/hwmon2/pwm2
ARRAY_FAN2=/sys/class/hwmon/hwmon2/pwm3
ARRAY_FAN3=/sys/class/hwmon/hwmon2/pwm4
ARRAY_FAN_RPM=/sys/class/hwmon/hwmon2/fan2_input
ARRAY_FAN2_RPM=/sys/class/hwmon/hwmon2/fan3_input
ARRAY_FAN3_RPM=/sys/class/hwmon/hwmon2/fan4_input
### END USER SET VARIABLES ###


# Program variables - do not modify
HIGHEST_TEMP=0
CURRENT_DRIVE=1
CURRENT_TEMP=0
OUTPUT=""

# Linear PWM Logic Variables - do not modify
NUM_STEPS=$((FAN_HIGH_TEMP - FAN_OFF_TEMP - 1))
PWM_INCREMENT=$(( (FAN_HIGH_PWM - FAN_LOW_PWM) / NUM_STEPS))
OUTPUT+="Linear PWM Range is "$FAN_LOW_PWM" to "$FAN_HIGH_PWM" in "$NUM_STEPS" increments of "$PWM_INCREMENT$'\n'


# while loop to get the highest temperature of active drives. 
# If all are spun down then high temp will be set to 0.
while [ "$CURRENT_DRIVE" -le "$NUM_OF_DRIVES" ]
do
  SLEEPING=$(hdparm -C ${HD[$CURRENT_DRIVE]} | grep -c standby)
  if [ "$SLEEPING" == "0" ]; then
    CURRENT_TEMP=$(smartctl -A ${HD[$CURRENT_DRIVE]} | grep -m 1 -i Temperature_Celsius | awk '{print $10}')
    OUTPUT+=" -- Drive "${HD[$CURRENT_DRIVE]}" temp "$CURRENT_TEMP$'\n'
    if [ "$HIGHEST_TEMP" -le "$CURRENT_TEMP" ]; then
      HIGHEST_TEMP=$CURRENT_TEMP
    fi
  fi
 #echo $CURRENT_TEMP
  let "CURRENT_DRIVE+=1"
done
OUTPUT+="Highest temp is: "$HIGHEST_TEMP$'\n'

# Enable speed change on 1st fan if not already
if [ "$ARRAY_FAN" != "1" ]; then
  echo 1 > "${ARRAY_FAN}_enable"
fi
# Enable speed change on 2nd fan if not already
if [ "$ARRAY_FAN2" != "1" ]; then
  echo 1 > "${ARRAY_FAN2}_enable"
fi
# Enable speed change on 3rd fan if not already
if [ "$ARRAY_FAN" != "1" ]; then
  echo 1 > "${ARRAY_FAN3}_enable"
fi
# previous speed
PREVIOUS_SPEED=$(cat $ARRAY_FAN)

# Set the fan speed based on highest temperature
if [ "$HIGHEST_TEMP" -le "$FAN_OFF_TEMP" ]; then
  # set fan to off
  echo $FAN_OFF_PWM  > $ARRAY_FAN
  echo $FAN_OFF_PWM  > $ARRAY_FAN2
  echo $FAN_OFF_PWM  > $ARRAY_FAN3
  OUTPUT+="Setting pwm to: "$FAN_OFF_PWM$'\n'
elif [ "$HIGHEST_TEMP" -ge "$FAN_HIGH_TEMP" ]; then
  # set fan to full speed
  echo $FAN_HIGH_PWM > $ARRAY_FAN
  echo $FAN_HIGH_PWM > $ARRAY_FAN2
  echo $FAN_HIGH_PWM > $ARRAY_FAN3
  OUTPUT+="Setting pwm to: "$FAN_HIGH_PWM$'\n'
else
  # set fan to starting speed first to make sure it spins up then change it to low setting.
#  if [ "$PREVIOUS_SPEED" -lt "$FAN_START_PWM" ]; then
#    echo $FAN_START_PWM > $ARRAY_FAN
#    echo $FAN_START_PWM > $ARRAY_FAN2
#    echo $FAN_START_PWM > $ARRAY_FAN3
#      sleep 4
#  fi
  # Calculate target fan PWM speed as a linear value between FAN_HIGH_PWM and FAN_LOW_PWM
  FAN_LINEAR_PWM=$(( ((HIGHEST_TEMP - FAN_OFF_TEMP - 1) * PWM_INCREMENT) + FAN_LOW_PWM))
  echo $FAN_LINEAR_PWM > $ARRAY_FAN
  echo $FAN_LINEAR_PWM > $ARRAY_FAN2
  echo $FAN_LINEAR_PWM > $ARRAY_FAN3
  OUTPUT+="Setting pwm to: "$FAN_LINEAR_PWM$'\n'
fi


# produce output if the fan speed was changed
CURRENT_SPEED=$(cat $ARRAY_FAN)
CURRENT_SPEED2=$(cat $ARRAY_FAN2)
CURRENT_SPEED3=$(cat $ARRAY_FAN3)
if [ "$PREVIOUS_SPEED" -ne "$CURRENT_SPEED" ]; then
  echo "Array fan speed has changed."
  echo "${OUTPUT}"
else
  echo "Hottest HDD: "$HIGHEST_TEMP", FAN2 "$(cat $ARRAY_FAN_RPM)", FAN3 "$(cat $ARRAY_FAN2_RPM)", FAN4 "$(cat $ARRAY_FAN3_RPM)
fi
# bash '/tmp/user.scripts/tmpScripts/unraid array fan/script'
