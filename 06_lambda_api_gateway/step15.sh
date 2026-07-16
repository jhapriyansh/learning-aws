#!/bin/zsh
setopt aliases
source ~/.zshrc

figlet cleanup

rm function.zip swagger-export.json response.json
awsfca apigateway delete-rest-api --rest-api-id $API_ID
awsfca lambda delete-function --function-name RetrieveUserData
awsfca iam delete-role --role-name lambda-basic-execution
echo
figlet done
