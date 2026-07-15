#!/bin/zsh
setopt aliases
source ~/.zshrc

# Add a new attribute in the item with id 1

awsfca dynamodb update-item --table-name ContentCatalog --key '{"Id": {"N": "1"}}' \
--update-expression "SET StudentsComplete = :val" \
--expression-attribute-values '{":val": {"S": "Nikko"}}'
