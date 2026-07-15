#!/bin/zsh
setopt aliases
source ~/.zshrc

figlet getting item from table

awsfca dynamodb get-item --table-name ContentCatalog --key '{"Id": {"N": "203"}}'
