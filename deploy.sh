#!/bin/bash

# usage: ./deploy.sh master

NOW=`date +%s`

BRANCH=$1
SHA1=`echo -n $NOW | openssl dgst -sha1 |awk '{print $NF}'`

[[ -z "$BRANCH" ]] && { echo "must pass a branch param" ; exit 1; }

# Main variables to modify for your account
AWS_ACCOUNT_ID='8214-2118-2219'
REGION='eu-west-2'
CLUSTER='test-app'
FAMILY='test-app'
DOCKER_IMAGE='test-app'
TASK='test-app'
SERVICE='app-service'
ECR_URI="${AWS_ACCOUNT_ID//-/}.dkr.ecr.${REGION}.amazonaws.com"

echo ${ECR_URI}

VERSION=$BRANCH-$SHA1
ZIP=$VERSION.zip

aws configure set default.region $REGION

# Authenticate against our Docker registry
eval $(aws ecr get-login --no-include-email)

# Build and push the image
docker build -t $DOCKER_IMAGE:$VERSION .
docker tag $DOCKER_IMAGE:$VERSION $ECR_URI/$DOCKER_IMAGE:$VERSION
docker push $ECR_URI/$DOCKER_IMAGE:$VERSION

# Create task for docker deploy
task_template='[
  {
    "name": "%s",
    "image": "%s.dkr.ecr.us-east-1.amazonaws.com/%s:%s",
    "essential": true,
    "memoryReservation": 1000,
    "portMappings": [
      {
        "containerPort": 3000,
        "hostPort": 80
      }
    ],
    "environment" : [
        { "name" : "NODE_ENV", "value" : "production" }
    ]
  }
]'

task_def=$(printf "$task_template" $TASK $AWS_ACCOUNT_ID $TASK $SHA1)

# Register task definition
json=$(aws ecs register-task-definition --container-definitions "$task_def" --family "$FAMILY")

# Grab revision # using regular bash and grep
revision=$(echo "$json" | grep -o '"revision": [0-9]*' | grep -Eo '[0-9]+')

# Deploy revision
aws ecs update-service --cluster "$CLUSTER" --service "$SERVICE" --task-definition "$TASK":"$revision"
