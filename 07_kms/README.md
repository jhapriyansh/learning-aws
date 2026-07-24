# Encrypt Data with AWS KMS — fakecloud Edition

A from-scratch tutorial for redoing the NextWork "Encrypt Data with AWS KMS" project against
a local **fakecloud** instance instead of real AWS. No console — KMS key creation, key
policies, DynamoDB encryption settings, and the access-denial test are all done via CLI.

---

## ⚠️ Read this first: KMS is not in fakecloud's enforced-IAM list

Recall from the earlier IAM/EC2 project: `--iam strict` enforcement in fakecloud currently
covers exactly **five services — IAM, STS, SQS, SNS, and S3**. **KMS is not one of them.**

This project's entire payoff (Step 5: the test user gets `AccessDenied` on `kms:Decrypt`
because their IAM policy doesn't grant KMS access) is fundamentally a **KMS authorization
check**. Based on the same pattern that broke the EC2 IAM project, expect this denial
**not to happen** on fakecloud — the test user will likely be able to decrypt and view the
data anyway, regardless of what the KMS key policy says.

**Recommended approach, learned from the EC2 project:**
1. Do steps 1–4 for real — genuinely useful CLI practice, and the control-plane side (key
   creation, key policies, table encryption config) works correctly.
2. For Step 5 (the actual access-denial proof), use the **IAM Policy Simulator** instead of
   a live API call — same workaround that saved the earlier IAM project's secret mission.
   `simulate-principal-policy` statically evaluates policy logic without executing the real
   action, so it's unaffected by whatever fakecloud does or doesn't enforce live.
3. Document both: the simulator result (proof your policy logic is correct) *and* whatever
   actually happens when you try the real `dynamodb get-item` call as the test user (useful
   "what I learned about tooling limits" material either way).

---

## 0. Prerequisites

```bash
export FAKECLOUD_IP=<your-fakecloud-host-ip>
alias awsfca='aws --profile fakecloud-admin --endpoint-url http://$FAKECLOUD_IP:4566'
```

---

## 1. Create a KMS key

```bash
awsfca kms create-key \
  --description "nextwork-kms-key" \
  --key-usage ENCRYPT_DECRYPT \
  --key-spec SYMMETRIC_DEFAULT \
  --query 'KeyMetadata.KeyId' --output text
```
```bash
export KMS_KEY_ID=<key-id-from-output>
```

Give it a friendly alias (the console does this automatically; CLI needs an explicit call):
```bash
awsfca kms create-alias \
  --alias-name alias/nextwork-kms-key \
  --target-key-id $KMS_KEY_ID
```

Confirm:
```bash
awsfca kms describe-key --key-id alias/nextwork-kms-key
```

### Set the key policy (admins + users)

This is what the console's "who's an administrator/user of this key" UI is actually doing
behind the scenes — writing a resource-based policy directly onto the key:

```bash
cat > kms-key-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Id": "nextwork-kms-key-policy",
  "Statement": [
    {
      "Sid": "EnableRootAndAdminAccess",
      "Effect": "Allow",
      "Principal": { "AWS": "arn:aws:iam::123456789012:root" },
      "Action": "kms:*",
      "Resource": "*"
    },
    {
      "Sid": "AllowAdminUse",
      "Effect": "Allow",
      "Principal": { "AWS": "arn:aws:iam::123456789012:user/<your-iam-admin-username>" },
      "Action": [
        "kms:Create*", "kms:Describe*", "kms:Enable*", "kms:List*",
        "kms:Put*", "kms:Update*", "kms:Revoke*", "kms:Disable*",
        "kms:Get*", "kms:Delete*", "kms:ScheduleKeyDeletion", "kms:CancelKeyDeletion"
      ],
      "Resource": "*"
    },
    {
      "Sid": "AllowAdminAsKeyUser",
      "Effect": "Allow",
      "Principal": { "AWS": "arn:aws:iam::123456789012:user/<your-iam-admin-username>" },
      "Action": [ "kms:Encrypt", "kms:Decrypt", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:DescribeKey" ],
      "Resource": "*"
    }
  ]
}
EOF

awsfca kms put-key-policy \
  --key-id $KMS_KEY_ID \
  --policy-name default \
  --policy file://kms-key-policy.json
```

---

## 2. Create and encrypt a DynamoDB table

```bash
awsfca dynamodb create-table \
  --table-name nextwork-kms-table \
  --attribute-definitions AttributeName=id,AttributeType=S \
  --key-schema AttributeName=id,KeyType=HASH \
  --provisioned-throughput ReadCapacityUnits=1,WriteCapacityUnits=1 \
  --sse-specification "Enabled=true,SSEType=KMS,KMSMasterKeyId=$KMS_KEY_ID"
```

The `--sse-specification` flag is the CLI equivalent of the console's "Stored in your
account, and owned and managed by you" option — `SSEType=KMS` plus an explicit
`KMSMasterKeyId` means this is a **customer managed key (CMK)**, not the AWS-owned or
AWS-managed defaults.

Wait for it to be active:
```bash
awsfca dynamodb wait table-exists --table-name nextwork-kms-table
```

Confirm the encryption settings stuck:
```bash
awsfca dynamodb describe-table --table-name nextwork-kms-table --query 'Table.SSEDescription'
```
Should show `Status: ENABLED`, `SSEType: KMS`, and your key's ARN.

---

## 3. Add and read data

```bash
awsfca dynamodb put-item \
  --table-name nextwork-kms-table \
  --item '{"id": {"S": "item1"}, "secret": {"S": "this is sensitive data"}}'
```

Read it back as the admin user (should work — transparent decryption in action):
```bash
awsfca dynamodb get-item \
  --table-name nextwork-kms-table \
  --key '{"id": {"S": "item1"}}'
```

You should see the item in plain, readable form — DynamoDB handled the decrypt behind the
scenes because your admin credentials have `kms:Decrypt` on this key.

---

## 4. Create the test user (DynamoDB access, no KMS access)

```bash
awsfca iam create-user --user-name nextwork-kms-user

awsfca iam attach-user-policy \
  --user-name nextwork-kms-user \
  --policy-arn arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess

awsfca iam create-access-key --user-name nextwork-kms-user
```

> If `AmazonDynamoDBFullAccess` isn't recognized (AWS-managed policies aren't guaranteed to
> exist in fakecloud's local IAM store), write an equivalent customer-managed policy instead:
> ```bash
> cat > dynamodb-full-access.json << 'EOF'
> {
>   "Version": "2012-10-17",
>   "Statement": [
>     { "Effect": "Allow", "Action": "dynamodb:*", "Resource": "*" }
>   ]
> }
> EOF
> awsfca iam create-policy --policy-name DynamoDBFullAccessCustom --policy-document file://dynamodb-full-access.json
> awsfca iam attach-user-policy --user-name nextwork-kms-user --policy-arn <arn-from-output>
> ```

Note: **this user's policy grants no KMS permissions at all** — that's the whole point.

Set up a profile for the test user:
```bash
aws configure --profile nextwork-kms-test-user
# paste in the AccessKeyId / SecretAccessKey from create-access-key

alias awsfc-kmstest='aws --profile nextwork-kms-test-user --endpoint-url http://$FAKECLOUD_IP:4566'
```

---

## 5. Validate encryption — the real test (and its fakecloud caveat)

### Try the live API call

```bash
awsfc-kmstest dynamodb get-item \
  --table-name nextwork-kms-table \
  --key '{"id": {"S": "item1"}}'
```

**On real AWS:** this fails with `AccessDeniedException` referencing `kms:Decrypt` — the
user can reach DynamoDB fine (their IAM policy allows that), but DynamoDB can't decrypt the
item on their behalf because *they* don't have `kms:Decrypt` on the key.

**On fakecloud, given KMS isn't in the enforced-service list:** expect this call to likely
**succeed anyway** and return the plaintext item, since there's currently no authorization
check happening at the KMS layer. Record whatever actually happens here — it's a legitimate,
useful finding either way.

### Prove the policy logic is correct via the IAM Policy Simulator instead

This sidesteps the enforcement gap entirely, since the simulator evaluates policy documents
statically rather than performing the real action:

```bash
awsfca iam simulate-principal-policy \
  --policy-source-arn arn:aws:iam::123456789012:user/nextwork-kms-user \
  --action-names kms:Decrypt \
  --resource-arns arn:aws:kms:us-east-1:123456789012:key/$KMS_KEY_ID \
  --output table
```

Expected: `implicitDeny` — the test user's attached policy (`AmazonDynamoDBFullAccess`
/ your custom equivalent) grants nothing on `kms:*`, so no Allow statement matches.

---

## 6. Secret mission — give the test user KMS access

### Update the key policy to add the test user

```bash
cat > kms-key-policy-updated.json << 'EOF'
{
  "Version": "2012-10-17",
  "Id": "nextwork-kms-key-policy",
  "Statement": [
    {
      "Sid": "EnableRootAndAdminAccess",
      "Effect": "Allow",
      "Principal": { "AWS": "arn:aws:iam::123456789012:root" },
      "Action": "kms:*",
      "Resource": "*"
    },
    {
      "Sid": "AllowAdminUse",
      "Effect": "Allow",
      "Principal": { "AWS": "arn:aws:iam::123456789012:user/<your-iam-admin-username>" },
      "Action": [
        "kms:Create*", "kms:Describe*", "kms:Enable*", "kms:List*",
        "kms:Put*", "kms:Update*", "kms:Revoke*", "kms:Disable*",
        "kms:Get*", "kms:Delete*", "kms:ScheduleKeyDeletion", "kms:CancelKeyDeletion"
      ],
      "Resource": "*"
    },
    {
      "Sid": "AllowAdminAsKeyUser",
      "Effect": "Allow",
      "Principal": { "AWS": "arn:aws:iam::123456789012:user/<your-iam-admin-username>" },
      "Action": [ "kms:Encrypt", "kms:Decrypt", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:DescribeKey" ],
      "Resource": "*"
    },
    {
      "Sid": "AllowTestUserDecrypt",
      "Effect": "Allow",
      "Principal": { "AWS": "arn:aws:iam::123456789012:user/nextwork-kms-user" },
      "Action": [ "kms:Decrypt", "kms:DescribeKey" ],
      "Resource": "*"
    }
  ]
}
EOF

awsfca kms put-key-policy \
  --key-id $KMS_KEY_ID \
  --policy-name default \
  --policy file://kms-key-policy-updated.json
```

### Re-verify with the simulator (should now flip to `allowed`)

```bash
awsfca iam simulate-principal-policy \
  --policy-source-arn arn:aws:iam::123456789012:user/nextwork-kms-user \
  --action-names kms:Decrypt \
  --resource-arns arn:aws:kms:us-east-1:123456789012:key/$KMS_KEY_ID \
  --output table
```

> **Note:** the simulator evaluates identity-based policies attached to the principal by
> default. Resource-based policies (like this KMS key policy) participate in real AWS
> authorization decisions too, but `simulate-principal-policy`'s handling of resource
> policies varies by exact API/version — if this still shows `implicitDeny` after the key
> policy update, that's expected simulator behavior (it's primarily evaluating the user's own
> IAM policies), not a sign the key policy update failed. Cross-check the key policy directly:
> ```bash
> awsfca kms get-key-policy --key-id $KMS_KEY_ID --policy-name default
> ```

### Re-try the live call too

```bash
awsfc-kmstest dynamodb get-item \
  --table-name nextwork-kms-table \
  --key '{"id": {"S": "item1"}}'
```
Given the enforcement gap, this likely already succeeded even *before* this policy update —
worth explicitly noting the before/after comparison (or lack thereof) in your documentation.

---

## 7. Clean up

```bash
awsfca dynamodb delete-table --table-name nextwork-kms-table

awsfca kms schedule-key-deletion --key-id $KMS_KEY_ID --pending-window-in-days 7

awsfca iam detach-user-policy --user-name nextwork-kms-user --policy-arn arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess
awsfca iam delete-access-key --user-name nextwork-kms-user --access-key-id <KEY_ID>
awsfca iam delete-user --user-name nextwork-kms-user
```

---

## Quick command reference

| Action | Command |
|---|---|
| Create KMS key | `awsfca kms create-key --description "X" --key-usage ENCRYPT_DECRYPT --key-spec SYMMETRIC_DEFAULT` |
| Create alias | `awsfca kms create-alias --alias-name alias/X --target-key-id <id>` |
| Set key policy | `awsfca kms put-key-policy --key-id <id> --policy-name default --policy file://p.json` |
| View key policy | `awsfca kms get-key-policy --key-id <id> --policy-name default` |
| Create table with CMK encryption | `awsfca dynamodb create-table ... --sse-specification "Enabled=true,SSEType=KMS,KMSMasterKeyId=<id>"` |
| Check table encryption | `awsfca dynamodb describe-table --table-name X --query 'Table.SSEDescription'` |
| Simulate a KMS permission check | `awsfca iam simulate-principal-policy --policy-source-arn <user-arn> --action-names kms:Decrypt --resource-arns <key-arn>` |
| Schedule key deletion | `awsfca kms schedule-key-deletion --key-id <id> --pending-window-in-days 7` |

---

## What this project demonstrates (worth noting in your documentation)

- **Encryption at rest vs. in transit vs. in use** — KMS specifically manages long-lived
  keys for data at rest; TLS session keys handle transit, and "in use" data isn't something
  a key management system addresses at all.
- **Customer managed keys (CMKs) vs. AWS-owned/AWS-managed keys** — the CMK option is the
  only one where *you* control the key policy and can grant/revoke specific principals'
  access independently of the resource itself.
- **Transparent data encryption** — DynamoDB decrypts on the fly for authorized callers;
  the complexity is invisible until someone lacks `kms:Decrypt`, at which point the whole
  request fails even though their DynamoDB-level permissions are otherwise fine.
- **Key policies are resource-based, separate from IAM identity policies** — a real,
  important AWS concept: access to a KMS key is governed by *both* what the key's own policy
  allows *and* what the calling principal's IAM policy allows. This project's Step 5 is
  specifically about the key-policy side of that equation.
- **fakecloud's enforcement gap (KMS not in the enforced-service list)** is itself a useful
  finding worth documenting — it's the same category of limitation hit in the EC2/IAM
  project, and knowing to reach for the Policy Simulator as a reliable workaround is a
  transferable skill, not just a one-off fix.
