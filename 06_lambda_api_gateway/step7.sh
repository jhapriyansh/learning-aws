#!/bin/zsh
setopt aliases
source ~/.zshrc

figlet find root resource
echo
echo "API ID"
echo $API_ID
echo
echo "id"
awsfca apigateway get-resources --rest-api-id $API_ID --query 'items[0].id' --output text
echo
echo "Copy the id and run ths command below with that id"
echo "export ROOT_ID=<id>"

