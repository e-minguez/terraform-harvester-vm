# terraform-harvester-vm

![SUSE Geeko managing virtual machines with Harvester HCI and Terraform](assets/geeko-harvester.png)

Provisions one or more virtual machines on [SUSE Harvester HCI](https://harvesterhci.io/) using two independent [Terraform](https://developer.hashicorp.com/terraform) / [OpenTofu](https://opentofu.org/) root modules:

| Module | Purpose |
|---|---|
| `image/` | Uploads or downloads a `VirtualMachineImage` — manages image lifecycle |
| `vm/` | Creates a `VirtualMachine` by looking up an existing image by name |

The modules have **separate state files**. Running `terraform destroy` on the `vm/` module leaves the image intact. Use `--destroy-vm`, `--destroy-image`, or `--destroy-all` in `harvester-vm.sh` to control what gets destroyed.

## Features

- **Local image upload** (`image/`) — streams a local ISO/raw/qcow2 file to Harvester via its two-step upload API using `curl`
- **Remote image download** (`image/`) — instructs Harvester to pull an image from an HTTP/HTTPS URL
- **Existing image** — skip the `image/` module entirely; `vm/` looks up the image by its Kubernetes resource name
- **Multiple VMs** — `vm_count` creates N VMs in a single `terraform apply`; names auto-indexed (`my-vm-0`, `my-vm-1`, …); optional per-VM MAC addresses
- **Decoupled lifecycle** — destroying a VM never touches the image
- **Kubeconfig-only auth** — server URL and bearer token are extracted from your kubeconfig with `yamldecode()`; no `kubectl` or external tools required
- **UEFI boot** — VMs use UEFI firmware by default; pass `--boot bios` (script) or `efi = false` (module) for legacy BIOS
- **Input validation** — `variable` validation blocks and `lifecycle.precondition` blocks catch misconfigurations before infrastructure is touched
- **Companion shell script** — `harvester-vm.sh` wraps both modules; derives names, checks paths, then delegates entirely to `terraform`/`tofu`. Supports both tools via auto-detection or the `--tofu` flag / `TF_CMD` env var

## Requirements

| Tool | Minimum version |
|---|---|
| [Terraform](https://developer.hashicorp.com/terraform/downloads) **or** [OpenTofu](https://opentofu.org/docs/intro/install/) | 1.4 |
| [harvester/harvester provider](https://registry.terraform.io/providers/harvester/harvester) | 0.6.4 |
| `curl` | any (required for `image_source = "upload"` only) |

## Quick start — `harvester-vm.sh`

`harvester-vm.sh` auto-detects the image mode, runs both modules in the correct order, and writes `.tfvars` files so you can destroy without re-running the script.

```sh
# Upload a local image and create a VM
./harvester-vm.sh \
  -k ~/.kube/harvester.yaml \
  -n my-vm \
  --vm-namespace default \
  --network vlan10 \
  ./openSUSE-Leap-15.6.qcow2

# Have Harvester download an image from a URL, then create a VM
./harvester-vm.sh \
  -k ~/.kube/harvester.yaml \
  -n my-vm \
  --vm-namespace default \
  --network vlan10 \
  --image-name opensuse-leap \
  --image-display-name "openSUSE Leap 15.6" \
  --image-url https://example.com/openSUSE-Leap-15.6.qcow2

# Create a VM from an image already in Harvester (image module is skipped)
./harvester-vm.sh \
  -k ~/.kube/harvester.yaml \
  -n my-vm \
  --vm-namespace default \
  --network vlan10 \
  --image-source existing \
  --image-name image-74wx4

# Create 3 VMs from the same image (named my-vm-0, my-vm-1, my-vm-2)
./harvester-vm.sh \
  -k ~/.kube/harvester.yaml \
  -n my-vm \
  --vm-namespace default \
  --network vlan10 \
  --image-source existing \
  --image-name image-74wx4 \
  --count 3

# Create 2 VMs with explicit MAC addresses
./harvester-vm.sh \
  -k ~/.kube/harvester.yaml \
  -n my-vm \
  --vm-namespace default \
  --network vlan10 \
  --image-source existing \
  --image-name image-74wx4 \
  --count 2 \
  --mac-address AA:BB:CC:DD:EE:01,AA:BB:CC:DD:EE:02

# Upload an image and create a VM with legacy BIOS boot
./harvester-vm.sh \
  -k ~/.kube/harvester.yaml \
  -n my-vm \
  --vm-namespace default \
  --network vlan10 \
  --boot bios \
  ./my-image.qcow2

# Create a VM with a specific storage class
./harvester-vm.sh \
  -k ~/.kube/harvester.yaml \
  -n my-vm \
  --vm-namespace default \
  --network vlan10 \
  --image-source existing \
  --image-name image-74wx4 \
  --storage-class longhorn-fast

# Destroy only the VM (image is preserved)
./harvester-vm.sh \
  -k ~/.kube/harvester.yaml \
  -n my-vm \
  --vm-namespace default \
  --network vlan10 \
  --image-name image-74wx4 \
  --destroy-vm

# Destroy only the image (VM must already be gone)
./harvester-vm.sh \
  -k ~/.kube/harvester.yaml \
  -n my-vm \
  --vm-namespace default \
  --network vlan10 \
  --image-name image-74wx4 \
  --destroy-image

# Destroy the VM and then the image
./harvester-vm.sh \
  -k ~/.kube/harvester.yaml \
  -n my-vm \
  --vm-namespace default \
  --network vlan10 \
  --image-name image-74wx4 \
  --destroy-all
```

Run `./harvester-vm.sh --help` for all options.

### `harvester-vm.sh` options

| Flag | Default | Description |
|---|---|---|
| `<image-file>` | — | Path to local ISO/raw/qcow2/img file *(upload mode)* |
| `-k`, `--kubeconfig` *(required)* | `$KUBECONFIG` | Path to the Harvester kubeconfig file |
| `-n`, `--vm-name` *(required)* | — | Name for the virtual machine |
| `--vm-namespace` *(required)* | — | Namespace where the VM will be created |
| `--network` *(required)* | — | Existing Harvester network/VLAN name |
| `--image-name` | derived from filename | Kubernetes resource name of the image (required for `existing`/`download`) |
| `--image-source` | auto-detected | Image mode: `upload`, `download`, or `existing` |
| `--image-url` | — | HTTP/HTTPS URL *(download mode)* |
| `--image-namespace` | `harvester-public` | Namespace for the image |
| `--image-display-name` | same as `--image-name` | Human-readable image label *(upload/download modes)* |
| `--network-namespace` | `default` | Namespace of the network |
| `--cpu` | `2` | Number of vCPUs (must be ≥ 1) |
| `--memory` | `4Gi` | RAM — must match `^[0-9]+(Mi\|Gi)$` (e.g. `4Gi`, `2048Mi`) |
| `--disk-size` | `40Gi` | Root disk size — must match `^[0-9]+(Mi\|Gi)$` (e.g. `40Gi`, `100Gi`) |
| `--storage-class` | — | Storage class for the root disk. If not set, uses the cluster default |
| `--count` | `1` | Number of VMs to create. Names are suffixed with the index when > 1 (e.g. `my-vm-0`, `my-vm-1`) |
| `--mac-address` | — | MAC address(es), comma-separated (e.g. `AA:BB:CC:DD:EE:FF` or `AA:BB:CC:DD:EE:01,AA:BB:CC:DD:EE:02`). Positionally matched to VMs; missing entries auto-assign |
| `--boot` | `uefi` | Boot firmware: `uefi` (default) or `bios` |
| `--destroy-vm` | — | Destroy the VM only (image is preserved) |
| `--destroy-image` | — | Destroy the image only (VM must already be gone) |
| `--destroy-all` | — | Destroy the VM first, then the image |
| `--skip-image` | — | Skip the image module; image must already exist |
| `--image-only` | — | Only manage the image; skip the VM module |
| `--image-dir` | `<script-dir>/image` | Path to the image Terraform module |
| `--vm-dir` | `<script-dir>/vm` | Path to the VM Terraform module |
| `--image-tfvars-file` | `<image-dir>/<image-name>-<image-ns>.tfvars` | Path for the image module `.tfvars` file |
| `--vm-tfvars-file` | `<vm-dir>/<vm-name>-<vm-ns>.tfvars` | Path for the VM module `.tfvars` file |
| `--tofu` | — | Use `tofu` instead of `terraform`. Equivalent to `TF_CMD=tofu` |

The script auto-detects which binary to use: it prefers `terraform` if found in `PATH`, then falls back to `tofu`. Override with `--tofu` or `TF_CMD=tofu ./harvester-vm.sh ...`.

Each run writes a `.tfvars` file per module. These are left on disk so you can run `terraform`/`tofu` destroy directly:

```sh
# Destroy only the VM
terraform -chdir=vm destroy -var-file=my-vm-default.tfvars
# or with OpenTofu:
tofu -chdir=vm destroy -var-file=my-vm-default.tfvars

# Destroy only the image
terraform -chdir=image destroy -var-file=image-74wx4-harvester-public.tfvars
```

## Using the modules directly

### Upload mode (local file)

```hcl
# Step 1 — image/
module "image" {
  source = "./terraform-harvester-vm/image"

  kubeconfig_path    = "~/.kube/harvester.yaml"
  image_source       = "upload"
  local_image_path   = "/home/user/images/openSUSE-Leap-15.6.qcow2"
  image_name         = "opensuse-leap-156"
  image_namespace    = "harvester-public"
  image_display_name = "openSUSE Leap 15.6"
}

# Step 2 — vm/
module "vm" {
  source = "./terraform-harvester-vm/vm"

  kubeconfig_path   = "~/.kube/harvester.yaml"
  vm_name           = "my-vm"
  vm_namespace      = "default"
  image_name        = module.image.image_name
  image_namespace   = module.image.image_namespace
  network_name      = "vlan10"
  network_namespace = "default"

  # Optional: specify storage class
  # storage_class_name = "longhorn-fast"
}
```

> **Note:** When running as separate root modules (separate `terraform apply` invocations) you must pass `image_name` and `image_namespace` as variables manually, not via module outputs.

### Download mode (remote URL)

```hcl
module "image" {
  source = "./terraform-harvester-vm/image"

  kubeconfig_path    = "~/.kube/harvester.yaml"
  image_source       = "download"
  image_url          = "https://download.opensuse.org/leap/15.6/openSUSE-Leap-15.6.qcow2"
  image_name         = "opensuse-leap-156"
  image_namespace    = "harvester-public"
  image_display_name = "openSUSE Leap 15.6"
}
```

### Existing image mode

When the image already exists in Harvester, use the `vm/` module directly — no `image/` module needed.

To find the Kubernetes resource name of an existing image:

```sh
kubectl --kubeconfig=<path> get virtualmachineimages.harvesterhci.io -A
```

Use the value in the `NAME` column (e.g. `image-74wx4`), not the display name.

```hcl
module "vm" {
  source = "./terraform-harvester-vm/vm"

  kubeconfig_path   = "~/.kube/harvester.yaml"
  vm_name           = "my-vm"
  vm_namespace      = "default"
  image_name        = "image-74wx4"       # NAME column from kubectl output
  image_namespace   = "harvester-public"
  network_name      = "vlan10"
  network_namespace = "default"

  # Optional: create multiple VMs
  # vm_count      = 3
  # mac_addresses = ["AA:BB:CC:DD:EE:01", "AA:BB:CC:DD:EE:02"]

  # Optional: specify storage class
  # storage_class_name = "longhorn-fast"
}
```

## Input variables

### `image/` module

| Name | Type | Default | Description |
|---|---|---|---|
| `kubeconfig_path` | `string` | — | Path to the Harvester kubeconfig file |
| `image_source` | `string` | — | `"upload"` or `"download"` |
| `image_name` | `string` | — | Kubernetes resource name for the image |
| `image_namespace` | `string` | `"harvester-public"` | Namespace for the image |
| `image_display_name` | `string` | `""` | Human-readable label (defaults to `image_name`) |
| `local_image_path` | `string` | `""` | Absolute path to local image file *(upload only)* |
| `image_url` | `string` | `""` | HTTP/HTTPS URL to pull from *(download only)* |

### `vm/` module

| Name | Type | Default | Description |
|---|---|---|---|
| `kubeconfig_path` | `string` | — | Path to the Harvester kubeconfig file |
| `vm_name` | `string` | — | Name of the virtual machine |
| `vm_namespace` | `string` | `"default"` | Namespace for the VM |
| `image_name` | `string` | — | Kubernetes resource name of the image (must already exist) |
| `image_namespace` | `string` | `"harvester-public"` | Namespace where the image lives |
| `network_name` | `string` | — | Name of the existing Harvester network/VLAN |
| `network_namespace` | `string` | `"default"` | Namespace of the network |
| `cpu` | `number` | `2` | vCPU count (≥ 1) |
| `memory` | `string` | `"4Gi"` | RAM (e.g. `4Gi`, `2048Mi`) |
| `disk_size` | `string` | `"40Gi"` | Root disk size (e.g. `40Gi`, `100Gi`) |
| `storage_class_name` | `string` | `""` | Storage class for the root disk. If not set, uses the cluster default |
| `vm_count` | `number` | `1` | Number of VMs to create. When > 1, names are suffixed with the index (`my-vm-0`, `my-vm-1`, …) |
| `mac_addresses` | `list(string)` | `[]` | MAC addresses for the NICs, one per VM (positional). Missing entries auto-assign. |
| `efi` | `bool` | `true` | Boot with UEFI firmware. Set to `false` for legacy BIOS. |

> **Timeouts:** `harvester_virtualmachine` uses `create = 10m` / `update = 10m` / `delete = 5m`. VM creation involves cloning the root disk from the image and waiting for a DHCP lease (`wait_for_lease = true`), which can take several minutes on a busy cluster.

## Outputs

### `image/` module

| Name | Description |
|---|---|
| `image_id` | Resource ID of the image |
| `image_name` | Kubernetes resource name of the image |
| `image_namespace` | Namespace of the image |
| `image_state` | Current image state (e.g. `Active`) |

### `vm/` module

| Name | Description |
|---|---|
| `vm_names` | Names of the created virtual machines (list) |
| `vm_ids` | Resource IDs of the created virtual machines (list) |
| `image_id` | Resource ID of the image used by the VMs |

## TLS / self-signed certificates

If your Harvester cluster uses a self-signed certificate you will see an error like:

```
tls: failed to verify certificate: x509: certificate is not valid for any names
```

The Harvester Terraform provider has no `insecure` option, so the fix is to patch the kubeconfig before running Terraform. In the `clusters[].cluster` section, remove `certificate-authority-data` and add `insecure-skip-tls-verify: true`:

```yaml
clusters:
  - name: harvester
    cluster:
      server: https://harvester-hpc.example.org
      insecure-skip-tls-verify: true   # add this
      # certificate-authority-data: ...  # remove this
```

Then pass the patched file to `harvester-vm.sh` or the module:

```sh
./harvester-vm.sh -k /path/to/harvester-kubeconfig-insecure.yaml ...
```

> **Security note:** Only use this on trusted networks. TLS verification protects against man-in-the-middle attacks. The proper fix is to add the cluster's CA certificate to your system trust store or to the kubeconfig's `certificate-authority-data`.

## How image upload works

Harvester's `VirtualMachineImage` CRD supports a two-step upload flow:

1. **Create the CRD** — `harvester_image` with `source_type = "upload"` registers the image object and waits for it to reach `Active` state.
2. **Stream the binary** — `terraform_data.upload_image` runs as a `local-exec` provisioner concurrently with step 1. It:
   - Pre-computes the file size with `stat` (not `wc -c` — see below) before the polling loop begins.
   - Polls `GET /v1/harvester/harvesterhci.io.virtualmachineimages/{ns}/{name}` every 1 s (single curl per iteration, HTTP status embedded in the response) until CDI's upload proxy reports `Initialized`.
   - Immediately streams the file via `curl -F "chunk=@<file>;type=application/octet-stream" "...?action=upload&size=<bytes>"` with zero additional delay.

These two operations must run **concurrently**: the CRD must exist before the upload API accepts data, but the CRD only reaches `Active` after the binary is received. There is intentionally **no `depends_on`** between `harvester_image.upload` and `terraform_data.upload_image` — adding one would create a deadlock.

Both `harvester-vm.sh` and direct `terraform`/`tofu apply` invocations follow exactly this path. The script is a pure wrapper that writes `.tfvars` files and calls `terraform apply` (or `tofu apply`); all upload logic lives inside the module.

> **Note:** Upload mode requires a **bearer-token kubeconfig** (as downloaded from the Harvester UI). Client-certificate or exec-plugin kubeconfigs are not supported for upload; use `--image-source download` instead.

### CDI timing sensitivity

CDI starts an internal countdown once the image CRD is created. If no data begins flowing within ~2 minutes of CDI reporting `Initialized`, CDI fails the upload with:

```
timeout waiting for the datasource file processing begin
```

After enough failed attempts CDI marks the image `RetryLimitExceeded`, which is permanent — the image resource must be deleted before a new upload can be attempted.

**Why `stat` instead of `wc -c`:** `wc -c < file` reads every byte of the file on macOS to count them. For a multi-GB image this can take tens of seconds, burning into CDI's countdown window between when `Initialized` is detected and when `curl` starts sending data. `stat` reads the file size from the inode in microseconds. The file size is also pre-computed before the polling loop so the upload starts with zero delay once CDI is ready.

**Why the path, not `filemd5()`, in `triggers_replace`:** `filemd5()` reads the entire image file at apply time when Terraform evaluates `triggers_replace`. For a multi-GB image this blocks `terraform_data.upload_image` from starting for minutes — by which point CDI's countdown has nearly expired and the upload fails immediately. `triggers_replace` uses `var.local_image_path` (the path string) instead. If you replace the file at the same path without changing the path, taint the resource manually: `terraform taint 'terraform_data.upload_image[0]'`.

**Why a single curl per poll iteration:** the previous approach made two sequential requests per iteration (one for the HTTP status code, one for the body). Each is a full TLS handshake. Merging them into one call with `-w '\nHTTPSTATUS:%{http_code}'` halves the overhead; combined with a 1 s sleep (down from 2 s) this cuts the worst-case lag between CDI reporting `Initialized` and the upload starting.

### Debug tracing

To get a full `bash -x` trace of the upload script (useful for diagnosing timing or API issues), set `HARVESTER_UPLOAD_DEBUG=1` before running Terraform — `local-exec` inherits the parent environment automatically:

```sh
HARVESTER_UPLOAD_DEBUG=1 terraform -chdir=image apply -var-file=<your>.tfvars
```

The trace shows every curl invocation with resolved values, HTTP codes, and grep results at each poll iteration.

### Troubleshooting `RetryLimitExceeded`

If `terraform apply` fails with this error, destroy the image and re-apply:

```sh
# Option A — via Terraform (recommended, keeps state clean)
terraform -chdir=image destroy -var-file=<your>.tfvars
terraform -chdir=image apply  -var-file=<your>.tfvars

# Option B — manual delete + taint
kubectl delete virtualmachineimage -n <namespace> <image-name>
terraform -chdir=image taint 'harvester_image.upload[0]'
terraform -chdir=image taint 'terraform_data.upload_image[0]'
terraform -chdir=image apply -var-file=<your>.tfvars
```

To verify the API endpoint and image state before re-applying:

```sh
KUBECONFIG=~/path/to/harvester.yaml
SERVER=$(kubectl --kubeconfig=$KUBECONFIG config view --minify -o jsonpath='{.clusters[0].cluster.server}' \
  | sed 's/:6443//' | grep -oP '^https://[^/]+')
TOKEN=$(kubectl --kubeconfig=$KUBECONFIG config view --minify --raw -o jsonpath='{.users[0].user.token}')

# Check image state
curl -sk -H "Authorization: Bearer $TOKEN" \
  "$SERVER/v1/harvester/harvesterhci.io.virtualmachineimages/<namespace>/<image-name>" \
  | python3 -m json.tool | grep -E '"state"|RetryLimit|Initialized'
```

### Image format and size warnings

`harvester-vm.sh` checks the image file before handing off to Terraform and prints warnings for any of the following conditions:

| Condition | Detection | Recommendation |
|---|---|---|
| **Raw format** | `qemu-img info` (if available), else file extension (`.raw`, `.img`) | Convert to qcow2 |
| **Sparse file** | Logical size > 5× actual disk usage | Convert to qcow2 or dense raw |
| **Large file** | Logical size > 2 GiB | Convert to qcow2 if not already; expect a long upload |

**Raw images** transfer every allocated block. qcow2 stores only the data actually written, typically reducing upload size by 50–90% and avoiding Rancher's nginx reverse-proxy body-size limit (~10 GB).

**Recommended: convert to qcow2 before uploading.** Harvester/KubeVirt supports qcow2 natively:

```sh
qemu-img convert -f raw -O qcow2 image.raw image.qcow2
```

Alternatively, convert to a dense raw file (no zero-block compression, but no sparse holes):

```sh
qemu-img convert -f raw -O raw image.raw image-dense.raw
```

After conversion, pass the new file path to `harvester-vm.sh`.

## Examples

See the [`examples/`](examples/) directory:

- [`examples/local-image/`](examples/local-image/main.tf) — `image/` module, upload mode
- [`examples/url-image/`](examples/url-image/main.tf) — `image/` module, download mode
- [`examples/existing-image/`](examples/existing-image/main.tf) — `vm/` module only, existing image

## License

[MIT](LICENSE)
