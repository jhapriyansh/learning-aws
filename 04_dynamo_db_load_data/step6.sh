#!/bin/zsh
setopt aliases
source ~/.zshrc

# Get item with id 1

awsfca dynamodb get-item \
    --table-name ContentCatalog \
    --key '{"Id": {"N": "1"}}'
