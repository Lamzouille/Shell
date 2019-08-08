#!/bin/sh

# -------------------------------------------------------------------------------------------------------
#  ######  ########  ########    ###    ######## ########          ##       ########   #######  ##     ##
# ##    ## ##     ## ##         ## ##      ##    ##                ##       ##     ## ##     ## ###   ###
# ##       ##     ## ##        ##   ##     ##    ##                ##       ##     ## ##     ## #### ####
# ##       ########  ######   ##     ##    ##    ######            ##       ##     ## ##     ## ## ### ##
# ##       ##   ##   ##       #########    ##    ##                ##       ##     ## ##     ## ##     ##
# ##    ## ##    ##  ##       ##     ##    ##    ##                ##       ##     ## ##     ## ##     ##
#  ######  ##     ## ######## ##     ##    ##    ########          ######## ########   #######  ##     ##
# -------------------------------------------------------------------------------------------------------
#
# @author : sthirard
# @description : Script d'automatisation de création des LDOMS
# param1 : option
# param2 : fichier de config a utiliser (si -f)
#
# ------------------------------------------
# Suivi des modifications
# ------------------------------------------
#
# DATE : MODIFICATION (TRIGRAMME_AUTEUR)
#
# 05/02/2018 : Initialisation du script (STD)
# 07/05/2018 : Ajout des options OPTGET --gen / --help / -f
# 08/05/2018 : Ajout de la partie création des disques
# 10/04/2018 : Ajout fonction création des adresses mac sur les vnet du LDOM
# 18/04/2018 : Ajout gestion de la destruction
#
#
# -----------------------------------------------------------------------------------------------------------



# Chargement des variables
TMSTP=$(date "+%Y-%m-%d %H:%M:%S")
CURR_PATH=$(pwd)
LOG_PATH=${CURR_PATH}/../log
LOG_FILE=${LOG_PATH}/create_ldom_${TMSTP}.log
CONF_PATH=${CURR_PATH}/../conf
VAR_PATH=${CURR_PATH}/../var
CONF_FILE=${CONF_PATH}/config_ldom.conf
LIB_PATH=${CURR_PATH}/../lib

# Chargement des librairies
if [ ! -d ${LIB_PATH} ]; then
    echo -e "Dossier lib inexistant"
    exit 1
else
    . ${LIB_PATH}/lib.utilities.sh
fi

f_setCommandAlias

#Fonction d'afichage des différentes options possibles au script
f_usage(){
    echo "Utilisation du script : "
    echo "--help      : Affichage des différents paramètres possibles"
    echo "--gen       : generation des fichiers de configuration pour tous les LDOMS"
    echo "-f          : creation du LDOM (fichier de configuration du LDOM à passer en paramètre)"
}

# Fonction de purge des anciens fichiers de configuration
f_purge(){
    rm -rf ${VAR_PATH}/*.cfg*
}

# Fonction ajout de X adresses MAC sur vnet ($2) du LDOM ($3)
f_addMacAdress(){
    nb_addr=$1
    vnet=$2
    ldom_name=$3
    conf_file=$4

    echo "for ((cpt=1; cpt<${nb_addr}; cpt++)); do /usr/sbin/ldm set-vnet alt-mac-addrs=+auto ${vnet} ${ldom_name}; done" >> ${conf_file}
}

f_list_KO(){
    # Listing des générations de conf KO
    v_nb_KO=$(ls -l ${VAR_PATH}/*KO | wc -l)
    v_nb_gen=$(ls -l ${VAR_PATH}/*.cfg* | wc -l )
    echo "\n"
    f_logMessage DEBUG "##################### STATUS GENERATION #####################"
    f_logMessage INFO "Nombre de générations : ${v_nb_gen}"
    f_logMessage INFO "Nombre de générations KO : ${v_nb_KO}"
    f_logMessage DEBUG "##################### END STATUS GENERATION #####################"
    echo "\n"
}

f_gen(){

    LDOM=$1
    DISK=$2
    ID_DISK=$3
    DOMAIN=$4
    MPGROUP=$5
    regex="^(c0t).*"
    
    if [[ ${DISK} =~ $regex ]]; then    
        test=$(echo | format | grep ${DISK%%s2})
        if [ "$test" != "" ]; then
            echo "/usr/sbin/ldm add-vdsdev -f mpgroup=${LDOM}-${MPGROUP}-mp /dev/rdsk/${DISK} ${LDOM}-${MPGROUP}@pdom-vds0" >> ${VAR_PATH}/config_${LDOM}.cfg
            echo "sleep 10" >> ${VAR_PATH}/config_${LDOM}.cfg
            echo "/usr/sbin/ldm add-vdsdev -f mpgroup=${LDOM}-${MPGROUP}-mp /dev/rdsk/${DISK} ${LDOM}-${MPGROUP}@sdom-vds0" >> ${VAR_PATH}/config_${LDOM}.cfg
            echo "sleep 10" >> ${VAR_PATH}/config_${LDOM}.cfg
            echo "/usr/sbin/ldm add-vdisk vdisk${ID_DISK} ${LDOM}-${MPGROUP}@${DOMAIN}-vds0 ${LDOM}" >> ${VAR_PATH}/config_${LDOM}.cfg
        else
            f_logMessage WARNING "Génération de la configuration du LDOM ${LDOM} : KO - Disque ${DISK} absent"
        fi
    else
        f_logMessage WARNING "Génération de la configuration du LDOM ${LDOM} : KO - Disque absent"
    fi
}

#Fonction de génération de la conf de tous les LDOMS
f_generateConf(){

    #Vérification de la présence du fichier de config ($CONF_FILE)
    if [ ! -f ${CONF_FILE} ]; then
        echo "Le fichier de config ${CONF_FILE} n'existe pas - Fin"
    fi
    
    # Parcours de la liste du fichier de configuration
    cat ${CONF_FILE} | grep "#" | while read line
    do
        # Récupération des différents LDOMS à créer
        LDOM_NAME=$(echo $line | sed 's/^#//')

        # Découpage des variables présentes dans le fichier de conf
        LDOM_VCPU=$(cat ${CONF_FILE} | grep "VCPU" | grep ${LDOM_NAME} | awk -F "=" '{print $2}')
        LDOM_RAM=$(cat ${CONF_FILE} | grep "RAM" | grep ${LDOM_NAME} | awk -F "=" '{print $2}')
        LDOM_IDCLUS=$(cat ${CONF_FILE} | grep "IDCLUS" | grep ${LDOM_NAME} | awk -F "=" '{print $2}')
        LDOM_IDSRV=$(cat ${CONF_FILE} | grep "IDSRV" | grep ${LDOM_NAME} | awk -F "=" '{print $2}')
        LDOM_DISK_ROOT=$(cat ${CONF_FILE} | grep "DISK" | grep "ROOT" | grep ${LDOM_NAME} | awk -F ":" '{print $3}')
        LDOM_DISK_BCKP=$(cat ${CONF_FILE} | grep "DISK" | grep "BCKP" | grep ${LDOM_NAME} | awk -F ":" '{print $3}')
        LDOM_DISK_DATA=$(cat ${CONF_FILE} | grep "DISK" | grep "DATA=" | grep ${LDOM_NAME} | awk -F ":" '{print $3}')
        LDOM_DISK_ZSTD=$(cat ${CONF_FILE} | grep "DISK" | grep "ZSTD" | grep ${LDOM_NAME} | awk -F ":" '{print $3}')
        LDOM_DISK_ORECO1=$(cat ${CONF_FILE} | grep "DISK" | grep "ORECO1" | grep ${LDOM_NAME} | awk -F ":" '{print $3}')
        LDOM_DISK_ORECO2=$(cat ${CONF_FILE} | grep "DISK" | grep "ORECO2" | grep ${LDOM_NAME} | awk -F ":" '{print $3}')
        LDOM_DISK_ODATA1=$(cat ${CONF_FILE} | grep "DISK" | grep "ODATA1" | grep ${LDOM_NAME} | awk -F ":" '{print $3}')
        LDOM_DISK_ODATA2=$(cat ${CONF_FILE} | grep "DISK" | grep "ODATA2" | grep ${LDOM_NAME} | awk -F ":" '{print $3}')
        LDOM_DISK_OMGMT1=$(cat ${CONF_FILE} | grep "DISK" | grep "OMGMT1" | grep ${LDOM_NAME} | awk -F ":" '{print $3}')
        LDOM_DISK_OMGMT2=$(cat ${CONF_FILE} | grep "DISK" | grep "OMGMT2" | grep ${LDOM_NAME} | awk -F ":" '{print $3}')
        LDOM_DISK_QUORUM=$(cat ${CONF_FILE} | grep "DISK" | grep "QUORUM" | grep ${LDOM_NAME} | awk -F ":" '{print $3}')
        LDOM_DISK_ZCLUS=$(cat ${CONF_FILE} | grep "DISK" | grep "ZCLUS" | grep ${LDOM_NAME} | awk -F ":" '{print $3}')
        ROOT_DOMAIN=$(cat ${CONF_FILE} | grep "DOMAIN" | grep "ROOT" | grep ${LDOM_NAME} | awk -F ":" '{print $3}')
        BCKP_DOMAIN=$(cat ${CONF_FILE} | grep "DOMAIN" | grep "BCKP" | grep ${LDOM_NAME} | awk -F ":" '{print $3}')
        ZSTD_DOMAIN=$(cat ${CONF_FILE} | grep "DOMAIN" | grep "ZSTD" | grep ${LDOM_NAME} | awk -F ":" '{print $3}')
        DATA_DOMAIN=$(cat ${CONF_FILE} | grep "DOMAIN" | grep "DATA=" | grep ${LDOM_NAME} | awk -F ":" '{print $3}')
        ODATA1_DOMAIN=$(cat ${CONF_FILE} | grep "DOMAIN" | grep "ODATA1" | grep ${LDOM_NAME} | awk -F ":" '{print $3}')
        ODATA2_DOMAIN=$(cat ${CONF_FILE} | grep "DOMAIN" | grep "ODATA2" | grep ${LDOM_NAME} | awk -F ":" '{print $3}')
        ORECO1_DOMAIN=$(cat ${CONF_FILE} | grep "DOMAIN" | grep "ORECO1" | grep ${LDOM_NAME} | awk -F ":" '{print $3}')
        ORECO2_DOMAIN=$(cat ${CONF_FILE} | grep "DOMAIN" | grep "ORECO2" | grep ${LDOM_NAME} | awk -F ":" '{print $3}')
        QUORUM_DOMAIN=$(cat ${CONF_FILE} | grep "DOMAIN" | grep "QUORUM" | grep ${LDOM_NAME} | awk -F ":" '{print $3}')
        OMGMT1_DOMAIN=$(cat ${CONF_FILE} | grep "DOMAIN" | grep "OMGMT1" | grep ${LDOM_NAME} | awk -F ":" '{print $3}')
        OMGMT2_DOMAIN=$(cat ${CONF_FILE} | grep "DOMAIN" | grep "OMGMT2" | grep ${LDOM_NAME} | awk -F ":" '{print $3}')
        ZCLUS_DOMAIN=$(cat ${CONF_FILE} | grep "DOMAIN" | grep "ZCLUS" | grep ${LDOM_NAME} | awk -F ":" '{print $3}')
        LDOM_PORT_CONSOLE=$(cat ${CONF_FILE} | grep "PORTCONSOLE" | grep ${LDOM_NAME} | awk -F "=" '{print $2}')
        
        touch ${VAR_PATH}/config_${LDOM_NAME}.cfg

        # Génération du fichier de config par ldom
        echo "/usr/sbin/ldm add-domain ${LDOM_NAME}" >> ${VAR_PATH}/config_${LDOM_NAME}.cfg
        echo "/usr/sbin/ldm set-vcpu ${LDOM_VCPU} ${LDOM_NAME}" >> ${VAR_PATH}/config_${LDOM_NAME}.cfg
        echo "/usr/sbin/ldm set-mem ${LDOM_RAM} ${LDOM_NAME}" >> ${VAR_PATH}/config_${LDOM_NAME}.cfg
        echo "/usr/sbin/ldm set-vconsole port=${LDOM_PORT_CONSOLE} service=primary-vcc0 ${LDOM_NAME}" >> ${VAR_PATH}/config_${LDOM_NAME}.cfg
        echo "/usr/sbin/ldm set-var auto-boot\?=false ${LDOM_NAME}" >> ${VAR_PATH}/config_${LDOM_NAME}.cfg

        # Génération des confs des vdsdev
        f_gen ${LDOM_NAME} ${LDOM_DISK_ROOT} 0 ${ROOT_DOMAIN} root
        f_gen ${LDOM_NAME} ${LDOM_DISK_BCKP} 1 ${BCKP_DOMAIN} bckp
        f_gen ${LDOM_NAME} ${LDOM_DISK_ZSTD} 2 ${ZSTD_DOMAIN} zstd
        f_gen ${LDOM_NAME} ${LDOM_DISK_DATA} 3 ${DATA_DOMAIN} data
        f_gen ${LDOM_NAME} ${LDOM_DISK_ODATA1} 4 ${ODATA1_DOMAIN} odata1 
        f_gen ${LDOM_NAME} ${LDOM_DISK_ODATA2} 5 ${ODATA2_DOMAIN} odata2
        f_gen ${LDOM_NAME} ${LDOM_DISK_ORECO1} 6 ${ORECO1_DOMAIN} oreco1
        f_gen ${LDOM_NAME} ${LDOM_DISK_ORECO2} 7 ${ORECO2_DOMAIN} oreco2
        f_gen ${LDOM_NAME} ${LDOM_DISK_ZCLUS} 8 ${ZCLUS_DOMAIN} zclus
        f_gen ${LDOM_NAME} ${LDOM_DISK_QUORUM} 9 ${QUORUM_DOMAIN} quorum
        f_gen ${LDOM_NAME} ${LDOM_DISK_OMGMT1} 10 ${OMGMT1_DOMAIN} omgmt1
        f_gen ${LDOM_NAME} ${LDOM_DISK_OMGMT2} 11 ${OMGMT2_DOMAIN} omgmt2

        echo "/usr/sbin/ldm bind ${LDOM_NAME}" >> ${VAR_PATH}/config_${LDOM_NAME}.cfg
        # carte data publique
        echo "/usr/sbin/ldm add-vnet id=0 linkprop=phys-state vnet0_data_pdom pdom-data-vsw0 ${LDOM_NAME}" >> ${VAR_PATH}/config_${LDOM_NAME}.cfg
        f_addMacAdress 30 vnet0_data_pdom ${LDOM_NAME} ${VAR_PATH}/config_${LDOM_NAME}.cfg
        echo "/usr/sbin/ldm add-vnet id=1 linkprop=phys-state vnet1_data_sdom sdom-data-vsw0 ${LDOM_NAME}" >> ${VAR_PATH}/config_${LDOM_NAME}.cfg
        f_addMacAdress 30 vnet1_data_sdom ${LDOM_NAME} ${VAR_PATH}/config_${LDOM_NAME}.cfg
        # carte data backup nfs
        echo "/usr/sbin/ldm add-vnet id=2 linkprop=phys-state vnet2_backup_pdom pdom-backup-vsw3 ${LDOM_NAME}" >> ${VAR_PATH}/config_${LDOM_NAME}.cfg
        echo "/usr/sbin/ldm add-vnet id=3 linkprop=phys-state vnet3_backup_sdom sdom-backup-vsw3 ${LDOM_NAME}" >> ${VAR_PATH}/config_${LDOM_NAME}.cfg
        
        # carte private oracle RAC
        echo "/usr/sbin/ldm add-vnet id=4 vnet4_orac_pdom pdom-orac-vsw2 ${LDOM_NAME}" >> ${VAR_PATH}/config_${LDOM_NAME}.cfg
        f_addMacAdress 10 vnet4_orac_pdom ${LDOM_NAME} ${VAR_PATH}/config_${LDOM_NAME}.cfg
        echo "/usr/sbin/ldm add-vnet id=5 vnet5_orac_sdom sdom-orac-vsw2 ${LDOM_NAME}" >> ${VAR_PATH}/config_${LDOM_NAME}.cfg
        f_addMacAdress 10 vnet5_orac_sdom ${LDOM_NAME} ${VAR_PATH}/config_${LDOM_NAME}.cfg

        # carte private cluster solaris
        echo "/usr/sbin/ldm add-vnet id=6 vnet6_cluster_pdom pdom-cluster-vsw1 ${LDOM_NAME}" >> ${VAR_PATH}/config_${LDOM_NAME}.cfg
        f_addMacAdress 10 vnet6_cluster_pdom ${LDOM_NAME} ${VAR_PATH}/config_${LDOM_NAME}.cfg
        echo "/usr/sbin/ldm add-vnet id=7 vnet7_cluster_sdom sdom-cluster-vsw1 ${LDOM_NAME}" >> ${VAR_PATH}/config_${LDOM_NAME}.cfg
        f_addMacAdress 10 vnet7_cluster_sdom ${LDOM_NAME} ${VAR_PATH}/config_${LDOM_NAME}.cfg
       
        #echo "/usr/sbin/ldm start ${LDOM_NAME}" >> ${VAR_PATH}/config_${LDOM_NAME}.cfg

        f_logMessage INFO "Génération de la configuration du LDOM ${LDOM_NAME} : OK"
    done

    f_list_KO
}

# Fonction de création du LDOM - nécessite de passer le fichier de config du LDOM en $1
f_createLdom(){
    # Vérification de la présence du fichier de création du LDOM
    if [ ! -f ${1} ]; then
        #echo -e "${red} Le fichier de configuration ${1} est inexistant ${no_color}"
        f_logMessage ERROR "Le fichier de configuration ${1} est inexistant"
        exit 1
        if [ $(echo ${1##*.} != "cfg" ) ]; then
            f_logMessage ERROR "Le fichier de configuration n'est pas correct - Extension incorrecte"
        fi
    else
        echo "Creation du LDOM ... avec fichier ${1}"
        # Affectation des droits d'execution sur le fichier de création du LDOM puis exécution
        chmod u+x ${1}
        /usr/bin/sh ${1}
        # Renommage du fichier + Desactivation des droits d'execution
        mv ${1} ${1}.OK
        chmod -x
    fi
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
        gen)
        f_purge
        f_generateConf
        ;;
        f)
        f_createLdom ${2}
        ;;
    esac
done
