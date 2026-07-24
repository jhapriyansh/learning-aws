#!/bin/zsh
setopt aliases
source ~/.zshrc

figlet creating key in kms
echo
awsfca kms create-key --description "nextwork-kms-key" --key-usage ENCRYPT_DECRYPT --key-spec SYMMETRIC_DEFAULT --query 'KeyMetaData.KeyId' --output text
echo
echo "Now copy the id and run this command"
echo "export KMS_KEY_ID=<id-copied-above>"

