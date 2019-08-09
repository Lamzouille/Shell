#!/bin/bash

#####################################################################################
#                            [get_rundeck_report.sh]                                #
#####################################################################################
# DESCRIPTION : Rundeck job description - sent by mail			            #
#                                                                                   #
#####################################################################################
# USE : get_rundeck_report.sh <job_id>                          	            #
#                                                                                   #
# PARAMETERS :  $1 : [job_id] : Job id of the rundeck job                           #
#               [--help] : Optional : Display script help	                    #
#               [-v] : Optional : Display script version	                    #
#                                                                                   #
# FONCTIONNEMENT : Récupération des informations d'execution d'un job Rundeck       #
#                  Envoi par mai des informations récupérées.                       #
# DEPENDANCIES :  Mandatories libraries to execute the job	                    #
#                - lib.utilities.sh                                                 #
#                                                                                   #
#####################################################################################
# AUTEUR : S.THIRARD                                                                #
# DATE DE CREATION : 09/08/2019                                                     #
#####################################################################################
# REVISIONS :                                                                       #
#-----------------------------------------------------------------------------------#
# DATE : 09/08/2019                                                                 #
# MODIFICATIONS : Initialisation du script                                          #
# AUTEUR : S.THIRARD                                                                #
#-----------------------------------------------------------------------------------#
#####################################################################################

RUNDECK_URL="<http://your_rundeck_url>"
RUNDECK_PORT="<your_rundeck_port>"
RUNDECK_TOKEN="<your_rundeck_token>"

UID_JOB=$1

REQUEST=$(curl -s --location --request GET "https://${RUNDECK_URL}:${RUNDECK_PORT}/api/21/job/${UID_JOB}/executions" --header "Accept: application/json" --header "X-Rundeck-Auth-Token: ${RUNDECK_TOKEN}" --header "Content-Type: application/json" | jq '.executions[0] | "\(.id) \(.status) \(.user) \(."date-started".date) \(."date-ended".date) \(.successfulNodes) \(.permalink) \(."date-started".unixtime) \(."date-ended".unixtime) \(."job".averageDuration)"')

_id_exec=$(echo $REQUEST | awk -F " " '{print $1}' | tr -d '"')
_status=$(echo $REQUEST | awk -F " " '{print $2}')
_username=$(echo $REQUEST | awk -F " " '{print $3}')
_date_start=$(echo $REQUEST | awk -F " " '{print $4}')
_start_unixtime=$(echo $REQUEST | awk -F " " '{print $8}')
_end_unixtime=$(echo $REQUEST | awk -F " " '{print $9}' | tr -d '"')
_date_end=$(echo $REQUEST | awk -F " " '{print $5}')
_permalink=$(echo $REQUEST | awk -F " " '{print $7}')
_nodes_list=$(echo $REQUEST | awk -F " " '{print $6}' | tr -d  '[]\\')
_job_avg_duration=$(echo $REQUEST | awk -F " " '{print $10}' | tr -d '"')
_job_avg_duration=$(($_job_avg_duration/1000))
_job_duration=$((($_end_unixtime-$_start_unixtime)/1000))
_formatted_job_duration=$(date -u -d @${_job_duration} +"%T")
_formatted_job_avg_duration=$(date -u -d @${_job_avg_duration} +"%T")
_log_saltstack_path="/home/sthirard"
_json_salstack_file="test.json"

f_loadExternalLibs(){   # Loads all externals libraries

  [[ ! -d ${LIB_PATH} ]] && exit -1
  for lib in $(ls ${LIB_PATH}/lib.*.sh); do
    . ${lib}
    LOADED_LIBS="${LOADED_LIBS} $(basename ${lib})"
  done
  if [[ DEBUG_MODE -ne 0 ]]; then
    printf "\e[36mLoading external libraries ...\n"
    printf "+++++++++++++++++++++++++++++++++++++++++++++++++++++\n"
    printf "Libraries loaded :\n"
    printf " - %s\n" $(echo ${LOADED_LIBS})
    printf "+++++++++++++++++++++++++++++++++++++++++++++++++++++\n"
    printf "Loading external libraries : DONE ...\e[36m%b\e[0m\n"
  fi
}

###### MAIN 
#f_logMessage DEBUG "============ DEBUG REQUEST ============"
#f_logMessage DEBUG "${REQUEST}"
f_logMessage DEBUG "============ DEBUT REPORT ============"
echo ""
f_logMessage INFO "Rundeck job link : ${_permalink}"
f_logMessage INFO "Execution ID : ${_id_exec}"
f_logMessage INFO "Owner : ${_username}" 
f_logMessage INFO "Status Job : ${_status}"
f_logMessage INFO "Start job date : ${_date_start}"
f_logMessage INFO "End job date : ${_date_end}"
#echo "Debut UNIXTIME : ${_start_unixtime}"
#echo "Fin UNIXTIME : ${_end_unixtime}"
f_logMessage INFO "Job Duration : ${_formatted_job_duration}"
f_logMessage INFO "Average job duration : ${_formatted_job_avg_duration}"
f_logMessage INFO "Impacted nodes : ${_nodes_list}"
echo ""
f_logMessage DEBUG "============ END REPORT ============"

###### END MAIN
