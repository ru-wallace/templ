#!/bin/bash

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
FILE_DATE="$(date +"%Y_%m_%d")"
DISPLAY_DATE="$(date +"%Y-%m-%d %H:%M:%S")"

LOG_DIR="$SCRIPT_DIR/logs"
LIVE_LOG_FILE="$SCRIPT_DIR/logs/live.csv"
LOG_FILE="$SCRIPT_DIR/logs/$FILE_DATE.csv"
IMAGE_FILE="$SCRIPT_DIR/temperature.png"

GNUPLOT_FILE="$SCRIPT_DIR/temp.gp"
SYMLINK_PATH="/usr/local/bin/templ"

SERVICE_FILE_PATH="/etc/systemd/system/templ.service"
SERVICE_FILE_TEXT="[Unit]\n \
Description=\"Templ Temperature Logging and plotting tool.\"\n \
\n \
[Service]\n \
Type=oneshot\n \
Environment=\"LAUNCHED_BY_SYSTEMD=yes\"\n \
ExecStart=\"/usr/local/bin/templ\"\n \
\n \
[Install]\n \
WantedBy=multi-user.target \n"

TIMER_FILE_PATH="/etc/systemd/system/templ.timer"
TIMER_FILE_TEXT="[Unit]\n \
Description=\"Timer to run templ service\"\n \
\n \
[Timer]\n \
OnBootSec=10s\n\
OnUnitActiveSec=30s\n\
AccuracySec=1\n\
\n\
[Install]\n\
WantedBy=timers.target\n"


N_ROWS=100

# Function to plot the last n lines of the live log file (up to 1000)
function plot_temp() {

    local N_ROWS=${1:-"100"}
    local SAVE_LOCATION=${2:-"$IMAGE_FILE"}
    # Use gnuplot to create a plot and save it as a PNG
    gnuplot -c "$GNUPLOT_FILE" "$IMAGE_FILE" "$LIVE_LOG_FILE" "$N_ROWS"

    echo "Plot saved as $IMAGE_FILE"
}

#Function to get the current temperature from an MS5837 sensor using the I2C protocol
function get_temp_MS5837() {

    sudo i2cset -y 1 0x76 0x1E
    sleep 0.05

    #MS5837 
    # Read calibration data
    calib=()
    for reg in 0xAA 0xAC; do
    value=$(sudo i2cget -y 1 0x76 $reg w)
    value=$((((value & 0xFF) <<8) | (value >> 8)))
    calib+=($value)
    done

    #Start temp conversion
    sudo i2cset -y 1 0x76 0x5a
    sleep 0.21  # Wait for conversion

    # Function to convert hex to decimal
    address=0x76
    start_reg_0=0x00
    start_reg_1=0x01
    start_reg_2=0x02

    temp_data=($(sudo i2cget -y 1 0x76 0x00 i 3))

    #These lines mess up the language highlighting in VSCode
    #I don't think it likes the "<<" left shift binary operator
    msb=$((temp_data[0]<<16))
    csb=$((temp_data[1]<<8))
    lsb=$((temp_data[2]))

    # Combine the three bytes into one 24-bit value using intermediate variables
    combined_data=$((msb | csb | lsb))

    dT=$((combined_data-calib[0]*256))
    temp=$((100*(2000+dT*calib[1]/8388608)))

    #Conversions
    if [ "$temp" -lt 200000 ]; then
        Ti=$(((30000*dT*dT)/8589934592))
    elif [ "$temp" -ge 200000 ]; then
        Ti=$((20000*(dT*dT)/137438953472))
    fi

    echo "$(bc <<< "scale=2; $temp/10000")"

}

function get_cpu_temp() {
    echo "$(vcgencmd measure_temp | cut -d "=" -f2 | cut -d "'" -f1)"
}

function show_help() {
    echo "templ"
    echo "  Tool for logging CPU and environmental temperature and plotting historical data. CPU data is captured using vcgencmd, \
     and environmental temperature is captured using an I2C interface with an MS5837 Sensor whic must be installed correctly."
    echo ""
    echo "USAGE"
    echo ""
    echo "  [-h | --help]          Show this information"
    echo "  [-i | --install]       Install templ tool. Must be run as root user"
    echo "  [-n | --npoints]       Set number of points to log in graph"
    echo "  [-f | --filepath]      Set location in which to save generated plot image (Default is \"temperature.png\" in templ directory)"
    echo "  [--cpu]                Display current CPU temperature in degrees Celsius"
    echo "  [--env]                Display current environmental temperature in degrees Celsius"

}

function install_templ() {
    if [[ "$EUID" -ne 0 ]]; then
        echo "Install routine must be run as root user. I.e \"sudo bash temple.sh --install\""
        echo "Once installation is complete, the tool can be run from anywhere using \"templ [options]\""
        exit 1
    fi

    mkdir -p "$LOG_DIR"
    if [ -f "$SYMLINK_PATH" ]; then
        rm "$SYMLINK_PATH"
    fi
    ln -s  "$SCRIPT_DIR/templ.sh" "/usr/local/bin/templ"
    chmod 777 "$SCRIPT_DIR/templ.sh"


    echo -e "$SERVICE_FILE_TEXT" > "$SERVICE_FILE_PATH"
    echo -e "$TIMER_FILE_TEXT" > "$TIMER_FILE_PATH"

    systemctl daemon-reload

    systemctl enable templ.timer
    systemctl start templ.timer

}

function uninstall() {
    if [[ "$EUID" -ne 0 ]]; then
        echo "Uninstall routine must be run as root user. I.e \"sudo bash temple.sh --uninstall\""
        exit 1
    fi

    read -p "Uninstall templ including systemd service? (Existing log files will not be deleted) [y/n]:" CONFIRM_UNINSTALL
    if [ ! "$CONFIRM_UNINSTALL" == "y" ]; then
        echo "Cancelled uninstall."
        exit 0
    fi

    systemctl stop templ.timer
    systemctl stop templ.service
    rm "$SERVICE_FILE_PATH"
    rm "$TIMER_FILE_PATH"
    rm "$SYMLINK_PATH"

    echo "Removed all symlinks and systemd services"
    echo "Uninstall complete."
    exit 0
}

# Parse command-line options
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            show_help
            exit 0
        ;;
        --cpu|--CPU)
            echo "$(get_cpu_temp)°C"
            exit 0
        ;;
        --env|--ENV|--environment)
            echo "$(get_temp_MS5837)°C"
            exit 0
        ;;
        -n|--npoints)
            shift
            if ! [[ $# -gt 0 ]]; then
                echo "Error: argument after "-n" or "--npoints" must be a positive integer between 0 and 1000"
                exit 1
            fi
            if ! [[ "$1" =~ '^[0-9]+$' ]]; then
                echo "Error: argument after "-n" or "--npoints" must be a positive integer between 0 and 1000"
                exit 1
            fi
            N_LINES="$1"
            shift
        ;;
        -f|--file)
            shift
            if ! [[ $# -gt 0 ]]; then
                echo "Error: argument after "-i" or "--image" must be a filepath in which to save the generated plot image."
                exit 1
            fi
            IMAGE_FILE="$1"
            shift
        ;;
        -i|--install)
            install_templ
            exit 0
        ;;
        -u|--uninstall)
            uninstall
            exit 0
        ;;
        *)
            echo "Unknown command \"$1\". Use -h or --help for usage"
        ;;
    esac
done


# Get the CPU temperature using vcgencmd
cpu_temp=$(get_cpu_temp)

#Get environmental temperature from a MS5837 sensor using the I2C protocol
env_temp="$(get_temp_MS5837)" 2>/dev/null

mkdir -p "$LOG_DIR"

if [ ! -f "$LOG_FILE" ]; then
    # If the file does not exist, write a CSV header
    echo "Timestamp, CPU Temperature, Enviromental Temp" > "$LOG_FILE"
fi

#Get the last 999 records
if [ -f "$LIVE_LOG_FILE" ]; then
    LENGTH=($(wc -l "$LIVE_LOG_FILE"))
    LENGTH=${LENGTH[0]}
    if [ "$LENGTH" -lt "3" ]; then
        return
    fi
    N_LINES=$((LENGTH-1))
    N_LINES=$((N_LINES<999 ? N_LINES : 999))
    echo "n lines: $N_LINES"
    RECENT_ENTRIES="$(tail -n $N_LINES $LIVE_LOG_FILE)"
fi

#clear the live log file and add the header and 999 most recent rows back, then append the new data

echo "Timestamp, CPU Temperature, Enviromental Temp" > "$LIVE_LOG_FILE"
if [ ! "$RECENT_ENTRIES" == "" ]; then
    echo "$RECENT_ENTRIES" >> "$LIVE_LOG_FILE"
fi

echo "$DISPLAY_DATE, $cpu_temp, $env_temp" >> "$LIVE_LOG_FILE"


# Append the temperature and datetime to the days log file
echo "$DISPLAY_DATE, $cpu_temp, $env_temp" >> "$LOG_FILE"

echo "Saved Temperature CPU: $cpu_temp°C", Environment: $env_temp°C""


#Check if launched by a systemd service
if [ "$LAUNCHED_BY_SYSTEMD" == yes ]; then

   #Only plot the chart if SSH session is active
    SSH_ACTIVE=$(who | grep tty)

    if [ -z "$SSH_ACTIVE" ]; then
        echo "No SSH Session Detected. Not Plotting Chart"
        exit 0
    fi

    if [ -f "$IMAGE_FILE" ]; then
        last_plot=$(date -r $IMAGE_FILE +%s)
        time_now=$(date +%s)
        
        time_difference=$(($time_now-$last_plot))

        if [ "$time_difference" -lt 300 ]; then
            echo "Less than 5 minutes since the last plot. Skipping. "
            exit 0
        fi
    fi

fi

plot_temp
