#!/bin/zsh
setopt aliases
source ~/.zshrc

figlet attaching policy document
awsfca kms put-key-policy --key-id $KMS_KEY_ID --policy-name default --policy file://kms-key-policy.json
