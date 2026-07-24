#!/bin/zsh
setopt aliases
source ~/.zshrc

figlet creating a table
awsfca dynamodb create-table \
  --table-name nextwork-kms-table \
  --attribute-definitions AttributeName=id,AttributeType=S \
  --key-schema AttributeName=id,KeyType=HASH \
  --provisioned-throughput ReadCapacityUnits=1,WriteCapacityUnits=1 \
  --sse-specification "Enabled=true,SSEType=KMS,KMSMasterKeyId=$KMS_KEY_ID"
echo
echo
figlet check table
echo
awsfca dynamodb wait table-exists --table-name nextwork-kms-table
echo
echo
figlet check kms setting
awsfca dynamodb describe-table --table-name nextwork-kms-table --query 'Table.SSEDescription'
echo
echo
figlet put data
awsfca dynamodb put-item \
  --table-name nextwork-kms-table \
  --item '{"id": {"S": "item1"}, "secret": {"S": "this is sensitive data"}}'
echo
echo
figlet get data
awsfca dynamodb get-item \
  --table-name nextwork-kms-table \
  --key '{"id": {"S": "item1"}}'

