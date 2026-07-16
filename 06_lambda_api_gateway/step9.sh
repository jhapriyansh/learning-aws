#!/bin/zsh
setopt aliases
source ~/.zshrc

figlet create get method
echo
awsfca apigateway put-method \
--rest-api-id $API_ID \
--resource-id $USERS_RESOURCE_ID \
--http-method GET \
--authorization-type NONE
echo
figlet done
