#!/bin/zsh
setopt aliases
source ~/.zshrc

figlet create test user
figlet attach test policy
figlet create access key
awsfca iam create-user --user-name nextwork-kms-user

awsfca iam attach-user-policy \
  --user-name nextwork-kms-user \
  --policy-arn arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess

echo "run aws configure --profile nextwork-kms-test-user in another terminal and paste the keys from here"

awsfca iam create-access-key --user-name nextwork-kms-user
echo
echo

