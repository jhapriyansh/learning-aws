#!/bin/zsh
setopt aliases
source ~/.zshrc

figlet json api docs
echo
awsfca apigateway create-documentation-part \
  --rest-api-id $API_ID \
  --location type=API \
  --properties '{"description":"API for retrieving user data via a serverless Lambda-backed endpoint.","info":{"title":"UserRequestAPI"}}'
echo
echo
echo docs for /users in GET
echo
awsfca apigateway create-documentation-part \
  --rest-api-id $API_ID \
  --location type=METHOD,path=/users,method=GET \
  --properties '{"description":"Retrieves user data by userId query parameter.","summary":"Get user data"}'
echo
echo
echo publish docs version
echo
awsfca apigateway create-documentation-version \
  --rest-api-id $API_ID \
  --documentation-version v1 \
  --stage-name prod
echo
echo
echo export api definition
echo
awsfca apigateway get-export \
  --rest-api-id $API_ID \
  --stage-name prod \
  --export-type swagger \
  swagger-export.json

cat swagger-export.json | jq
echo
echo
figlet done
