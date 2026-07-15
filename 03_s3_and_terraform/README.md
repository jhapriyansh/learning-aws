# Create S3 Buckets with Terraform — fakecloud Edition

A from-scratch tutorial for redoing the NextWork "Create S3 Buckets with Terraform" project
against a local **fakecloud** instance instead of real AWS.

---

## 0. Prerequisites

- Terraform installed locally (on your Mac, not inside the fakecloud VM — Terraform is just
  an HTTP client, no benefit to colocating it with the emulator):
  ```bash
  brew tap hashicorp/tap
  brew install hashicorp/tap/terraform
  terraform -version
  ```
- fakecloud reachable from your Mac (same LAN/Tailscale setup as your `awsfca` CLI work):
  ```bash
  export FAKECLOUD_IP=<your-fakecloud-host-ip>
  ```

---

## 1. Project structure

```
03_s3_and_terraform/
  main.tf
  README.md
```

---

## 2. `main.tf`

```hcl
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region                      = "us-east-1"
  access_key                  = "test"
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true

  endpoints {
    s3 = "http://<FAKECLOUD_IP>:4566"
  }
}

resource "aws_s3_bucket" "nextwork_bucket" {
  bucket = "nextwork-unique-bucket-priyanshu-6969"
}

resource "aws_s3_object" "sample_image" {
  bucket = aws_s3_bucket.nextwork_bucket.id
  key    = "image.jpg"
  source = "image.jpg"  # local file path, relative to this .tf file
}
```

> Replace `<FAKECLOUD_IP>` with the literal IP — Terraform doesn't expand shell environment
> variables inside `.tf` files. Use a `variable` block if you want it configurable instead of
> hardcoded.

> Bucket names must be unique within fakecloud's simulated namespace, hence the
> `-6969` suffix — swap in your own unique string if you rerun this from scratch.

---

## 3. Commands

```bash
# Download the AWS provider plugin and set up the working directory
terraform init

# Preview what Terraform will create
terraform plan

# Actually create the resources
terraform apply
```

`terraform apply` will prompt for confirmation — type `yes`.

---

## 3a. The workflow for every subsequent change to `main.tf`

Whenever you edit `main.tf` (change a bucket name, add a resource, modify a tag, etc.), the
loop is always the same three steps — you don't re-run `init` unless you changed the
provider block/version or added a new provider:

```bash
terraform plan    # see what Terraform intends to change, in a dry-run
terraform apply   # actually make the change (prompts for `yes`)
```

`terraform plan` is optional to run standalone (`apply` shows you the same plan and asks for
confirmation before doing anything), but running it separately first is good practice while
you're learning — it lets you read the diff calmly before committing to it.

**What `terraform plan` tells you, reading the symbols:**
- `+` — resource will be created
- `-` — resource will be destroyed
- `~` — resource will be modified in place
- `-/+` — resource will be destroyed and recreated (some attributes, like a bucket's name,
  can't be changed in place — Terraform has to tear down and rebuild)

**When you *do* need to re-run `terraform init`:**
- You changed the `required_providers` block (new provider, version constraint change)
- You added a new provider you haven't used before
- You deleted the `.terraform/` directory or switched machines/checked out the repo fresh

**A safe habit for this project specifically:** since bucket names must be unique and you're
iterating against fakecloud, if you ever want to rename `nextwork-unique-bucket-priyanshu-6969`
in `main.tf`, expect a `-/+` (destroy + recreate) rather than an in-place rename — S3 buckets
don't support renaming, in Terraform or in real AWS.

---

## 4. Verify the bucket and object were created

Using the AWS CLI against the same fakecloud endpoint (proves Terraform and the CLI are
talking to the same backend state):

```bash
awsfca s3 ls
awsfca s3 ls s3://nextwork-unique-bucket-priyanshu-6969
```

Download the object back down to confirm it round-trips correctly:
```bash
awsfca s3api get-object \
  --bucket nextwork-unique-bucket-priyanshu-6969 \
  --key image.jpg \
  check.jpg
```
Compare `check.jpg` against your original `image.jpg` (checksum or just open both) to confirm
the upload was byte-identical.

---

## 5. Clean up

```bash
terraform destroy
```
Confirm with `yes`. This tears down both the bucket and the object Terraform created,
mirroring real Terraform-managed infrastructure lifecycle — everything that was declared in
`main.tf` gets removed in dependency order.

Confirm it's actually gone:
```bash
awsfca s3 ls
```
Bucket should no longer appear.

---

## What this project actually demonstrates

- **Terraform as a client, not a service** — it doesn't need to live anywhere near fakecloud;
  it just needs network access to fakecloud's endpoint, same as the AWS CLI.
- **Infrastructure as Code round-trip** — declare resources in `.tf`, apply them, verify with
  an independent tool (the CLI), then destroy cleanly — the core IaC workflow you'd use
  identically against real AWS, just pointed at a different endpoint.
- **fakecloud's Terraform compatibility** — this is explicitly one of the workflows fakecloud
  is built to support (it runs upstream `terraform-provider-aws` acceptance tests in its own
  CI), so this project is a genuinely faithful stand-in for the real-AWS version.

---

## Persistence note

S3 is one of fakecloud's **persisted** services (state is written to disk on every mutation
when `--storage-mode persistent --data-path <dir>` is enabled) — so unlike the EC2/IAM
projects, a bucket created here will actually survive a fakecloud container restart, *if*
persistent mode is configured. If it's running in the default in-memory mode, a restart
wipes it just like everything else, and you'd need to `terraform apply` again.

---

## Troubleshooting notes from this run-through

**`terraform init` failing with `unexpected EOF` fetching the provider plugin:**
This was a network-level issue, not a Terraform or fakecloud problem — likely
SNI-based filtering/throttling on the network in use (same category of restriction that
required routing Tailscale through Tor SOCKS5 elsewhere in this setup). Symptoms: DNS
resolves fine, TLS handshake completes, but the actual binary transfer hangs indefinitely
or drops mid-stream. Diagnosis path that confirmed it:
```bash
curl -4 -v -o /tmp/test-provider.zip https://releases.hashicorp.com/terraform-provider-aws/<version>/terraform-provider-aws_<version>_darwin_arm64.zip
```
hung with no data received, while a control test to an unrelated domain
(`speed.hetzner.de`) failed DNS resolution outright — both consistent with restrictive
network filtering rather than a local machine or tool issue.

**Fix (if it recurs):** route the terminal session's traffic through the same SOCKS5 tunnel
used for Tailscale, either globally or per-tool:
```bash
export ALL_PROXY=socks5://127.0.0.1:<tor-socks-port>
terraform init
```
On this particular run, a retry eventually succeeded without needing the proxy — but if
`unexpected EOF` reappears, this is the first thing to reach for rather than re-diagnosing
from scratch.
