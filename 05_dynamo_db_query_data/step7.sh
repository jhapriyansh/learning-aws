#!/bin/zsh
setopt aliases
source ~/.zshrc

figlet verification

awsfca dynamodb get-item --table-name Forum \
--key '{"Name": {"S": "Events"}}'

awsfca dynamodb get-item \
    --table-name Comment \
    --key '{"Id": {"S": "Events/Do a Project Together - NextWork Study Session"}, "CommentDateTime": {"S": "2024-9-27T17:47:30Z"}}'
