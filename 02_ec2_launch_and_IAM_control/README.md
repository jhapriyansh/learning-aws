# Cloud Security with AWS IAM — fakecloud Edition

A from-scratch tutorial for redoing the NextWork "Cloud Security with AWS IAM" project against
a local **fakecloud** instance instead of real AWS. Covers EC2 launch + tagging, scoped IAM
policies, groups/users, access testing, and the IAM Policy Simulator secret mission.

---

## ⚠️ Read this first: fakecloud's IAM enforcement scope

fakecloud supports `--iam soft|strict` for real policy evaluation (Allow/Deny with deny
precedence, Condition blocks, wildcards, resource-based policies) — but **only across
five services: IAM, STS, SQS, SNS, and S3.**

**EC2 is not currently enforced.** You can create policies, attach them, and the control
plane works perfectly — but actual EC2 API calls (`RunInstances`, `StopInstances`,
`CreateTags`, etc.) are **not authorization-checked**, regardless of which credentials or
policies are in play. Any user can do anything to any EC2 resource right now.

This means:
- ✅ Steps 1–4 (launch instances, write the policy, create groups/users) work exactly as
  written and are genuinely useful practice.
- ❌ Step 5 ("test your intern's access" by trying `stop-instances` as the intern user and
  expecting a real `AccessDenied`) **will not behave correctly** — both the production and
  development stop calls will silently succeed.
- ✅ The **secret mission (IAM Policy Simulator)** works great and is unaffected by this gap,
  since it's a static policy-evaluation engine that doesn't actually perform the API call.
  **Use the simulator as your real proof of correct access control for this project.**

Source: fakecloud's own docs/README state enforcement explicitly covers "IAM, STS, SQS, SNS,
and S3" — EC2 is absent from that list despite running as a real container-backed service.

---

## 0. Prerequisites

```bash
export FAKECLOUD_IP=<your-fakecloud-host-ip>
alias awsfca='aws --profile fakecloud-admin --endpoint-url http://$FAKECLOUD_IP:4566'
```

Confirm connectivity:
```bash
awsfca ec2 describe-instances
```

---

## 1. Launch two EC2 instances (production + development)

Find a usable AMI:
```bash
awsfca ec2 describe-images --owners amazon \
  --filters "Name=name,Values=amzn2-ami-hvm*" \
  --query 'Images[0].ImageId' --output text
```

Launch **production**:
```bash
awsfca ec2 run-instances \
  --image-id <AMI_ID> \
  --instance-type t2.micro \
  --count 1 \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=nextwork-prod-<yourname>},{Key=Env,Value=production}]'
```

Launch **development**:
```bash
awsfca ec2 run-instances \
  --image-id <AMI_ID> \
  --instance-type t2.micro \
  --count 1 \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=nextwork-dev-<yourname>},{Key=Env,Value=development}]'
```

Verify + capture instance IDs:
```bash
awsfca ec2 describe-instances \
  --query 'Reservations[].Instances[].{ID:InstanceId,Name:Tags[?Key==`Name`]|[0].Value,Env:Tags[?Key==`Env`]|[0].Value,State:State.Name}' \
  --output table --no-cli-pager
```

> **Tip:** pipe through `| cat` or use `--no-cli-pager` to avoid the CLI dropping output into
> `less`, which can look like an empty response if you're not expecting it.

Save the IDs for later:
```bash
export PROD_ID=<i-xxxxxxxx>
export DEV_ID=<i-xxxxxxxx>
```

---

## 2. Write the scoped IAM policy

```bash
cat > enable-dev-access.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "ec2:*",
      "Resource": "*",
      "Condition": {
        "StringEquals": { "ec2:ResourceTag/Env": "development" }
      }
    },
    {
      "Effect": "Allow",
      "Action": "ec2:Describe*",
      "Resource": "*"
    },
    {
      "Effect": "Deny",
      "Action": ["ec2:DeleteTags", "ec2:CreateTags"],
      "Resource": "*"
    }
  ]
}
EOF
```

What it does:
- Statement 1: full EC2 access, but only on resources tagged `Env=development`
- Statement 2: unconditional read-only `Describe*` access to everything (so the intern can
  see production instances exist, just can't touch them)
- Statement 3: unconditionally denies tagging changes on **any** resource — an explicit Deny
  that overrides any Allow, no matter how permissive

Create the policy:
```bash
awsfca iam create-policy \
  --policy-name NextWorkDevEnvironmentPolicy \
  --policy-document file://enable-dev-access.json \
  --query 'Policy.Arn' --output text
```

Save the returned ARN:
```bash
export DEV_POLICY_ARN=<arn-from-output>
```

If you lose it later, recover it with:
```bash
export DEV_POLICY_ARN=$(awsfca iam list-policies --scope Local \
  --query "Policies[?PolicyName=='NextWorkDevEnvironmentPolicy'].Arn" --output text)
```

---

## 3. Account alias (optional — worth testing if fakecloud supports it)

```bash
awsfca iam create-account-alias --account-alias nextwork-alias-<yourname>
awsfca iam list-account-aliases
```

---

## 4. Create the group and user

```bash
awsfca iam create-group --group-name nextwork-dev-group

awsfca iam attach-group-policy \
  --group-name nextwork-dev-group \
  --policy-arn $DEV_POLICY_ARN

awsfca iam create-user --user-name nextwork-dev-<yourname>

awsfca iam add-user-to-group \
  --user-name nextwork-dev-<yourname> \
  --group-name nextwork-dev-group

# fakecloud has no console/browser login — generate CLI credentials instead
awsfca iam create-access-key --user-name nextwork-dev-<yourname>
```

Set up a separate profile with the returned keys:
```bash
aws configure --profile nextwork-dev-intern
# paste in AccessKeyId / SecretAccessKey from above

alias awsfc-intern='aws --profile nextwork-dev-intern --endpoint-url http://$FAKECLOUD_IP:4566'
```

Confirm the profile is really using the intern's identity, not your admin creds:
```bash
awsfc-intern sts get-caller-identity
```
This should **fail with `AccessDeniedException`** — the intern's policy never grants
`sts:GetCallerIdentity`, and since STS enforcement is real in fakecloud, you'll get a genuine
`AccessDenied` here. That failure is actually a good sign: it confirms (a) you're using the
right identity and (b) enforcement is active.

---

## 5. Test EC2 access (control-plane only — see warning above)

You can still run these for the CLI practice value, but **do not expect real denial
behavior** on the production instance:

```bash
# "Should fail" on real AWS — will actually succeed on fakecloud right now
awsfc-intern ec2 stop-instances --instance-ids $PROD_ID

# Should succeed either way
awsfc-intern ec2 stop-instances --instance-ids $DEV_ID
```

If you want a service where this test *does* work correctly end-to-end, redo the same
tag-conditioned Allow/Deny pattern against S3 objects instead — S3 is one of the five
enforced services.

---

## 6. Secret mission — IAM Policy Simulator

This is the reliable way to prove your policy logic is correct, independent of whether
fakecloud enforces EC2 authorization at the API layer. The simulator statically evaluates
policies without performing the actual action.

**Test 1 — intern tries to stop the production instance (expect `implicitDeny`):**
```bash
awsfca iam simulate-principal-policy \
  --policy-source-arn arn:aws:iam::123456789012:user/nextwork-dev-<yourname> \
  --action-names ec2:StopInstances \
  --resource-arns arn:aws:ec2:us-east-1:123456789012:instance/$PROD_ID \
  --context-entries ContextKeyName=ec2:ResourceTag/Env,ContextKeyType=string,ContextKeyValues=production \
  --output table
```
Expected: `implicitDeny` — no Allow statement matches (condition requires `development`).

**Test 2 — intern tries to stop the development instance (expect `allowed`):**
```bash
awsfca iam simulate-principal-policy \
  --policy-source-arn arn:aws:iam::123456789012:user/nextwork-dev-<yourname> \
  --action-names ec2:StopInstances \
  --resource-arns arn:aws:ec2:us-east-1:123456789012:instance/$DEV_ID \
  --context-entries ContextKeyName=ec2:ResourceTag/Env,ContextKeyType=string,ContextKeyValues=development \
  --output table
```
Expected: `allowed`.

**Test 3 — intern tries to create/delete tags on anything (expect `explicitDeny`):**
```bash
awsfca iam simulate-principal-policy \
  --policy-source-arn arn:aws:iam::123456789012:user/nextwork-dev-<yourname> \
  --action-names ec2:CreateTags \
  --resource-arns "*" \
  --output table
```
Expected: `explicitDeny` — notably different from `implicitDeny`. This confirms the
unconditional Deny statement is actively matching and overriding, not just "nothing
allows this." You may also see a `MissingContextValues` block calling out
`ec2:ResourceTag/Env` if you don't pass a context entry — that's the simulator correctly
telling you it evaluated the Condition block and didn't have a value to test it against.

**Why this triad is worth documenting:**
| Result | Meaning |
|---|---|
| `implicitDeny` | No policy statement grants this — default-deny kicked in |
| `allowed` | A matching Allow statement was found and nothing denies it |
| `explicitDeny` | A Deny statement actively matched and won, regardless of any Allow |

If `simulate-principal-policy` isn't available for some reason, `simulate-custom-policy`
works the same way but takes the policy JSON directly instead of referencing an attached
user:
```bash
awsfca iam simulate-custom-policy \
  --policy-input-list file://enable-dev-access.json \
  --action-names ec2:StopInstances \
  --resource-arns arn:aws:ec2:us-east-1:123456789012:instance/$PROD_ID \
  --context-entries ContextKeyName=ec2:ResourceTag/Env,ContextKeyType=string,ContextKeyValues=production \
  --output table
```

---

## Quick command reference

| Action | Command |
|---|---|
| Launch instance with tags | `awsfca ec2 run-instances --image-id <ami> --instance-type t2.micro --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=X},{Key=Env,Value=Y}]'` |
| List instances w/ tags | `awsfca ec2 describe-instances --query '...' --output table` |
| Add/update a tag | `awsfca ec2 create-tags --resources <id> --tags Key=K,Value=V` |
| View tags | `awsfca ec2 describe-tags --filters "Name=resource-id,Values=<id>"` |
| Create policy | `awsfca iam create-policy --policy-name X --policy-document file://p.json` |
| Find policy ARN later | `awsfca iam list-policies --scope Local --query "Policies[?PolicyName=='X'].Arn" --output text` |
| View live policy document | `awsfca iam get-policy-version --policy-arn <arn> --version-id <v>` |
| Push new policy version | `awsfca iam create-policy-version --policy-arn <arn> --policy-document file://p.json --set-as-default` |
| Create group | `awsfca iam create-group --group-name X` |
| Attach policy to group | `awsfca iam attach-group-policy --group-name X --policy-arn <arn>` |
| Create user | `awsfca iam create-user --user-name X` |
| Add user to group | `awsfca iam add-user-to-group --user-name X --group-name Y` |
| Create CLI credentials | `awsfca iam create-access-key --user-name X` |
| Simulate a policy decision | `awsfca iam simulate-principal-policy --policy-source-arn <arn> --action-names <action> --resource-arns <arn> --context-entries ...` |

---

## Cleanup

```bash
awsfca ec2 terminate-instances --instance-ids $PROD_ID $DEV_ID
awsfca iam remove-user-from-group --user-name nextwork-dev-<yourname> --group-name nextwork-dev-group
awsfca iam delete-access-key --user-name nextwork-dev-<yourname> --access-key-id <KEY_ID>
awsfca iam delete-user --user-name nextwork-dev-<yourname>
awsfca iam detach-group-policy --group-name nextwork-dev-group --policy-arn $DEV_POLICY_ARN
awsfca iam delete-group --group-name nextwork-dev-group
awsfca iam delete-policy --policy-arn $DEV_POLICY_ARN
```

---

## Debugging notes from the original run-through (useful if you hit the same walls)

- **`aws help` / `awsfca help` do not reflect fakecloud's actual service coverage.** That
  service list is baked into the local botocore install and is identical regardless of
  endpoint. To find real coverage, check `fakecloud.dev/docs/services` or the GitHub README
  directly.
- **Table output getting "swallowed":** it's not empty — the CLI is piping into `less` (the
  built-in pager). Use `--no-cli-pager` or pipe to `| cat`.
- **IAM policy edits not taking effect:** if you edit a policy JSON file after already running
  `create-policy`, the change never uploads on its own. Push a new version explicitly with
  `create-policy-version --set-as-default`, or verify what's actually live with
  `get-policy-version` before assuming a bug.
- **Be skeptical of AI/web answers claiming exact fakecloud internals** (e.g. specific
  "engine names," enforcement claims not matching the primary docs). Cross-check against
  fakecloud's own GitHub README / fakecloud.dev — these are the only fully reliable sources,
  since fakecloud is new enough that most secondary write-ups about it are thin or inferred.
