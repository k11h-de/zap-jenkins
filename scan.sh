#!/bin/bash

# setting default values
DEFAULT_DELAY_IN_MS="0"
DEFAULT_MAX_SCAN_DURATION_IN_MINS="0"
DEFAULT_THREADS_PER_HOST="2"
DEFAULT_RECURSIVE="true"
DEFAULT_CONTEXT_FOLDER="./zap-context"
DEFAULT_REPORT_FOLDER="./reports"
DEFAULT_LOGFILE="${DEFAULT_REPORT_FOLDER}/scan.log"
# ---------------------- no changes below ------------------- #

usage() {
echo "This script checks for an OPTIONAL folder named $DEFAULT_CONTEXT_FOLDER to contain zap context files named <target>.context
for example: $DEFAULT_CONTEXT_FOLDER/www.example.com.context 
There you can customize the scan (with auth details). 
(refer: https://github.com/Grunny/zap-cli#running-scans-as-authenticated-users)

The script also checks for an exclude file in: $DEFAULT_CONTEXT_FOLDER/www.example.com.context.exclude
put in one exclude regex per line - this is required to work aroung bug https://github.com/Grunny/zap-cli/issues/79

This script also creates a folder named $DEFAULT_REPORT_FOLDER and stores html, json and xml reports there

Usage: 
-t www.example.com                  - the target to scan; format: www.example.com
-a High                             - Alert Level for scanning, one of High|Medium|Low|Informational 
-d <DELAY_IN_MS>                    - defaults to $DEFAULT_DELAY_IN_MS
                                      The delay in milliseconds between each request while scanning. 
                                      Setting this to a non zero value will increase the time an active scan takes, 
                                      but will put less of a strain on the target host.
-m <MAX_SCAN_DURATION_IN_MINS>      - defaults to $DEFAULT_MAX_SCAN_DURATION_IN_MINS
                                      The maximum time that the whole scan can run for in minutes. 
                                      0 means no limit. This can be used to ensure that a scan is completed around a set time.
-j <JOB_ID>                         - defaults to scripts PID, used to allow concurrent runs
                                      can be e.g. Jenkins Build ID
                                      used to name the running container zap_<JOB_ID>
-r true|false                       - defautls to $DEFAULT_RECURSIVE; scan target recursively if true
-x THREADS_PER_HOST                 - defaults to $DEFAULT_THREADS_PER_HOST
                                      The number of threads the scanner will use per host. 
                                      Increasing the number of threads will speed up the scan but may 
                                      put extra strain on the computer ZAP is running on and the target host.
-l <LOGFILE>                        - defaults to $DEFAULT_LOGFILE
-o                                  - output result as json
-h                                  - print this help
" 1>&2
exit 1
}

while getopts ":t:a:d:m:j:r:x:l:oh" opt; do
  case $opt in
    t) ZAP_TARGET="$OPTARG"
    ;;
    a) ZAP_ALERT_LVL="$OPTARG"
    ;;
    d) DELAY_IN_MS="$OPTARG"
    ;;
    m) MAX_SCAN_DURATION_IN_MINS="$OPTARG"
    ;;
    j) JOB_ID="$OPTARG"
    ;;
    r) RECURSIVE="$OPTARG"
    ;;
    x) THREADS_PER_HOST="$OPTARG"
    ;;
    l) LOGFILE="$OPTARG"
    ;;
    o) OUTPUT_JSON="true"
    ;;
    h) usage
    ;;
    \?) echo "Invalid option -$OPTARG" >&2
    exit 1
    ;;
    :)  echo "Option -$OPTARG requires an argument." >&2
    exit 1
    ;;
  esac
done

# fail or set defaults
[ -z "$ZAP_TARGET" ] && usage
[ -z "$ZAP_ALERT_LVL" ] && usage
[ -z "$DELAY_IN_MS" ] && DELAY_IN_MS="$DEFAULT_DELAY_IN_MS"
[ -z "$MAX_SCAN_DURATION_IN_MINS" ] && MAX_SCAN_DURATION_IN_MINS="$DEFAULT_MAX_SCAN_DURATION_IN_MINS"
[ -z "$JOB_ID" ] && JOB_ID=$$
[ -z "$RECURSIVE" ] && RECURSIVE="$DEFAULT_RECURSIVE"
[ -z "$THREADS_PER_HOST" ] && THREADS_PER_HOST="$DEFAULT_THREADS_PER_HOST"
[ -z "$LOGFILE" ] && LOGFILE="$DEFAULT_LOGFILE"
# set cli flag
[ $RECURSIVE = "true" ] &&  RECURSIVE_FLAG="--recursive"
[ $RECURSIVE = "false" ] &&  RECURSIVE_FLAG=""
# check if requirements are present
docker -v > /dev/null 2>&1
[ $? -eq 128 ] && echo "The required program 'docker' is not installed." && exit 1
jq --version > /dev/null 2>&1
[ $? -eq 128 ] && echo "The required program 'jq' is not installed." && exit 1

# ensure reports folder
mkdir -p $DEFAULT_REPORT_FOLDER  &> /dev/null

# allow & catch ctrl-c
myInterruptHandler(){ 
    docker container rm --force zap_${JOB_ID} &> /dev/null
    exit 1
}
trap myInterruptHandler SIGINT;

# starting container
docker run --name zap_${JOB_ID} -d owasp/zap2docker-stable zap.sh -daemon \
-port 2375 \
-host 127.0.0.1 \
-config api.disablekey=true \
-config scanner.attackOnStart=true \
-config scanner.delayInMs=${DELAY_IN_MS} \
-config scanner.maxScanDurationInMins=${MAX_SCAN_DURATION_IN_MINS} \
-config scanner.threadPerHost=${THREADS_PER_HOST} \
-config view.mode=attack \
-config connection.dnsTtlSuccessfulQueries=-1 \
-config connection.socksProxy.enabled=true
-config connection.socksProxy.host=localhost
-config connection.socksProxy.port=3128
-config connection.socksProxy.version=5
-config connection.socksProxy.dns=true
-config api.addrs.addr.name=.* \
-config api.addrs.addr.regex=true \
-addoninstall ascanrulesBeta \
-addoninstall pscanrulesBeta \
-addoninstall alertReport  >>"$LOGFILE" 2>&1

ZAP_USE_CONTEXT_FILE="true"
# copy context file into container if exists
if [[ -f "$DEFAULT_CONTEXT_FOLDER/${ZAP_TARGET}.context" ]]; then
    echo "context file found in $DEFAULT_CONTEXT_FOLDER/${ZAP_TARGET}.context - Copying into container" >>"$LOGFILE" 2>&1
    docker cp $DEFAULT_CONTEXT_FOLDER/${ZAP_TARGET}.context zap_${JOB_ID}:/home/zap/${ZAP_TARGET}  >>"$LOGFILE" 2>&1
else
    echo "context file not found in $DEFAULT_CONTEXT_FOLDER/${ZAP_TARGET}.context"  >>"$LOGFILE" 2>&1
    ZAP_USE_CONTEXT_FILE="false"
fi

# wait for zap to be ready
docker exec zap_${JOB_ID} zap-cli -v -p 2375 status -t 120  >>"$LOGFILE" 2>&1

# start the actual scan, with or without context file
if [[ "${ZAP_USE_CONTEXT_FILE}" == "true" ]]; then
    docker exec zap_${JOB_ID} zap-cli -v -p 2375 context import /home/zap/$ZAP_TARGET  >>"$LOGFILE" 2>&1
    docker exec zap_${JOB_ID} zap-cli -v -p 2375 context info ${ZAP_TARGET}  >>"$LOGFILE" 2>&1 
    if [[ -f "$DEFAULT_CONTEXT_FOLDER/${ZAP_TARGET}.context.exclude" ]]; then
        echo "exclude file found in $DEFAULT_CONTEXT_FOLDER/${ZAP_TARGET}.context.exclude - applying."  >>"$LOGFILE" 2>&1
        cat $DEFAULT_CONTEXT_FOLDER/${ZAP_TARGET}.context.exclude | while read line || [[ -n $line ]]; 
        do
            docker exec zap_${JOB_ID} zap-cli -v -p 2375 exclude "$line"  >>"$LOGFILE" 2>&1
        done
    fi
    docker exec zap_${JOB_ID} zap-cli -v -p 2375 open-url https://${ZAP_TARGET}  >>"$LOGFILE" 2>&1
    docker exec zap_${JOB_ID} zap-cli -v -p 2375 spider -c ${ZAP_TARGET} https://${ZAP_TARGET}  >>"$LOGFILE" 2>&1
    docker exec zap_${JOB_ID} zap-cli -v -p 2375 active-scan -c ${ZAP_TARGET} $RECURSIVE_FLAG https://${ZAP_TARGET}  >>"$LOGFILE" 2>&1
else
    docker exec zap_${JOB_ID} zap-cli -v -p 2375 open-url https://${ZAP_TARGET} >>"$LOGFILE" 2>&1
    docker exec zap_${JOB_ID} zap-cli -v -p 2375 spider https://${ZAP_TARGET} >>"$LOGFILE" 2>&1
    docker exec zap_${JOB_ID} zap-cli -v -p 2375 active-scan $RECURSIVE_FLAG https://${ZAP_TARGET} >>"$LOGFILE" 2>&1
fi

# generate reports inside container
docker exec zap_${JOB_ID} zap-cli -p 2375 report -o /home/zap/report.html -f html >>"$LOGFILE" 2>&1
docker cp zap_${JOB_ID}:/home/zap/report.html $DEFAULT_REPORT_FOLDER/ >>"$LOGFILE" 2>&1
docker exec zap_${JOB_ID} zap-cli -p 2375 report -o /home/zap/report.xml -f xml >>"$LOGFILE" 2>&1
docker cp zap_${JOB_ID}:/home/zap/report.xml $DEFAULT_REPORT_FOLDER/ >>"$LOGFILE" 2>&1
# fetch all alerts json
docker exec zap_${JOB_ID} zap-cli -p 2375 alerts --alert-level "Informational" -f json > $DEFAULT_REPORT_FOLDER/report.json || true

# output json
[ $OUTPUT_JSON = "true" ] && jq 'map({ItemId: .risk}) | group_by(.ItemId) | map({risk: .[0].ItemId, count: length}) | .[]' $DEFAULT_REPORT_FOLDER/report.json
