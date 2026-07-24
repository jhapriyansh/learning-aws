#!/bin/zsh
setopt aliases
source ~/.zshrc

figlet check get item
echo "in real aws this will be denied, however fakecloud's kms isn't iam enforced."

awsfc-kmstest dynamodb get-item \
  --table-name nextwork-kms-table \
  --key '{"id": {"S": "item1"}}' \
  --no-cli-pager
