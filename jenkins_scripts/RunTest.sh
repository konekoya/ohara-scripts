#!/bin/bash

# ALL tempoaray containers should use this as prefix of name
# this prefix helps us to remove correct containers later
CONTAINER_BASE_NAME="$PREFIX_OF_BUILD$BUILD_NUMBER"

IT_TASKS=(
  "collieIT"
  "clientIT"
  "connectorIT"
  "streamIT"
  "otherIT"
)

echo "=========================================[cleanup dead containers and images]========================================="
# Remove Cluster 1 by jack
# let randomITCluster=${BUILD_NUMBER}%2
# if [ $randomITCluster -eq 0 ];
# then
#   it_nodes=("ohara-jenkins-it-00" "ohara-jenkins-it-01" "ohara-jenkins-it-02")
#   k8sMetricsServer="http://ohara-jenkins-it-00:8080/apis"
# else
#   it_nodes=("ohara-jenkins-it-10" "ohara-jenkins-it-11" "ohara-jenkins-it-12")
#   k8sMetricsServer="http://ohara-jenkins-it-10:8080/apis"
# fi
it_nodes=("ohara-jenkins-it-00" "ohara-jenkins-it-01" "ohara-jenkins-it-02")
k8sMetricsServer="http://ohara-jenkins-it-00:8080/apis"

echo "=========================================[Your running IT master is ${it_nodes[0]}]========================================="

EXITED_CONTAINERS=$(docker ps -a -q --filter status=exited)
if [[ "$EXITED_CONTAINERS" != "" ]];then
  docker rm $EXITED_CONTAINERS
fi
# Don't remove dangling images since them may be used by other QA

if [[ "$PULL_REQUEST_ACTION" == "opened" ]] || [[ "$PULL_REQUEST_ACTION" == "synchronize" ]]; then
  PULL_REQUEST_ID=$PULL_REQUEST_ID_OPENED
elif [[ "$PULL_REQUEST_ACTION" == "created" ]]; then
  PULL_REQUEST_ID=$PULL_REQUEST_ID_CREATED
else
  exit 2
fi

CHECKS_FOLDER=$WORKSPACE/checks

# get sha AND branch
SHA=$(curl -u $GITHUB_USER:$GITHUB_KEY -s https://api.github.com/repos/oharastream/ohara/pulls/$PULL_REQUEST_ID | jq -r '.head.sha')
PR_BASE_BRANCH=$(curl -u $GITHUB_USER:$GITHUB_KEY -s https://api.github.com/repos/oharastream/ohara/pulls/$PULL_REQUEST_ID | jq -r '.base.ref')

FORK_COUNT=4

NODE00_HOSTNAME=${it_nodes[0]}
NODE00_INFO="$NODE_USER_NAME:$NODE_PASSWORD@$NODE00_HOSTNAME:22"

NODE01_HOSTNAME=${it_nodes[1]}
NODE01_INFO="$NODE_USER_NAME:$NODE_PASSWORD@$NODE01_HOSTNAME:22"

NODE02_HOSTNAME=${it_nodes[2]}
NODE02_INFO="$NODE_USER_NAME:$NODE_PASSWORD@$NODE02_HOSTNAME:22"

K8S_HOSTNAME=${it_nodes[0]}
K8S_PORT="8080"
K8S_NODES="${it_nodes[1]},${it_nodes[2]}"

K8S_URL="http://$K8S_HOSTNAME:$K8S_PORT/api/v1"
K8S_METRICS_URL="http://$K8S_HOSTNAME:$K8S_PORT/apis"


IT_RANDOM_PORT=$((16000+$(($BUILD_NUMBER % 100))))
MANAGER_API_CONFIGURATOR_RANDOM_PORT=$((22000+$(($BUILD_NUMBER % 100))))
MANAGER_IT_CONFIGURATOR_RANDOM_PORT=$((26000+$(($BUILD_NUMBER % 100))))
MANAGER_FAKE_IT_CONFIGURATOR_RANDOM_PORT=$((28000+$(($BUILD_NUMBER % 100))))

# Create Samba docker container for Samba client test
SMB_CONTAINER_NAME="$CONTAINER_BASE_NAME-samba"
SMB_USER="ohara"
SMB_PASSWORD="island123"
SMB_SSN_PORT=$((19000+$(($BUILD_NUMBER % 100))))
SMB_DS_PORT=$((20000+$(($BUILD_NUMBER % 100))))  
  
docker run -d --rm \
  --name ${SMB_CONTAINER_NAME} \
  -p ${SMB_SSN_PORT}:139 \
  -p ${SMB_DS_PORT}:445 \
  dperson/samba -u "${SMB_USER};${SMB_PASSWORD}" -s "${SMB_USER};/tmp/;yes;no;no;all;${SMB_USER}:${SMB_USER}"  
echo "Samba server in the $HOSTNAME"


# Create postgresql docker container for JDBC Source Connector test
POSTGRESQL_RANDOM_PORT=$((18000+$(($BUILD_NUMBER % 100))))
POSTGRESQL_CONTAINER_NAME="$CONTAINER_BASE_NAME-postgresql"
POSTGRESQL_USERNAME="admin"
POSTGRESQL_PASSWORD="123456"
POSTGRESQL_DB_NAME="postgres"
  
docker run -d --rm \
  --name ${POSTGRESQL_CONTAINER_NAME} \
  -p ${POSTGRESQL_RANDOM_PORT}:5432 \
  --env "POSTGRES_USER=$POSTGRESQL_USERNAME" \
  --env "POSTGRES_PASSWORD=$POSTGRESQL_PASSWORD" \
  --env "POSTGRES_DB=$POSTGRESQL_DB_NAME" \
  -it islandsystems/postgresql:9.2.24
   
POSTGRESQL_URL="jdbc:postgresql://$HOSTNAME:$POSTGRESQL_RANDOM_PORT/$POSTGRESQL_DB_NAME"
echo "The db url is ${POSTGRESQL_URL}"

# Setting oracle connection info
ORACLE_URL="jdbc:oracle:thin:@//${it_nodes[1]}:1521/xe.localdomain"
echo "Oracle Database URL is ${ORACLE_URL}"
#DB_USERNAME=$ORACLE_USER_NAME
#DB_PASSWORD=$ORACLE_PASSWORD

# Setting jar folder path
JAR_FOLDER_PATH="/jar"


EXTRA_PROPERTIES="\
-Pohara.it.docker=$NODE00_INFO,$NODE01_INFO,$NODE02_INFO \
-Pohara.it.configurator.node=$NODE00_INFO \
-Pohara.it.k8s=$K8S_URL \
-Pohara.it.k8s.metrics.server=$k8sMetricsServer \
-Pohara.it.hostname=$(hostname) \
-Pohara.it.port=$IT_RANDOM_PORT \
-Pohara.manager.api.configurator="http://$(hostname):$MANAGER_API_CONFIGURATOR_RANDOM_PORT/v0" \
-Pohara.manager.e2e.configurator="http://$(hostname):$MANAGER_IT_CONFIGURATOR_RANDOM_PORT/v0" \
-Pohara.manager.it.configurator="http://$(hostname):$MANAGER_FAKE_IT_CONFIGURATOR_RANDOM_PORT/v0" \
-Pohara.manager.e2e.nodeHost=$K8S_HOSTNAME \
-Pohara.manager.e2e.nodePort=22 \
-Pohara.manager.e2e.nodeUser=$NODE_USER_NAME \
-Pohara.manager.e2e.nodePass=$NODE_PASSWORD \
-Pohara.it.postgresql.db.url=$POSTGRESQL_URL \
-Pohara.it.postgresql.db.username=$POSTGRESQL_USERNAME \
-Pohara.it.postgresql.db.password=$POSTGRESQL_PASSWORD \
-Pohara.it.oracle.db.url=$ORACLE_URL \
-Pohara.it.oracle.db.username=$ORACLE_USER_NAME \
-Pohara.it.oracle.db.password=$ORACLE_PASSWORD \
-Pohara.it.jar.folder=$JAR_FOLDER_PATH \
-Pohara.it.container.prefix=$CONTAINER_BASE_NAME \
-Pohara.it.smb.hostname=$(hostname) \
-Pohara.it.smb.port=$SMB_DS_PORT \
-Pohara.it.smb.username=$SMB_USER \
-Pohara.it.smb.password=$SMB_PASSWORD \
-Pohara.it.smb.shareName=$SMB_USER \
"

ALL_TESTS=(
  "testing-util"
  "common"
  "metrics"
  "client"
  "kafka"
  "configurator"
  # those names do not exist on our code. they are used to parse which tests we want to run for UI
  "manager-ut"
  "manager-api"
  "manager-e2e"
  "manager-it"
  "connector"
  "shabondi"
  "agent"
  "stream"
  )

# add the it tasks to all tests
for task in ${IT_TASKS[@]}; do
  ALL_TESTS+=("$task")
done

TARGET_TESTS=()
for targetTest in "${ALL_TESTS[@]}"
do
  if [[ -f "$WORKSPACE/target_tests/$targetTest" ]]; then
    echo "=========================================[add $targetTest to test queue]========================================="
    TARGET_TESTS+=("$targetTest")
  else
    echo "=========================================[$targetTest is excluded from QA]========================================="
  fi
done

TEST_COMMAND=""

NEED_MANAGER_UT_TESTS="false"
NEED_MANAGER_IT_TESTS="false"
NEED_MANAGER_API_TESTS="false"

for targetTest in "${TARGET_TESTS[@]}"
do
  isItTask="false"
  for task in ${IT_TASKS[@]}; do
  
    if [[ "$targetTest" == "$task" ]]; then
      TEST_COMMAND="$task $TEST_COMMAND"
      isItTask="true"
    fi

  done
  
  if [[ "$isItTask" == "false" ]]; then
    if [[ "$targetTest" == "manager-ut" ]]; then
      TEST_COMMAND="ohara-manager:test $TEST_COMMAND"
      NEED_MANAGER_UT_TESTS="true"
      
    elif [[ "$targetTest" == "manager-api" ]]; then
      TEST_COMMAND="ohara-manager:api $TEST_COMMAND"
      NEED_MANAGER_API_TESTS="true"
      
    elif [[ "$targetTest" == "manager-e2e" ]]; then
      TEST_COMMAND="ohara-manager:e2e $TEST_COMMAND"
    
    elif [[ "$targetTest" == "manager-it" ]]; then
      TEST_COMMAND="ohara-manager:it $TEST_COMMAND"
      NEED_MANAGER_IT_TESTS="true"
    
    else
      TEST_COMMAND="ohara-$targetTest:test $TEST_COMMAND"
    fi
  fi

done

if [[ "$TEST_COMMAND" == "" ]]; then
  echo "=========================================[PR:$PULL_REQUEST_ID does not change any modules so we skip the tests]========================================="
  exit 0
fi

OHARA_VERSION=""
# we reassign the version if this PR requires the changed images
if [[ -f "$WORKSPACE/tmp_images_version" ]]; then
  OHARA_VERSION=$(cat $WORKSPACE/tmp_images_version)
else
  OHARA_VERSION=$(cat $WORKSPACE/version)
fi

if [[ "$OHARA_VERSION" == "" ]]; then
  echo "failed to find the version for configurator"
  exit 2
fi

if [[ "$TEST_COMMAND" == *"ohara-manager"* ]]; then  
  if [[ "$TEST_COMMAND" == *"ohara-manager:api"* ]]; then
    echo "=========================================[tag:$OHARA_VERSION, port:$MANAGER_API_CONFIGURATOR_RANDOM_PORT, API tests]========================================="
    docker run \
         --name "$CONTAINER_BASE_NAME-api-configurator" \
         -p $MANAGER_API_CONFIGURATOR_RANDOM_PORT:$MANAGER_API_CONFIGURATOR_RANDOM_PORT \
         -d \
         --rm \
         oharastream/configurator:$OHARA_VERSION \
         --port $MANAGER_API_CONFIGURATOR_RANDOM_PORT \
         --hostname $(hostname) \
         --fake true
    
    echo "sleep 15 seconds for API configurator"
    sleep 15
    docker logs "$CONTAINER_BASE_NAME-api-configurator" > $CHECKS_FOLDER/api_configurator.log
  fi
  
  if [[ "$TEST_COMMAND" == *"ohara-manager:e2e"* ]]; then
    echo "=========================================[tag:$OHARA_VERSION, port:$MANAGER_IT_CONFIGURATOR_RANDOM_PORT, IT tests]========================================="
    docker run \
         --name "$CONTAINER_BASE_NAME-it-configurator" \
         -p $MANAGER_IT_CONFIGURATOR_RANDOM_PORT:$MANAGER_IT_CONFIGURATOR_RANDOM_PORT \
         -d \
         --rm \
         oharastream/configurator:$OHARA_VERSION \
         --port $MANAGER_IT_CONFIGURATOR_RANDOM_PORT \
         --hostname $(hostname) \
         --k8s ${K8S_URL} \
         --k8s-metrics-server ${K8S_METRICS_URL}
    
    echo "sleep 15 seconds for IT configurator"
    sleep 15
    docker logs "$CONTAINER_BASE_NAME-it-configurator" > $CHECKS_FOLDER/it_configurator.log
  fi
  
  if [[ "$TEST_COMMAND" == *"ohara-manager:it"* ]]; then
    echo "=========================================[tag:$OHARA_VERSION, port:$MANAGER_FAKE_IT_CONFIGURATOR_RANDOM_PORT, FAKE IT tests]========================================="
    docker run \
       --name "$CONTAINER_BASE_NAME-fake-it-configurator" \
       -p $MANAGER_FAKE_IT_CONFIGURATOR_RANDOM_PORT:$MANAGER_FAKE_IT_CONFIGURATOR_RANDOM_PORT \
       -d \
       --rm \
       oharastream/configurator:$OHARA_VERSION \
       --port $MANAGER_FAKE_IT_CONFIGURATOR_RANDOM_PORT \
       --fake true
    
    echo "sleep 15 seconds for Fake IT configurator"
    sleep 15
    docker logs "$CONTAINER_BASE_NAME-fake-it-configurator" > $CHECKS_FOLDER/fake_it_configurator.log
  fi
  
  GRADLE_COMMAND="./gradlew clean -PmaxTestRetries=1 -PmaxTestFailures=10 -PmaxParallelForks=$FORK_COUNT -Pohara.version=$OHARA_VERSION $TEST_COMMAND $EXTRA_PROPERTIES --continue"
else
  GRADLE_COMMAND="./gradlew clean -PmaxTestRetries=1 -PmaxTestFailures=10 -PmaxParallelForks=$FORK_COUNT -Pohara.version=$OHARA_VERSION $TEST_COMMAND $EXTRA_PROPERTIES -PskipManager --continue"
fi

echo "=========================================[OHARA_VERSION:$OHARA_VERSION TEST_COMMAND:TEST_COMMAND]========================================="

COMMAND="cd /ohara \
  && git config --global user.name \"jenkins\" \
  && git config --global user.email \"jenkins@example.com\" \
  && git pull \
  && git checkout $PR_BASE_BRANCH \
  && git pull \
  && git fetch origin pull/$PULL_REQUEST_ID/head:$BUILD_NUMBER \
  && git checkout $BUILD_NUMBER \
  && git pull --rebase origin $PR_BASE_BRANCH \
  && $GRADLE_COMMAND \
"

# For run the gradle report command to show ohara-manager code coverage report
if [[ "$NEED_MANAGER_UT_TESTS" == "true" ]] && [[ "$NEED_MANAGER_API_TESTS" == "true" ]] && [[ "$NEED_MANAGER_IT_TESTS" == "true" ]]; then
  COMMAND="$COMMAND && ./gradlew report"
fi

echo "=========================================[start QA for PR:$PULL_REQUEST_ID based on $PR_BASE_BRANCH]========================================="
# run the docker
docker run \
  --name $CONTAINER_BASE_NAME \
  -v $JAR_FOLDER_PATH:$JAR_FOLDER_PATH \
  -p $IT_RANDOM_PORT:$IT_RANDOM_PORT \
  $CI_IMAGE \
  /bin/bash -c "$COMMAND" | tee $CHECKS_FOLDER/console.log

if [[ -d "$WORKSPACE/ohara" ]]; then
 rm -rf "$WORKSPACE/ohara"
fi


docker cp $CONTAINER_BASE_NAME:/ohara $WORKSPACE

echo "=========================================[parse reports]========================================="

MODULES=(
  "testing-util"
  "common"
  "metrics"
  "client"
  "kafka"
  "configurator"
  "manager"
  "connector"
  "shabondi"
  "agent"
  "it"
  "stream"
)

for MODULE in ${MODULES[@]}; do
  # ohara-manager doesn't have "summary" report so we have got to parse it manually.
  if [[ "$MODULE" == "manager" ]]; then
    files=("clientE2e.xml" "clientUnits.xml" "serverUnits.xml" "clientApi.xml" "clientIt.xml")
    itFailureCount=0
    utFailureCount=0
    apiFailureCount=0
    fakeItFailureCount=0
    passCount=0
    for file in ${files[@]}; do
      index="$WORKSPACE/ohara/ohara-$MODULE/test-reports/$file"
      if [[ -f "$index" ]]; then
        # all reports have xml declaration...
        # clientUnits.xml
        # <testsuites name="jest tests" tests="206" failures="0" time="11.028">
        # serverUnits.xml
        # <testsuites name="jest tests" tests="7" failures="0" time="2.267">
        # clientE2e.xml
        # <testsuites tests="29" failures="5" errors="0"><testsuite name="Root Suite" timestamp="2019-04-30T08:29:23" tests="0" failures="0" time="0">
        lineNumber=2
        if [[ "$index" == *"clientUnits.xml"* ]] || [[ "$index" == *"serverUnits.xml"* ]]; then
          keyIndex=5
        else
          keyIndex=3
        fi     

        result=$(head -n $lineNumber $index | cut -d' ' -f $keyIndex)

        if [[ "$result" == *"failures=\"0\""* ]]; then
          passCount=$((passCount+1))
        else
          if [[ "$file" == "clientE2e.xml" ]]; then
            itFailureCount=$((itFailureCount+1))
          elif [[ "$file" == "clientApi.xml" ]]; then
            apiFailureCount=$((apiFailureCount+1))
          elif [[ "$file" == "clientIt.xml" ]]; then
            fakeItFailureCount=$((fakeItFailureCount+1))
          else
            utFailureCount=$((utFailureCount+1))
          fi
        fi
      else
        if [[ "$file" == "clientE2e.xml" ]]; then
          itFailureCount="-999"
        elif [[ "$file" == "clientApi.xml" ]]; then
          apiFailureCount="-999"
        elif [[ "$file" == "clientUnits.xml" ]]; then
          utFailureCount="-999"
        elif [[ "$file" == "clientIt.xml" ]]; then
          fakeItFailureCount="-999" 
        fi
      fi
    done
    
    # Ohara Manager may miss the report after completing all testing
    # Hence, the negative count may be caused by missed report file.
    if [[ "$utFailureCount" == "0" ]]; then
      echo -n "success" >> "$WORKSPACE/manager-ut_state"
    elif [[ -f "$WORKSPACE/manager-ut_exist" ]]; then
      echo -n "failure" >> "$WORKSPACE/manager-ut_state"
    fi

    if [[ "$apiFailureCount" == "0" ]]; then
      echo -n "success" >> "$WORKSPACE/manager-api_state"
    elif [[ -f "$WORKSPACE/manager-api_exist" ]]; then
      echo "=========================================[API compatibility is broken!!! Attach warning to PR:$PULL_REQUEST_ID]========================================="
      curl -s --header "Content-Type: application/json" \
        -u $GITHUB_USER:$GITHUB_KEY \
        -X POST "https://api.github.com/repos/oharastream/ohara/issues/$PULL_REQUEST_ID/comments" \
        -d "{\"body\": \"This PR may break API compatibility!!! ping $UI_COMMITTERS see $BUILD_URL for logs\"}" \
        >> $CHECKS_FOLDER/ping_ui_committers.log 2>&1

      echo -n "failure" >> "$WORKSPACE/manager-api_state"
    fi

    if [[ "$fakeItFailureCount" == "0" ]]; then
      echo -n "success" >> "$WORKSPACE/manager-it_state"
    elif [[ -f "$WORKSPACE/manager-it_exist" ]]; then
      echo -n "failure" >> "$WORKSPACE/manager-it_state"
    fi
    
    if [[ "$itFailureCount" == "0" ]]; then
      echo -n "success" >> "$WORKSPACE/manager-e2e_state"
    elif [[ -f "$WORKSPACE/manager-e2e_exist" ]]; then
      echo -n "failure" >> "$WORKSPACE/manager-e2e_state"
    fi
  elif [[ "$MODULE" == "it" ]]; then
    for task in ${IT_TASKS[@]}; do
      index="$WORKSPACE/ohara/ohara-it/build/reports/tests/$task/index.html"
      if [[ -f "$index" ]]; then
        elapsed=$(grep -m 1 -o -P "([[:digit:]]+h)?([[:digit:]]+m)?([[:digit:]]+(\.[[:digit:]]+)?s)" $index)
        if grep -q "infoBox success\|infoBox skipped" "$index"
        then
          echo -n "success" >> $WORKSPACE/${task}_state
          echo -n "$elapsed" >> $WORKSPACE/${task}_elapsed
        else
          echo -n "failure" >> $WORKSPACE/${task}_state
          echo -n "$elapsed" >> $WORKSPACE/${task}_elapsed
        fi
      else
        echo -n "error" >> $WORKSPACE/${task}_state
        echo -n "no tests!" >> $WORKSPACE/${task}_elapsed
      fi
    done
  else
    index="$WORKSPACE/ohara/ohara-$MODULE/build/reports/tests/test/index.html"
    if [[ -f "$index" ]]; then
      elapsed=$(grep -m 1 -o -P "([[:digit:]]+h)?([[:digit:]]+m)?([[:digit:]]+(\.[[:digit:]]+)?s)" $index)
      if grep -q "infoBox success\|infoBox skipped" "$index"
      then
        echo -n "success" >> $WORKSPACE/${MODULE}_state
        echo -n "$elapsed" >> $WORKSPACE/${MODULE}_elapsed
      else
        echo -n "failure" >> $WORKSPACE/${MODULE}_state
        echo -n "$elapsed" >> $WORKSPACE/${MODULE}_elapsed
      fi
    else
      echo -n "error" >> $WORKSPACE/${MODULE}_state
      echo -n "no tests!" >> $WORKSPACE/${MODULE}_elapsed
    fi
  fi
done
  
