#!/usr/bin/bash

#####################################################################################
#                                [gestion-zone.sh]                                   #
#####################################################################################
# DESCRIPTION : Modification du fichier template pour la création de la zone        #
#                                                                                   #
#####################################################################################
# UTILISATION : gestion-zone.sh [-c file.properties] -[h] [-v]                       #
#                                                                                   #
# PARAMETRES :  [-c <config>] : Fichier de properties à utiliser                    #
#               [-h] : Facultatif : Affiche l'aide du script                        #
#               [-v] : Facultatif : Affiche la version du script                    #
#                                                                                   #
# FONCTIONNEMENT : Creation des ZFS et configuration de la zone                     #
#                                                                                   #
# DEPENDANCES :  bibliothèques nécéssaire au fonctionnement du script               #
#                - lib.utilities.sh                                                 #
#                - lib.naming.sh                                                    #
#                - lib.system.sh                                                    #
#                                                                                   #
#####################################################################################
# AUTEUR : S.THIRARD                                                                #
# DATE DE CREATION : 23/03/2018                                                     #
#####################################################################################
# REVISIONS :                                                                       #
#-----------------------------------------------------------------------------------#
# DATE : 10/04/2018                                                                 #
# MODIFICATIONS : Initialisation du script                                          #
# AUTEUR : S.THIRARD                                                                #
#-----------------------------------------------------------------------------------#
# DATE : 13/04/2018                                                                 #
# MODIFICATIONS : Ajout de l'option de destruction de la zone                       #
# AUTEUR : S.THIRARD                                                                #
#-----------------------------------------------------------------------------------#
# DATE : 28/05/2018                                                                 #
# MODIFICATIONS : Alimentation des .profile des différents users                    #
# AUTEUR : S.THIRARD                                                                #
#####################################################################################

#=============================== VARIABLES GLOBALES =================================
DEBUG_MODE=0
#====================================================================================

SCRIPT_NAME=$(basename "$0")
SCRIPT_PATH=$(dirname "$0")
SCRIPT_PATH=$(cd "${SCRIPT_PATH}"; pwd -P)
SCRIPT_ARGS=$*
LOADED_LIBS=""
CONF_PATH="${SCRIPT_PATH}/../conf"
LIB_PATH="${SCRIPT_PATH}/../lib"
TMP_PATH="${SCRIPT_PATH}/../tmp"
VAR_PATH="${SCRIPT_PATH}/../var"
ZONE_CONF_PATH=${CONF_PATH}/zoneconfig
PROPERTIES_PATH="${CONF_PATH}/properties/"
SCRIPT_VERSION="1.0"

#====================================================================================

# ICI LES VARIABLES GLOBALES OU CONSTANTES PERSONNALISEES
# FORMAT : MAJ_MAJ_MAJ ...

#====================================================================================

GRID_PATH=/softs/souche-grid
GRID_BIN_PATH=/u01/app/12.2.0/grid/bin
ORACLE_PATH=/softs/souche-database

#================================ FONCTIONS LOCALES =================================

f_loadExternalLibs(){   # Chargement des librairie externes : Lancer au debut du main

  [[ ! -d ${LIB_PATH} ]] && exit -1
  for lib in $(ls ${LIB_PATH}/lib.*.sh); do
    . ${lib}
    LOADED_LIBS="${LOADED_LIBS} $(basename ${lib})"
  done
  if [[ DEBUG_MODE -ne 0 ]]; then
    printf "\e[36mChargement des librairie externes ...\n"
    printf "+++++++++++++++++++++++++++++++++++++++++++++++++++++\n"
    printf "Liste des librairies chargées :\n"
    printf " - %s\n" $(echo ${LOADED_LIBS})
    printf "+++++++++++++++++++++++++++++++++++++++++++++++++++++\n"
    printf "Chargement des librairie terminé ...\e[36m%b\e[0m\n"
  fi
}

f_createZFS(){

  ZFS_PATH=$1

  mkdir -p /"${ZFS_PATH}"
  if [ "$(zfs list -H /${ZFS_PATH} | grep ${ZFS_PATH})" != "" ]; then
    f_logMessage INFO "Le point de montage ${ZFS_PATH} existe déjà"
  else
    f_logMessage INFO "Création du ZFS ${ZFS_PATH}"
    zfs create -o mountpoint=/"${ZFS_PATH}" ${ZFS_PATH}
    sleep 2
  fi
}



# Fonction de récupération de la premiere adresse MAC non utilisée sur la carte passée en $1
f_getMacAddress(){
  INTERFACE=$1

  if [ $# -eq 0 ]; then
    echo "Nombre d'arguments incorrect - Usage : f_getMacAddress <interface_name>"
    exit 1
  fi

  a="dladm show-phys -m ${INTERFACE} | grep -v ADDRESS | grep -v primary | grep -v yes | nawk '{print \$2}'"
  test=$(ls /etc/zones/ | egrep -e "^z.*\.xml" | wc -l)
  if [ $test -gt 0 ]; then
    b=$(grep -h mac-address /etc/zones/z*.xml | nawk '{print $6}' | nawk -F '"' '{ print "grep -v " $2 " | "}')
  else
    b=""
  fi
  c=$a" | "$b" head -n 1"
  eval "$c"
}

# f_labelDisk(){

#   ZONENAME=$1
#   RAWDEVICE=$2

#     if [ -z ${RAWDEVICE} ]; then
#       zlogin -l root ${ZONENAME} ". .profile;${GRID_BIN_PATH}/asmcmd afd_label DATA_GRP1 /dev/rdsk/${RAWFS0_DEVICE} --init"
#     else
#       f_logMessage ERROR "${RAWDEVICE} Inexistant - Labellisation impossible"
#     fi

# }

f_prepareZone(){

  mkdir -p ${ZONE_CONF_PATH}

  MASTER_ARCHIVE_FILE=${CONF_PATH}/zones-archives/master.uar
  ZONE_CONFIG_FILE=${ZONE_CONF_PATH}/create_${ZONENAME}.cfg
  ZONE_XML_FILE=${ZONE_CONF_PATH}/create_${ZONENAME}.xml

  f_createZFS "${ZONEROOTPATH}"
  f_createZFS "${ZONEROOTPATH}/${ZONEPATH}"
  f_createZFS "${ZONEROOTPATH}/${ZONEPATH}-fs"

  cat ${PROPERTIES_FILE} | grep MOUNTPOINT | while read line
  do
    fs=$(echo $line | awk -F '=' '{print $2}')
    f_createZFS "${ZONEROOTPATH}/${ZONEPATH}-fs/${fs}"
  done

  f_createZFS "backup"
  f_createZFS "backup/${ZONEPATH}"
  f_createZFS "backup/${ZONEPATH}/zoneconfig"
  f_createZFS "backup/${ZONEPATH}/zfssnap"
  f_createZFS "backup/${ZONEPATH}/rman"

  # Génération du fichier de création de la zone (CFG)
  if [ -f ${ZONE_CONFIG_FILE} ]; then
    rm -f ${ZONE_CONFIG_FILE}
  fi

  echo "create -b" >> ${ZONE_CONFIG_FILE}
  echo "set zonepath=/${ZONEROOTPATH}/${ZONEPATH}" >> ${ZONE_CONFIG_FILE}
  VNIC_LIST=$(cat ${PROPERTIES_FILE} | egrep -e "^VNIC" |  nawk -F "_" '{print $1}' | sort -u)
  for vnic in ${VNIC_LIST}
  do
    NAME=$(cat ${PROPERTIES_FILE} | grep $vnic | grep NAME | awk -F "=" '{print $2}')
    LOWERLINK=$(cat ${PROPERTIES_FILE} | grep $vnic | grep LOWERLINK  | awk -F "=" '{print $2}')
    #MACADDR=$(cat ${PROPERTIES_FILE} | grep $vnic | grep MAC | awk -F "=" '{print $2}')
    # echo "RECUPERATION MAC ADRESSE"
    # MACADDR=$(f_getMacAddress ${LOWERLINK})
    # echo ${MACADDR}
    echo "add anet" >> ${ZONE_CONFIG_FILE}
    echo "set linkname=${NAME}" >> ${ZONE_CONFIG_FILE}
    echo "set lower-link=${LOWERLINK}" >> ${ZONE_CONFIG_FILE}
    echo "set mac-address=auto" >> ${ZONE_CONFIG_FILE}
    echo "set configure-allowed-address=false" >> ${ZONE_CONFIG_FILE}
    echo "end" >> ${ZONE_CONFIG_FILE}
  done

  FS_LIST=$(cat ${PROPERTIES_FILE} | egrep -e "^FS" |  nawk -F "_" '{print $1}' | sort -u)
  for fs in ${FS_LIST}
  do
    MOUNTPOINT=$(cat ${PROPERTIES_FILE} | grep $fs | grep MOUNTPOINT | awk -F "=" '{print $2}')
    TYPE=$(cat ${PROPERTIES_FILE} | grep $fs | grep TYPE | awk -F "=" '{print $2}')
    echo "add fs" >> ${ZONE_CONFIG_FILE}
    echo "set dir=/${MOUNTPOINT}" >> ${ZONE_CONFIG_FILE}
    echo "set type=${TYPE}" >> ${ZONE_CONFIG_FILE}
    echo "set special=/${ZONEROOTPATH}/${ZONEPATH}-fs/${MOUNTPOINT}" >> ${ZONE_CONFIG_FILE}
    echo "end" >> ${ZONE_CONFIG_FILE}
  done

  RAW_LIST=$(cat ${PROPERTIES_FILE} | egrep -e "^RAWFS" |  nawk -F "_" '{print $1}' | sort -u)
  for fs in ${RAW_LIST}
  do
    DEVICE=$(cat ${PROPERTIES_FILE} | grep $fs | grep DEVICE | awk -F "=" '{print $2}')
    echo "add device" >> ${ZONE_CONFIG_FILE}
    echo "set match=/dev/rdsk/${DEVICE}" >> ${ZONE_CONFIG_FILE}
    echo "end" >> ${ZONE_CONFIG_FILE}
  done

  echo "verify" >> ${ZONE_CONFIG_FILE}
  echo "commit" >> ${ZONE_CONFIG_FILE}

  # Mise à jour du template XML

  sed -e s:\!__ZONENAME__\!:$ZONENAME:g \
    -e s:\!__VNIC0_NAME__\!:$VNIC0_NAME:g \
    -e s:\!__VNIC0_IPADDR__\!:$VNIC0_IPADDR:g \
    -e s:\!__VNIC1_NAME__\!:$VNIC1_NAME:g \
    -e s:\!__VNIC1_IPADDR__\!:$VNIC1_IPADDR:g \
    -e s:\!__VNIC2_NAME__\!:$VNIC2_NAME:g \
    -e s:\!__VNIC2_IPADDR__\!:$VNIC2_IPADDR:g \
    -e s:\!__DEFAULTROUTE__\!:$DEFAULTROUTE:g $TEMPLATE_XML > ${ZONE_XML_FILE}

  # Installation de la zone
  zonecfg -z ${ZONENAME} -f ${ZONE_CONF_PATH}/create_${ZONENAME}.cfg
  zoneadm -z ${ZONENAME} install -c ${ZONE_CONF_PATH}/create_${ZONENAME}.xml -a ${MASTER_ARCHIVE_FILE}
  zoneadm -z ${ZONENAME} boot

  # Temporisation pour boot de la zone

  _start=1
  _end=300

  # Proof of concept
  for number in $(seq ${_start} ${_end})
  do
      sleep 0.1
      ProgressBar ${number} ${_end}
  done
  f_logMessage INFO "${ZONENAME} booted"

  f_logMessage INFO "Création des interfaces IP & IPMP"

  # Création des interfaces
  for vnic in ${VNIC_LIST}
  do
    NAME=$(cat ${PROPERTIES_FILE} | grep $vnic | grep NAME | awk -F "=" '{print $2}')
    f_logMessage INFO "Création de l'interface ${NAME}"
    zlogin -l root ${ZONENAME} "ipadm create-ip ${NAME}"
  done

  # Création des interfaces ipmp
  IPMP_LIST=$(cat ${PROPERTIES_FILE} | egrep -e "^IPMP" |  awk -F "_" '{print $1}' | sort -u)
  for ipmp in ${IPMP_LIST}
  do
    NAME=$(grep $ipmp ${PROPERTIES_FILE} | grep NAME | awk -F "=" '{print $2}')
    MEMBERS="$(grep $ipmp ${PROPERTIES_FILE} | grep MEMBER | awk -F "=" 'BEGIN{ORS=" "} {print " -i " $2}')"
    ADDRESS="$(grep $ipmp ${PROPERTIES_FILE} | grep IPADDR | awk -F "=" '{print $2}')"

    zlogin -l root ${ZONENAME} "ipadm create-ipmp ${NAME}"
    zlogin -l root ${ZONENAME} "ipadm add-ipmp ${MEMBERS} ${NAME}"

    for addr in $ADDRESS;
    do
      zlogin -l root ${ZONENAME} "ipadm create-addr -a $addr ${NAME}"
    done
  done

  zlogin -l root ${ZONENAME} "route -p add default 10.236.80.1"

  f_logMessage INFO "Reboot de la ZONE"
  zoneadm -z ${ZONENAME} reboot

  sleep 10

  # Création des interfaces pour les zones orac
  if [[ ${ORACLE} = "TRUE" ]]; then

    f_logMessage INFO "Création des groupes spécifiques oracle"
    zlogin -l root ${ZONENAME} "groupadd -g 1000 dba"
    zlogin -l root ${ZONENAME} "groupadd -g 1001 oinstall"
    zlogin -l root ${ZONENAME} "groupadd -g 1003 racoper"
    zlogin -l root ${ZONENAME} "groupadd -g 1004 asmdba"
    zlogin -l root ${ZONENAME} "groupadd -g 1005 asmoper"
    zlogin -l root ${ZONENAME} "groupadd -g 1006 asmadmin"

    f_logMessage INFO "Création des users et répertoires pour les zones oracle"
    zlogin -l root ${ZONENAME} "useradd -u 1000 -g 1001 -s /usr/bin/sh -d /u01/app/grid -c 'Utilisateur grid' grid"
    zlogin -l root ${ZONENAME} "usermod -G +1004,1000,1005,1006 grid"
    zlogin -l root ${ZONENAME} "/opt/capgemini/bin/change-passwd.exp grid 123_Orcl!"
    zlogin -l root ${ZONENAME} "useradd -u 1001 -g 1001 -s /usr/bin/sh -d /u01/app/oracle -c 'Utilisateur oracle' oracle"
    zlogin -l root ${ZONENAME} "usermod -G +1000,1004 oracle"
    zlogin -l root ${ZONENAME} "/opt/capgemini/bin/change-passwd.exp oracle 123_Orcl!"

    f_logMessage INFO "Création des arborescences oracle et attribution des bons droits"
    zlogin -l root ${ZONENAME} "mkdir -p /u01/app/oracle/product/ /u01/app/grid /u01/app/oraInventory/"
    zlogin -l root ${ZONENAME} "chown -R oracle:oinstall /u01/app/oracle"
    zlogin -l root ${ZONENAME} "chown -R grid:oinstall /u01/app/grid"
    zlogin -l root ${ZONENAME} "chown -R grid:oinstall /u01/app/oraInventory"
    zlogin -l root ${ZONENAME} "chmod 775 /u01/app/oraInventory"
    zlogin -l root ${ZONENAME} "mkdir -p /softs/souche-grid"
    zlogin -l root ${ZONENAME} "mkdir -p /softs/souche-database"
    zlogin -l root ${ZONENAME} "mkdir -p /u01/app/12.2.0/grid"

    f_logMessage INFO "Copie des souches GRID et ORACLE depuis le point de montage NFS"
    zlogin -l root ${ZONENAME} "mount -f nfs  dm0pzfsi0102.nirvana-mgt.lan:/export/SOUCHES /mnt"
    zlogin -l root ${ZONENAME} "cp /mnt/Middleware/solarissparc64_12201_grid_home.zip ${GRID_PATH}"
    zlogin -l root ${ZONENAME} "unzip /softs/souche-grid/solarissparc64_12201_grid_home.zip -d ${GRID_PATH}"
    zlogin -l root ${ZONENAME} "rm -f ${GRID_PATH}/solarissparc64_12201_grid_home.zip"
    zlogin -l root ${ZONENAME} "cp /mnt/Middleware/solarissparc64_12201_database.zip ${ORACLE_PATH}"
    zlogin -l root ${ZONENAME} "unzip /softs/souche-database/solarissparc64_12201_database.zip -d ${ORACLE_PATH}"
    zlogin -l root ${ZONENAME} "rm -f ${ORACLE_PATH}/solarissparc64_12201_database.zip"
    zlogin -l root ${ZONENAME} "cp -r ${GRID_PATH}/* /u01/app/12.2.0/grid"
    zlogin -l root ${ZONENAME} "chown -R grid:oinstall /u01/app/12.2.0/grid"

    f_logMessage INFO "Installation des packages pour RAC/GRID"
    zlogin -l root ${ZONENAME} "pkg install oracle-rdbms-server-12-1-preinstall"
    zlogin -l root ${ZONENAME} "pkg install openmp"
    zlogin -l root ${ZONENAME} "pkg install assembler"
    zlogin -l root ${ZONENAME} "pkg install make"
    zlogin -l root ${ZONENAME} "pkg install dtrace"
    zlogin -l root ${ZONENAME} "pkg install header"
    zlogin -l root ${ZONENAME} "pkg install oracka"
    zlogin -l root ${ZONENAME} "pkg install pkg install pkg://solaris/system/library"
    zlogin -l root ${ZONENAME} "pkg install linker"
    zlogin -l root ${ZONENAME} "pkg install xcu4"
    zlogin -l root ${ZONENAME} "pkg install x11-info-clients"
    zlogin -l root ${ZONENAME} "pkg install --accept jdk-8"
    zlogin -l root ${ZONENAME} "pkg install --accept pkg://solaris/runtime/java/jre-8"
    zlogin -l root ${ZONENAME} "pkg install pkg://solaris/system/picl"

    f_logMessage INFO "Modification des RAW devices"
    zlogin -l root ${ZONENAME} "chown -R grid:asmadmin /dev/rdsk/*"
    zlogin -l root ${ZONENAME} "chmod 660 /dev/rdsk/*"

    f_logMessage INFO "Ajout des variables d'environnement pour l'utilisateur root"
    zlogin -l root ${ZONENAME} "echo 'export ORACLE_HOME=/u01/app/12.2.0/grid' >> /root/.profile"
    zlogin -l root ${ZONENAME} "echo 'export CRS_HOME=\$ORACLE_HOME' >> /root/.profile"

    f_logMessage INFO "Ajout des variables d'environnement pour l'utilisateur oracle"
    zlogin -l root ${ZONENAME} "echo 'export ORACLE_HOME=/u01/app/oracle/product/12.2.0/dbhome_1' >> /u01/app/oracle/.profile"
    zlogin -l root ${ZONENAME} "echo 'export ORACLE_BASE=/u01/app/oracle' >> /u01/app/oracle/.profile"
    zlogin -l root ${ZONENAME} "echo 'export PATH=\$ORACLE_HOME/bin:\$PATH' >> /u01/app/oracle/.profile"
    _alias="ls -ltra"
    zlogin -l root ${ZONENAME} "echo alias ll=\'${_alias}\' >> /u01/app/oracle/.profile"
    zlogin -l root ${ZONENAME} "echo 'export GRID_HOME=\$ORACLE_HOME' >> /u01/app/oracle/.profile"

    f_logMessage INFO "Ajout des variables d'environnement pour l'utilisateur grid"
    zlogin -l root ${ZONENAME} "echo 'export ORACLE_HOME=/u01/app/12.2.0/grid' >> /u01/app/grid/.profile"
    zlogin -l root ${ZONENAME} "echo 'export JAVA=\$ORACLE_HOME/jdk/bin/sparcv9/java' >> /u01/app/grid/.profile"
    zlogin -l root ${ZONENAME} "echo 'export LD_LIBRARY_PATH=\$ORACLE_HOME/lib:/usr/lib:\$ORACLE_HOME/jdk/lib/sparcv9/jli/' >> /u01/app/grid/.profile"
    zlogin -l root ${ZONENAME} "echo 'export PATH=\$ORACLE_HOME/bin:\$PATH' >> /u01/app/grid/.profile"
    zlogin -l root ${ZONENAME} "echo 'export CRS_HOME=\$ORACLE_HOME' >> /u01/app/grid/.profile"
    zlogin -l root ${ZONENAME} "echo 'export GRID_HOME=\$ORACLE_HOME' >> /u01/app/grid/.profile"
    zlogin -l root ${ZONENAME} "echo alias ll=\'${_alias}\' >> /u01/app/grid/.profile"
    zlogin -l root ${ZONENAME} "chown grid:oinstall /u01/app/grid/.profile"


    f_logMessage INFO "Création liens symboliques pour installation du GIMR"
    zlogin -l root ${ZONENAME} "ln -s /usr/jdk/instances/jdk1.6.0/lib/sparcv9/jli/libjli.so /lib/64/libjli.so"
    zlogin -l root ${ZONENAME} "ln -s /usr/jdk/instances/jdk1.6.0/lib/sparcv9/jli/libjli.so /lib/32/libjli.so"
    zlogin -l root ${ZONENAME} "chmod -R 777 /u01/app/12.2.0/grid/QOpatch"

    f_logMessage INFO "Labelisation des disques"
    [[ "${RAWFS0_DEVICE}" != "" ]] && zlogin -l root ${ZONENAME} ". .profile;${GRID_BIN_PATH}/asmcmd afd_label DATA_GRP1 /dev/rdsk/${RAWFS0_DEVICE} --init"
    [[ "${RAWFS1_DEVICE}" != "" ]] && zlogin -l root ${ZONENAME} ". .profile;${GRID_BIN_PATH}/asmcmd afd_label DATA_GRP2 /dev/rdsk/${RAWFS1_DEVICE} --init"
    [[ "${RAWFS2_DEVICE}" != "" ]] && zlogin -l root ${ZONENAME} ". .profile;${GRID_BIN_PATH}/asmcmd afd_label RECO_GRP1 /dev/rdsk/${RAWFS2_DEVICE} --init"
    [[ "${RAWFS3_DEVICE}" != "" ]] && zlogin -l root ${ZONENAME} ". .profile;${GRID_BIN_PATH}/asmcmd afd_label RECO_GRP2 /dev/rdsk/${RAWFS3_DEVICE} --init"
    [[ "${RAWFS4_DEVICE}" != "" ]] && zlogin -l root ${ZONENAME} ". .profile;${GRID_BIN_PATH}/asmcmd afd_label MGMT_GRP1 /dev/rdsk/${RAWFS4_DEVICE} --init"
    [[ "${RAWFS5_DEVICE}" != "" ]] && zlogin -l root ${ZONENAME} ". .profile;${GRID_BIN_PATH}/asmcmd afd_label MGMT_GRP2 /dev/rdsk/${RAWFS5_DEVICE} --init"

    # f_logMessage INFO "Alimentation du fichier /etc/hosts"
    # HOST_LIST=$(egrep -e "^HOST" ${PROPERTIES_FILE} | awk -F "=" '{print $2}' )
    # for host in ${HOST_LIST}
    # do
    #   a=$(echo ${host} | sed 's/:/ /g')
    #   zlogin -l root ${ZONENAME} "echo '${a}'>> /etc/hosts"
    # done

    f_logMessage INFO "Modification de /etc/project"
    zlogin -l root ${ZONENAME} "echo 'system:0::::' >> /etc/project.tmp"
    zlogin -l root ${ZONENAME} "echo 'user.root:1::::process.max-file-descriptor=(basic,1024,deny);process.max-stack-size=(basic,10485760,deny)' >> /etc/project.tmp"
    zlogin -l root ${ZONENAME} "echo 'noproject:2::::' >> /etc/project.tmp"
    zlogin -l root ${ZONENAME} "echo 'default:3::::' >> /etc/project.tmp"
    zlogin -l root ${ZONENAME} "echo 'group.staff:10::::' >> /etc/project.tmp"
    zlogin -l root ${ZONENAME} "echo 'user.grid:100:Project for Oracle Clusterware user:grid::process.max-file-descriptor=(basic,1024,deny);process.max-stack-size=(basic,10485760,deny)' >> /etc/project.tmp"
    zlogin -l root ${ZONENAME} "echo 'user.oracle:101:Project for Oracle Database user:grid::process.max-file-descriptor=(basic,1024,deny);process.max-stack-size=(basic,10485760,deny)' >> /etc/project.tmp"
    zlogin -l root ${ZONENAME} "mv /etc/project.tmp /etc/project"
  fi

  # Mise en forme du XML généré dans /etc/zones
  xmllint --format /etc/zones/${ZONENAME}.xml > /etc/zones/${ZONENAME}.xml.tmp
  mv /etc/zones/${ZONENAME}.xml.tmp /etc/zones/${ZONENAME}.xml

  # Mise a jour du motd avant reboot
  /usr/bin/bash /opt/capgemini/bin/update-motd.sh

  f_logMessage INFO "Reboot de la ZONE"
  zoneadm -z ${ZONENAME} reboot

  sleep 10

  f_logMessage INFO "La zone ${ZONENAME} a bien été créée"
}

f_destroyZone(){
  ZONE_NAME=$1

  f_promptYesNoAnswer "Vous êtes sur le point de détruire la zone ${1} - Etes vous sur ?" "$ANSWER"

  zoneadm -z ${ZONE_NAME} halt
  zoneadm -z ${ZONE_NAME} uninstall
  zonecfg -z ${ZONE_NAME} delete -F
  f_logMessage INFO "Zone ${ZONENAME} successfully destroyed !"

  f_promptYesNoAnswer "Voulez vous détruire les ZFS associés ?" "$ANSWER"
  # Chargement du fichier properties associés à la zone
  ZONE_PROPERTIES=$(echo ${ZONE_NAME} | awk -F "." '{print $1}')
  . ${PROPERTIES_PATH}/${ZONE_PROPERTIES}.properties
  zfs destroy -r "${ZONEROOTPATH}/${ZONEPATH}-fs"
  zfs destroy -r "${ZONEROOTPATH}/${ZONEPATH}"
  f_logMessage INFO "ZFS successfully destroyed !"

  # Formatage des RAW DISKS
  # RAW_LIST=$(cat ${PROPERTIES_FILE} | egrep -e "^RAWFS" |  nawk -F "_" '{print $1}' | sort -u)
  # for fs in ${RAW_LIST}
  # do
  #   DEVICE=$(cat ${PROPERTIES_FILE} | grep $fs | grep DEVICE | awk -F "=" '{print $2}')
  #   dd if=/dev/zero of=/dev/rdsk/${DEVICE} bs=4k count=1024
  # done
}

f_showUsage(){ # aide du script OBLIGATOIRE
  printf "\n%s [-c <config>] [-h] [-v]\n\n" ${SCRIPT_NAME}
  printf "     [-c <config>] : Création de la zone avec le fichier properties passé en param \n"
  printf "     [-d <zonename>] : Destruction de la zone\n"
  printf "     [-v] : Affiche la version du script\n"
  printf "     [-h] : Affiche ce message d'aide\n\n"
}

f_parseParams(){ # parse des parametres du script
  if [ "$*" = "" ] # pour l'action par defaut du script sans argument
  then
    f_showUsage # ici on affiche l'aide
    exit 0
  fi

  while getopts ":c:d:hv" opt $@ # parse des parametres
  do
    case $opt in
      h )
        f_showUsage
        exit 0
      ;;
      c )
        if [[ -f $OPTARG ]]; then
          PROPERTIES_FILE=${OPTARG}
          . ${PROPERTIES_FILE}
          f_prepareZone
        else
          printf "Le fichier de properties spécifié n'existe pas.\n\n"
          exit -1
        fi
      ;;
      d )
        f_destroyZone $OPTARG
      ;;
      v )
         printf "\e[36m\nVersion du script : ${SCRIPT_VERSION}. \n\n\e[0m"
         exit 0
      ;;
      \? )
        printf "\nAppel du script invalide : -%s\n\n" "$OPTARG" >&2 # tout le reste erreur de syntaxe
        f_showUsage
        exit -1
      ;;

      : )
        printf "\nOption %s requiert un argument.\n\n" "$OPTARG" >&2 # manque argument au parametre
        f_showUsage
        exit -1
      ;;
    esac
  done

  # mauvais usage de la ligne de commnade si encore des paramètres à parser
  # à commenter si il faut traiter des paramètre en fin de commande sans switch
  if [ $OPTIND -le $# ]
  then
    f_showUsage
    exit -1
  fi
}

#================================== VARIABLES =======================================

#====================================================================================

#===================================== MAIN =========================================

#f_detectOS # détection de l'OS
f_loadExternalLibs # chargement des libs de $LIB_DIR
f_setCommandAlias # permet de redefinir des commandes pour Solaris ou Linux
f_parseParams ${SCRIPT_ARGS} # Parse des arguments du script : Fonction à modifier plus haut. Si pas d'argument commenter la ligne

#====================================================================================
