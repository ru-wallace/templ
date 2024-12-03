# tempL

tempL (Short for temperature log, I guess) Is a utility for logging temperature readings made with a MS5837 sensor using the I2C protocol to communicate.
I have only tested this on a Raspberry Pi 4B, and I would not expect it to run un-modified on a non-Raspberry Pi.

You must have the i2c-tools package installed (Available from most linux package managers)

If enabled, every 30s the program takes a temperature reading from the sensor, and a CPU temperature reading using vcgenmd, writing them to a CSV log. A graph of the most recent readings is created and updated every 5 minutes using GNUPlot.

## NOTICE: Using the 'install' function adds a systemd service and timer, and enables them to run every 30s from startup, continously logging and occasionally plotting data. If you do not want this, you can use the tool without installing (See below)
Because the tool uses the i2c-tools utilities, some tools from which require root access, the tool will likely not work without using ```sudo``` or otherwise running as a root user.


## Usage
- Navigate to the directory in which you want to install tempL
- Run ```git clone https://github.com/ru-wallace/templ``` to download.
### Use Without Installing
- Enter into your terminal ```sudo bash ./templ.sh <args>``` from the installation directory to run the commands for logging or printing. (See below for usage)
- If you allow execution permissions, you can run tempL from the terminal in any directory by editing your PATH environment variable.
- Use ```export PATH=<installation directory>:$PATH``` to allow access from anywhere. Add that line to your `.bashrc` file in your home directory to run this every time you open a shell instance.

### Installation

- Use ```sudo bash templ.sh [--install|-i]``` to install.
This will create a softlink to the script in `/usr/local/bin` (I know it's not a binary file and maybe doesn't live there, I'll find a better home at some point). It enables execution permissions.
It also creates a systemd service and timer in `/etc/system/systemd/service` and enables them.
This enables you to use `templ <args>` from the command line in any directory.

### Commands

`templ` (No Args)        Take a temperature measurement, add to log file, and update chart.

`[-h | --help]`          Show this information

`[-i | --install]`       Install templ tool. Must be run as root user

`[-n | --npoints]`       Set number of points to log in graph

`[-f | --filepath]`      Set location in which to save generated plot image (Default is \"temperature.png\" in templ directory)

`[--cpu]`                Display current CPU temperature in degrees Celsius (Does not add to log)

`[--env]`                Display current environmental temperature in degrees Celsius (Does not add to log)

