#!/bin/zsh
setopt aliases
source ~/.zshrc

figlet setting up api gateway

echo
echo
echo "id"
awsfca apigateway create-rest-api \
--name UserRequestAPI \
--query 'id' \
--output text

echo run this command and paste the output id
echo "export API_ID=<id>"
