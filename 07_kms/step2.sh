#!/bin/zsh
setopt aliases
source ~/.zshrc

figlet giving key an alias
echo
awsfca kms create-alias --alias-name alias/nextwork-kms-key --target-key-id $KMS_KEY_ID
echo
echo
figlet confirming
awsfca kms describe-key --key-id alias/nextwork-kms-key

