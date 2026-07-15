# Query Data with DynamoDB — fakecloud Edition

A from-scratch tutorial for redoing the NextWork "Query Data with DynamoDB" project against a
local **fakecloud** instance instead of real AWS. Picks up right where "Load Data into
DynamoDB" left off — same four tables, same dataset.

---

## 0. Prerequisites

```bash
export FAKECLOUD_IP=<your-fakecloud-host-ip>
alias awsfca='aws --profile fakecloud-admin --endpoint-url http://$FAKECLOUD_IP:4566'
```

If you already have `ContentCatalog`, `Forum`, `Post`, and `Comment` tables loaded from the
previous project, confirm they're still there (remember: DynamoDB isn't a confirmed
*persisted* fakecloud service, so if your container restarted, you'll need to redo table
creation + `batch-write-item` loading from the previous tutorial first):

```bash
awsfca dynamodb list-tables
```

If empty, go back to `dynamodb-load-data-fakecloud-tutorial.md` and redo steps 1–5 before
continuing here.

---

## 1. Query basics — console steps translated to CLI

The NextWork project has you click through the console's "Scan or query items" panel first,
then repeats the same queries via CLI. Since fakecloud has no console, we go straight to CLI
— it's the same underlying operation either way (`Query`/`GetItem`), just typed instead of
clicked.

### Get a single item by partition key (ContentCatalog, Id = 201)

```bash
awsfca dynamodb get-item \
    --table-name ContentCatalog \
    --key '{"Id":{"N":"201"}}'
```

### Query the Comment table by partition key + sort key range

The project's console exercise: find comments on the post
`"I have a question/Just Complete Project #7 Dependencies and CodeArtifacts"`, posted on or
after `2024-09-01`.

CLI equivalent using `query` (not `get-item`, since we want a *range* of sort key values,
not one exact item):

```bash
awsfca dynamodb query \
    --table-name Comment \
    --key-condition-expression "Id = :pk AND CommentDateTime >= :sk" \
    --expression-attribute-values '{
        ":pk": {"S": "I have a question/Just Complete Project #7 Dependencies and CodeArtifacts"},
        ":sk": {"S": "2024-09-01"}
    }'
```

### Why you can't query by a non-key attribute (e.g. `PostedBy`)

Try this and expect it to fail:
```bash
awsfca dynamodb query \
    --table-name Comment \
    --key-condition-expression "PostedBy = :user" \
    --expression-attribute-values '{":user": {"S": "User Abdulrahman"}}'
```
This errors because `Query` **must** use the table's key schema (partition key, optionally
+ sort key) — `PostedBy` is a regular attribute, not a key. This is the exact lesson the
NextWork project is making: DynamoDB requires you to plan your access patterns (data
modeling) *before* loading data, since you can't efficiently query by arbitrary attributes
after the fact — unlike SQL, where `WHERE PostedBy = 'X'` just works on any column.

**If you actually need to search by a non-key attribute**, the (much less efficient)
workaround is `scan` with a filter:
```bash
awsfca dynamodb scan \
    --table-name Comment \
    --filter-expression "PostedBy = :user" \
    --expression-attribute-values '{":user": {"S": "User Abdulrahman"}}'
```
`scan` reads the *entire table* and filters client-side (or server-side but post-read), so
it's far more expensive than `query` and doesn't scale — worth explicitly noting in your
documentation as the "expensive fallback," not a real substitute for good data modeling.

---

## 2. Query with extra options: consistency, projection, capacity reporting

```bash
# This one intentionally returns nothing — Id 101 doesn't exist in the dataset
awsfca dynamodb get-item \
    --table-name ContentCatalog \
    --key '{"Id":{"N":"101"}}' \
    --consistent-read \
    --projection-expression "Title, ContentType, Services" \
    --return-consumed-capacity TOTAL
```

Now with a real ID and default (eventually consistent) reads:
```bash
awsfca dynamodb get-item \
    --table-name ContentCatalog \
    --key '{"Id":{"N":"202"}}' \
    --projection-expression "Title, ContentType, Services" \
    --return-consumed-capacity TOTAL
```

**What each flag does:**
- `--consistent-read` — forces a strongly consistent read (guaranteed latest write). Costs
  2x the read capacity of the default eventually-consistent read.
- `--projection-expression` — only return specific attributes instead of the whole item,
  saving bandwidth/parsing on both ends.
- `--return-consumed-capacity TOTAL` — reports how many capacity units the request actually
  used, worth comparing between the consistent and eventually-consistent versions of the
  same query to see the 2x difference directly in the `ConsumedCapacity.CapacityUnits` field
  of the response.

---

## 3. Transactions — updating two tables atomically

This is the project's centerpiece: adding a new `Comment` **and** incrementing the related
`Forum`'s comment count, as a single atomic operation — either both succeed or neither does.

```bash
awsfca dynamodb transact-write-items --client-request-token TRANSACTION1 --transact-items '[
    {
        "Put": {
            "TableName" : "Comment",
            "Item" : {
                "Id" : {"S": "Events/Do a Project Together - NextWork Study Session"},
                "CommentDateTime" : {"S": "2024-9-27T17:47:30Z"},
                "Comment" : {"S": "Excited to attend!"},
                "PostedBy" : {"S": "User Connor"}
            }
        }
    },
    {
        "Update": {
            "TableName" : "Forum",
            "Key" : {"Name" : {"S": "Events"}},
            "UpdateExpression": "ADD Comments :inc",
            "ExpressionAttributeValues" : { ":inc": {"N" : "1"} }
        }
    }
]'
```

**Why this needs to be a transaction, not two separate calls:** if you ran the `Put` and the
`Update` as two independent `dynamodb put-item`/`update-item` calls, there's a window where
the comment exists but the forum's count hasn't updated yet (or vice versa, if the second
call fails) — leaving your data inconsistent. `transact-write-items` guarantees all-or-nothing:
if either operation would fail, *neither* one applies.

**Verify the transaction worked:**
```bash
awsfca dynamodb get-item \
    --table-name Forum \
    --key '{"Name" : {"S": "Events"}}'
```
Check that `Comments` incremented by exactly 1 from whatever it was before.

Also confirm the new comment landed:
```bash
awsfca dynamodb get-item \
    --table-name Comment \
    --key '{"Id": {"S": "Events/Do a Project Together - NextWork Study Session"}, "CommentDateTime": {"S": "2024-9-27T17:47:30Z"}}'
```

> **Note:** `--client-request-token` makes the transaction idempotent — if you accidentally
> re-run the exact same command with the same token, DynamoDB recognizes it as a retry of the
> same transaction rather than applying it twice. Use a different token value if you
> deliberately want to run a *different* transaction.

---

## 4. Clean up

```bash
awsfca dynamodb delete-table --table-name Comment
awsfca dynamodb delete-table --table-name Forum
awsfca dynamodb delete-table --table-name ContentCatalog
awsfca dynamodb delete-table --table-name Post
```

Confirm:
```bash
awsfca dynamodb list-tables
```

> The NextWork project's terminal sometimes drops into a text-editor/pager mode after a
> delete command in real CloudShell (shows a `:` prompt) — type `:q` and press Enter to
> escape it. This is a `less`/pager artifact, same category of gotcha as the `--no-cli-pager`
> issue from earlier projects; if your local terminal does something similar, `:q<Enter>` or
> `q` alone usually gets you out.

---

## Quick command reference

| Action | Command |
|---|---|
| Get single item by key | `awsfca dynamodb get-item --table-name X --key '{...}'` |
| Query by partition (+sort) key | `awsfca dynamodb query --table-name X --key-condition-expression "..." --expression-attribute-values '{...}'` |
| Scan with filter (non-key attribute) | `awsfca dynamodb scan --table-name X --filter-expression "..." --expression-attribute-values '{...}'` |
| Strongly consistent read | add `--consistent-read` |
| Limit returned attributes | add `--projection-expression "Attr1, Attr2"` |
| See capacity used | add `--return-consumed-capacity TOTAL` |
| Atomic multi-table write | `awsfca dynamodb transact-write-items --client-request-token X --transact-items '[...]'` |
| Delete table | `awsfca dynamodb delete-table --table-name X` |

---

## What this project demonstrates (worth noting in your documentation)

- **`Query` vs `Scan`** — `Query` is fast and cheap but only works against key attributes;
  `Scan` works against any attribute but reads the whole table, making it slow and expensive
  at scale. This is the core trade-off DynamoDB forces you to confront that SQL databases
  hide from you.
- **Data modeling matters upfront** — you must know your access patterns (what you'll query
  by) *before* designing your table's key schema, since you can't cheaply query by arbitrary
  attributes after the fact.
- **Eventually consistent vs strongly consistent reads** — a real cost/performance trade-off,
  not just a toggle; eventually-consistent reads cost half as much and are the sensible
  default for most use cases.
- **Transactions guarantee cross-table consistency** — something the AWS Console literally
  cannot do (no transaction UI exists there), making this one of the clearest "CLI is
  strictly more powerful than console" moments in the whole NextWork series.
- **fakecloud coverage:** DynamoDB (including `Query`, `Scan`, and `TransactWriteItems`) is
  one of fakecloud's well-covered services, so this project should run end-to-end without
  the kind of enforcement gaps hit in the earlier EC2/IAM project.
