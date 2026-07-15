#!/bin/zsh
setopt aliases
source ~/.zshrc

figlet Query with additional info

awsfca dynamodb get-item \
--table-name ContentCatalog \
--key '{"Id": {"N": "202"}}' \
--consistent-read \
--projection-expression "Title,ContentType,Services" \
--return-consumed-capacity TOTAL
