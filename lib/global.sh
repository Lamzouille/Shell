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

# Fonction de détection de l'OS
f_detectOS(){
  v_os=$(uname | tr '[a-z]' '[A-Z]') # recup du type d'OS 
}

# 1. Create ProgressBar function
# 1.1 Input is currentState($1) and totalState($2)
function ProgressBar {
# Process data
    let _progress=(${1}*100/${2}*100)/100
    let _done=(${_progress}*4)/10
    let _left=40-$_done
# Build progressbar string lengths
    _fill=$(printf "%${_done}s")
    _empty=$(printf "%${_left}s")

# 1.2 Build progressbar strings and print the ProgressBar line
# 1.2.1 Output example:
# 1.2.1.1 Progress : [########################################] 100%
printf "\rProgress : [${_fill// /#}${_empty// /-}] ${_progress}%%"

}

f_createMotd(){
  properties=$1
  tmpfile=$2
  motdfile=$3
  echo >> ${tmpfile}
  echo " SERVER CONFIGURATION :" >> ${tmpfile}
  echo >> ${tmpfile}
  f_detectOS
  if [ "${v_os}" == "LINUX" ]; then
    field=""
    field=$(echo "${properties}" | awk -F ';' '{print $1}' | awk -F ':' '{print $2}')
    echo " Hostname : ${field}" >> ${tmpfile}
    field=$(echo "${properties}" | awk -F ';' '{print $2}' | awk -F ':' '{print $2}')
    echo " OS Type : ${field}">> ${tmpfile}
    echo " Number of CPU : $(nproc)" >> ${tmpfile}
    echo " RAM size : $(cat /proc/meminfo | egrep MemTotal: |awk '{print $2/1024 " MB"}')" >> ${tmpfile}
    echo " Swap size : $(cat /proc/meminfo | egrep SwapTotal: |awk '{print $2/1024 " MB"}')" >> ${tmpfile}
  else 
    echo " Hostname : $(hostname | awk -F '.' '{print $1}')" >> ${tmpfile}
    field=$(echo "${properties}" | awk -F ';' '{print $2}' | awk -F ':' '{print $2}')
    echo " OS Type : ${field}">> ${tmpfile}
  fi
  field=""
  field="$(echo "${properties}" | awk -F ';' '{print $3}' | awk -F ':' '{print $2}')"
  echo " Chaine : ${field}" >> ${tmpfile}
  field=""
  field="$(echo "${properties}" | awk -F ';' '{print $4}' | awk -F ':' '{print $2}')"
  echo " Environment : ${field}" >> ${tmpfile}
  field=""
  field="$(echo "${properties}" | awk -F ';' '{print $5}' | awk -F ':' '{print $2}')"
  echo " System : ${field}" >> ${tmpfile}
  field=""
  field="$(echo "${properties}" | awk -F ';' '{print $6}' | awk -F ':' '{print $2}')"
  echo " Role : ${field}" >> ${tmpfile}
  field=""
  field="$(echo "${properties}" | awk -F ';' '{print $7}' | awk -F ':' '{print $2}')"
  echo " Class : ${field}" >> ${tmpfile}
  field=""
  field="$(echo "${properties}" | awk -F ';' '{print $8}' | awk -F ':' '{print $2}')"
  echo " Cluster index : ${field}" >> ${tmpfile}
  field=""
  field="$(echo "${properties}" | awk -F ';' '{print $9}' | awk -F ':' '{print $2}')"
  echo " Server / Node index : ${field}">> ${tmpfile} 
  echo "" >> ${tmpfile}
  mv ${tmpfile} /etc/motd
}

# Fonction de récupération de l'intégralité d'une chaine depuis un séparateur précis
f_getChaineFromField(){
  chaine=$1
  separator=$2
  index=$3

  echo $1 | awk -F "$2" -v START="$3" -v CHAINE="$1" '{print substr(CHAINE,index(CHAINE,$START))}'

}


# --------------------------------------------------------------------------------
function f_get_line_max_len {
# --------------------------------------------------------------------------------
# retourne le nombre de caractères de la ligne la plus longue dans un fichier ($1)
# possibilité d'affiner le calcul sur un champ de ligne en passant un delimiter,  
# et le numéro de champ à considérer ($2 et $3)
# paramètres:
# $1 = optionnel : le fichier contenant les lignes à analyser. Si vide retourne 0
# $2 = delimiter, optionnel : permet de passer le délimiter (, ;) à chercher
# $3 = champ, optionnel mais obligatoire si $2 est fourni :
#      > Affine le calcul du nb de caractère sur le numéro (entier) de champ indiqué
# --------------------------------------------------------------------------------
    # parse parameter
    [[ "$#" -eq 0 ]] && echo 0 && return
    file=$1
    [[ "$#" -eq 1 ]] && parseFullLine=True || parseFullLine=False 
    if [[ "$parseFullLine" -eq "False" ]]
    then 
        [[ "$2" != "" ]] && delimiter=$2
        [[ "$3" != "" ]] && field=$3 || return 1
        [[ "$3" =~ ^[0-9]+$ ]] || return 1
    fi
    # # debug parse parameter, comment it out !!:
    # echo -e "$file\n$parseFullLine\n$delimiter\n$filed"

    # now do some stuff 
    max_len=0
    while read line
    do 
        case $parseFullLine in 
            "True")  cur_len=$(echo $line | wc -m) ;;
            "False") cur_len=$(echo $line | cut -d "$delimiter" -f "$field" | wc -m) ;;
        esac
        [[ $cur_len -gt $max_len ]] && max_len=$cur_len 
    done < $file
    echo $max_len
}


# Fonction de reformatage de l'adresse MAC avec 6x2 caractères
f_reformatMacAddress(){
  addr_nf=$1
  list=$(echo ${addr_nf} | tr ':' ' ')
  c=""

  for b in $list
  do
    b="00$b"
    c="$c $(echo $b | nawk '{print substr($1,length($1)-1,2)}')"
  done

  echo $c | tr ' ' ':' 
}

# Fonction de vérification de la connectivité SSH sur une machine
f_checkSshPubkeyAuthent(){
  user=$1
  host=$2
  ssh -q  -o NumberOfPasswordPrompts=0 $user@$host ls 2>&1 > /dev/null
  echo $?
}

# Fonction d'envoi de fichier sur un hôte distant
f_sendFilesToRemoteHost(){
  user=$1
  host=$2
  sourceFiles=$3
  targetFiles=$4
  command="scp -rqp $sourceFiles $user@$host:${targetFiles}"
  f_logMessage DEBUG "Sending file $sourceFiles to $host:/$targetFiles"
  eval $command
  return $?
}

# Fonction de vérification de la présence d'un répertoire sur un hôte distant
f_checkRemoteDirExists(){
  user=$1
  host=$2
  directory=$3
  ssh -q  $user@$host "[[ ! -d $directory ]]" 2>&1 >/dev/null
  echo $?
}

# Fonction de vérification de la présence d'un fichier sur un hôte distant
f_checkRemoteFileExists(){
  user=$1
  host=$2
  file=$3
  ssh -q  $user@$host "[[ ! -f $file ]]" 2>&1 >/dev/null
  return $?
}

# Fonction de création d'un répertoire sur un hôte distant 
f_createRemoteDir(){
  user=$1
  host=$2
  directory=$3
  [[ $(f_checkRemoteDirExists $user $host $directory -eq 0) ]] && ssh -q  $user@$host "mkdir -p $directory" 2>&1 >/dev/null || [[ 0 -eq 0 ]]
  return $?
}

# Fonction d execution d'une commande sur un hôte distant
f_executeRemoteCommand(){
  user="$1"
  host="$2"
  command="$3"
  ssh -q $user@$host "${command}" </dev/null
  return $?
}
