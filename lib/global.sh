f_logMessage(){
  
  # DESCRIPTION : PRINT FORMATED LOG MESSAGE ON CONSOLE OR TRACE LOG FILE
  # PARAM : 
  # - $1 : log level : DEBUG | INFO | WARN | ERROR | FATAL | SUCCESS
  # - $2 : log message
  # - $3 : log file (optional)  
  # OUTPUT 
  # - Console output
  # - File output (optional)

  # COLOR DECLARATION
  RED="31m"
  GREEN="32m"
  YELLOW="33m"
  DARKBLUE="34m"
  PINK="35m"
  LIGHTBLUE="36m"
  WHITE="37m"
  ENDCOLOR="\e[0m"

  LOGLEVEL=$(printf "%s" "${1}" | tr '[:lower:]' '[:upper:]')
  TEXT=$2
  LOGFILE=""
  
  if [[ $# -eq 3 ]]
  then
    LOGFILE=$3
  fi
  if [[ "$LOGLEVEL" == "DEBUG" ]]
  then
    COLOR="\e[$LIGHTBLUE"
    printf "$COLOR[%s] - $COLOR[%s] - $COLOR%b$ENDCOLOR%s\n" "$(date '+%d/%m/%Y - %H:%M:%S')" "$LOGLEVEL" "$TEXT"
    if [[ "$LOGFILE" != "" ]]
    then
      printf "[%s] - [%s] - %s\n" "$(date '+%d/%m/%Y - %H:%M:%S')" "DEBUG" "$TEXT" >> $LOGFILE
    fi
  elif [[ "$LOGLEVEL" == "INFO" || "$LOGLEVEL" == "WARN" || "$LOGLEVEL" == "ERROR" || "$LOGLEVEL" == "FATAL" || "$LOGLEVEL" == "SUCCESS" ]]
  then
    case $LOGLEVEL in 
      SUCCESS) COLOR="\e[$GREEN"
      FATAL | ERROR) COLOR="\e[$RED"
      INFO) COLOR="\e[$WHITE"
      WARNING) COLOR="\e[$YELLOW"
    esac
    printf "$COLOR[%s] - $COLOR[%s] - $COLOR%b$ENDCOLOR%s\n" "$(date '+%d/%m/%Y - %H:%M:%S')" "$LOGLEVEL" "$TEXT"
    if [[ "$LOGFILE" != "" ]]
    then
      printf "[%s] - [%s] - %s\n" "$(date '+%d/%m/%Y - %H:%M:%S')" "$LOGLEVEL" "$TEXT" >> $LOGFILE
    fi
  fi

}
