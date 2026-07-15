#!/bin/zsh
setopt aliases
source ~/.zshrc

awsfca dynamodb create-table \
    --table-name NextWorkStudents \
    --attribute-definitions AttributeName=StudentName,AttributeType=S \
    --key-schema AttributeName=StudentName,KeyType=HASH \
    --provisioned-throughput ReadCapacityUnits=1,WriteCapacityUnits=1 \
    --query "TableDescription.TableStatus"

awsfca dynamodb wait table-exists --table-name NextWorkStudents
