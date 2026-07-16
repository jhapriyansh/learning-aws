#!/bin/zsh
setopt aliases
source ~/.zshrc

figlet create resource /users
echo
awsfca apigateway create-resource \
  --rest-api-id $API_ID \
  --parent-id $ROOT_ID \
  --path-part users \
  --query 'id' --output text
echo
echo "Copy the id and run ths command below with that id"
echo "export USERS_RESOURCE_ID=<id>"
