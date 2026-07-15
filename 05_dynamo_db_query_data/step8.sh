#!/bin/zsh
setopt aliases
source ~/.zshrc

awsfca dynamodb delete-table --table-name ContentCatalog
awsfca dynamodb delete-table --table-name Forum
awsfca dynamodb delete-table --table-name Post
awsfca dynamodb delete-table --table-name Comment

awsfca dynamodb list-tables
