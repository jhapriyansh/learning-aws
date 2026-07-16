#!/bin/zsh
setopt aliases
source ~/.zshrc

figlet testing 
echo
curl -H "Host: $API_ID.execute-api.us-east-1.amazonaws.com" \
  "http://$FAKECLOUD_IP:4566/prod/users?userId=test123"
echo
echo
figlet done
