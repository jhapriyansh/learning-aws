# Host a Static Website on S3 — fakecloud Edition

A from-scratch tutorial for redoing the NextWork "Host a Website on Amazon S3" project against
a local **fakecloud** instance instead of real AWS. Covers bucket creation, uploads, the
public-read policy needed for website access, and the "secret mission" delete-protection policy.

---

## 0. Prerequisites

- fakecloud running and reachable (e.g. via an Incus VM + proxy device forwarding host port 4566)
- Your `awsfca` / `awsfcr` aliases set up, pointing at fakecloud's endpoint:
  ```bash
  export FAKECLOUD_IP=<your-fakecloud-host-ip>
  alias awsfca='aws --profile fakecloud-admin --endpoint-url http://$FAKECLOUD_IP:4566'
  alias awsfcr='aws --profile fakecloud-root --endpoint-url http://$FAKECLOUD_IP:4566'
  ```
- Confirm connectivity before starting:
  ```bash
  awsfca s3 ls
  ```
  If this hangs or times out, fix networking first (proxy device, NAT rules, host FORWARD
  policy) — see the "Common connectivity gotchas" section at the bottom.

---

## 1. Create the bucket

Bucket names should be unique to you (no need for global uniqueness in fakecloud, but good
practice anyway):

```bash
awsfca s3 mb s3://nextwork-website-project-<yourname>
```

Verify:

```bash
awsfca s3 ls
```

---

## 2. Prepare your website files

Export or download your site as static HTML/CSS/JS/images into a local folder, e.g.:

```
~/code/s3-test-website/
  index.html
  <site-name>_files/
    1.jpg
    2.jpg
    ...
    css/
    js/
```

---

## 3. Upload files to the bucket

Upload the main HTML file:

```bash
awsfca s3 cp index.html s3://nextwork-website-project-<yourname>
```

Upload the rest of the assets recursively:

```bash
awsfca s3 cp "<site-name>_files" \
  s3://nextwork-website-project-<yourname>/<site-name>_files/ \
  --recursive
```

> **Gotcha:** Don't leave `your-bucket-name` as a literal placeholder in the command —
> always substitute your actual bucket name. Leaving the placeholder in will either 404
> (bucket doesn't exist) or, on real AWS, hit someone else's bucket entirely (bucket names
> are globally unique on real AWS) and return `AccessDenied`.

---

## 4. Enable static website hosting on the bucket

```bash
awsfca s3 website s3://nextwork-website-project-<yourname>/ \
  --index-document index.html
```

Confirm the config took:

```bash
awsfca s3api get-bucket-website --bucket nextwork-website-project-<yourname>
```

---

## 5. Make the site publicly readable

**S3 buckets are private by default.** Even with website hosting configured, anonymous
requests will get `403 AccessDenied` until you explicitly allow public reads.

### 5a. Disable "Block Public Access" settings

fakecloud models S3's public-access-block feature, which overrides bucket policies even if
the policy itself is correct. Check current state:

```bash
awsfca s3api get-public-access-block --bucket nextwork-website-project-<yourname>
```

If any of the four flags are `true`, disable them:

```bash
awsfca s3api put-public-access-block \
  --bucket nextwork-website-project-<yourname> \
  --public-access-block-configuration \
  BlockPublicAcls=false,IgnorePublicAcls=false,BlockPublicPolicy=false,RestrictPublicBuckets=false
```

### 5b. Apply a public-read bucket policy

```bash
cat > public-read-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "PublicReadGetObject",
      "Effect": "Allow",
      "Principal": "*",
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::nextwork-website-project-<yourname>/*"
    }
  ]
}
EOF

awsfca s3api put-bucket-policy \
  --bucket nextwork-website-project-<yourname> \
  --policy file://public-read-policy.json
```

### 5c. Test it

```bash
curl -v http://$FAKECLOUD_IP:4566/nextwork-website-project-<yourname>/index.html
```

Expect `HTTP/1.1 200 OK`. A `403 Forbidden` here means either the public-access-block
settings or the bucket policy (or both) still aren't right — recheck steps 5a/5b.

> **Note:** Real AWS gives you a dedicated website endpoint
> (`http://<bucket>.s3-website-<region>.amazonaws.com`) that's genuinely internet-routable.
> fakecloud only listens on your LAN/Tailscale, so the "public" URL above is only reachable
> from your own network — it's a stand-in for the real thing, useful for CLI/policy practice,
> not for actually sharing a link with someone else.

---

## 6. Secret mission: protect `index.html` from deletion

Goal: add a policy that blocks `DeleteObject` on `index.html` specifically, even for an
admin-level IAM user — an explicit `Deny` in a bucket policy always overrides an `Allow`
in IAM, regardless of how permissive the IAM policy is.

> **Important:** an S3 bucket has only **one** policy document at a time. If you already
> have the public-read policy from step 5b applied, you need to **combine both statements
> into a single policy document** rather than overwrite one with the other.

```bash
cat > combined-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "PublicReadGetObject",
      "Effect": "Allow",
      "Principal": "*",
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::nextwork-website-project-<yourname>/*"
    },
    {
      "Sid": "DenyDeleteIndexHtml",
      "Effect": "Deny",
      "Principal": "*",
      "Action": "s3:DeleteObject",
      "Resource": "arn:aws:s3:::nextwork-website-project-<yourname>/index.html"
    }
  ]
}
EOF

awsfca s3api put-bucket-policy \
  --bucket nextwork-website-project-<yourname> \
  --policy file://combined-policy.json
```

### Test the protection

```bash
awsfca s3 rm s3://nextwork-website-project-<yourname>/index.html
```

Expect `AccessDenied` — the deny statement is working.

### Remove just the deny-delete rule later (keep public-read)

Since a bucket only has one policy document, "removing one rule" means re-applying a new
document that omits it — not `delete-bucket-policy` (which wipes the whole thing):

```bash
cat > public-read-only-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "PublicReadGetObject",
      "Effect": "Allow",
      "Principal": "*",
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::nextwork-website-project-<yourname>/*"
    }
  ]
}
EOF

awsfca s3api put-bucket-policy \
  --bucket nextwork-website-project-<yourname> \
  --policy file://public-read-only-policy.json
```

### Full wipe (removes ALL policy statements, including public-read)

```bash
awsfca s3api delete-bucket-policy --bucket nextwork-website-project-<yourname>
```

Confirm it's gone:

```bash
awsfca s3api get-bucket-policy --bucket nextwork-website-project-<yourname>
```

`NoSuchBucketPolicy` error = confirmed deleted. Remember: deleting the policy at this point
means the site goes private again (back to step 5) — deleting a policy never grants access,
it only removes whatever rules (allow or deny) were there.

---

## Quick command reference

| Action | Command |
|---|---|
| Create bucket | `awsfca s3 mb s3://<bucket>` |
| Upload single file | `awsfca s3 cp <file> s3://<bucket>` |
| Upload folder recursively | `awsfca s3 cp <folder> s3://<bucket>/<folder>/ --recursive` |
| Enable website hosting | `awsfca s3 website s3://<bucket>/ --index-document index.html` |
| Check website config | `awsfca s3api get-bucket-website --bucket <bucket>` |
| Check public access block | `awsfca s3api get-public-access-block --bucket <bucket>` |
| Disable public access block | `awsfca s3api put-public-access-block --bucket <bucket> --public-access-block-configuration BlockPublicAcls=false,IgnorePublicAcls=false,BlockPublicPolicy=false,RestrictPublicBuckets=false` |
| Apply bucket policy | `awsfca s3api put-bucket-policy --bucket <bucket> --policy file://policy.json` |
| View current policy | `awsfca s3api get-bucket-policy --bucket <bucket>` |
| Delete entire policy | `awsfca s3api delete-bucket-policy --bucket <bucket>` |
| Delete an object | `awsfca s3 rm s3://<bucket>/<key>` |
| List bucket contents | `awsfca s3 ls s3://<bucket>` |
| Check object details | `awsfca s3api head-object --bucket <bucket> --key <key>` |
| Test public URL | `curl -v http://$FAKECLOUD_IP:4566/<bucket>/<key>` |

---

## Common connectivity gotchas (fakecloud on Incus/homelab setups)

If `awsfca` commands hang or time out before you even get to the S3 work:

1. **Incus VM proxy device for `docker-proxy`-based services**: for VM instances (not
   containers), Incus implements proxy devices via NAT rules (iptables/nftables DNAT), not a
   userspace forwarding process — so `ss -tlnp` on the host will *never* show a listening
   socket for a VM proxy device, even when it's working correctly. Check NAT rules instead:
   ```bash
   sudo nft list ruleset | grep -A5 <port>
   ```
2. **Docker's default FORWARD policy**: Docker sets the host's `iptables FORWARD` chain to
   `DROP` by default, only opening exceptions for its own bridges. This silently kills new
   (not yet established) inbound connections to other bridges like Incus's `incusbr0`, even
   though NAT/DNAT rules are correctly rewriting the packets. Fix:
   ```bash
   sudo iptables -I FORWARD -d <vm-subnet>/24 -j ACCEPT
   ```
   Persist it:
   ```bash
   sudo apt install iptables-persistent
   sudo netfilter-persistent save
   ```
3. **IP forwarding disabled**: `sysctl net.ipv4.ip_forward` should return `1`. If not:
   ```bash
   sudo sysctl -w net.ipv4.ip_forward=1
   ```
