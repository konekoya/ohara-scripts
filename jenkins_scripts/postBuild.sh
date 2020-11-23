#!/bin/bash

CONTAINER_BASE_NAME="$PREFIX_OF_BUILD$BUILD_NUMBER"
TAG_BASE_NAME="$PREFIX_OF_BUILD$BUILD_NUMBER"

CHECKS_FOLDER=$WORKSPACE/checks
mkdir -p $CHECKS_FOLDER

echo "=========================================[cleanup container:$BUILD_TAG]========================================="
    
# remove local containers
targets=$(docker ps -a -q --filter name=$CONTAINER_BASE_NAME)
if [[ "$targets" != "" ]]; then
  docker rm -f $targets
else
  echo "no idle docker containers on local"
fi

# remove local images 
targets=$(docker images -q --filter reference=oharastream/*:$TAG_BASE_NAME)
if [[ "$targets" != "" ]]; then
  docker rmi -f $targets
else
  echo "no temporary images on local"
fi

# cleanup temporary images only if we had sync them
# we don't care for the true cluster since the temporary jar is indepenent to other QA
# it is safe to loop all it nodes to cleanup "possible" jars


# Remove cluster 1 by jack
#it_nodes=(
#  "ohara-jenkins-it-00"
#  "ohara-jenkins-it-01"
#  "ohara-jenkins-it-02"
#  "ohara-jenkins-it-10"
#  "ohara-jenkins-it-11"
#  "ohara-jenkins-it-12"
#)

it_nodes=(
  "ohara-jenkins-it-00"
  "ohara-jenkins-it-01"
  "ohara-jenkins-it-02"
)



# we have to remove containers first. Otherwise, the temporary images can't be removed
for node in "${it_nodes[@]}"; do
  echo "=========================================[cleanup container for $node]========================================="

  # if [[ "$node" == "ohara-jenkins-it-00" ]] || [[ "$node" == "ohara-jenkins-it-10" ]]; then
  if [[ "$node" == "ohara-jenkins-it-00" ]]; then
    # remove the containers created by k8s
    targets=$(ssh ohara@$node kubectl get pods | awk "/$CONTAINER_BASE_NAME/ "' { print $1 }')
    if [[ "$targets" != "" ]]; then
      ssh ohara@$node kubectl delete pod $targets --grace-period=0
    else
      echo "no idle k8s containers on $node"
    fi
  fi
  
  # remove the containers created by docker
  targets=$(ssh ohara@$node docker ps -a -q --filter name=$CONTAINER_BASE_NAME)
  if [[ "$targets" != "" ]]; then
    ssh ohara@$node docker rm -f $targets
  else
    echo "no idle docker containers on $node"
  fi
  
  # remove docker images
  targets=$(ssh ohara@$node docker images -q --filter reference=oharastream/*:$TAG_BASE_NAME)
  if [[ "$targets" != "" ]]; then
    ssh ohara@$node docker rmi -f $targets
  else
    echo "no temporary images on $node"
  fi

done

IT_TASKS=(
  "collieIT"
  "clientIT"
  "connectorIT"
  "streamIT"
  "otherIT"
)

if [[ "$PULL_REQUEST_ACTION" == "opened" ]] || [[ "$PULL_REQUEST_ACTION" == "synchronize" ]]; then
  PULL_REQUEST_ID=$PULL_REQUEST_ID_OPENED
elif [[ "$PULL_REQUEST_ACTION" == "created" ]]; then
  PULL_REQUEST_ID=$PULL_REQUEST_ID_CREATED
else
  exit 2
fi

# get sha AND branch
SHA=$(curl -u $GITHUB_USER:$GITHUB_KEY -s https://api.github.com/repos/oharastream/ohara/pulls/$PULL_REQUEST_ID | jq -r '.head.sha')

if [[ -f "$CHECKS_FOLDER/check_build" ]]; then
  DESCRIPTION=$(cat $CHECKS_FOLDER/check_build)
  
  if [[ "$DESCRIPTION" != "good" ]]; then
    # bad build
    curl -s --header "Content-Type: application/json" \
      -u $GITHUB_USER:$GITHUB_KEY \
      -X POST "https://api.github.com/repos/oharastream/ohara/statuses/$SHA" \
      -d "{\"state\": \"failure\",\"target_url\": \"$BUILD_URL\",\"description\": \"$DESCRIPTION! Triggered by $EVENT_SENDER at $(date "+%Y/%m/%d %H:%M:%S")\",\"context\": \"build\"}" \
      >> $CHECKS_FOLDER/update_status_of_build.log 2>&1
  else
    
    # the file exists if we failed to build temporary image
    if [[ -f "$WORKSPACE/build_image" ]]; then
     message=$(cat $WORKSPACE/build_image)
     curl -s --header "Content-Type: application/json" \
      -u $GITHUB_USER:$GITHUB_KEY \
      -X POST "https://api.github.com/repos/oharastream/ohara/statuses/$SHA" \
      -d "{\"state\": \"failure\",\"target_url\": \"$BUILD_URL\",\"description\": \"$message Triggered by $EVENT_SENDER at $(date "+%Y/%m/%d %H:%M:%S")\",\"context\": \"build images\"}" \
      >> $CHECKS_FOLDER/update_status_of_build_images.log 2>&1

    fi
 
    if [ ! -d "$WORKSPACE/target_tests" ]; then
      echo "==========================[jenkins only test for the build so it does not need to update module status]=========================="
      exit 0
    fi
    TARGET_TESTS=(
      "testing-util"
      "common"
      "metrics"
      "client"
      "kafka"
      "configurator"
      # the following names do not exist in our source code actually...It is just used to parse the folder
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
      TARGET_TESTS+=("$task")
    done

    for targetTest in "${TARGET_TESTS[@]}"
    do

      if [[ -f "$WORKSPACE/${targetTest}_exist" ]]; then
        STATE="error"
        if [[ -f "$WORKSPACE/${targetTest}_state" ]]; then
          STATE=$(cat $WORKSPACE/${targetTest}_state)
        fi


        DESCRIPTION="aborted"

        # pup command for parser html file, please refer: https://github.com/ericchiang/pup by jack
        if [[ "$targetTest" == "manager-ut" ]]; then
          coverageSummary="$WORKSPACE/ohara/ohara-manager/client/coverage/ut/lcov-report/index.html"
          if [[ -f $coverageSummary ]]; then
            strong=$(cat $coverageSummary | pup 'span[class="strong"] text{}' | head -1)
            quiet=$(cat $coverageSummary | pup 'span[class="quiet"] text{}' | head -1)
            fraction=$(cat $coverageSummary | pup 'span[class="fraction"] text{}' | head -1)
            DESCRIPTION="$quiet: $strong ( $fraction )"
          else
            DESCRIPTION="Not found the manager-ut module report"
          fi
        elif [[ "$targetTest" == "manager-api" ]]; then
          coverageSummary="$WORKSPACE/ohara/ohara-manager/client/coverage/api/coverage-summary.json"
          if [[ -f $coverageSummary ]]; then
            total=$(cat $coverageSummary | jq -r '.total.statements.total')
            covered=$(cat $coverageSummary | jq -r '.total.statements.covered')
            pct=$(cat $coverageSummary | jq -r '.total.statements.pct')
            DESCRIPTION="Statements: $pct% ( $covered/$total )"
          else
            DESCRIPTION="Not found the manager-api module report"
          fi
        elif [[ "$targetTest" == "manager-it" ]]; then
          coverageSummary="$WORKSPACE/ohara/ohara-manager/client/coverage/it/coverage-summary.json"
          if [[ -f $coverageSummary ]]; then
            total=$(cat $coverageSummary | jq -r '.total.statements.total')
            covered=$(cat $coverageSummary | jq -r '.total.statements.covered')
            pct=$(cat $coverageSummary | jq -r '.total.statements.pct')
            DESCRIPTION="Statements: $pct%  ($covered/$total )"
          else
            DESCRIPTION="Not found the manager-it module report"
          fi
        elif [[ "$targetTest" == "manager-e2e" ]]; then
          DESCRIPTION="we all don't understand the ohara Manager"
        elif [[ -f "$WORKSPACE/${targetTest}_elapsed" ]]; then
          DESCRIPTION=$(cat $WORKSPACE/${targetTest}_elapsed)
        fi  
        
        
        echo "==========================[attach result of $targetTest state:$STATE description:$DESCRIPTION]=========================="
        prefix="test"
        
        for task in ${IT_TASKS[@]}; do
          if [[ "$targetTest" == "$task" ]]; then
            prefix="it"
          fi
        done
        
        
        curl -s --header "Content-Type: application/json" \
          -u $GITHUB_USER:$GITHUB_KEY \
          -X POST "https://api.github.com/repos/oharastream/ohara/statuses/$SHA" \
          -d "{\"state\": \"$STATE\",\"target_url\": \"$BUILD_URL\",\"description\": \"$DESCRIPTION! Triggered by $EVENT_SENDER at $(date "+%Y/%m/%d %H:%M:%S")\",\"context\": \"$prefix/$targetTest\"}" \
          >> $CHECKS_FOLDER/update_status_of_tests.log 2>&1
      fi
    done
    totalCoverageSummary="$WORKSPACE/ohara/ohara-manager/client/coverage/coverage-summary.json"
    if [[ -f $totalCoverageSummary ]]; then
      total=$(cat $totalCoverageSummary | jq -r '.total.statements.total')
      covered=$(cat $totalCoverageSummary | jq -r '.total.statements.covered')
      pct=$(cat $totalCoverageSummary | jq -r '.total.statements.pct')
      statement="Statements: $pct% ( $covered/$total )"
      curl -s --header "Content-Type: application/json" \
        -u $GITHUB_USER:$GITHUB_KEY \
        -X POST "https://api.github.com/repos/oharastream/ohara/statuses/$SHA" \
        -d "{\"state\": \"success\",\"target_url\": \"$BUILD_URL\",\"description\": \"$statement! Triggered by $EVENT_SENDER at $(date "+%Y/%m/%d %H:%M:%S")\",\"context\": \"code/coverage\"}" >> $CHECKS_FOLDER/update_status_of_tests.log 2>&1
    
      if [[ -f "$WORKSPACE/ohara/ohara-manager/client/coverage/index.html" ]]; then
        curl -s --header "Content-Type: application/json" \
          -u $GITHUB_USER:$GITHUB_KEY \
          -X POST "https://api.github.com/repos/oharastream/ohara/issues/$PULL_REQUEST_ID/comments" \
          -d "{\"body\": \"Manager code coverge result: https://builds.is-land.com.tw/job/PreCommit-OHARA/$BUILD_NUMBER/artifact/ohara/ohara-manager/client/coverage/index.html\"}" \
          >> $CHECKS_FOLDER/manager_it_report.log 2>&1
      fi
    fi
  fi
else
  echo "=========================================[$CHECKS_FOLDER/check_build does not exist!!!]========================================="
fi

# make jenkins succeed
exit 0