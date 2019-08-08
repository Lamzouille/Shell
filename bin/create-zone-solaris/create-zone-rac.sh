#!/usr/bin/bash

#####################################################################################
#                                [create-zone-rac.sh]                               #
#####################################################################################
# DESCRIPTION : Modification du fichier template pour la création de la zone        #
#                                                                                   #
#####################################################################################
# UTILISATION : create-zone-rac.sh [-c file.properties] -[h] [-v]                   #
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
# DATE : 19/04/2018                                                                 #
# MODIFICATIONS : Initialisation du script                                          #
# AUTEUR : S.THIRARD                                                                #
#-----------------------------------------------------------------------------------#
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
ZONE_CONF_PATH="${CONF_PATH}/zoneconfig"
PROPERTIES_PATH="${CONF_PATH}/properties/"
SCRIPT_VERSION="1.0"

#====================================================================================

# ICI LES VARIABLES GLOBALES OU CONSTANTES PERSONNALISEES
# FORMAT : MAJ_MAJ_MAJ ...

#====================================================================================

GRID_PATH=/softs/souche-grid
GRID_BIN_PATH=/u01/app/12.2.0/grid/bin
ORACLE_PATH=/softs/souche-database
MASTER_ARCHIVE_FILE=${CONF_PATH}/zones-archives/master.uar
ZONE_CONFIG_FILE=${ZONE_CONF_PATH}/create_${CLUSTER_NAME}.cfg
ZONE_XML_FILE=${ZONE_CONF_PATH}/create_${CLUSTER_NAME}.xml

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

f_verifVNIC(){

  VNIC_=$1

  test=$(dladm show-vnic | grep -v LINK | grep ${VNIC_} | wc -l)
  if [ $test -eq 0 ]; then
    f_logMessage ERROR "${VNIC_} manquante ..."
    f_logMessage DEBUG "Executez la commande suivante sur le LDOM ${NODE1_LDOM} : dladm create-vnic -l <net-interface> ${VNIC_}"
    exit 1
  else
    f_logMessage INFO "${VNIC_} : OK"
  fi
}

f_verifRemoteVNIC(){

  VNIC_=$1
  USER=$2
  HOST=$3

  test=$(ssh -q -l ${USER} -o StrictHostKeyChecking=no ${HOST} "dladm show-vnic | grep -v LINK | grep ${VNIC_} | wc -l")
  if [ $test -eq 0 ]; then
    f_logMessage ERROR "${VNIC_} manquante ..."
    f_logMessage DEBUG "Executez la commande suivante sur le LDOM ${HOST} : dladm create-vnic -l <net-interface> ${VNIC_}"
    exit 1
  else
    f_logMessage INFO "${VNIC_} : OK"
  fi
}

f_genSSHkey(){
  
  test=$(ls ~/.ssh/id_rsa.pub | wc -l)
  if [ test -ne 1 ]; then
    f_logMessage INFO "Création de la clé publique "
    ssh-keygen -t rsa -f ~/.ssh/id_rsa -q -N ''
    f_logMessage INFO "Copie de la clé publique vers le noeud 2 : ${NODE2_LDOM}"
    scp -rp ~/.ssh/id_rsa.pub ${NODE2_LDOM}:~/.ssh/authorized_keys
  fi
}

f_verifPackage(){
  
  PACKAGE_NAME=$1

  isInstalled=$(pkg info ${PACKAGE_NAME} | grep "State: Installed" | wc -l)
  if [ ${isInstalled} -eq 1 ]; then
    f_logMessage INFO "Package ${PACKAGE_NAME} : OK"
  else
    f_logMessage WARNING "Package ${PACKAGE_NAME} : KO "
  fi
}

f_verifRemotePackage(){
  
  PACKAGE_NAME=$1
  USER=$2
  HOST=$3

  isInstalled=$(ssh -q -l ${USER} -o StrictHostKeyChecking=no ${HOST} "pkg info ${PACKAGE_NAME} | grep 'State: Installed' | wc -l")
  if [ ${isInstalled} -eq 1 ]; then
    f_logMessage INFO "Package ${PACKAGE_NAME} : OK"
  else
    f_logMessage WARNING "Package ${PACKAGE_NAME} : KO"
  fi
}

f_checkZpool(){
  
  ZPOOL_NAME=$1
  
  NB_ZPOOL=$(zpool list | grep ${ZPOOL_NAME} | grep -v ALLOC | wc -l)
  if [ ${NB_ZPOOL} -eq 0 ]; then
    f_logMessage FATAL "ZPOOL ${ZPOOL_NAME} : KO"
    exit 1
  else
    f_logMessage INFO "ZPOOL ${ZPOOL_NAME} : OK"
  fi
}

f_checkRemoteZpool(){
  
  ZPOOL_NAME=$1
  USER=$2
  HOST=$3

  NB_ZPOOL=$(ssh -q -l ${USER} -o StrictHostKeyChecking=no ${HOST} "zpool list | grep ${ZPOOL_NAME} | grep -v ALLOC | wc -l")
  if [[ ${NB_ZPOOL} -eq 0 ]]; then
    f_logMessage FATAL "ZPOOL ${ZPOOL_NAME} : KO"
    exit 1
  else
    f_logMessage INFO "ZPOOL ${ZPOOL_NAME} : OK"
  fi
}

f_checkFile(){
  
  FILE=$1
  if [ ! -f ${FILE} ]; then
    f_logMessage FATAL "Fichier ${FILE} : KO"
    exit 1
  else
    f_logMessage INFO "Fichier ${FILE} : OK"
  fi
}

f_checkRemoteFile(){

  FILE=$1
  USER=$2
  HOST=$3

  NB_FILE=$(ssh -q -l ${USER} -o StrictHostKeyChecking=no ${HOST} "ls ${FILE} | wc -l")
  if [[ ${NB_FILE} -ne 1 ]]; then
    f_logMessage FATAL "Fichier ${FILE} : KO"
    exit 1
  else 
    f_logMessage INFO "Fichier ${FILE} : OK"
  fi
}

f_verifPrerequis(){

  mkdir -p ${ZONE_CONF_PATH}
  
  printf "\n"
  f_logMessage INFO "###########################################################################"
  f_logMessage INFO "#  Verification des prerequis pour la création du cluster ${CLUSTER_NAME}  #"
  f_logMessage INFO "###########################################################################"
  printf "\n"

  # Vérification de la connectivité SSH
  f_logMessage INFO "Vérification de la connectivité SSH"
  ssh -l root -q -o StrictHostKeyChecking=no -o BatchMode=yes -o ConnectionAttempts=1 ${NODE2_LDOM} echo > /dev/null
  if [ $? -ne 0 ];then
    f_logMessage FATAL "Connection SSH failed on ${NODE2_LDOM}"
    exit 0
  else 
    f_logMessage INFO "Connectivité SSH : OK"
  fi
  printf "\n"


  # Vérification de la présence des VNICS
  f_logMessage INFO "Verification des VNICS sur le LDOM ${NODE1_LDOM}"
  VNIC_LIST=$(cat ${PROPERTIES_FILE} | grep VNIC | grep NAME | awk -F "=" '{print $2}')
  for vnic in ${VNIC_LIST}
  do
    f_verifVNIC ${vnic}
  done
  printf "\n"

  f_logMessage INFO "Verification des VNICS sur le LDOM ${NODE2_LDOM}"
  VNIC_LIST=$(cat ${PROPERTIES_FILE} | grep VNIC | grep NAME | awk -F "=" '{print $2}')
  for vnic in ${VNIC_LIST}
  do
    f_verifRemoteVNIC ${vnic} root ${NODE2_LDOM}
  done
  printf "\n"

  # Vérification de la présence des ZPOOLS
  f_logMessage INFO "Vérification de la présence des ZPOOLS sur ${NODE1_LDOM}"
  f_checkZpool backup
  f_checkZpool zones-standard
  printf "\n"

  f_logMessage INFO "Vérification de la présence des ZPOOLS sur ${NODE2_LDOM}"
  f_checkRemoteZpool backup root ${NODE2_LDOM}
  f_checkRemoteZpool zones-standard root ${NODE2_LDOM}
  printf "\n"

  # Vérification de la présence des livrables
  f_logMessage INFO "Vérification de la présence des livrables sur ${NODE1_LDOM}"
  f_checkFile ${SCRIPT_PATH}/post-install.sh
  f_checkFile ${MASTER_ARCHIVE_FILE}
  f_checkFile ${TEMPLATE_XML}
  printf "\n"

  f_logMessage INFO "Vérification de la présence des livrables sur ${NODE2_LDOM}"
  f_checkRemoteFile ${SCRIPT_PATH}/post-install.sh root ${NODE2_LDOM}
  if [ $? -ne 0 ]; then
    scp -p ${SCRIPT_PATH}/post-install.sh ${NODE2_LDOM}:${SCRIPT_PATH}
  fi
  f_checkRemoteFile ${MASTER_ARCHIVE_FILE} root ${NODE2_LDOM}
  if [ $? -ne 0 ]; then
    scp -p ${MASTER_ARCHIVE_FILE} ${NODE2_LDOM}:${MASTER_ARCHIVE_FILE}
  fi
  f_checkRemoteFile ${TEMPLATE_XML} root ${NODE2_LDOM}
  if [ $? -ne 0 ]; then
    scp -p ${TEMPLATE_XML} ${NODE2_LDOM}:${TEMPLATE_XML}
  fi
  printf "\n"  

  
  # Vérification de la présence du package ha-cluster
  f_logMessage INFO "Vérification des packages sur ${NODE1_LDOM}"
  f_verifPackage ha-cluster-full
  if [ $? -ne 0 ]; then
    f_logMessage INFO "Installation du package ha-cluster-full"
    pkg install ha-cluster-full
  fi
  printf "\n"

  f_logMessage INFO "Vérification des packages sur ${NODE2_LDOM}"
  f_verifRemotePackage ha-cluster-full root ${NODE2_LDOM}
  if [ $? -ne 0 ]; then
    f_logMessage INFO "Installation du package ha-cluster-full"
    ssh -q -l root -o StrictHostKeyChecking=no ${NODE2_LDOM} "pkg install ha-cluster-full"
  fi
  printf "\n"
}

f_createZFS(){
  ZFS_PATH=$1

  mkdir -p /"${ZFS_PATH}"
  if [ "$(zfs list -H /${ZFS_PATH} | grep ${ZFS_PATH})" != "" ]; then
    f_logMessage INFO "Le point de montage ${ZFS_PATH} existe déjà"
  else
    f_logMessage INFO "Création du ZFS ${ZFS_PATH}"
    zfs create "${ZFS_PATH}"
    sleep 2
    zfs set mountpoint="/${ZFS_PATH}" "${ZFS_PATH}"
  fi
}

f_createRemoteZFS(){
  
  ZFS_PATH=$1
  USER=$2
  HOST=$3
  
  ssh -q $USER@$HOST "mkdir -p /\"${ZFS_PATH}\""
  if [ "$(ssh -q $USER@$HOST "zfs list -H /${ZFS_PATH} | grep ${ZFS_PATH}")" != "" ]; then
    f_logMessage WARNING "Le point de montage ${ZFS_PATH} existe déjà sur le serveur ${HOST}"
  else
    f_logMessage INFO "Création du ZFS ${ZFS_PATH} sur le serveur ${HOST}"
    ssh -q $USER@$HOST "zfs create \"${ZFS_PATH}\""
    sleep 2
    ssh -q $USER@$HOST "zfs set mountpoint=\"/${ZFS_PATH}\" \"${ZFS_PATH}\""
  fi
}

f_prepareZone(){

  f_logMessage INFO "Création des ZFS sur ${NODE1_LDOM}"
  f_createZFS "${ZONEROOTPATH}"
  f_createZFS "${ZONEROOTPATH}/${ZONEPATH}"
  f_createZFS "${ZONEROOTPATH}/${ZONEPATH}-fs"
  f_createZFS "${ZONEROOTPATH}/${ZONEPATH}-fs/softs"
  f_createZFS "${ZONEROOTPATH}/${ZONEPATH}-fs/appli"
  f_createZFS "${ZONEROOTPATH}/${ZONEPATH}-fs/u01"
  f_createZFS "${ZONEROOTPATH}/${ZONEPATH}-fs/logs"
  f_createZFS "backup"
  f_createZFS "backup/${ZONEPATH}"
  f_createZFS "backup/${ZONEPATH}/zoneconfig"
  f_createZFS "backup/${ZONEPATH}/zfssnap"
  f_createZFS "backup/${ZONEPATH}/rman"
  printf "\n\n"

  f_logMessage INFO "Création des ZFS sur ${NODE2_LDOM}"
  f_createRemoteZFS "${ZONEROOTPATH}" root ${NODE2_LDOM}
  f_createRemoteZFS "${ZONEROOTPATH}/${ZONEPATH}" root ${NODE2_LDOM}
  f_createRemoteZFS "${ZONEROOTPATH}/${ZONEPATH}-fs" root ${NODE2_LDOM}
  f_createRemoteZFS "${ZONEROOTPATH}/${ZONEPATH}-fs/softs" root ${NODE2_LDOM}
  f_createRemoteZFS "${ZONEROOTPATH}/${ZONEPATH}-fs/appli" root ${NODE2_LDOM}
  f_createRemoteZFS "${ZONEROOTPATH}/${ZONEPATH}-fs/logs" root ${NODE2_LDOM}
  f_createRemoteZFS "${ZONEROOTPATH}/${ZONEPATH}-fs/u01" root ${NODE2_LDOM}
  f_createRemoteZFS "backup" root ${NODE2_LDOM}
  f_createRemoteZFS "backup/${ZONEPATH}" root ${NODE2_LDOM}
  f_createRemoteZFS "backup/${ZONEPATH}/zoneconfig" root ${NODE2_LDOM}
  f_createRemoteZFS "backup/${ZONEPATH}/zfssnap" root ${NODE2_LDOM}
  f_createRemoteZFS "backup/${ZONEPATH}/rman" root ${NODE2_LDOM}
  printf "\n"
  
  # cat ${PROPERTIES_FILE} | grep MOUNTPOINT | while read line
  # do
  #   fs=$(echo $line | awk -F '=' '{print $2}')
  #   f_createZFS "${ZONEROOTPATH}/${ZONEPATH}-fs/${fs}"
  #   f_createRemoteZFS "${ZONEROOTPATH}/${ZONEPATH}-fs/${fs}" root ${NODE2_LDOM}
  # done

  # Génération du fichier de création de la zone (CFG)
  if [ -f ${ZONE_CONFIG_FILE} ]; then
    rm -f ${ZONE_CONFIG_FILE}
  fi
  echo "create" >> ${ZONE_CONFIG_FILE}
  echo "set brand=solaris" >> ${ZONE_CONFIG_FILE}
  echo "set zonepath=/${ZONEROOTPATH}/${ZONEPATH}" >> ${ZONE_CONFIG_FILE}
  echo "set ip-type=exclusive" >> ${ZONE_CONFIG_FILE}
  echo "set autoboot=false" >> ${ZONE_CONFIG_FILE}

  # Boucle sur les différents nodes

  #Ajout des physical-hosts
  NODE_LIST=$(cat ${PROPERTIES_FILE} | egrep -e "^NODE" |  nawk -F "_" '{print $1}' | sort -u)
  for node in ${NODE_LIST}
  do
    LDOM_NAME=$(cat ${PROPERTIES_FILE} | grep ${node} | grep LDOM | nawk -F "=" '{print $2}')
    HOST=$(cat ${PROPERTIES_FILE} | grep ${node} | grep HOST | nawk -F "=" '{print $2}')
    echo "add node" >> ${ZONE_CONFIG_FILE}
    echo "set physical-host=${LDOM_NAME}" >> ${ZONE_CONFIG_FILE}
    echo "set hostname=${HOST}" >> ${ZONE_CONFIG_FILE}

    # Ajout des net
    VNIC_LIST=$(cat ${PROPERTIES_FILE} | egrep -e "^${node}" | grep VNIC | nawk -F "_" '{print $2}' | sort -u)
    for vnic in ${VNIC_LIST}
    do
      NAME=$(cat ${PROPERTIES_FILE} | grep ${node} | grep $vnic | grep NAME | nawk -F "=" '{print $2}')
      TYPE=$(cat ${PROPERTIES_FILE} | grep ${node} | grep $vnic | grep TYPE | nawk -F "=" '{print $2}')
      echo "add ${TYPE}" >> ${ZONE_CONFIG_FILE}
      echo "set physical=${NAME}" >> ${ZONE_CONFIG_FILE}
      echo "end" >> ${ZONE_CONFIG_FILE}
    done

    # Ajout des FS
    FS_LIST=$(cat ${PROPERTIES_FILE} | egrep -e "^FS" |  nawk -F "_" '{print $1}' | sort -u)
    for fs in ${FS_LIST}
    do
      MOUNTPOINT=$(cat ${PROPERTIES_FILE} | grep $fs | grep MOUNTPOINT | nawk -F "=" '{print $2}')
      TYPE=$(cat ${PROPERTIES_FILE} | grep $fs | grep TYPE | nawk -F "=" '{print $2}')
      echo "add fs" >> ${ZONE_CONFIG_FILE}
      echo "set dir=/${MOUNTPOINT}" >> ${ZONE_CONFIG_FILE}
      echo "set type=${TYPE}" >> ${ZONE_CONFIG_FILE}
      echo "set special=/${ZONEROOTPATH}/${ZONEPATH}-fs/${MOUNTPOINT}" >> ${ZONE_CONFIG_FILE}
      echo "end" >> ${ZONE_CONFIG_FILE}
    done

    # Ajout des RAW
    RAW_LIST=$(cat ${PROPERTIES_FILE} | egrep -e "^${node}" | grep RAWFS |  nawk -F "_" '{print $2}' | sort -u)
    for fs in ${RAW_LIST}
    do
      DEVICE=$(cat ${PROPERTIES_FILE} | grep ${node} | grep $fs | grep DEVICE | nawk -F "=" '{print $2}')
      echo "add device" >> ${ZONE_CONFIG_FILE}
      echo "set match=/dev/rdsk/${DEVICE}" >> ${ZONE_CONFIG_FILE}
      echo "end" >> ${ZONE_CONFIG_FILE}
    done

    echo "end" >> ${ZONE_CONFIG_FILE}

  done

  echo "verify" >> ${ZONE_CONFIG_FILE}
  echo "commit" >> ${ZONE_CONFIG_FILE}

# Mise à jour du template XML

  sed -e s:\!__ZONENAME__\!:$ZONENAME:g \
    -e s:\!__HOSTNAME__\!:$HOSTNAME:g  $TEMPLATE_XML > ${ZONE_XML_FILE}

  # Installation du cluster de zone
  f_logMessage INFO "Installation du cluster de zone"
  clzc configure -f ${ZONE_CONFIG_FILE} ${CLUSTER_NAME}
  clzonecluster install -c ${ZONE_XML_FILE} -a ${MASTER_ARCHIVE_FILE} -v ${CLUSTER_NAME}
  clzonecluster boot ${CLUSTER_NAME}
  clzc reboot ${CLUSTER_NAME}
  printf "\n"
  f_logMessage INFO "Rebooting cluster ${CLUSTER_NAME} ..."
  sleep 60
  clzonecluster install-cluster ${CLUSTER_NAME}
  
  # Création des resourcegroups
  NODELIST=$(echo ${NODE1_HOST},${NODE2_HOST})

  /usr/cluster/bin/clresourcegroup create -Z ${CLUSTER_NAME} -p Desired_primaries=2 -p RG_mode=Scalable -p Maximum_primaries=2 -p nodelist=${NODELIST} rac-frmk-${ZONENAME}-rg
  /usr/cluster/bin/clresourcetype register -Z ${CLUSTER_NAME} SUNW.rac_framework:5
  /usr/cluster/bin/clresource create -Z ${CLUSTER_NAME} -t SUNW.rac_framework:5 -g rac-frmk-${ZONENAME}-rg rac-frmk-${ZONENAME}-rs
  /usr/cluster/bin/clresourcegroup online -emM -Z ${CLUSTER_NAME} rac-frmk-${ZONENAME}-rg

  # Temporisation pour boot de la zone 
  _start=1
  _end=300

  for number in $(seq ${_start} ${_end})
  do
    sleep 0.1
    ProgressBar ${number} ${_end}
  done

  f_logMessage INFO "${CLUSTER_NAME} booted"

  f_logMessage INFO "Préparation de la zone sur ${NODE1_LDOM}"
  /usr/bin/bash ${SCRIPT_PATH}/post-install.sh ${PROPERTIES_FILE}
  f_logMessage INFO "Préparation de la zone sur ${NODE2_LDOM}"
  ssh -q -l root -o StrictHostKeyChecking=no ${NODE2_LDOM} "/usr/bin/bash ${SCRIPT_PATH}/post-install.sh ${PROPERTIES_FILE}"

  f_logMessage INFO "La zone ${CLUSTER_NAME} a bien été créée"
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
          f_verifPrerequis
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
