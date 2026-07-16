#!/bin/zsh
setopt aliases
source ~/.zshrc

figlet applying policy 
lolcat "trust-policy.json"

awsfca iam create-role \
--role-name lambda-basic-execution \
--assume-role-policy-document file://trust-policy.json \
--query 'Role.Arn'

figlet applied

export LAMBDA_ROLE_ARN=arn:aws:iam::123456789012:role/lambda-basic-execution
