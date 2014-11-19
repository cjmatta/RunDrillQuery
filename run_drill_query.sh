#!/bin/bash
# This is a MapR-specific script that will run a query against drill.
# The main use of this script is to simplify the collection of log files related to a failing query.
# It assumes that Drill is installed on the MapR host it's running on, and that you have ssh key
# authentication configured around the cluster.
#
# Usage: run_drill_query.sh -f file.sql [-d outputdir]
set -o nounset
set -o errexit

# Get options
OPTIND=1
sQueryFile=""
sOutputDir=$(pwd)

function show_help {
    echo "$0 -f file.sql [-d outputdir]"
}

while getopts "hf:d:" opt
do
    case "$opt" in
        h)
            show_help
            exit 0
            ;;
        f)  sQueryFile=$OPTARG
            ;;
        d)  sOutputDir=$OPTARG
            ;;
    esac
done

shift $((OPTIND-1))

if [[ ! -f $sQueryFile ]]
then
    echo "Query file ${sQueryFile} not found, exiting."
    exit 1
fi

if [[ ! -d $sOutputDir ]]
then
    echo "Dir ${sOutputDir} not found, exiting."
    exit 1
fi

if [[ ! -d /opt/mapr/drill ]]
then
    echo "Drill not installed on this host."
    exit 1
fi

sDrillVersion=$(ls /opt/mapr/drill)

echo "Determining drillbit hosts..."
aDrillHosts=($(maprcli node list -filter csvc=="drill-bits" -columns ip | awk '{print $1}' | tail -n +2))

if [[ ${#aDrillHosts[@]} -eq 0 ]]
then
    echo "Couldn't find any nodes running Drill!"
    exit 1
fi

sZKConnect=$(cat /opt/mapr/drill/${sDrillVersion}/conf/drill-override.conf | grep zk.connect | awk '{print $2}' | sed 's/"//g')

SQLLINE="/opt/mapr/drill/${sDrillVersion}/bin/sqlline -u \"jdbc:drill:zk=${sZKConnect}\""


function join { local IFS="$1"; shift; echo "$*";  }


function set_current_drillbit_logs {
    # will copy the current drillbit.log to /tmp and return the location
    # to be used with get_drillbit_logs to get only the updated log data.
    sFilename="/tmp/$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 8 | head -n 1)_drillbit.log"
    
    for host in ${aDrillHosts[@]}
    do
        ssh -q $host "cp /opt/mapr/drill/${sDrillVersion}/logs/drillbit.log ${sFilename}" 2> /dev/null
    done

    echo $sFilename
}

function delete_temp_file {
    for host in ${aDrillHosts[@]}
    do
        ssh -q $host rm -f $1 2> /dev/null
    done
}

function get_drillbit_logs {
    # This function will go around to each host in aDrillHosts and get the difference
    # in the drillbit.log since `set_current_drillbit_logs` was run.
    sFilename=$1
    sHostString=$(join , ${aDrillHosts[@]})
    echo "Collecting log files from: ${sHostString}"
    for host in ${aDrillHosts[@]}
    do
        ssh $host "diff ${sFilename} /opt/mapr/drill/${sDrillVersion}/logs/drillbit.log" > $sOutputDir/${host}_drillbit.log && echo "Received log file from ${host}"
    done
}

function run_query {
    echo "Running query from ${1}"
    sOutputFile="$sOutputDir/$(basename $1)_output.log"
    if [[ -f $sOutputFile ]]
    then
        rm $sOutputFile
    fi

    $SQLLINE -f $1 2>&1 >>$sOutputFile| tee --append $sOutputFile
}

FILE=$(set_current_drillbit_logs)
run_query $sQueryFile
get_drillbit_logs $FILE
delete_temp_file $FILE

