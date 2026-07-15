#!/bin/zsh
setopt aliases
source ~/.zshrc

awsfca dynamodb put-item \
    --table-name NextWorkStudents \
    --item '{"StudentName": {"S": "Nikko"}, "ProjectsComplete": {"N": "4"}}'
