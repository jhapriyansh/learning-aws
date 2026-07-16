#!/bin/zsh
setopt aliases
source ~/.zshrc

figlet invoking lambda

awsfca lambda invoke \
--function-name RetrieveUserData \
--payload '{"queryStringParameters":{"userId": "test123"}}' \
--cli-binary-format raw-in-base64-out \
response.json

cat response.json | jq

figlet test done
