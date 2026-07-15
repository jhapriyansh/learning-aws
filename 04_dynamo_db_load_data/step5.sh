#!/bin/zsh
setopt aliases
source ~/.zshrc

awsfca dynamodb batch-write-item --request-items file://nextworksampledata/ContentCatalog.json
awsfca dynamodb batch-write-item --request-items file://nextworksampledata/Forum.json
awsfca dynamodb batch-write-item --request-items file://nextworksampledata/Post.json
awsfca dynamodb batch-write-item --request-items file://nextworksampledata/Comment.json
