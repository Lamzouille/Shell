#!/bin/sh

#!/usr/bin/bash

#####################################################################################
#                                [create-lnxdisk.sh]                                #
#####################################################################################
# DESCRIPTION : Creation d'un disque sur une machine Linux                          #
#                                                                                   #
#####################################################################################
# UTILISATION : create-lnxdisk.sh [--create file.properties] --[help] [-v]          #
#                                                                                   #
# PARAMETRES :  [--create <config-file>] : Fichier de properties à utiliser         #
#               [--help] : Facultatif : Affiche l'aide du script                    #
#               [-v] : Facultatif : Affiche la version du script                    #
#                                                                                   #
# FONCTIONNEMENT : Creation d'un disque sur une machine Linux                       #
#                                                                                   #
# DEPENDANCES :  bibliothèques nécéssaire au fonctionnement du script               #
#                - lib.utilities.sh                                                 #
#                - lib.naming.sh                                                    #
#                                                                                   #
#####################################################################################
# AUTEUR : S.THIRARD                                                                #
# DATE DE CREATION : 23/03/2018                                                     #
#####################################################################################
# REVISIONS :                                                                       #
#-----------------------------------------------------------------------------------#
# DATE : 23/03/2018                                                                 #
# MODIFICATIONS : Initialisation du script                                          #
# AUTEUR : S.THIRARD                                                                #
#-----------------------------------------------------------------------------------#
#####################################################################################

# Chargement des variables
TMSTP=$(date "+%Y-%m-%d %H:%M:%S")
SCRIPT_NAME=$(basename "$0")
SCRIPT_PATH=$(dirname "$0")
SCRIPT_PATH=$(cd "${SCRIPT_PATH}"; pwd -P)
CURR_PATH=$(dirname "$0")
LOG_PATH=${CURR_PATH}/../log
LOG_FILE=${LOG_PATH}/create_ldom_${TMSTP}.log
CONF_PATH=${CURR_PATH}/../conf
VAR_PATH=${CURR_PATH}/../var
LIB_PATH=${CURR_PATH}/../lib
CONF_FILE_NAMING=${CONF_PATH}/server-naming.conf
SCRIPT_VERSION="1.0"

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

f_loadExternalLibs
f_setCommandAlias

a=$(f_analyseNaming CUT $(hostname) ${CONF_FILE_NAMING})
TRI=$(f_getTriFromAnalysedString "$a")
TYPE=$(f_getTypeFromAnalysedString "$a")
CLASS=$(f_getClassFromAnalysedString "$a")

# Vérification de la présence du fichier lock
if [ -f /opt/capgemini/var/${SCRIPT_NAME}.lock ]; then
    f_logMessage ERROR "Fichier lock présent - Fin du script "
    exit 1
fi

f_usage(){
    echo "Utilisation du script : "
    echo "--help      : Affichage des différents paramètres possibles"
    echo "--create    : Creation de tous les disques en fonction d'un fichier de configuration passé en paramètre"
    echo "-v          : Affichage de la version du script"
}

f_create_lv(){
    CONF_FILE=$1

    # Vérification de la présence du fichier de configuration
    if [ ! -f ${CONF_FILE} ]; then
        f_logMessage ERROR "Le fichier de config ${CONF_FILE} n'existe pas"
        exit 1
    fi

    test=$(cat ${CONF_FILE} | grep ":LV:" | grep ${TRI}${CLASS} | grep -v "#"| wc -l)
    if [ $test -eq 0 ]; then
        TRI="default"
    fi

    cat ${CONF_FILE} | grep ":LV:" | grep ${TRI}${CLASS} | grep -v "#" | while read line
    do
        volume_name=$(echo ${line} | awk -F ":" '{print $3}')
        volume_size=$(echo ${line} | awk -F ":" '{print $4}')
        volume_format=$(echo ${line} | awk -F ":" '{print $5}')
        pool_name=$(echo ${line} | awk -F ":" '{print $6}')
        volume_disk=$(echo ${line} | awk -F ":" '{print $7}')
        volume_mnt_pt=$(echo ${line} | awk -F ":" '{print $8}')
        volume_mnt_options=$(echo ${line} | awk -F ":" '{print $9}')

        # Vérification du point de montage - Création si non existante
        if [ ! -d ${volume_mnt_pt} ]; then
            mkdir -p ${volume_mnt_pt}
        fi

        # Création du lv
        ssm -f create -s ${volume_size} -n ${volume_name} --fstype ${volume_format} -p ${pool_name} ${volume_disk} ${volume_mnt_pt}

        # Mise à jour du fichier /etc/fstab
        test=$(cat /etc/fstab | grep ${volume_name})
        if [ "$test" = "" ]; then
            echo "/dev/mapper/${pool_name}-${volume_name} ${volume_mnt_pt}          ${volume_format}    defaults 0 0" >> /etc/fstab
        fi

        # Montage du point
        mount ${volume_mnt_pt}

    done

}

f_create_vg(){

    CONF_FILE=$1

    # Vérification de la présence du fichier de configuration
    if [ ! -f ${CONF_FILE} ]; then
        f_logMessage ERROR "Le fichier de config ${CONF_FILE} n'existe pas"
        exit 1
    fi

    # Verification de la présence du trigramme - si absent TRI => default
    test=$(cat ${CONF_FILE} | grep ":VG:" | grep ${TRI}${CLASS} | grep -v "#"| wc -l)
    if [ $test -eq 0 ]; then
        TRI="default"
    fi
    # Decoupage des variables du fichier de configuration
    cat ${CONF_FILE} | grep ":VG:" | grep ${TRI}${CLASS} | grep -v "#" | while read line
    do
        vg_name=$(echo ${line} | awk -F ":" '{print $3}')
        vg_disk=$(echo ${line} | awk -F ":" '{print $4}')

        # Création du vg
        ssm add -p ${vg_name} ${vg_disk}

    done

}

f_lock(){
    touch /opt/capgemini/var/${SCRIPT_NAME}.lock
}

# Début
if [ $# -eq 0 ]; then
    f_usage
fi

optspec=":-:"
while getopts "$optspec" optchar; do
    case "${OPTARG}" in
        help)
          f_usage
          exit 1
        ;;
        create)
          f_create_vg $2
          f_create_lv $2
          f_lock
        ;;
        v)
          printf "\e[36m\n Version du script ${SCRIPT_NAME} : ${SCRIPT_VERSION}. \n\n\e[0m"
          exit 0
    esac
done
