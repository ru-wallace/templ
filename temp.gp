 #!/usr/bin/gnuplot
 
#Check correct number of args given
if (ARGC != 3) {
    print "Usage: gnuplot -c plot_script.gp <image_file_path> <data_file_path> <n_rows>"
    exit
}
#Set variables
IMAGE_FILE = ARG1
DATA_FILE = ARG2
N_ROWS = ARG3
#Get current datetime and format
current_date = strftime("%Y-%m-%d %H:%M:%S", time(0.0))

set datafile separator ","
set terminal png
set output IMAGE_FILE

#Define a macro which is used to set up the graph in the same way
set macros
GRAPH_STYLE="\
set xdata time; \
set timefmt '%Y-%m-%d %H:%M:%S'; \
set format x '%H:%M'; \
set ytics format '%.2f°'; \
set xlabel 'Time'; \
set ylabel 'Temperature'; \
set grid; \
set title sprintf('CPU Temperature - Generated: %s', current_date); \
set yrange[*:*]; \
set key left bottom; \
"

#Open a multiplot to plot two charts on the same image
# layout format is <rows>,<cols>
set multiplot layout 2,1

#Plot CPU temperature
@GRAPH_STYLE
plot sprintf('< tail -n %s %s', N_ROWS, DATA_FILE) using 1:2 with lines title 'CPU Temp'

#plot environment temperature
@GRAPH_STYLE
plot sprintf('< tail -n %s %s', N_ROWS, DATA_FILE) using 1:3 with lines title 'Environmental Temperature'

unset multiplot