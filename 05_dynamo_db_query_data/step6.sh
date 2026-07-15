#!/bin/zsh
setopt aliases
source ~/.zshrc

figlet transaction

awsfca dynamodb transact-write-items --client-request-token TRANSACTION1 --transact-items '[
	{
		"Put": {
			"TableName": "Comment",
			"Item": {
					"Id": {"S": "Events/Do a Project Together - NextWork Study Session"},
					"CommentDateTime": {"S": "2024-9-27T17:47:30Z"},
					"Comment": {"S": "Excited to attend"},
					"PostedBy": {"S": "User Connor"}
			}
		}
	},
	{
		"Update": {
				"TableName": "Forum",
				"Key": {"Name": {"S": "Events"}},
				"UpdateExpression": "ADD Comments :inc",
				"ExpressionAttributeValues": {":inc": {"N": "1"}}
		}
	}
]'
