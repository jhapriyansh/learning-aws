#!/bin/zsh
setopt aliases
source ~/.zshrc

figlet give permission to apigateway to invoke the lambda function
echo
awsfca lambda add-permission \
  --function-name RetrieveUserData \
  --statement-id apigateway-invoke \
  --action lambda:InvokeFunction \
  --principal apigateway.amazonaws.com \
  --source-arn "arn:aws:execute-api:us-east-1:123456789012:$API_ID/*/GET/users"
echo
echo
figlet done

