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

f_createZone(){

  f_logMessage INFO "Creation de la zone ${ZONENAME}"
  f_logMessage DEBUG "${TYPEZONE}"

  if [ ! -z ${TYPEZONE} ]; then
    if [ "${TYPEZONE}" = "STANDARD" ];then
      /usr/bin/bash ${SCRIPT_PATH}/create-zone-standard.sh -c ${PROPERTIES_FILE}
      # . ${SCRIPT_PATH}/create-zone-standard.sh -c ${PROPERTIES_FILE}
      exit 0
    elif [ "${TYPEZONE}" = "RAC" ]; then
      /usr/bin/bash ${SCRIPT_PATH}/create-zone-rac.sh -c ${PROPERTIES_FILE}
      exit 0
    elif [ "${TYPEZONE}" = "HA" ]; then
      /usr/bin/bash ${SCRIPT_PATH}/create-zone-ha.sh -c ${PROPERTIES_FILE}
      exit 0
    else
      f_logMessage ERROR "'${TYPEZONE}' n'est pas reconnu comme un type de zone valide (STANDARD|RAC|HA)"  
    fi
  else 
    f_logMessage ERROR "TYPEZONE n'est pas défini dans le fichier de configuration"
  fi
}

f_destroyZoneStandard(){
  
  f_logMessage DEBUG "${ZONENAME}"
  f_promptYesNo "Vous êtes sur le point de détruire la zone ${ZONENAME} - Etes vous sur ?" || exit 0

  zoneadm -z ${ZONENAME} halt
  zoneadm -z ${ZONENAME} uninstall
  zonecfg -z ${ZONENAME} delete -F
  f_logMessage INFO "Zone ${ZONENAME} successfully destroyed !"

  f_promptYesNo "Voulez vous détruire les ZFS associés ?" || exit 0
  # Chargement du fichier properties associés à la zone
  ZONE_PROPERTIES=$(echo ${ZONENAME} | nawk -F "." '{print $1}')
  . ${PROPERTIES_PATH}/${ZONE_PROPERTIES}.properties
  zfs destroy -r "${ZONEROOTPATH}/${ZONEPATH}-fs"
  zfs destroy -r "${ZONEROOTPATH}/${ZONEPATH}"
  f_logMessage INFO "ZFS successfully destroyed !"
}

f_destroyZoneHA(){
  rgOwner=$(f_getClusterRgOwner ha-zones-rg global)
  if [ "$rgOwner" = $(hostname) ]; then
    f_disableLocalResource ${ZONENAME}
    f_deleteLocalResource ${ZONENAME}
  else
    f_disableRemoteResource ${ZONENAME} root $rgOwner
    f_deleteRemoteResource ${ZONENAME} root $rgOwner
  fi
    zonecfg -z ${ZONENAME} delete -F
    remoteNode="$(f_getRemoteClusterNodes $(f_getClusterNodes global))"
    f_executeRemoteCommand root $remoteNode "zonecfg -z ${ZONENAME} delete -F"
    zfs destroy -r ${ZONEROOTPATH}/${ZONEPATH}
    zfs destroy -r ${ZONEROOTPATH}/${ZONEPATH}-fs
    f_executeRemoteCommand root $remoteNode "zfs destroy -r ${ZONEROOTPATH}/${ZONEPATH}"
    f_executeRemoteCommand root $remoteNode "zfs destroy -r ${ZONEROOTPATH}/${ZONEPATH}-fs"
}

f_destroyZoneRAC(){

  test=$(clzc status | grep ${CLUSTER_NAME} | wc -l)
  if [ $test -eq 0 ]; then
    f_logMessage ERROR "Le cluster indiqué n'existe pas"
    exit 1
  fi
  clzc halt ${CLUSTER_NAME}
  clzc uninstall ${CLUSTER_NAME}
  clzc delete ${CLUSTER_NAME}

}

f_destroyZone(){

  if [ ! -z ${TYPEZONE} ]; then
    if [ "${TYPEZONE}" = "STANDARD" ];then
      f_destroyZoneStandard
    fi

    if [ "${TYPEZONE}" = "RAC" ]; then
      f_destroyZoneRAC
    fi

    if [ "${TYPEZONE}" = "HA" ]; then
      f_destroyZoneHA
    fi
  else 
    f_logMessage ERROR "TYPEZONE n'est pas défini dans le fichier de configuration"
  fi

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
          . ${PROPERTIES_FILE}
          f_createZone
        else
          f_logMessage FATAL "Le fichier de properties spécifié n'existe pas.\n\n"
          exit -1
        fi
      ;;
      d )
        if [ ${OPTARG:0:1} != '/' ];then
          f_logMessage FATAL "Merci de renseigner le chemin complet du fichier properties"
          exit 1
        fi
        if [[ -f $OPTARG ]]; then
          PROPERTIES_FILE=${OPTARG}
          . ${PROPERTIES_FILE}
          f_destroyZone
        else
          f_logMessage FATAL "Le fichier de properties spécifié n'existe pas.\n\n"
          exit -1
        fi
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

#====================================================================================
