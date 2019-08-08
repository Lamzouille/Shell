#!/usr/bin/bash

#####################################################################################
#                                [create-zone-ha.sh]                                #
#####################################################################################
# DESCRIPTION : Script de creation pour les zones HA - script appelé par            #
#               gestion-zone.sh                                                     #
#                                                                                   #
#####################################################################################
# UTILISATION : gestion-zone.sh [-c file.properties] -[h] [-v]                      #
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
#                - lib.cluster.sh                                                   #
#                                                                                   #
#####################################################################################
# AUTEUR : M.DUQUESNOY                                                              #
# DATE DE CREATION : 05/07/2018                                                     #
#####################################################################################
# REVISIONS :                                                                       #
#####################################################################################

#=============================== VARIABLES GLOBALES =================================
DEBUG_MODE=1
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
PROPERTIES_PATH="${CONF_PATH}/properties/"
SCRIPT_VERSION="1.0"

#====================================================================================

# ICI LES VARIABLES GLOBALES OU CONSTANTES PERSONNALISEES
# FORMAT : MAJ_MAJ_MAJ ...

MASTER_ARCHIVE_FILE=${CONF_PATH}/zones-archives/master.uar

#====================================================================================



#================================ FONCTIONS LOCALES =================================

f_loadExternalLibs(){   # Chargement des librairies externes : Lancer au debut du main

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


f_checkLocalZpoolExists(){
  zpoolName=$1
  zpool list ${zpoolName} 2>/dev/null 1>/dev/null
  return $?
}

f_checkRemoteZpoolExists(){
  zpoolName=$1
  user=$2
  host=$3
  ssh -q $user@$host "zpool list ${zpoolName} 2>/dev/null 1>/dev/null"
  return $?
}

f_createLocalZfs(){
  zfsPath=$1
  mkdir -p /"${zfsPath}"
  if [ "$(zfs list -H /${zfsPath} | grep ${zfsPath})" != "" ]; then
    f_logMessage WARNING "Le point de montage ${zfsPath} existe déjà"
  else
    f_logMessage INFO "Création du ZFS ${zfsPath}"
    zfs create "${zfsPath}"
    sleep 2
    zfs set mountpoint="/${zfsPath}" "${zfsPath}"
  fi
}

f_createRemoteZfs(){
  zfsPath=$1
  user=$2
  host=$3

  ssh -q $user@$host "mkdir -p /\"${zfsPath}\""
  if [ "$(ssh -q $user@$host "zfs list -H /${zfsPath} | grep ${zfsPath}")" != "" ]; then
    f_logMessage WARNING "Le point de montage ${zfsPath} existe déjà sur le serveur ${host}"
  else
    f_logMessage INFO "Création du ZFS ${zfsPath} sur le serveur ${host}"
    ssh -q $user@$host "zfs create \"${zfsPath}\""
    sleep 2
    ssh -q $user@$host "zfs set mountpoint=\"/${zfsPath}\" \"${zfsPath}\""
  fi
}

f_prepareClusterZfs(){
  config="$1"
  resourceGroup=$2
  zoneRootPath=$(echo "$config" | grep ZONEROOTPATH | awk -F '=' '{print $2}')
  zonePath=$(echo "$config" | grep ZONEPATH | awk -F '=' '{print $2}')
  remoteNodes="$(f_getRemoteClusterNodes $(f_getClusterNodes global))"
  rgOwner=$(f_getClusterRgOwner $resourceGroup global)

  f_logMessage "DEBUG" "Zone root path = $zoneRootPath"
  f_logMessage "DEBUG" "Zone path = $zonePath"
  f_logMessage "DEBUG" "Remote node = $remoteNodes"
  f_logMessage "DEBUG" "$resourceGroup owner = $rgOwner"

  [[ "$rgOwner" = "" ]] && f_errorFatal "Le groupe de ressource $rgOwner est indisponible sur le cluster global"
  if [[ "$rgOwner" = "$HOSTNAME" ]]; then
    f_checkLocalZpoolExists "${zoneRootPath}"; f_errorFatal "Le zpool ${zoneRootPath} n'existe pas sur le noeud local du cluster global - NODE : $rgOwner"
    f_logMessage "DEBUG" "Local create on $rgOwner"
    f_createLocalZfs "${zoneRootPath}"
    f_createLocalZfs "${zoneRootPath}/${zonePath}"
    f_createLocalZfs "${zoneRootPath}/${zonePath}-fs"
    for mp in $(echo "$config" | grep MOUNTPOINT | awk -F '=' '{print $2}'); do
        f_logMessage "DEBUG" "MountPoint : zfs = ${zoneRootPath}/${zonePath}-fs/$mp - mp = /$mp"
        f_createLocalZfs "${zoneRootPath}/${zonePath}-fs/$mp"
    done
  else
    if [ $(f_checkSshPubkeyAuthent root $rgOwner) -eq 0 ]; then
      f_checkRemoteZpoolExists "${zoneRootPath}" root $rgOwner; f_errorFatal "Le zpool ${zoneRootPath} n'existe pas sur le noeud distant du cluster global - NODE : $rgOwner"
      f_logMessage "DEBUG" "Remote create on $rgOwner"
      f_createRemoteZfs "${zoneRootPath}" root $rgOwner
      f_createRemoteZfs "${zoneRootPath}/${zonePath}" root $rgOwner
      f_createRemoteZfs "${zoneRootPath}/${zonePath}-fs" root $rgOwner
      for mp in $(echo "$config" | grep MOUNTPOINT | awk -F '=' '{print $2}'); do
        f_logMessage "DEBUG" "MountPoint : zfs = ${zoneRootPath}/${zonePath}-fs/$mp - mp = /$mp"
        f_createRemoteZfs "${zoneRootPath}/${zonePath}-fs/$mp" root $rgOwner
      done
    else
      [[ 1 -eq 0 ]]; f_errorFatal "Echec de l'authentification ssh PublicKey - NODE : $rgOwner"
    fi
  fi
}

f_prepareBackupZfs(){
  config="$1"
  backupRootPath="backup"
  zonePath=$(echo "$config" | grep ZONEPATH | awk -F '=' '{print $2}')
  remoteNodes="$(f_getRemoteClusterNodes $(f_getClusterNodes global))"
  rgOwner=$(f_getClusterRgOwner $resourceGroup global)

  f_logMessage "DEBUG" "Backup root path = $zoneRootPath"
  f_logMessage "DEBUG" "Zone path = $zonePath"
  f_logMessage "DEBUG" "Remote node = $remoteNodes"

  f_checkLocalZpoolExists "${backupRootPath}"; f_errorFatal "Le zpool ${backupRootPath} n'existe pas sur le noeud local du cluster global - NODE : $HOSTNAME"
  f_logMessage "DEBUG" "Local create on $HOSTNAME"
  f_createLocalZfs "${backupRootPath}"
  f_createLocalZfs "${backupRootPath}/${zonePath}"
  f_createLocalZfs "${backupRootPath}/${zonePath}/zoneconfig"
  f_createLocalZfs "${backupRootPath}/${zonePath}/zfssnap"
  f_createLocalZfs "${backupRootPath}/${zonePath}/rman"
  for node in $remoteNodes; do
    if [ $(f_checkSshPubkeyAuthent root $node) -eq 0 ]; then
      f_checkRemoteZpoolExists "${backupRootPath}" root $node; f_errorFatal "Le zpool ${backupRootPath} n'existe pas sur le noeud distant du cluster global - NODE : $node"
      f_logMessage "DEBUG" "Remote create on $node"
      f_createRemoteZfs "${backupRootPath}" root $node
      f_createRemoteZfs "${backupRootPath}/${zonePath}" root $node
      f_createRemoteZfs "${backupRootPath}/${zonePath}/zoneconfig" root $node
      f_createRemoteZfs "${backupRootPath}/${zonePath}/zfssnap" root $node
      f_createRemoteZfs "${backupRootPath}/${zonePath}/rman" root $node
    else
      [[ 1 -eq 0 ]]; f_errorFatal "Echec de l'authentification ssh PublicKey - NODE : $node"
    fi
  done

}


f_createZoneHaConfig(){
  config=$1
  outFile=$2
  zoneRootPath=$(echo "$config" | grep ZONEROOTPATH | awk -F '=' '{print $2}')
  zonePath=$(echo "$config" | grep ZONEPATH | awk -F '=' '{print $2}')
  vnicList="$(echo "$config" | egrep -e '^VNIC' | awk -F '_' '{print $1}' | sort -u)"
  fsList="$(echo "$config" | egrep -e '^FS' | awk -F '_' '{print $1}' | sort -u)"
  rawDevList="$(echo "$config" | egrep -e '^RAWFS' | awk -F '_' '{print $1}' | sort -u)"
  f_logMessage "DEBUG" "Adding standard zones parameters"
  echo "create -b" > ${outFile}
  echo "set zonepath=/${zoneRootPath}/${zonePath}" >> ${outFile}
  echo "set brand=solaris" >> ${outFile}
  echo "set autoboot=false" >> ${outFile}
  echo "set ip-type=exclusive" >> ${outFile}
  f_logMessage "DEBUG" "Adding ha-zones parameters"
  echo "add attr" >> ${outFile}
  echo "set name=osc-ha-zone" >> ${outFile}
  echo "set type=boolean" >> ${outFile}
  echo "set value=true" >> ${outFile}
  echo "end" >> ${outFile}
  for vnic in $vnicList; do
    f_logMessage "DEBUG" "Adding auto vnic $vnic"
    vnicName=""
    lowerLinkName=""
    vnicName="$(echo "$config" | grep "^${vnic}_" | grep NAME | awk -F '=' '{print $2}')"
    lowerLinkName="$(echo "$config" | egrep -e "^${vnic}_" | grep LOWERLINK | awk -F '=' '{print $2}')"
    echo "add anet" >> ${outFile}
    echo "set linkname=$vnicName" >> ${outFile}
    echo "set lower-link=$lowerLinkName" >> ${outFile}
    echo "set configure-allowed-address=false" >> ${outFile}
    echo "end" >> ${outFile}
  done
  for fs in $fsList; do
    f_logMessage "DEBUG" "Adding filesystem $fs"
    mountPoint=""
    fsType=""
    mountPoint="$(echo "$config" | egrep -e "^${fs}_" | grep MOUNTPOINT | awk -F "=" '{print $2}')"
    fsType="$(echo "$config" | egrep -e "^${fs}_" | grep TYPE | awk -F "=" '{print $2}')"
    echo "add fs" >> ${outFile}
    echo "set dir=/${mountPoint}" >> ${outFile}
    echo "set type=${fsType}" >> ${outFile}
    echo "set special=/${zoneRootPath}/${zonePath}-fs/${mountPoint}" >> ${outFile}
    echo "end" >> ${outFile}
  done
  for rawDev in $rawDevList; do
    f_logMessage "DEBUG" "Adding raw device $rawDev"
    rawDevName=$(echo "$config" | egrep -e "^${rawDev}_" | grep DEVICE | awk -F "=" '{print $2}')
    echo "add device" >> ${outFile}
    echo "set match=/dev/rdsk/${rawDevName}" >> ${outFile}
    echo "end" >> ${outFile}
  done
  echo "verify" >> ${outFile}
  echo "commit" >> ${outFile}
}

f_createZoneTemplateXml(){
  config=$1
  zoneTemplateFile=$2
  outFile=$3
  command="sed $(echo "$config" | nawk -F '=' 'BEGIN{ORS=" "}{print "-e s:\\\!__"$1"__\\\!:"$2":g"}' ) $zoneTemplateFile > $outFile"
  eval "$command"
}

f_createLocalZone(){
  zoneName=$1
  zoneConfigFile=$2
  /usr/sbin/zonecfg -z $zoneName -f $zoneConfigFile 1>/dev/null 2>/dev/null
  return $?
}

f_createRemoteZone(){
  user=$1
  host=$2
  zoneName=$3
  zoneConfigFile=$4
  f_executeRemoteCommand $user $host "/usr/sbin/zonecfg -z ${zoneName} -f ${zoneConfigFile}"
  return $?
}

f_createZoneHa(){
  config=$1
  resourceGroup=$2
  zoneConfigFile=$3
  remoteNodes="$(f_getRemoteClusterNodes $(f_getClusterNodes global))"
  rgOwner=$(f_getClusterRgOwner $resourceGroup global)
  zoneName=$(echo "$config" | egrep -e '^ZONENAME' | awk -F '=' '{print $2}')

  f_logMessage "DEBUG" "Zone config file = $zoneConfigFile"
  f_logMessage "DEBUG" "Remote nodes = $remoteNodes"
  f_logMessage "DEBUG" "$resourceGroup owner = $rgOwner"
  f_logMessage "DEBUG" "Zone name = $zoneName"
  
  [[ "$rgOwner" = "" ]] && f_errorFatal "Le groupe de ressource $rgOwner est indisponible sur le cluster global"
  f_createZoneHaConfig "$config" "$zoneConfigFile"
  f_createLocalZone $zoneName $zoneConfigFile; f_errorFatal "Echec de la creation de la zone en local"

  for node in $remoteNodes; do
    if [ $(f_checkSshPubkeyAuthent root $node) -eq 0 ]; then
      f_logMessage "INFO" "Sending file to remote node : $node"
      f_sendFilesToRemoteHost root $node "$zoneConfigFile" "$zoneConfigFile"; f_errorFatal "Echec de la copie du fichier de configuration de zone - NODE : $node"
      f_logMessage "INFO" "Creating zone on remote node : $node"
      f_createRemoteZone root $node $zoneName $zoneConfigFile; f_errorFatal "Echec de la creation de la zone à distance - NODE : $node"
    else
      [[ 1 -eq 0 ]]; f_errorFatal "Echec de l'authentification ssh PublicKey - NODE : $node"
    fi
  done
}

f_installLocalZone(){
  zoneName=$1
  zoneTemplate=$2
  zoneArchive=$3
  /usr/sbin/zoneadm -z $zoneName install -c $zoneTemplate -a $zoneArchive
  return $?
}

f_installRemoteZone(){
  user=$1
  host=$2
  zoneName=$3
  zoneTemplate=$4
  zoneArchive=$5
  f_executeRemoteCommand $user $host "/usr/sbin/zoneadm -z $zoneName install -c $zoneTemplate -a $zoneArchive"
  return $?
}
f_installZoneHa(){
  config=$1
  resourceGroup=$2
  zoneXmlFile=$3
  zoneArchiveFile=$4
  zoneRootPath=$(echo "$config" | grep ZONEROOTPATH | awk -F '=' '{print $2}')
  zonePath=$(echo "$config" | grep ZONEPATH | awk -F '=' '{print $2}')
  remoteNodes="$(f_getRemoteClusterNodes $(f_getClusterNodes global))"
  rgOwner=$(f_getClusterRgOwner $resourceGroup global)
  zoneName=$(echo "$config" | egrep -e '^ZONENAME' | awk -F '=' '{print $2}')

  f_logMessage "DEBUG" "Zone Xml file = $zoneXmlFile"
  f_logMessage "DEBUG" "Zone template file = $zoneArchiveFile"
  f_logMessage "DEBUG" "Remote nodes = $remoteNodes"
  f_logMessage "DEBUG" "$resourceGroup owner = $rgOwner"
  f_logMessage "DEBUG" "Zone name = $zoneName"

  [[ "$rgOwner" = "" ]] && f_errorFatal "Le groupe de ressource $rgOwner est indisponible sur le cluster global"
  if [[ "$rgOwner" = "$HOSTNAME" ]]; then
    f_logMessage "DEBUG" "Local install on $rgOwner"
    [[ ! -f $zoneXmlFile ]] && f_errorFatal "Le fichier $zoneXmlFile n'existe pas"
    [[ ! -f $zoneArchiveFile ]] && f_errorFatal "Le fichier $zoneArchiveFile n'existe pas"
    f_installLocalZone $zoneName $zoneXmlFile $zoneArchiveFile; f_errorFatal "Echec de l'installation de la zone $zoneName en local"
    mkdir -p "/$zoneRootPath/$zonePath/params"
  else
    if [ $(f_checkSshPubkeyAuthent root $rgOwner) -eq 0 ]; then
      f_logMessage "DEBUG" "Remote install on $rgOwner"
      f_sendFilesToRemoteHost root $rgOwner "$zoneXmlFile" "$zoneXmlFile" ; f_errorFatal "Echec du transfertdu fichier "$zoneXmlFile" - NODE : $rgOwner"
      [[ $(f_checkRemoteFileExists $user $host $zoneArchiveFile) ]] && f_errorFatal "Le fichier distant $zoneArchiveFile n'existe pas - NODE : $rgOwner"
      f_installRemoteZone root $rgOwner $zoneName $zoneXmlFile $zoneArchiveFile; f_errorFatal "Echec de l'installation de la zone $zoneName à distance - NODE : $rgOwner"
      f_createRemoteDir root $rgOwner "/$zoneRootPath/$zonePath/params"
    else
      [[ 1 -eq 0 ]]; f_errorFatal "Echec de l'authentification ssh PublicKey - NODE : $rgOwner"
    fi
  fi
}

f_createZoneHaRsconfig(){
  config=$1
  resourceGroup=$2
  outFile=$3
  zoneName=$(echo "$config" | egrep -e '^ZONENAME' | awk -F '=' '{print $2}')
  zoneRootPath=$(echo "$config" | grep ZONEROOTPATH | awk -F '=' '{print $2}')
  zonePath=$(echo "$config" | grep ZONEPATH | awk -F '=' '{print $2}')
  haspResource=$(/usr/cluster/bin/clrg show $resourceGroup | grep Resource: | grep hasp | awk '{print $2}')
  
  echo "RS=zone-${zoneName}-rs" > $outFile
  echo "RG=${resourceGroup}" >> $outFile
  echo "PARAMETERDIR=/$zoneRootPath/$zonePath/params" >> $outFile
  echo "SC_NETWORK=false" >> $outFile
  echo "SC_LH=" >> $outFile
  echo "FAILOVER=true" >> $outFile
  echo "HAS_RS=$haspResource" >> $outFile
  echo "Zonename=\"$zoneName\"" >> $outFile
  echo "Zonebrand=\"solaris\"" >> $outFile
  echo "Zonebootopt=\"\"" >> $outFile
  echo "Milestone=\"svc:/milestone/multi-user-server\"" >> $outFile
  echo "LXrunlevel=\"3\"" >> $outFile
  echo "SLrunlevel=\"3\"" >> $outFile
  echo "Mounts=\"\"" >> $outFile
  echo "Migrationtype=\"cold\"" >> $outFile
}

f_registerZoneHaRsConfig(){
  resourceFile=$1
  /opt/SUNWsczone/sczbt/util/sczbt_register -f $resourceFile
  return $?
}

f_enableClusterResource(){
  clusterResource=$1
  clusterName=$2
  /usr/cluster/bin/clrs enable -Z $clusterName $clusterResource
  return $?
}

f_enableZoneHaResource(){
  config=$1
  resourceGroup=$2
  zoneName=$(echo "$config" | egrep -e '^ZONENAME' | awk -F '=' '{print $2}')
  clusterResource=$(/usr/cluster/bin/clrg show $resourceGroup | grep Resource: | grep $zoneName | awk '{print $2}')
  f_enableClusterResource $clusterResource global
  return $?
}

f_createIpInterfaceCommand(){
  config=$1
  clusterNode=$2
  zoneName=$(echo "$config" | egrep -e '^ZONENAME' | awk -F '=' '{print $2}')
  command=""
  if [[ "$clusterNode" = "" ]]; then
    vnicList="$(echo "$config" | egrep -e 'VNIC.?_' | awk -F '_' '{print $(NF-1)}' | sort -u)"
  else
    vnicList="$(echo "$config" | egrep -e "^${clusterNode}_VNIC.?_" | awk -F '_' -v "NODE=${clusterNode}" '{print NODE"_"$(NF-1)}' | sort -u)"
  fi
  for vnic in $vnicList; do
    vnicType=""
    vnicType="$(echo "$config" | egrep -e "${vnic}_TYPE" | awk -F '=' '{print $2}')"
    vnicName="$(echo "$config" | egrep -e "${vnic}_NAME" | awk -F '=' '{print $2}')"
    [[ "$vnicType" != "privnet" ]] && command="${command} zlogin -l root ${zoneName} 'ipadm create-ip $vnicName';"
  done
  echo "$command"
}

f_createIpmpInterfaceCommand(){
  config=$1
  clusterNode=$2
  zoneName=$(echo "$config" | egrep -e '^ZONENAME' | awk -F '=' '{print $2}')
  command=""
  if [[ "$clusterNode" = "" ]]; then
    ipmpList="$(echo "$config" | egrep -e '^IPMP.?_' | awk -F '_' '{print $(NF-1)}' | sort -u)"
  else
    ipmpList="$(echo "$config" | egrep -e "^${clusterNode}_IPMP.?_" | awk -F '_' -v "NODE=${clusterNode}" '{print NODE"_"$(NF-1)}' | sort -u)"
  fi
  for ipmp in $ipmpList; do
    ipmpMember=""
    ipmpMember="$(echo "$config" | egrep -e "${ipmp}_MEMBER" | awk -F '=' '{print $2}')"
    ipmpName="$(echo "$config" | egrep -e "${ipmp}_NAME" | awk -F '=' '{print $2}')"
    command="zlogin -l root ${zoneName} '${command} ipadm create-ipmp $(echo "$ipmpMember" | nawk 'BEGIN{ORS=" "}{print "-i " $1}') $ipmpName';"
  done
  echo "$command"
}

f_createIPAdressCommand(){
  #f_logMessage DEBUG "Entering function = ${FUNCNAME[0]}"
  config=$1
  clusterNode=$2
  zoneName=$(echo "$config" | egrep -e '^ZONENAME' | awk -F '=' '{print $2}')
  command=""
  if [[ "$clusterNode" = "" ]]; then
    ipAddrList="$(echo "$config" | egrep -e '^.*_IPADDR' | awk -F '=' '{print $(NF-1)}' | sed -e 's/_IPADDR//g' | sort -u)"
  else
    ipAddrList="$(echo "$config" | egrep -e "^${clusterNode}_.*_IPADDR" | awk -F '=' '{print $(NF-1)}' | sed -e 's/_IPADDR//g' | sort -u)"
  fi
  for ipAddr in $ipAddrList; do
    ipAdress=""
    ipmpName="$(echo "$config" | egrep -e "${ipAddr}_NAME" | awk -F '=' '{print $2}')"
    ipmpAdresses="$(echo "$config" | egrep -e "${ipAddr}_IPADDR" | awk -F '=' '{print $2}')"
    for ipAddr_ in $ipmpAdresses; do
      command="zlogin -l root ${zoneName} '${command} ipadm create-addr -T static -a "$ipAddr_" $ipmpName';"
    done
  done
  echo "$command"
  #f_logMessage DEBUG "Exiting function = ${FUNCNAME[0]}"
}

f_ConfigureZoneNetwork(){
  config=$1
  resourceGroup=$2
  remoteNodes="$(f_getRemoteClusterNodes $(f_getClusterNodes global))"
  rgOwner=$(f_getClusterRgOwner $resourceGroup global)
  zoneName=$(echo "$config" | egrep -e '^ZONENAME' | awk -F '=' '{print $2}')
  defaultRoute=$(echo "$config" | egrep -e '^DEFAULTROUTE' | awk -F '=' '{print $2}')
  ifCommand="$(f_createIpInterfaceCommand "$config")"
  ipmpCommand="$(f_createIpmpInterfaceCommand "$config")"
  addrCommand="$(f_createIPAdressCommand "$config")"
  routeCommand="zlogin -l root ${zoneName} \"route -p add default $defaultRoute\""
  f_logMessage "DEBUG" "Remote nodes = $remoteNodes"
  f_logMessage "DEBUG" "$resourceGroup owner = $rgOwner"
  f_logMessage "DEBUG" "Zone name = $zoneName"
  f_logMessage "DEBUG" "Interface command = $ifCommand"
  f_logMessage "DEBUG" "Ipmp command = $ipmpCommand"
  f_logMessage "DEBUG" "Address command = $addrCommand"

  [[ "$rgOwner" = "" ]] && f_errorFatal "Le groupe de ressource $rgOwner est indisponible sur le cluster global"
  if [[ "$rgOwner" = "$HOSTNAME" ]]; then
    f_logMessage "DEBUG" "Local zone configuration on $rgOwner"
    eval $ifCommand
    eval $ipmpCommand
    eval $addrCommand
    eval $routeCommand
  else
    if [ $(f_checkSshPubkeyAuthent root $rgOwner) -eq 0 ]; then
      f_logMessage "DEBUG" "Remote zone configuration on $rgOwner"
      f_executeRemoteCommand root $rgOwner "$ifCommand"
      f_executeRemoteCommand root $rgOwner "$ipmpCommand"
      f_executeRemoteCommand root $rgOwner "$addrCommand"
      f_executeRemoteCommand root $rgOwner "$routeCommand"
    else
      [[ 1 -eq 0 ]]; f_errorFatal "Echec de l'authentification ssh PublicKey - NODE : $rgOwner"
    fi
  fi
}

f_prepareZoneHA(){

  config=$1

  ZONE_NAME="$(echo "$config" | egrep -e "^ZONENAME=" | awk -F '=' '{print $2}')"
  ZONE_XML_TEMPLATE="$(echo "$config" | egrep -e "^TEMPLATE_XML=" | awk -F '=' '{print $2}')"
  ZONE_CONFIG_FILE=${CONF_PATH}/zoneconfig/create_${ZONE_NAME}.cfg
  CLUSTER_RS_FILE=${CONF_PATH}/zoneconfig/create_${ZONE_NAME}.rs
  ZONE_XML_FILE=${CONF_PATH}/zoneconfig/create_${ZONE_NAME}.xml
  f_logMessage "INFO" "Creation arborescences"
  mkdir -p "${CONF_PATH}/zoneconfig"
  f_createRemoteDir root $(f_getRemoteClusterNodes $(f_getClusterNodes global)) "${CONF_PATH}/zoneconfig"
  f_logMessage "INFO" "Test du cluster"
  f_isFullClusterUp global; f_errorFatal "Le cluster global n'est pas completement up"
  f_logMessage "INFO" "Preparation ZFS de la zone ha"
  f_prepareClusterZfs "$config" ha-zones-rg
  f_logMessage "INFO" "Preparation ZFS backup de la zone ha"
  f_prepareBackupZfs "$config"
  f_logMessage "INFO" "Création de la zone sur les noeuds du cluster solaris"
  f_createZoneHa "$config" "ha-zones-rg" "$ZONE_CONFIG_FILE"
  f_logMessage "INFO" "Valoristation du template d'installation"
  f_createZoneTemplateXml "$config" "$ZONE_XML_TEMPLATE" "$ZONE_XML_FILE"
  f_logMessage "INFO" "Installation de la zone ha"
  f_installZoneHa "$config" "ha-zones-rg" "$ZONE_XML_FILE" "$MASTER_ARCHIVE_FILE"
  f_logMessage "INFO" "Creation du fichier de ressource cluster"
  f_createZoneHaRsconfig "$config" "ha-zones-rg" "$CLUSTER_RS_FILE"
  f_logMessage "INFO" "Enregistrement de la ressource cluster"
  f_registerZoneHaRsConfig $CLUSTER_RS_FILE
  f_logMessage "INFO" "Activation de la zone ha"
  f_enableZoneHaResource "$config" "ha-zones-rg"
  f_logMessage "INFO" "Configuration du réseau de la zone"
  f_ConfigureZoneNetwork "$config" "ha-zones-rg"
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
        if [ ${OPTARG:0:1} != '/' ];then
          f_logMessage FATAL "Merci de renseigner le chemin complet du fichier properties"
          exit 1
        fi
        if [[ -f $OPTARG ]]; then
          PROPERTIES_FILE=${OPTARG}
          ZONE_CONFIG="$(cat ${PROPERTIES_FILE} | egrep -v -e '^$' | egrep -v -e '^#')"
          INSTALL=1
        else
          f_logMessage FATAL "Le fichier de properties spécifié n'existe pas.\n\n"
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


f_loadExternalLibs # chargement des libs de $LIB_DIR
f_detectOS # détection de l'OS
f_setCommandAlias # permet de redefinir des commandes pour Solaris ou Linux
f_parseParams ${SCRIPT_ARGS} # Parse des arguments du script : Fonction à modifier plus haut. Si pas d'argument commenter la ligne
if [[ $INSTALL -eq 1 ]]; then
  f_prepareZoneHA "$ZONE_CONFIG"
else
  f_logMessage WARNING "Rien à faire"
fi
f_logMessage INFO "Script terminé."
exit 0

#====================================================================================


