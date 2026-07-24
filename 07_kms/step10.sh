#!/bin/zsh
setopt aliases
source ~/.zshrc

figlet cleanup
awsfca dynamodb delete-table --table-name nextwork-kms-table

awsfca kms schedule-key-deletion --key-id $KMS_KEY_ID --pending-window-in-days 7

echo "Run this command with the variable ACCESS_KEY_ID set to delete the access key access as well"

awsfca iam detach-user-policy --user-name nextwork-kms-user --policy-arn arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess
awsfca iam delete-access-key --user-name nextwork-kms-user --access-key-id $ACCESS_KEY_ID
awsfca iam delete-user --user-name nextwork-kms-user
