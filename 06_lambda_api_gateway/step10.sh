#!/bin/zsh
setopt aliases
source ~/.zshrc

figlet connect lambda to the endpoint
echo
awsfca apigateway put-integration \
  --rest-api-id $API_ID \
  --resource-id $USERS_RESOURCE_ID \
  --http-method GET \
  --type AWS_PROXY \
  --integration-http-method POST \
  --uri arn:aws:apigateway:us-east-1:lambda:path/2015-03-31/functions/arn:aws:lambda:us-east-1:123456789012:function:RetrieveUserData/invocations
echo
echo
figlet done

