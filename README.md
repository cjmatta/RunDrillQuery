RunDrillQuery
=============
To be used for debugging [drill](http://incubator.apache.org/drill/) queries on [MapR](http://www.mapr.com).

A small script that will accept a sql file and an output directory, saving all results and log files for the query by using `diff` to compare the log files pre and post query run.

This script assumes it's running on a MapR cluster, that `mapr-drill` is installed and that the node you're runnig it on can ssh to all other drill nodes without a password.

## Usage
./run_drill_query.sh -f file.sql [-d outputdir]

### Notes
* This script uses the `maprcli` command to figure which nodes have drill installed. If your user doesn't have permissions to run that command it will return an empty list.
