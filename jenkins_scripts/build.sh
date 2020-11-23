#!/bin/bash

# ALL tempoaray containers should use this as prefix of name
# this prefix helps us to remove correct containers later
CONTAINER_BASE_NAME="$PREFIX_OF_BUILD$BUILD_NUMBER"

AVAILABLE_BRANCHES=("0.12" "0.11")
IT_TASKS=(
  "collieIT"
  "clientIT"
  "connectorIT"
  "streamIT"
  "otherIT"
)

# build the folder for current job
CHECKS_FOLDER=$WORKSPACE/checks
mkdir -p $CHECKS_FOLDER

echo "abort!" > $CHECKS_FOLDER/check_build

if [[ "$PULL_REQUEST_ACTION" == "opened" ]] || [[ "$PULL_REQUEST_ACTION" == "synchronize" ]]; then
  PULL_REQUEST_ID=$PULL_REQUEST_ID_OPENED
elif [[ "$PULL_REQUEST_ACTION" == "created" ]]; then
  PULL_REQUEST_ID=$PULL_REQUEST_ID_CREATED
else
  echo "failed to PR id from https://api.github.com/repos/oharastream/ohara/pulls/$PULL_REQUEST_ID" > $CHECKS_FOLDER/check_build
  exit 2
fi

# get sha AND branch
SHA=$(curl -u $GITHUB_USER:$GITHUB_KEY -s https://api.github.com/repos/oharastream/ohara/pulls/$PULL_REQUEST_ID | jq -r '.head.sha')
if [[ "$SHA" == "" ]] || [[ "$SHA" == "null" ]]; then
  echo "failed to fetch SHA from https://api.github.com/repos/oharastream/ohara/pulls/$PULL_REQUEST_ID" > $CHECKS_FOLDER/check_build
  exit 2
fi

ASSIGNEE=$(curl -u $GITHUB_USER:$GITHUB_KEY -s https://api.github.com/repos/oharastream/ohara/pulls/$PULL_REQUEST_ID | jq -r '.head.repo.owner.login')
if [[ "$ASSIGNEE" == "" ]] || [[ "$ASSIGNEE" == "null" ]]; then
  echo "failed to fetch repo owner from https://api.github.com/repos/oharastream/ohara/pulls/$PULL_REQUEST_ID" > $CHECKS_FOLDER/check_build
  exit 2
fi

PR_BASE_BRANCH=$(curl -u $GITHUB_USER:$GITHUB_KEY -s https://api.github.com/repos/oharastream/ohara/pulls/$PULL_REQUEST_ID | jq -r '.base.ref')
if [[ "$PR_BASE_BRANCH" == "" ]] || [[ "$PR_BASE_BRANCH" == "null" ]]; then
  echo "failed to fetch base branch from https://api.github.com/repos/oharastream/ohara/pulls/$PULL_REQUEST_ID" > $CHECKS_FOLDER/check_build
  exit 2
fi

PR_HEAD_BRANCH=$(curl -u $GITHUB_USER:$GITHUB_KEY -s https://api.github.com/repos/oharastream/ohara/pulls/$PULL_REQUEST_ID | jq -r '.head.ref')
if [[ "$PR_HEAD_BRANCH" == "" ]] || [[ "$PR_HEAD_BRANCH" == "null" ]]; then
  echo "failed to fetch head branch from https://api.github.com/repos/oharastream/ohara/pulls/$PULL_REQUEST_ID" > $CHECKS_FOLDER/check_build
  exit 2
fi

echo "=========================================[PR:$PULL_REQUEST_ID PR_BASE_BRANCH:$PR_BASE_BRANCH PR_HEAD_BRANCH:$ASSIGNEE:$PR_HEAD_BRANCH]========================================="
curl -s --header "Content-Type: application/json" \
  -u $GITHUB_USER:$GITHUB_KEY \
  -X POST "https://api.github.com/repos/oharastream/ohara/statuses/$SHA" \
  -d "{\"state\": \"pending\",\"target_url\": \"$BUILD_URL\",\"description\": \"Triggered by $EVENT_SENDER at $(date "+%Y/%m/%d %H:%M:%S")\",\"context\": \"build\"}" > $CHECKS_FOLDER/update_status_of_build.log 2>&1

echo "=========================================[sync deps and $CI_IMAGE]========================================="
docker pull oharastream/ohara:deps
docker pull $CI_IMAGE

echo "PULL_REQUEST_ID: $PULL_REQUEST_ID"
echo "BUILD_NUMBER: $BUILD_NUMBER"

docker run \
  --name $CONTAINER_BASE_NAME \
  $CI_IMAGE \
  /bin/bash -c \
  "cd /ohara \
    && git fetch origin pull/$PULL_REQUEST_ID/head:$BUILD_NUMBER \
    && git checkout $BUILD_NUMBER \
    && ./gradlew properties | grep \"version:\" | cut -d' ' -f 2 > /version" \
  > $CHECKS_FOLDER/version.log 2>&1
docker cp $CONTAINER_BASE_NAME:/version $WORKSPACE/
docker rm -f $CONTAINER_BASE_NAME

OHARA_VERSION=""
if [[ -f "$WORKSPACE/version" ]]; then
  OHARA_VERSION=$(cat $WORKSPACE/version)
fi

if [[ "$OHARA_VERSION" == "" ]]; then
  echo "failed to get version of ohara" > $CHECKS_FOLDER/check_build
  exit 2
else
  isAvailable="false"
  for branch in "${AVAILABLE_BRANCHES[@]}"; do
    if [[ "$OHARA_VERSION" == "$branch"* ]]; then
      isAvailable="true"
    fi
  done
  if [[ "$isAvailable" == "false" ]]; then
    echo "the version:$OHARA_VERSION is unsupported now!!!" > $CHECKS_FOLDER/check_build
    exit 2
  fi
fi

echo "=========================================[PR:$PULL_REQUEST_ID is associated to version:$OHARA_VERSION]========================================="

LABEL_VERSION="v${OHARA_VERSION%"-SNAPSHOT"}"
echo "=========================================[attach version label:$LABEL_VERSION]========================================="
curl -s --header "Content-Type: application/json" \
  -u $GITHUB_USER:$GITHUB_KEY \
  -X POST "https://api.github.com/repos/oharastream/ohara/issues/$PULL_REQUEST_ID/labels" \
  -d "{\"labels\":[\"$LABEL_VERSION\"]}" >> $CHECKS_FOLDER/update_label_of_build.log 2>&1

echo "=========================================[check the build of PR:$PULL_REQUEST_ID]========================================="

docker run \
  --rm \
  $CI_IMAGE \
  /bin/bash -c \
  "cd /ohara \
    && git config --global user.name jenkins \
    && git config --global user.email jenkins@example.com \
    && git pull \
    && git checkout $PR_BASE_BRANCH \
    && git fetch origin pull/$PULL_REQUEST_ID/head:$BUILD_NUMBER \
    && echo \"ohara qa fetch succeed\" \
    && git checkout $BUILD_NUMBER \
    && git pull --rebase origin $PR_BASE_BRANCH \
    && echo \"ohara qa rebase succeed\" \
    && ./gradlew licenseTest \
    && echo \"ohara qa licenseTest succeed\" \
    && ./gradlew spotlessCheck \
    && echo \"ohara qa spotlessCheck succeed\" \
    && ./gradlew clean build -x test \
    && echo \"ohara qa build succeed\"" \
  > $CHECKS_FOLDER/build.log 2>&1

if ! grep -q "ohara qa fetch succeed" "$CHECKS_FOLDER/build.log"; then
  echo "fetch error!!!" > $CHECKS_FOLDER/check_build
  exit 2
fi

if ! grep -q "ohara qa rebase succeed" "$CHECKS_FOLDER/build.log"; then
  echo "rebase conflict!!!" > $CHECKS_FOLDER/check_build
  exit 2
fi

if ! grep -q "ohara qa licenseTest succeed" "$CHECKS_FOLDER/build.log"; then
  echo "license error!" > $CHECKS_FOLDER/check_build
  exit 2
fi

if ! grep -q "ohara qa spotlessCheck succeed" "$CHECKS_FOLDER/build.log"; then
  echo "checkstyle error!" > $CHECKS_FOLDER/check_build
  exit 2
fi

if ! grep -q "ohara qa build succeed" "$CHECKS_FOLDER/build.log"; then
  echo "build error!" > $CHECKS_FOLDER/check_build
  exit 2
fi

echo "good" > $CHECKS_FOLDER/check_build

# update status of build
curl -s --header "Content-Type: application/json" \
  -u $GITHUB_USER:$GITHUB_KEY \
  -X POST "https://api.github.com/repos/oharastream/ohara/statuses/$SHA" \
  -d "{\"state\": \"success\",\"target_url\": \"$BUILD_URL\",\"description\": \"Triggered by $EVENT_SENDER at $(date "+%Y/%m/%d %H:%M:%S")\",\"context\": \"build\"}" \
  >> $CHECKS_FOLDER/update_status_of_build.log 2>&1

# break the following progress
if [[ "$RETRY" == "retry build" ]]; then
  exit 0
fi

echo "=========================================[check the javadoc of PR:$PULL_REQUEST_ID]========================================="
# check the javadoc
docker run \
  --rm \
  $CI_IMAGE \
  /bin/bash -c \
  "cd /ohara \
    && git config --global user.name jenkins \
    && git config --global user.email jenkins@example.com \
    && git pull \
    && git checkout $PR_BASE_BRANCH \
    && git fetch origin pull/$PULL_REQUEST_ID/head:$BUILD_NUMBER \
    && echo \"ohara qa fetch succeed\" \
    && git checkout $BUILD_NUMBER \
    && git pull --rebase origin $PR_BASE_BRANCH \
    && ./gradlew javadoc" \
  > $CHECKS_FOLDER/javadoc.log 2>&1


if [[ "$?" != "0" ]]; then
  JAVADOC_STATE="failure"
else
  JAVADOC_STATE="success"
fi

JAVADOC_WARNINGS_COUNT=$(cat "$CHECKS_FOLDER/javadoc.log" | grep "warning:" | wc -l)
if [[ "$JAVADOC_WARNINGS_COUNT" != "0" ]]; then
  JAVADOC_STATE="failure"
fi

curl -s --header "Content-Type: application/json" \
  -u $GITHUB_USER:$GITHUB_KEY \
  -X POST "https://api.github.com/repos/oharastream/ohara/statuses/$SHA" \
  -d "{\"state\": \"$JAVADOC_STATE\",\"target_url\": \"$BUILD_URL/artifact/checks/javadoc.log\",\"description\": \"$JAVADOC_WARNINGS_COUNT warnings. Triggered by $EVENT_SENDER at $(date "+%Y/%m/%d %H:%M:%S")\",\"context\": \"javadoc\"}" \
  > $CHECKS_FOLDER/update_status_of_javadoc.log 2>&1

echo "=========================================[check the scaladoc of PR:$PULL_REQUEST_ID]========================================="
# check the scaladoc
docker run \
  --rm \
  $CI_IMAGE \
  /bin/bash -c \
  "cd /ohara \
    && git config --global user.name jenkins \
    && git config --global user.email jenkins@example.com \
    && git pull \
    && git checkout $PR_BASE_BRANCH \
    && git fetch origin pull/$PULL_REQUEST_ID/head:$BUILD_NUMBER \
    && echo \"ohara qa fetch succeed\" \
    && git checkout $BUILD_NUMBER \
    && git pull --rebase origin $PR_BASE_BRANCH \
    && ./gradlew scaladoc" \
  > $CHECKS_FOLDER/scaladoc.log 2>&1
  
SCALADOC_STATE="success"
SCALADOC_WARNINGS_COUNT=$(cat "$CHECKS_FOLDER/scaladoc.log" | grep ": warning:" | wc -l)
if [[ "$SCALADOC_WARNINGS_COUNT" != "0" ]]; then
  SCALADOC_STATE="failure"
fi

curl -s --header "Content-Type: application/json" \
  -u $GITHUB_USER:$GITHUB_KEY \
  -X POST "https://api.github.com/repos/oharastream/ohara/statuses/$SHA" \
  -d "{\"state\": \"$SCALADOC_STATE\",\"target_url\": \"$BUILD_URL/artifact/checks/scaladoc.log\",\"description\": \"$SCALADOC_WARNINGS_COUNT warnings. Triggered by $EVENT_SENDER at $(date "+%Y/%m/%d %H:%M:%S")\",\"context\": \"scaladoc\"}" \
  > $CHECKS_FOLDER/update_status_of_scaladoc.log 2>&1


echo "=========================================[attach status for build]========================================="

docker run \
  --name $CONTAINER_BASE_NAME \
  $CI_IMAGE \
  /bin/bash -c \
  "git config --global user.name jenkins \
    && git config --global user.email jenkins@example.com \
    && git pull \
    && git checkout $PR_BASE_BRANCH \
    && git pull \
    && ./gradlew properties | grep version: | cut -d '' -f 2 > /${PR_BASE_BRANCH}_version \
    && git fetch origin pull/$PULL_REQUEST_ID/head:$PULL_REQUEST_ID \
    && git checkout $PULL_REQUEST_ID \
    && git pull --rebase origin $PR_BASE_BRANCH \
    && ./gradlew properties | grep version: | cut -d '' -f 2 > /${PULL_REQUEST_ID}_version \
    && git diff --name-only origin/$PR_BASE_BRANCH..$PULL_REQUEST_ID | tee /changed_files.log" \
  > $CHECKS_FOLDER/changes.log 2>&1

docker cp $CONTAINER_BASE_NAME:/changed_files.log $CHECKS_FOLDER/changed_files.log 2>&1
docker cp $CONTAINER_BASE_NAME:/${PULL_REQUEST_ID}_version $CHECKS_FOLDER/${PULL_REQUEST_ID}_version 2>&1
docker cp $CONTAINER_BASE_NAME:/${PR_BASE_BRANCH}_version $CHECKS_FOLDER/${PR_BASE_BRANCH}_version 2>&1
docker rm -f $CONTAINER_BASE_NAME

ALL_MODULES=(
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

CHANGED_MODULES=()
OTHERS_CODE_CHANGED="false"
UI_CODE_CHANGED="false"
BACKEND_CODE_CHANGED="false"
IT_CODE_CHANGED="false"
OHARA_VERSION_CHANGED="false"

PULL_REQUEST_ID_VERSION=$(cat $CHECKS_FOLDER/${PULL_REQUEST_ID}_version)
PR_BASE_BRANCH_VERSION=$(cat $CHECKS_FOLDER/${PR_BASE_BRANCH}_version)

if [[ "$PULL_REQUEST_ID_VERSION" != "$PR_BASE_BRANCH_VERSION" ]]; then
  echo "the version is changed from $PR_BASE_BRANCH_VERSION to $PULL_REQUEST_ID_VERSION so the following tests are skipped"
  # gradle.properties has a property which control the version of ohara
  # we rebuild the configurator image to make image up-to-date
  OHARA_VERSION_CHANGED="true"
fi


for file in $(cat $CHECKS_FOLDER/changed_files.log | tr " " "\n"); do
  matched="false"
  for MODULE in "${ALL_MODULES[@]}"
  do
    
    if [[ "$file" == "ohara-$MODULE"* ]]; then
      matched="true"
      duplicate="false"
      for EXISTENT_MODULE in "${CHANGED_MODULES[@]}"
      do
        if [[ "$EXISTENT_MODULE" == "$MODULE" ]]; then
          duplicate="true"
          break
        fi
      done
      
      if [[ "$duplicate" == "false" ]]; then
        if [[ "$file" == "ohara-manager"* ]]; then
          UI_CODE_CHANGED="true"
        elif [[ "$file" == "ohara-it"* ]]; then
          IT_CODE_CHANGED="true"
        else
          BACKEND_CODE_CHANGED="true"
        fi
        CHANGED_MODULES+=("$MODULE")
      fi
    fi
  done
  
  if [[ "$matched" == "false" ]]; then
    if [[ "$file" == "docker"* ]]; then
      OTHERS_CODE_CHANGED="true"
    else
      OTHERS_CODE_CHANGED="true"
    fi
  fi
done

TARGET_TESTS=()
if [[ "$RETRY" == "retry" ]]; then
  
  if [[ "$BACKEND_CODE_CHANGED" == "true" ]]; then
    # exclude manager-e2e, manager-ut, manager-it and it
    TARGET_TESTS=(
      "testing-util"
      "common"
      "metrics"
      "client"
      "kafka"
      "configurator"
      # we ought to test APIs compatibility
      "manager-api"
      "connector"
      "shabondi"
      "agent"
      "stream"
    )
    # add IT for backend changes by default
    for task in ${IT_TASKS[@]}; do
      TARGET_TESTS+=( "$task" )
    done
  fi
  
  if [[ "$IT_CODE_CHANGED" == "true" ]]; then
    
    for task in ${IT_TASKS[@]}; do
      TARGET_TESTS+=( "$task" )
    done
  fi
  
  if [[ "$UI_CODE_CHANGED" == "true" ]]; then
    # requested by UI developer: don't run IT by default
    TARGET_TESTS+=("manager-ut" "manager-api" "manager-it")
  fi
else
  target=$(echo $RETRY | cut -d' ' -f 2)
  if [[ "$target" == "manager" ]]; then
    TARGET_TESTS=( "manager-api" "manager-ut" "manager-e2e" "manager-it")
  elif [[ "$target" == "it" ]]; then
    for task in ${IT_TASKS[@]}; do
      TARGET_TESTS+=( "$task" )
    done
  else
    TARGET_TESTS=( "$target" )
  fi
fi

# skip tests if this PR is used to update the version
if [[ "$OHARA_VERSION_CHANGED" == "true" ]]; then
  TARGET_TESTS=()
  curl -s --header "Content-Type: application/json" \
    -u $GITHUB_USER:$GITHUB_KEY \
    -X POST "https://api.github.com/repos/oharastream/ohara/issues/$PULL_REQUEST_ID/comments" \
    -d "{\"body\": \"DON'T touch the gradle.properties if you are NOT release manager (no tests)\"}" \
    >> $CHECKS_FOLDER/say_version_changed.log 2>&1
fi

# remove all module labels
for MODULE in "${ALL_MODULES[@]}"
do
  curl -s -u $GITHUB_USER:$GITHUB_KEY \
    -X DELETE "https://api.github.com/repos/oharastream/ohara/issues/$PULL_REQUEST_ID/labels/$MODULE" >> $CHECKS_FOLDER/update_label_of_build.log 2>&1
done
for MODULE in "${CHANGED_MODULES[@]}"
do
  echo "=========================================[attach $MODULE label]========================================="
  curl -s --header "Content-Type: application/json" \
    -u $GITHUB_USER:$GITHUB_KEY \
    -X POST "https://api.github.com/repos/oharastream/ohara/issues/$PULL_REQUEST_ID/labels" \
    -d "{\"labels\":[\"$MODULE\"]}" >> $CHECKS_FOLDER/update_label_of_build.log 2>&1
done


# we have a label called "others"
if [[ "$OTHERS_CODE_CHANGED" == "true" ]]; then
  echo "=========================================[attach others label]========================================="
  curl -s --header "Content-Type: application/json" \
    -u $GITHUB_USER:$GITHUB_KEY \
    -X POST "https://api.github.com/repos/oharastream/ohara/issues/$PULL_REQUEST_ID/labels" \
    -d "{\"labels\":[\"others\"]}" >> $CHECKS_FOLDER/update_label_of_build.log 2>&1
else
  curl -s -u $GITHUB_USER:$GITHUB_KEY \
  -X DELETE "https://api.github.com/repos/oharastream/ohara/issues/$PULL_REQUEST_ID/labels/others" >> $CHECKS_FOLDER/update_label_of_build.log 2>&1
fi

for targetTest in "${TARGET_TESTS[@]}"
do
  echo "=========================================[update status of $targetTest test]========================================="
  # log the target tests. It wil be used later...
  mkdir -p $WORKSPACE/target_tests
  
  # just a dumb content
  echo "good" > $WORKSPACE/target_tests/$targetTest
  # set status of build
  prefix="test"
  for task in ${IT_TASKS[@]}; do
    if [[ "$targetTest" == "$task" ]]; then
      prefix="it"
    fi
  done
  curl -s --header "Content-Type: application/json" \
    -u $GITHUB_USER:$GITHUB_KEY \
    -X POST "https://api.github.com/repos/oharastream/ohara/statuses/$SHA" \
    -d "{\"state\": \"pending\",\"target_url\": \"$BUILD_URL\",\"description\": \"Triggered by $EVENT_SENDER at $(date "+%Y/%m/%d %H:%M:%S")\",\"context\": \"$prefix/$targetTest\"}" \
    >> $CHECKS_FOLDER/update_status_of_tests.log 2>&1

  echo "exist" > $WORKSPACE/${targetTest}_exist
done

NEED_IT_TESTS="false"
NEED_API_TESTS="false"
NEED_E2E_TESTS="false"
NEED_MANAGER_IT_TESTS="false"

for targetTest in "${TARGET_TESTS[@]}"; do

  for task in ${IT_TASKS[@]}; do
    if [[ "$targetTest" == "$task" ]]; then
      NEED_IT_TESTS="true"
    fi
  done
  
  if [[ "$targetTest" == "manager-api" ]]; then
    NEED_API_TESTS="true"
  fi
  
  if [[ "$targetTest" == "manager-e2e" ]]; then
    NEED_E2E_TESTS="true"
  fi
  
  if [[ "$targetTest" == "manaer-it" ]]; then
    NEED_MANAGER_IT_TESTS="true"
  fi
done

# those flags means that this PR needs some docker images to complete QA
if [[ "$NEED_IT_TESTS" == "true" ]] || [[ "$NEED_API_TESTS" == "true" ]] || [[ "$NEED_E2E_TESTS" == "true" ]] || [[ "$NEED_MANAGER_IT_TESTS" == "true" ]]; then

  # used to calculate the elapsed time. it is a internal variable
  SECONDS=0
  # create tmp folder to store tmp images
  TMP_IMAGE_FOLDER=$WORKSPACE/tmp_images
  mkdir -p $TMP_IMAGE_FOLDER
  
  curl -s --header "Content-Type: application/json" \
    -u $GITHUB_USER:$GITHUB_KEY \
    -X POST "https://api.github.com/repos/oharastream/ohara/statuses/$SHA" \
    -d "{\"state\": \"pending\",\"target_url\": \"$BUILD_URL\",\"description\": \"Triggered by $EVENT_SENDER at $(date "+%Y/%m/%d %H:%M:%S")\",\"context\": \"build images\"}" \
    >> $CHECKS_FOLDER/update_status_of_build_images.log 2>&1

  echo "exist" > $WORKSPACE/build_image

  REPO="https://github.com/$ASSIGNEE/ohara"
  
  # clone the repo via docker so we don't require slave to install git
  docker run \
    --name $CONTAINER_BASE_NAME \
    $CI_IMAGE \
    /bin/bash -c \
    "cd /ohara \
      && git config --global user.name jenkins \
      && git config --global user.email jenkins@example.com \
      && git pull \
      && git checkout $PR_BASE_BRANCH \
      && git fetch origin pull/$PULL_REQUEST_ID/head:$BUILD_NUMBER \
      && git checkout $BUILD_NUMBER \
      && git pull --rebase origin $PR_BASE_BRANCH" \
    > $CHECKS_FOLDER/clone_other_ohara_repo.log 2>&1
    
  if [[ "$?" != "0" ]]; then
    echo "failed to rebase repo" > $WORKSPACE/build_image
    exit 2
  fi
  docker cp $CONTAINER_BASE_NAME:/ohara/docker $WORKSPACE/
  docker rm -f $CONTAINER_BASE_NAME
  
  ALL_SERVICES=("configurator" "manager" "zookeeper" "broker" "worker" "stream" "shabondi")
  
  # we only rebuild configurator image since there is no IT tests.
  CONFIGURATOR_ONLY="fase"
  if [[ "$NEED_IT_TESTS" == "false" ]] && [[ "$NEED_E2E_TESTS" == "false" ]] && [[ "$NEED_MANAGER_IT_TESTS" == "false" ]]; then
    CONFIGURATOR_ONLY="true"
    ALL_SERVICES=("configurator")
  fi
  
  # Remove IT Cluster 1 (ohara-jenkins-it-10, ohara-jenkins-it-11, ohara-jenkins-it-12) by jack
  # let randomITCluster=${BUILD_NUMBER}%2
  # if [ $randomITCluster -eq 0 ];
  # then
  #   it_nodes=("ohara-jenkins-it-00" "ohara-jenkins-it-01" "ohara-jenkins-it-02")
  # else
  #   it_nodes=("ohara-jenkins-it-10" "ohara-jenkins-it-11" "ohara-jenkins-it-12")
  # fi
  it_nodes=("ohara-jenkins-it-00" "ohara-jenkins-it-01" "ohara-jenkins-it-02")
  
  
  # the backend code is changed so we are going to rebuild all images based on PR
  if [[ "$BACKEND_CODE_CHANGED" == "true" ]]; then
    beforeBuild="git config user.name jenkins \
    && git config user.email jenkins@email.com \
    && git remote add upstream $OFFICIAL_REPO \
    && git pull --rebase upstream $PR_BASE_BRANCH"
    
    tag=$CONTAINER_BASE_NAME
    # docker-compose replace the variable by env ...
    export TAG=$tag
      
    if [[ "$CONFIGURATOR_ONLY" == "true" ]]; then

      echo "=========================================[create Ohara Configurator image based on $REPO:$SHA]========================================="
        
      docker-compose \
        -f $WORKSPACE/docker/build.yml build \
        --build-arg BEFORE_BUILD="$beforeBuild" \
        --build-arg REPO=$REPO \
        --build-arg BRANCH=$PR_HEAD_BRANCH \
        --build-arg OHARA_VERSION=$tag \
        --build-arg STAGE=$tag \
        --force-rm \
        configurator > $CHECKS_FOLDER/build_image.log 2>&1
      
    else

      echo "=========================================[create all Ohara images based on $REPO:$SHA]========================================="
      
      docker-compose \
        -f $WORKSPACE/docker/build.yml build \
        --build-arg BEFORE_BUILD="$beforeBuild" \
        --build-arg REPO=$REPO \
        --build-arg BRANCH=$PR_HEAD_BRANCH \
        --build-arg OHARA_VERSION=$tag \
        --build-arg STAGE=$tag \
        --force-rm \
        --parallel \
        configurator \
        manager \
        zookeeper \
        broker \
        worker \
        stream \
        shabondi > $CHECKS_FOLDER/build_image.log 2>&1
    fi
 
    if [[ "$?" != "0" ]]; then
      docker rmi -f $(docker images -q --filter label=stage=$tag)
      echo "failed to build image via docker-compose" > $WORKSPACE/build_image
      exit 2
    fi
    
    docker rmi -f $(docker images -q --filter label=stage=$tag)

    echo "=========================================[save docker images to local files]========================================="

    # sync images to IT nodes
    for service in "${ALL_SERVICES[@]}"; do
      if [[ "$service" == "worker" ]]; then
        tmp_image="oharastream/connect-worker:$tag"
      else
        tmp_image="oharastream/$service:$tag"
      fi

      image_file="${service}.${BUILD_NUMBER}.tar"
      docker save $tmp_image -o $TMP_IMAGE_FOLDER/$image_file
      if [[ ! -f "$TMP_IMAGE_FOLDER/$image_file" ]]; then
        echo "failed to build $service image" > $WORKSPACE/build_image
        exit 2
      fi
      
      # tmp image of configurator is useful in testing APIs so we can't remove it :)
      if [[ "$service" != "configurator" ]]; then
        docker rmi -f $tmp_image
      fi
    done

    for service in "${ALL_SERVICES[@]}"; do
      image_file="${service}.${BUILD_NUMBER}.tar"
      for node in "${it_nodes[@]}"; do
        echo "=========================================[copy $service images to $node]========================================="
        scp $TMP_IMAGE_FOLDER/$image_file ohara@$node:/home/ohara/
        echo "=========================================[$node is loading $service images]========================================="
        ssh ohara@$node "docker load < /home/ohara/$image_file"
        echo "=========================================[$node cleans up $service images]========================================="
        ssh ohara@$node "rm -f /home/ohara/$image_file"
        echo "=========================================[$node is pulling centos:7]========================================="
        ssh ohara@$node "docker pull centos:7"
      done
    done
  
    echo $tag > $WORKSPACE/tmp_images_version

  else 
    # the backend code is NOT changed so we just pull the images  
  
    # pull the required images
    
    echo "=========================================[pull configurator image from $OHARA_VERSION]========================================="
      
    docker pull oharastream/configurator:$OHARA_VERSION
    
    # make other nodes to pull images
    for node in "${it_nodes[@]}"; do
      
      if [[ "$CONFIGURATOR_ONLY" == "true" ]]; then
      
        echo "=========================================[$node is pulling oharastream/configurator:$OHARA_VERSION]========================================="
        
        ssh $node "docker pull oharastream/configurator:$OHARA_VERSION"
        
      else
      
        service_names=(
          "configurator"
          "stream"
          "zookeeper"
          "broker"
          "connect-worker"
          "shabondi"
        )
        
        for service_name in "${service_names[@]}"; do
      
          echo "=========================================[$node is pulling oharastream/$service_name:$OHARA_VERSION]========================================="
        
          ssh $node "docker pull oharastream/$service_name:$OHARA_VERSION"
        
        done
      
      fi
      
    done
    
    echo "$OHARA_VERSION" > $WORKSPACE/tmp_images_version
  
  fi
  
  # update status of building tmporary images
  curl -s --header "Content-Type: application/json" \
    -u $GITHUB_USER:$GITHUB_KEY \
    -X POST "https://api.github.com/repos/oharastream/ohara/statuses/$SHA" \
    -d "{\"state\": \"success\",\"target_url\": \"$BUILD_URL\",\"description\": \"elapsed:${SECONDS}s! Triggered by $EVENT_SENDER at $(date "+%Y/%m/%d %H:%M:%S")\",\"context\": \"build images\"}" \
    >> $CHECKS_FOLDER/update_status_of_build_images.log 2>&1

  rm -f $WORKSPACE/build_image
  
  rm -rf $WORKSPACE/ohara

else
  
  echo "=========================================[skip to build temporary images]========================================="
  
fi

