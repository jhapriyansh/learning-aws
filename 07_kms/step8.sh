#!/bin/zsh
setopt aliases
source ~/.zshrc

figlet give test user the permissions
awsfca kms put-key-policy \
  --key-id $KMS_KEY_ID \
  --policy-name default \
  --policy file://kms-key-policy-updated.json
