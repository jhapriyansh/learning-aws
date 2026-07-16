#!/bin/zsh
setopt aliases
source ~/.zshrc


figlet creating-lambda-function

echo lambda arn
echo $LAMBDA_ROLE_ARN
echo endpoint
echo $FAKECLOUD_IP

awsfca lambda create-function \
--function-name RetrieveUserData \
--runtime nodejs18.x \
--role $LAMBDA_ROLE_ARN \
--handler index.handler \
--zip-file fileb://function.zip \
--environment "Variables={DYNAMODB_ENDPOINT=http://$FAKECLOUD_IP:4566}"

figlet created 
