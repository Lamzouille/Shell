#!/bin/bash

#####################################################################################
#                            [get_rundeck_report.sh]                                #
#####################################################################################
# DESCRIPTION : Génération d'un rapport d'un job Rundeck et envoi par mail          #
#                                                                                   #
#####################################################################################
# UTILISATION : get_rundeck_report.sh <job_id>                                      #
#                                                                                   #
# PARAMETRES :  [job_id] : Job id du job                                            #
#               [--help] : Facultatif : Affiche l'aide du script                    #
#               [-v] : Facultatif : Affiche la version du script                    #
#                                                                                   #
# FONCTIONNEMENT : Récupération des informations d'execution d'un job Rundeck       #
#                  Envoi par mai des informations récupérées.                       #
# DEPENDANCES :  bibliothèques nécéssaire au fonctionnement du script               #
#                - lib.utilities.sh                                                 #
#                                                                                   #
#####################################################################################
# AUTEUR : S.THIRARD                                                                #
# DATE DE CREATION : 23/03/2018                                                     #
#####################################################################################
# REVISIONS :                                                                       #
#-----------------------------------------------------------------------------------#
# DATE : 09/08/2019                                                                 #
# MODIFICATIONS : Initialisation du script                                          #
# AUTEUR : S.THIRARD                                                                #
#-----------------------------------------------------------------------------------#
#####################################################################################

UID_JOB=$1
:
REQUETE=$(curl -s --location --request GET "https://lsc-brown-01-a:8443/api/21/job/${UID_JOB}/executions" --header "Accept: application/json" --header "X-Rundeck-Auth-Token: 641t0wAZOsInOi7JDpZr8DwNiQLOjnIw" --header "Content-Type: application/json" | jq '.executions[0] | "\(.id) \(.status) \(.user) \(."date-started".date) \(."date-ended".date) \(.successfulNodes) \(.permalink) \(."date-started".unixtime) \(."date-ended".unixtime) \(."job".averageDuration)"')

_id_exec=$(echo $REQUETE | awk -F " " '{print $1}' | tr -d '"')
_status=$(echo $REQUETE | awk -F " " '{print $2}')
_username=$(echo $REQUETE | awk -F " " '{print $3}')
_date_start=$(echo $REQUETE | awk -F " " '{print $4}')
_start_unixtime=$(echo $REQUETE | awk -F " " '{print $8}')
_end_unixtime=$(echo $REQUETE | awk -F " " '{print $9}' | tr -d '"')
_date_end=$(echo $REQUETE | awk -F " " '{print $5}')
_permalink=$(echo $REQUETE | awk -F " " '{print $7}')
_nodes_list=$(echo $REQUETE | awk -F " " '{print $6}' | tr -d  '[]\\')
_job_avg_duration=$(echo $REQUETE | awk -F " " '{print $10}' | tr -d '"')
_job_avg_duration=$(($_job_avg_duration/1000))
_job_duration=$((($_end_unixtime-$_start_unixtime)/1000))
_formatted_job_duration=$(date -u -d @${_job_duration} +"%T")
_formatted_job_avg_duration=$(date -u -d @${_job_avg_duration} +"%T")
_log_saltstack_path="/home/sthirard"
_json_salstack_file="test.json"

f_logMsg(){

	level=$1
	msg=$2

	RED="\033[31m"
	GREEN="\033[32m"
	YELLOW="\033[33m"
	BLUE="\033[34m"
	BLACK="\033[30m"
	DELIM_FIN="\033[m"
	_date=$(date '+%d/%m/%Y - %T')


	if [ $level == "ERROR" ]; then
		COLOR="${RED}"
	elif [ $level == "DEBUG" ]; then
		COLOR="${BLUE}"
	elif [ $level == "SUCCESS" ]; then
		COLOR="${GREEN}"
	elif [ $level == "WARNING" ]; then
		COLOR="${YELLOW}"
	else COLOR="${WHITE}"
	fi

	echo -e "${COLOR}""["$level"] [${_date}] - ""${msg}""${DELIM_FIN}"
}

###### MAIN 
#f_logMsg DEBUG "============ DEBUG REQUETE ============"
#f_logMsg DEBUG "${REQUETE}"
f_logMsg DEBUG "============ DEBUT RAPPORT ============"
echo ""
f_logMsg INFO "Lien Rundeck : ${_permalink}"
f_logMsg INFO "ID execution : ${_id_exec}"
f_logMsg INFO "Owner : ${_username}" 
f_logMsg INFO "Status Job : ${_status}"
f_logMsg INFO "Date début execution: ${_date_start}"
f_logMsg INFO "Date fin execution : ${_date_end}"
#echo "Debut UNIXTIME : ${_start_unixtime}"
#echo "Fin UNIXTIME : ${_end_unixtime}"
f_logMsg INFO "Temps de traitement job : ${_formatted_job_duration}"
f_logMsg INFO "Temps de traitement moyen : ${_formatted_job_avg_duration}"
f_logMsg INFO "Liste serveurs impactes : ${_nodes_list}"
echo ""
f_logMsg DEBUG "============ FIN RAPPORT ============"

###### END MAIN
