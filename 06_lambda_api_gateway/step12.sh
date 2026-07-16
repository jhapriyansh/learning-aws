#!/bin/zsh
setopt aliases
source ~/.zshrc

figlet deploy to prod stage
echo
awsfca apigateway create-deployment \
  --rest-api-id $API_ID \
  --stage-name prod
echo
echo
figlet done
