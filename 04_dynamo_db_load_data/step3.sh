#!/bin/zsh
setopt aliases
source ~/.zshrc

# Create 4 tables.

# ContentCatalog

awsfca dynamodb create-table \
--table-name ContentCatalog \
--attribute-definitions AttributeName=Id,AttributeType=N \
--key-schema AttributeName=Id,KeyType=HASH \
--provisioned-throughput ReadCapacityUnits=1,WriteCapacityUnits=1 \
--query "TableDescription.TableStatus"

# Forum
awsfca dynamodb create-table \
--table-name Forum \
--attribute-definitions AttributeName=Name,AttributeType=S \
--key-schema AttributeName=Name,KeyType=HASH \
--provisioned-throughput ReadCapacityUnits=1,WriteCapacityUnits=1 \
--query "TableDescription.TableStatus"

# Post
awsfca dynamodb create-table \
--table-name Post \
--attribute-definitions AttributeName=ForumName,AttributeType=S AttributeName=Subject,AttributeType=S \
--key-schema AttributeName=ForumName,KeyType=HASH AttributeName=Subject,KeyType=RANGE \
--provisioned-throughput ReadCapacityUnits=1,WriteCapacityUnits=1 \
--query "TableDescription.TableStatus"

# Comment
awsfca dynamodb create-table \
--table-name Comment \
--attribute-definitions AttributeName=Id,AttributeType=S AttributeName=CommentDateTime,AttributeType=S \
--key-schema AttributeName=Id,KeyType=HASH AttributeName=CommentDateTime,KeyType=RANGE \
--provisioned-throughput ReadCapacityUnits=1,WriteCapacityUnits=1 \
--query "TableDescription.TableStatus"

# Wait for tables to exist
awsfca dynamodb wait table-exists --table-name ContentCatalog
awsfca dynamodb wait table-exists --table-name Forum
awsfca dynamodb wait table-exists --table-name Post
awsfca dynamodb wait table-exists --table-name Comment
