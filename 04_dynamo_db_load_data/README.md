# Load Data into DynamoDB — fakecloud Edition

A from-scratch tutorial for redoing the NextWork "Load Data into DynamoDB" project against a
local **fakecloud** instance instead of real AWS. No CloudShell needed — your Mac's terminal
with `awsfca` plays that role instead.

---

## 0. Prerequisites

```bash
export FAKECLOUD_IP=<your-fakecloud-host-ip>
alias awsfca='aws --profile fakecloud-admin --endpoint-url http://$FAKECLOUD_IP:4566'
```

Confirm connectivity:
```bash
awsfca dynamodb list-tables
```

> **Note on persistence:** DynamoDB was not among the confirmed persisted services (only
> S3 and a handful of others were confirmed) — assume table data is wiped on any fakecloud
> restart unless you've verified otherwise with `--storage-mode persistent` configured.

---

## 1. Create your first table: `NextWorkStudents`

Real AWS console equivalent, done via CLI instead:

```bash
awsfca dynamodb create-table \
    --table-name NextWorkStudents \
    --attribute-definitions AttributeName=StudentName,AttributeType=S \
    --key-schema AttributeName=StudentName,KeyType=HASH \
    --provisioned-throughput ReadCapacityUnits=1,WriteCapacityUnits=1 \
    --query "TableDescription.TableStatus"
```

Wait for it to be ready:
```bash
awsfca dynamodb wait table-exists --table-name NextWorkStudents
```

---

## 2. Add an item (Nikko) via CLI instead of the console

The NextWork project has you do this through the AWS Management Console UI. Since fakecloud
has no console, the CLI equivalent is `put-item`:

```bash
awsfca dynamodb put-item \
    --table-name NextWorkStudents \
    --item '{"StudentName": {"S": "Nikko"}, "ProjectsComplete": {"N": "4"}}'
```

Confirm it's there:
```bash
awsfca dynamodb scan --table-name NextWorkStudents
```

You should see `Nikko` with `ProjectsComplete: 4` — matching what the RCU-consumption banner
in the real console would have confirmed.

---

## 3. Create the four bulk-data tables

These map directly from the NextWork CloudShell script — same commands, just via `awsfca`:

```bash
awsfca dynamodb create-table \
    --table-name ContentCatalog \
    --attribute-definitions AttributeName=Id,AttributeType=N \
    --key-schema AttributeName=Id,KeyType=HASH \
    --provisioned-throughput ReadCapacityUnits=1,WriteCapacityUnits=1 \
    --query "TableDescription.TableStatus"

awsfca dynamodb create-table \
    --table-name Forum \
    --attribute-definitions AttributeName=Name,AttributeType=S \
    --key-schema AttributeName=Name,KeyType=HASH \
    --provisioned-throughput ReadCapacityUnits=1,WriteCapacityUnits=1 \
    --query "TableDescription.TableStatus"

awsfca dynamodb create-table \
    --table-name Post \
    --attribute-definitions \
        AttributeName=ForumName,AttributeType=S \
        AttributeName=Subject,AttributeType=S \
    --key-schema \
        AttributeName=ForumName,KeyType=HASH \
        AttributeName=Subject,KeyType=RANGE \
    --provisioned-throughput ReadCapacityUnits=1,WriteCapacityUnits=1 \
    --query "TableDescription.TableStatus"

awsfca dynamodb create-table \
    --table-name Comment \
    --attribute-definitions \
        AttributeName=Id,AttributeType=S \
        AttributeName=CommentDateTime,AttributeType=S \
    --key-schema \
        AttributeName=Id,KeyType=HASH \
        AttributeName=CommentDateTime,KeyType=RANGE \
    --provisioned-throughput ReadCapacityUnits=1,WriteCapacityUnits=1 \
    --query "TableDescription.TableStatus"
```

Confirm all four exist:
```bash
awsfca dynamodb wait table-exists --table-name ContentCatalog
awsfca dynamodb wait table-exists --table-name Forum
awsfca dynamodb wait table-exists --table-name Post
awsfca dynamodb wait table-exists --table-name Comment

awsfca dynamodb list-tables
```

**Table shapes at a glance:**

| Table | Partition key | Sort key |
|---|---|---|
| ContentCatalog | `Id` (Number) | — |
| Forum | `Name` (String) | — |
| Post | `ForumName` (String) | `Subject` (String) |
| Comment | `Id` (String) | `CommentDateTime` (String) |

---

## 4. Download the sample dataset

This step doesn't touch fakecloud at all — it's a plain internet download, so run it
directly on your Mac (or wherever you're running `awsfca` from):

```bash
curl -O https://storage.googleapis.com/nextwork_course_resources/courses/aws/AWS%20Project%20People%20projects/Project%3A%20Query%20Data%20with%20DynamoDB/nextworksampledata.zip

unzip nextworksampledata.zip
cd nextworksampledata
ls
```

You should see `ContentCatalog.json`, `Forum.json`, `Post.json`, `Comment.json`.

Peek inside one to understand the format:
```bash
cat Forum.json
```

Each file wraps its records in a structure keyed by table name, with `PutRequest` blocks per
item — this is the exact shape `batch-write-item` expects.

---

## 5. Bulk-load the data

```bash
awsfca dynamodb batch-write-item --request-items file://ContentCatalog.json
awsfca dynamodb batch-write-item --request-items file://Forum.json
awsfca dynamodb batch-write-item --request-items file://Post.json
awsfca dynamodb batch-write-item --request-items file://Comment.json
```

Each should return an empty `UnprocessedItems: {}` — that's your success signal, same as the
real project.

**If you get unprocessed items:** re-run the same `batch-write-item` command again — it's
idempotent per-item and will retry whatever didn't land the first time. If it persists,
open the file and check the JSON is well-formed (a single bad record can cause partial
batch failures):
```bash
cat ContentCatalog.json | python3 -m json.tool > /dev/null && echo "valid JSON" || echo "malformed JSON"
```

---

## 6. Explore and edit the loaded data

View everything in a table:
```bash
awsfca dynamodb scan --table-name ContentCatalog --output table --no-cli-pager
```

Look at one specific item (swap in an actual `Id` from your data, e.g. `1`):
```bash
awsfca dynamodb get-item \
    --table-name ContentCatalog \
    --key '{"Id": {"N": "1"}}'
```

**Add a new attribute to just that one item** (mirrors the console step of adding
`StudentsComplete` to a single Project item):
```bash
awsfca dynamodb update-item \
    --table-name ContentCatalog \
    --key '{"Id": {"N": "1"}}' \
    --update-expression "SET StudentsComplete = :val" \
    --expression-attribute-values '{":val": {"S": "Nikko"}}'
```

Confirm the attribute exists on item `1` but not on another item (e.g. `203`, a Video):
```bash
awsfca dynamodb get-item --table-name ContentCatalog --key '{"Id": {"N": "1"}}'
awsfca dynamodb get-item --table-name ContentCatalog --key '{"Id": {"N": "203"}}'
```
The first should show `StudentsComplete`; the second shouldn't — exactly the flexible-schema
behavior the project is demonstrating, just proven via CLI instead of clicking through the
console.

---

## 7. Clean up

```bash
awsfca dynamodb delete-table --table-name Comment
awsfca dynamodb delete-table --table-name Forum
awsfca dynamodb delete-table --table-name ContentCatalog
awsfca dynamodb delete-table --table-name Post
awsfca dynamodb delete-table --table-name NextWorkStudents
```

Confirm they're gone:
```bash
awsfca dynamodb list-tables
```

---

## Quick command reference

| Action | Command |
|---|---|
| Create table (simple key) | `awsfca dynamodb create-table --table-name X --attribute-definitions AttributeName=K,AttributeType=S --key-schema AttributeName=K,KeyType=HASH --provisioned-throughput ReadCapacityUnits=1,WriteCapacityUnits=1` |
| Create table (partition + sort key) | add second `AttributeName=...,AttributeType=...` and `AttributeName=...,KeyType=RANGE` |
| Wait until table ready | `awsfca dynamodb wait table-exists --table-name X` |
| List tables | `awsfca dynamodb list-tables` |
| Add a single item | `awsfca dynamodb put-item --table-name X --item '{...}'` |
| Bulk load from file | `awsfca dynamodb batch-write-item --request-items file://X.json` |
| Scan whole table | `awsfca dynamodb scan --table-name X` |
| Get one item | `awsfca dynamodb get-item --table-name X --key '{...}'` |
| Update/add attribute | `awsfca dynamodb update-item --table-name X --key '{...}' --update-expression "SET Attr = :v" --expression-attribute-values '{":v": {...}}'` |
| Delete table | `awsfca dynamodb delete-table --table-name X` |

---

## What this project demonstrates (worth noting in your documentation)

- **DynamoDB's flexible schema** — items in the same table can have completely different
  sets of attributes (a Project item gets `StudentsComplete`, a Video item doesn't need it).
  This is impossible in a relational database without every row carrying a null/unused column.
- **Partition keys vs. partition+sort keys** — `ContentCatalog`/`Forum` use a single partition
  key; `Post`/`Comment` use a composite key (partition + sort) to allow multiple items sharing
  the same partition key but differing by the sort key (e.g. many `Post` items per `ForumName`,
  differentiated by `Subject`).
- **Bulk loading via `batch-write-item`** — far faster than the console's one-item-at-a-time
  UI, and this is genuinely how real data pipelines seed DynamoDB tables in practice.
- **fakecloud coverage:** DynamoDB is one of fakecloud's well-covered services (control plane
  and actual data operations both work), so this project should run end-to-end with no gaps
  like the EC2 IAM-enforcement issue hit in the earlier IAM project.
