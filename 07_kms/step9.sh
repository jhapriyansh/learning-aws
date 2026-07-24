#!/bin/zsh
setopt aliases
source ~/.zshrc

figlet test again with permissions
awsfca iam simulate-principal-policy \
  --policy-source-arn arn:aws:iam::123456789012:user/nextwork-kms-user \
  --action-names kms:Decrypt \
  --resource-arns arn:aws:kms:us-east-1:123456789012:key/$KMS_KEY_ID \
  --output table

