# Learning AWS with fakecloud

Hands-on AWS practice using [fakecloud](https://github.com/faiscadev/fakecloud), a
Rust-based, container-backed AWS API emulator, self-hosted in an Incus VM on my homelab —
mainly because my AWS free tier expired a long time ago. No AWS console; everything here is
done through the AWS CLI, which turned out to be a good forcing function for actually
learning the CLI properly instead of clicking through a UI.

Following the [NextWork](https://learn.nextwork.org) project series, adapted step-by-step to
run against fakecloud instead of a real AWS account.

## What's actually covered

| Directory | Project | Services |
|---|---|---|
| `01_s3_static_website_hosting` | Host a static site on S3, with a bucket policy protecting `index.html` from deletion | S3 |
| `02_ec2_launch_and_IAM_control` | Launch tagged EC2 instances, write a scoped IAM policy (allow/deny by resource tag), test access with a restricted IAM user | EC2, IAM |
| `03_s3_and_terraform` | Manage an S3 bucket and object declaratively instead of via CLI calls | S3, Terraform |
| `04_dynamodb_load_data` | Create four related tables (partition-key-only and partition+sort-key schemas), bulk-load sample data with `batch-write-item` | DynamoDB |
| `05_dynamodb_query_data` | Query by partition/sort key, `scan` with filters, strongly vs. eventually consistent reads, atomic cross-table `transact-write-items` | DynamoDB |
| `06_lambda_api_gateway` | A Node.js Lambda function fronted by a REST API (Lambda proxy integration), deployed to a `prod` stage, documented in hand-authored OpenAPI | Lambda, API Gateway |
| `07_kms` | Customer-managed KMS key encrypting a DynamoDB table at rest, key policy administration, testing decrypt access for a restricted user | KMS, DynamoDB, IAM |

## Tech stack

- AWS CLI v2
- fakecloud (self-hosted, running in an Incus VM)
- Terraform (`hashicorp/aws` provider, pointed at fakecloud's endpoint)
- Node.js 18 (Lambda runtime)
- Docker (fakecloud runs Lambda/EC2/RDS as real containers under the hood)

## Setup

1. fakecloud running somewhere reachable on your network (mine's in an Incus VM, proxied to
   a host port via an Incus proxy device).
2. AWS CLI installed locally — no need to run it anywhere near fakecloud itself, it's just an
   HTTP client:
   ```bash
   brew install awscli
   ```
3. Point the CLI at fakecloud instead of real AWS:
   ```bash
   export FAKECLOUD_IP=<your-fakecloud-host-ip>
   alias awsfca='aws --profile fakecloud-admin --endpoint-url http://$FAKECLOUD_IP:4566'
   ```
4. Each numbered directory has its own `README.md` with the exact CLI commands for that
   project, plus troubleshooting notes for anything that came up while building it.

## Notes on fakecloud's actual coverage (learned the hard way)

fakecloud is a genuinely capable emulator (~100+ AWS service namespaces, Smithy-model-based,
runs the real `terraform-provider-aws` acceptance test suite in its own CI) — but it has a
few sharp edges worth knowing before you assume something is "broken":

- **IAM authorization enforcement (`--iam strict`) only covers five services: IAM, STS, SQS,
  SNS, and S3.** EC2 and KMS calls are *not* authorization-checked regardless of attached
  policies — any credentials can do anything to any EC2/KMS resource right now. Confirmed by
  testing an explicit `Deny` policy against each and watching it get ignored. The IAM Policy
  Simulator (`simulate-principal-policy`) is unaffected by this gap since it evaluates policy
  logic statically rather than performing the real action — use it to validate policy design
  even where live enforcement doesn't exist yet.
- **API Gateway routes by `Host` header, not URL path.** The older
  `/restapis/<id>/<stage>/_user_request_/<resource>` path convention returns
  `NotFoundException` even when everything is configured correctly. Use a faked `Host` header
  instead:
  ```bash
  curl -H "Host: <api-id>.execute-api.us-east-1.amazonaws.com" \
    "http://$FAKECLOUD_IP:4566/<stage>/<resource>"
  ```
- **State is in-memory by default** — any container recreation (image pull, `compose down`)
  wipes everything. `--storage-mode persistent` exists, but persistence support is currently
  service-by-service (S3 is covered; IAM/EC2 are not, as of this writing).
- **`get-export` on API Gateway doesn't fold in documentation parts** created via
  `create-documentation-part`/`create-documentation-version`, even though both are correctly
  stored — hand-author the OpenAPI spec if documentation content actually needs to ship.
- **VM-backed Incus proxy devices show nothing in `ss -tlnp`** even when working correctly —
  they're implemented as NAT/DNAT rules, not a listening userspace process. Check
  `nft list ruleset` / `iptables -t nat -L` instead.
- **Docker's default `FORWARD` chain policy is `DROP`**, and only carves out exceptions for
  its own bridges — this silently blocks new inbound connections to other bridges (like
  Incus's `incusbr0`) unless you add an explicit accept rule.

## License

Personal learning project — no license, use whatever's useful.