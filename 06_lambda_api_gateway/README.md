# APIs with Lambda + API Gateway — fakecloud Edition

A from-scratch tutorial for redoing the NextWork "APIs with Lambda + API Gateway" project
against a local **fakecloud** instance instead of real AWS. No console — everything done via
CLI, including writing/deploying the Lambda code, since there's no in-browser code editor
here.

---

## ⚠️ Confirmed invoke URL pattern (found by testing, differs from older LocalStack style)

**fakecloud routes API Gateway requests by `Host` header, not by URL path.** The older
LocalStack-style path convention (`http://<ip>:4566/restapis/<api-id>/<stage>/_user_request_/<resource>`)
does **not** work on this fakecloud version — it returns `NotFoundException: No matching API
for path ...` even when the API, resource, method, and deployment are all genuinely correct.
This makes sense given fakecloud explicitly aims for real-AWS behavioral parity, and real AWS
(and modern LocalStack) route by subdomain/`Host` header, not URL path.

**The pattern that actually works** — fake the real-AWS `Host` header while hitting fakecloud's
real IP:port:

```bash
curl -H "Host: <api-id>.execute-api.us-east-1.amazonaws.com" \
  "http://$FAKECLOUD_IP:4566/<stage>/<resource>?<query-string>"
```

Example from this walkthrough:
```bash
curl -H "Host: $API_ID.execute-api.us-east-1.amazonaws.com" \
  "http://$FAKECLOUD_IP:4566/prod/users?userId=test123"
```

An equivalent alternative, using `curl --resolve` to fake full DNS resolution of a
`localhost`-style subdomain (matches LocalStack's own convention, also confirmed working):
```bash
curl --resolve "$API_ID.execute-api.localhost:4566:$FAKECLOUD_IP" \
  "http://$API_ID.execute-api.localhost:4566/prod/users?userId=test123"
```

Either form works — the `Host`-header version is simpler and doesn't need `--resolve`.

**Lambda-to-DynamoDB reachability.** Since fakecloud runs Lambda as a real Docker
   container, your function's own DynamoDB SDK client needs a way to reach fakecloud's API
   from *inside* that container — it won't automatically know to talk to
   `$FAKECLOUD_IP:4566` unless you tell it to. The `index.mjs` below includes an optional
   endpoint override via an environment variable for exactly this reason — set
   `DYNAMODB_ENDPOINT` when creating the function (see Step 1) and adjust if it doesn't
   resolve correctly from inside the container's network namespace.

---

## 0. Prerequisites

```bash
export FAKECLOUD_IP=<your-fakecloud-host-ip>
alias awsfca='aws --profile fakecloud-admin --endpoint-url http://$FAKECLOUD_IP:4566'
```

---

## 1. Create the Lambda function

### 1a. Write the function code

```bash
mkdir -p lambda-package && cd lambda-package
```

`index.mjs`:
```javascript
import { DynamoDBClient } from "@aws-sdk/client-dynamodb";
import { DynamoDBDocumentClient, GetCommand } from "@aws-sdk/lib-dynamodb";

// DYNAMODB_ENDPOINT lets this function talk back to fakecloud from inside its
// own container. Leave unset to fall back to normal AWS behavior.
const clientConfig = { region: process.env.AWS_REGION || "us-east-1" };
if (process.env.DYNAMODB_ENDPOINT) {
  clientConfig.endpoint = process.env.DYNAMODB_ENDPOINT;
}

const ddbClient = new DynamoDBClient(clientConfig);
const ddb = DynamoDBDocumentClient.from(ddbClient);

async function handler(event) {
    const userId = event.queryStringParameters?.userId;
    const params = {
        TableName: 'UserData',
        Key: { userId }
    };

    try {
        const command = new GetCommand(params);
        const { Item } = await ddb.send(command);
        if (Item) {
            return {
                statusCode: 200,
                body: JSON.stringify(Item),
                headers: { 'Content-Type': 'application/json' }
            };
        } else {
            return {
                statusCode: 404,
                body: JSON.stringify({ message: "No user data found" }),
                headers: { 'Content-Type': 'application/json' }
            };
        }
    } catch (err) {
        console.error("Unable to retrieve data:", err);
        return {
            statusCode: 500,
            body: JSON.stringify({ message: "Failed to retrieve user data" }),
            headers: { 'Content-Type': 'application/json' }
        };
    }
}

export { handler };
```

`package.json`:
```json
{
  "name": "retrieve-user-data",
  "type": "module",
  "dependencies": {
    "@aws-sdk/client-dynamodb": "^3.x",
    "@aws-sdk/lib-dynamodb": "^3.x"
  }
}
```

### 1b. Install dependencies and package

Real Lambda's Node 18+ runtime bundles AWS SDK v3, but fakecloud's Lambda containers may not
— bundle your own copy to be safe:
```bash
npm install
zip -r ../function.zip .
cd ..
```

### 1c. Create an execution role

Even though fakecloud doesn't enforce IAM authorization for Lambda calls, `create-function`
still requires a syntactically valid role ARN as a parameter:

```bash
cat > trust-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": { "Service": "lambda.amazonaws.com" },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

awsfca iam create-role \
  --role-name lambda-basic-execution \
  --assume-role-policy-document file://trust-policy.json \
  --query 'Role.Arn' --output text
```

Save the returned ARN:
```bash
export LAMBDA_ROLE_ARN=<arn-from-output>
```

(Skip attaching `AWSLambdaBasicExecutionRole` — it's an AWS-managed policy and may not exist
in fakecloud's local IAM store. Not required for the function to run in this environment.)

### 1d. Create the function

```bash
awsfca lambda create-function \
  --function-name RetrieveUserData \
  --runtime nodejs18.x \
  --role $LAMBDA_ROLE_ARN \
  --handler index.handler \
  --zip-file fileb://function.zip \
  --environment "Variables={DYNAMODB_ENDPOINT=http://$FAKECLOUD_IP:4566}"
```

Confirm it exists:
```bash
awsfca lambda get-function --function-name RetrieveUserData
```

### 1e. Sanity-check the function in isolation (before wiring up API Gateway)

```bash
awsfca lambda invoke \
  --function-name RetrieveUserData \
  --payload '{"queryStringParameters":{"userId":"test123"}}' \
  --cli-binary-format raw-in-base64-out \
  response.json

cat response.json
```

Expect a `404` body right now (`UserData` table doesn't exist yet — that's created in the
next project in this series) — but a clean `404` response, not a Lambda execution error,
confirms the function itself runs correctly and the SDK endpoint override is working.

---

## 2. Set up API Gateway

### 2a. Create the REST API

```bash
awsfca apigateway create-rest-api --name UserRequestAPI --query 'id' --output text
```
```bash
export API_ID=<id-from-output>
```

### 2b. Find the root resource

```bash
awsfca apigateway get-resources --rest-api-id $API_ID --query 'items[0].id' --output text
```
```bash
export ROOT_ID=<id-from-output>
```

---

## 3. Create the `/users` resource

```bash
awsfca apigateway create-resource \
  --rest-api-id $API_ID \
  --parent-id $ROOT_ID \
  --path-part users \
  --query 'id' --output text
```
```bash
export USERS_RESOURCE_ID=<id-from-output>
```

---

## 4. Create the GET method with Lambda proxy integration

```bash
awsfca apigateway put-method \
  --rest-api-id $API_ID \
  --resource-id $USERS_RESOURCE_ID \
  --http-method GET \
  --authorization-type NONE
```

Wire it to the Lambda function with `AWS_PROXY` integration type (this *is* what "Lambda
proxy integration" means under the hood — passes the full request through untransformed):

```bash
awsfca apigateway put-integration \
  --rest-api-id $API_ID \
  --resource-id $USERS_RESOURCE_ID \
  --http-method GET \
  --type AWS_PROXY \
  --integration-http-method POST \
  --uri arn:aws:apigateway:us-east-1:lambda:path/2015-03-31/functions/arn:aws:lambda:us-east-1:123456789012:function:RetrieveUserData/invocations
```

Give API Gateway permission to invoke the function:
```bash
awsfca lambda add-permission \
  --function-name RetrieveUserData \
  --statement-id apigateway-invoke \
  --action lambda:InvokeFunction \
  --principal apigateway.amazonaws.com \
  --source-arn "arn:aws:execute-api:us-east-1:123456789012:$API_ID/*/GET/users"
```

---

## 5. Deploy to the `prod` stage

```bash
awsfca apigateway create-deployment \
  --rest-api-id $API_ID \
  --stage-name prod
```

### Test it

Use the confirmed working pattern — `Host` header override, since fakecloud routes by
`Host`, not URL path (see the callout at the top of this doc):

```bash
curl -H "Host: $API_ID.execute-api.us-east-1.amazonaws.com" \
  "http://$FAKECLOUD_IP:4566/prod/users?userId=test123"
```

You should get back your Lambda's own error JSON body, something like
`{"message":"Failed to retrieve user data"}` — a `500`-style error, not a `404`, since the
`UserData` table doesn't exist yet at all (so `GetCommand` throws, landing in the function's
`catch` block), rather than existing-but-empty. Either way, this is the same expected
"error" checkpoint the real NextWork project describes at this stage — the `UserData` table
gets created in the next project in this series.

**If you get `{"__type":"NotFoundException","message":"No matching API for path ..."}`
instead** — that means you're hitting fakecloud with the old path-style URL
(`/restapis/<id>/<stage>/_user_request_/<resource>`) instead of using the `Host`-header
override above. Double-check every piece is actually correct before assuming it's a routing
bug — run through `get-rest-api`, `get-stages`, `get-resources`, `get-integration`, and
`lambda get-policy` for the affected API/resource/function; if those all check out but you
still get `NotFoundException`, it's almost certainly the URL pattern, not your setup.

---

## 6. Secret mission — API documentation in JSON

```bash
awsfca apigateway create-documentation-part \
  --rest-api-id $API_ID \
  --location type=API \
  --properties '{"description":"API for retrieving user data via a serverless Lambda-backed endpoint.","info":{"title":"UserRequestAPI"}}'
```

Add documentation for the `/users` GET method specifically:
```bash
awsfca apigateway create-documentation-part \
  --rest-api-id $API_ID \
  --location type=METHOD,path=/users,method=GET \
  --properties '{"description":"Retrieves user data by userId query parameter.","summary":"Get user data"}'
```

Publish a documentation version:
```bash
awsfca apigateway create-documentation-version \
  --rest-api-id $API_ID \
  --documentation-version v1 \
  --stage-name prod
```

Export the full API definition (includes your documentation) as OpenAPI/Swagger JSON:
```bash
awsfca apigateway get-export \
  --rest-api-id $API_ID \
  --stage-name prod \
  --export-type swagger \
  swagger-export.json

cat swagger-export.json
```

This JSON file is your "written documentation" deliverable for the secret mission —
genuinely more advanced than the console's documentation UI, since you're producing a real
OpenAPI-compatible spec that other tools (Postman, code generators, other API Gateway
imports) can consume directly.

---

## 7. Clean up

```bash
awsfca apigateway delete-rest-api --rest-api-id $API_ID
awsfca lambda delete-function --function-name RetrieveUserData
awsfca iam delete-role --role-name lambda-basic-execution
```

---

## Quick command reference

| Action | Command |
|---|---|
| Create Lambda function | `awsfca lambda create-function --function-name X --runtime nodejs18.x --role <arn> --handler index.handler --zip-file fileb://function.zip` |
| Invoke Lambda directly | `awsfca lambda invoke --function-name X --payload '{...}' --cli-binary-format raw-in-base64-out out.json` |
| Create REST API | `awsfca apigateway create-rest-api --name X` |
| Get root resource ID | `awsfca apigateway get-resources --rest-api-id <id>` |
| Create a resource/path | `awsfca apigateway create-resource --rest-api-id <id> --parent-id <root> --path-part <name>` |
| Create a method | `awsfca apigateway put-method --rest-api-id <id> --resource-id <r> --http-method GET --authorization-type NONE` |
| Wire method to Lambda | `awsfca apigateway put-integration --rest-api-id <id> --resource-id <r> --http-method GET --type AWS_PROXY --integration-http-method POST --uri <lambda-invoke-arn>` |
| Allow API Gateway to invoke | `awsfca lambda add-permission --function-name X --statement-id Y --action lambda:InvokeFunction --principal apigateway.amazonaws.com --source-arn <execute-api-arn>` |
| Deploy a stage | `awsfca apigateway create-deployment --rest-api-id <id> --stage-name prod` |
| Add API documentation | `awsfca apigateway create-documentation-part --rest-api-id <id> --location type=API --properties '{...}'` |
| Export as OpenAPI | `awsfca apigateway get-export --rest-api-id <id> --stage-name prod --export-type swagger out.json` |
| Delete API | `awsfca apigateway delete-rest-api --rest-api-id <id>` |
| Delete function | `awsfca lambda delete-function --function-name X` |

---

## Troubleshooting notes from this run-through

**Multi-line shell scripts silently dropping a step:** a missing trailing `\` at the end of a
line breaks the continuation — zsh treats everything before it as one complete command and
starts a *new* command on the next line. Symptom: a param-validation error on the first
command (missing an argument that was supposed to come from the next line) immediately
followed by `command not found: --whatever` for the orphaned flag. Fix: every line in a
multi-line command except the last needs the trailing `\`.

**Exported variables don't survive across separate script invocations.** Running
`./step2.sh` then `./step3.sh` as two separate script executions means each spawns its own
subshell — an `export` inside `step2.sh` dies with that subshell the moment it exits, so
`step3.sh` never sees it, even though it looks like it should. Symptoms: a variable expands
to empty, often with no obvious error pointing at the real cause. Fixes:
- `source step2.sh` (or `. step2.sh`) instead of `./step2.sh`, so it runs in your *current*
  shell rather than a subshell, or
- write the value to a file at the end of one script and read it back at the start of the
  next (`echo $VALUE > .some_var` / `export VALUE=$(cat .some_var)`), which survives
  regardless of how the scripts are invoked.

**A hardcoded/assumed value instead of capturing real command output** is a related trap —
e.g. `export LAMBDA_ROLE_ARN=arn:aws:iam::123456789012:role/lambda-basic-execution` assumes
what `create-role` returned rather than checking. If the earlier command actually failed
(malformed JSON in a policy file, for instance), the hardcoded guess still "succeeds" and
masks the real failure until much later, at a step that looks unrelated.

**Large zip uploads can silently hang / drop the connection on a flaky network** — same
category of issue as the Terraform provider download problem from an earlier project, just
in the upload direction this time. Symptom: `create-function` hangs indefinitely or dies with
`ConnectionClosedError` / `TimeoutError`, with fakecloud's own server-side logs showing no
record the request ever arrived (confirmed via `docker logs fakecloud`). Mitigation: avoid
bundling `node_modules` in the deployment zip if the runtime already provides the SDK
(smaller upload = less exposure), or retry on a better connection.

**fakecloud's API Gateway invoke routing is `Host`-header-based, not path-based** — see the
callout at the top of this document. This one cost the most debugging time because every
other signal (API exists, stage deployed, resource created, integration correct, Lambda
permission correct) checked out fine, and the actual issue was purely about which URL
convention to test against.

---

## What this project demonstrates (worth noting in your documentation)

- **Serverless logic tier** — no server to provision or patch; Lambda runs your code on
  demand, API Gateway handles the HTTP-facing side (routing, methods, stages).
- **Lambda proxy integration** — API Gateway passes the *entire* raw request through to
  Lambda untransformed, and your function is responsible for parsing it and shaping a
  properly-formed response (`statusCode`, `body`, `headers`) — the alternative
  (non-proxy integration) would have API Gateway doing request/response mapping itself,
  which is more configuration but less code.
- **Stages as deployment snapshots** — `prod` here is one stage; the same API definition
  could be deployed to `dev`/`test` stages independently, letting you iterate without
  touching what's live.
- **fakecloud's container-backed Lambda** — since Lambda genuinely executes your code in a
  real container rather than just returning canned responses, this is one of the more
  faithful fakecloud projects — the actual JS runs, actual errors surface, and the
  DynamoDB-endpoint override pattern used here is a real technique you'd also reach for in
  LocalStack-based testing, not just a fakecloud quirk.
