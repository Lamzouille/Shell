f_errorDebug(){
  # this function test the proper execution of the last command executed.
  # $1 : message to display
  # $2 : logFile (optional)
  errCode="$?"
  logLevel="DEBUG"
  msgToDisplay="$1"
  logFile="$2"

  [[ $errCode != 0 ]] && f_logMessage "$logLevel" "Code error ${errCode} : ${msgToDisplay}" "$logFile"
}

f_errorWarning(){
  # this function test the proper execution of the last command executed.
  # $1 : message to display
  # $2 : logFile (optional)
  errCode="$?"
  logLevel="WARNING"
  msgToDisplay="$1"
  logFile="$2"

  [[ $errCode != 0 ]] && f_logMessage "$logLevel" "Code error ${errCode} : ${msgToDisplay}" "$logFile"
}

f_errorContinue(){
  # this function test the proper execution of the last command executed.
  # $1 : message to display
  # $2 : logFile (optional)
  errCode="$?"
  logLevel="ERROR"
  msgToDisplay="$1"
  logFile="$2"

  [[ $errCode != 0 ]] && f_logMessage "$logLevel" "Code error ${errCode} : ${msgToDisplay}" "$logFile"
}

f_errorExit(){
  # this function test the proper execution of the last command executed.
  # $1 : message to display
  # $2 : logFile (optional)
  errCode="$?"
  logLevel="ERROR"
  msgToDisplay="$1"
  logFile="$2"

  if [[ $errCode != 0 ]]; then
    f_logMessage "$logLevel" "Code error '${errCode}' : ${msgToDisplay}" "$logFile"
    exit -1
  fi
}

f_errorFatal(){
  # this function test the proper execution of the last command executed.
  # $1 : message to display
  # $2 : logFile (optional)
  errCode="$?"
  logLevel="FATAL"
  msgToDisplay="$1"
  logFile="$2"

  if [[ $errCode != 0 ]]; then
    f_logMessage "$logLevel" "Code error '${errCode}' : ${msgToDisplay}" "$logFile"
    exit -1
  fi
}

f_testEchecOrSuccess(){
  errCode="$?"
  msgToDisplay="$1"
  logFile="$2"

  if [[ $errCode -eq 0 ]]; then
    f_logMessage "SUCCESS" "${msgToDisplay}" "$logFile"
  else
    f_logMessage "ECHEC" "${msgToDisplay}" "$logFile"
  fi
  return $errCode
}

f_errorRaise(){
  [[ 0 -eq 1 ]]
  return $?
}

f_errorClear(){
  [[ 0 -eq 0 ]]
  return $?
}
