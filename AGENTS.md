# AGENTS.md

Guidelines for AI agents (Copilot, Codex, etc.) working in this repository.

## Repository layout

```
terraform-harvester-vm/
├── image/
│   ├── main.tf       # Image management — provider, harvester_image, terraform_data upload
│   ├── variables.tf  # kubeconfig, image_source (upload|download), image vars
│   ├── outputs.tf    # image_id, image_name, image_namespace, image_state
│   └── versions.tf   # Terraform and provider version constraints
├── vm/
│   ├── main.tf       # VM management — provider, data.harvester_image lookup, harvester_virtualmachine (count-based)
│   ├── variables.tf  # kubeconfig, vm vars, vm_count, mac_addresses, image_name/namespace (no image_source)
│   ├── outputs.tf    # vm_names, vm_ids, image_id
│   └── versions.tf   # Terraform and provider version constraints
├── harvester-vm.sh         # Non-interactive shell wrapper orchestrating both modules
├── assets/           # Project assets (e.g., images for documentation)
├── examples/
│   ├── local-image/  # image/ module, upload mode
│   ├── url-image/    # image/ module, download mode
│   └── existing-image/ # vm/ module only (image already exists)
├── README.md
├── LICENSE
└── AGENTS.md         # This file
```

The two modules have **separate state files** and are applied independently. Destroying the `vm/` module never touches resources owned by the `image/` module.

## How to validate changes

Always run these after editing any `.tf` file:

```sh
# Modules (use tofu or terraform interchangeably)
terraform -chdir=image validate
terraform -chdir=vm validate

# Same with OpenTofu
tofu -chdir=image validate
tofu -chdir=vm validate

# Examples
terraform -chdir=examples/local-image validate
terraform -chdir=examples/url-image validate
terraform -chdir=examples/existing-image validate
```

For `harvester-vm.sh`, check syntax with:

```sh
bash -n harvester-vm.sh
```

There are no automated tests beyond `terraform validate` / `tofu validate` and `bash -n`. Do not add new testing frameworks.

## Key design decisions

### Decoupled modules
`image/` and `vm/` are independent root modules with separate `.terraform/` state directories. This is intentional: `terraform destroy` on `vm/` only destroys the VM. Use `--destroy-image` in `harvester-vm.sh` to also destroy the image explicitly.

### Upload flow

`harvester_image.upload` and `terraform_data.upload_image` run **concurrently** within a single `terraform apply` — there is intentionally **no `depends_on`** between them. Adding one creates a deadlock (each waits for the other to finish first).

`terraform_data.upload_image` is a `local-exec` provisioner that:
1. Pre-computes file size with `stat` (not `wc -c`) **before** the polling loop begins. `wc -c` reads the entire file on macOS; for large images this burns seconds from CDI's countdown window.
2. Polls `GET /v1/harvester/harvesterhci.io.virtualmachineimages/{ns}/{name}` every 1 s using a **single curl per iteration** — HTTP status is embedded via `-w '\nHTTPSTATUS:%{http_code}'` so no second round-trip is needed to fetch the body.
3. Immediately streams the binary via `curl -F "chunk=@<file>;type=application/octet-stream" "...?action=upload&size=<bytes>"` — zero delay between detecting `Initialized` and sending data.
4. After any `curl` failure, rechecks image state — exits 0 if the image is already `Active` (handles 504 gateway timeouts from nginx).

CDI starts an internal countdown once the CRD is created. If no data begins flowing within ~2 minutes of CDI reporting `Initialized`, CDI fails with `timeout waiting for the datasource file processing begin`. After exhausting retries the image is permanently marked `RetryLimitExceeded` and must be deleted before a new upload can be attempted.

`harvester-vm.sh` is a pure Terraform/OpenTofu wrapper: it writes `.tfvars` files and calls `terraform apply` (or `tofu apply`). All upload logic lives inside the module. There is no separate shell-side upload.

### vm/ always uses a data source
The `vm/` module never manages image lifecycle. It always looks up the image via `data "harvester_image" "image"`. There is no `image_source` variable in `vm/`.

### No external YAML tools
Kubeconfig parsing uses `yamldecode(file(var.kubeconfig_path))` — Terraform built-in. Do not introduce `kubectl`, `yq`, or any shell-based YAML parsing.

### `curl` for binary upload
`terraform-provider-restapi` is JSON-only and cannot stream binary files. `curl` is the only viable tool for the `?action=upload` endpoint. Do not attempt to replace it with an HTTP provider.

### Heredoc escaping in `image/main.tf`
Inside `<<-SHELL` heredocs, Terraform template directives are active:
- Shell variables must be written as `$${VAR}` (double `$`)
- `curl` format strings must be written as `%%{http_code}` (double `%`)

Breaking this escaping will cause `terraform validate` / `tofu validate` to fail with `invalid template control keyword`.

### `filemd5()` must not be used in `triggers_replace`

`filemd5(var.local_image_path)` reads the **entire image file** at apply time when Terraform evaluates `triggers_replace`. For a multi-GB image this blocks `terraform_data.upload_image` from starting for minutes — by which point CDI's countdown has nearly expired and the upload fails with `timeout waiting for the datasource file processing begin`.

`triggers_replace` uses `var.local_image_path` (the path string) instead. If the image file is replaced at the same path, taint the resource manually:
```sh
terraform taint 'terraform_data.upload_image[0]'
```

### Plan-time validation
Use `lifecycle.precondition` for cross-variable checks that `variable` validation blocks cannot express (e.g. "field X is required when field Y equals Z"). Preconditions must only reference Terraform-known values — not shell commands or runtime state.

## Conventions

- **Terraform / OpenTofu version** — `>= 1.4` minimum (required for the built-in `terraform_data` resource). Both Terraform and OpenTofu are supported; the modules are compatible with both tools.
- **Provider source** — always use the fully-qualified source `registry.terraform.io/harvester/harvester` in `versions.tf`. OpenTofu expands the bare shorthand `harvester/harvester` to `registry.opentofu.org/harvester/harvester`, which does not host this provider. The explicit path works correctly with both tools.
- **Resource naming** — all Kubernetes resource names must be lowercase alphanumeric + hyphens. Validated by `variable` validation blocks in both `image/variables.tf` and `vm/variables.tf` (regex `^[a-z0-9]([a-z0-9-]*[a-z0-9])?$`). `sanitize_k8s_name()` in `harvester-vm.sh` auto-derives a valid name from the image filename.
- **`image/` image_source** — only `"upload"` and `"download"` are valid. `"existing"` is not a valid value for the `image/` module; when the image already exists, skip the `image/` module entirely.
- **`vm/` has no image_source** — the `vm/` module always looks up the image by name via a data source. Do not add an `image_source` variable to `vm/`.
- **Count-gated resources** — `harvester_image.download` and `harvester_image.upload` are mutually exclusive via `count = var.image_source == "..." ? 1 : 0`. Access them as `harvester_image.upload[0]`.
- **`vm_count` multi-VM** — `harvester_virtualmachine.vm` uses `count = var.vm_count`. When `vm_count = 1` the name is `var.vm_name`; when `> 1` names are `${var.vm_name}-${count.index}`. Outputs `vm_names` and `vm_ids` are always lists (splat `[*]`).
- **`mac_addresses`** — a `list(string)` in `vm/`. Each entry is matched positionally to the VM at that index. The `lifecycle.precondition` rejects lists longer than `vm_count`. Shell script accepts a comma-separated value for `--mac-address`.
- **Network reference format** — `"${namespace}/${name}"`, e.g. `"default/vlan10"`.
- **harvester-vm.sh destroy flags** — `--destroy-vm` (VM only), `--destroy-image` (image only), `--destroy-all` (VM first, then image). Default (no destroy flag) = apply both modules.
- **`--vm-namespace` is required** — no default is provided in `harvester-vm.sh` to prevent accidental deployments into the wrong namespace.
- **`TF_CMD` / `--tofu`** — `harvester-vm.sh` auto-detects the binary: prefers `terraform` if found in `PATH`, falls back to `tofu`. Users can override with `TF_CMD=tofu` env var or the `--tofu` flag. All `terraform -chdir=` calls in the script use `$TF_CMD`.
- **`efi` boot** — `vm/variables.tf` has `efi` (bool, default `true`). `harvester-vm.sh` maps `--boot uefi` → `efi = true` and `--boot bios` → `efi = false`.
- **`storage_class_name`** — `vm/variables.tf` has `storage_class_name` (string, default `""`). When empty or unset, the VM disk uses the cluster's default storage class. `harvester-vm.sh` accepts `--storage-class <name>` to set this value.
- **`harvester-vm.sh` pre-flight validation** — `--cpu`, `--memory`, and `--disk-size` are validated before any Terraform call, mirroring `vm/variables.tf` rules (`cpu >= 1`; memory/disk match `^[0-9]+(Mi|Gi)$`). This produces a clear error message and exits before touching any state.
- **Image format/size warnings in `harvester-vm.sh`** — before handing off to Terraform, the script checks the image file and prints warnings to stderr for: (1) raw format (detected via `qemu-img info` if available, else extension), (2) sparse file (logical > 5× physical), (3) large file (> 2 GiB). All three recommend `qemu-img convert -O qcow2`. These checks run only for `upload` mode during `apply`.
- **No cloud-init, no SSH keys** — out of scope for this module.

## What agents should not do

- Do not merge `image/` and `vm/` back into a single module — the decoupling is intentional.
- Do not add a `depends_on` from `terraform_data.upload_image` to `harvester_image.upload` — this deadlocks (each waits for the other).
- Do not add `image_source` to the `vm/` module — the vm module always uses a data source lookup.
- Do not remove or weaken `lifecycle.precondition` blocks.
- Do not replace the `curl` binary upload with an HTTP/REST provider.
- Do not use `filemd5()` in `triggers_replace` for `terraform_data.upload_image` — it reads the entire image file at apply time and blocks the resource from starting, causing CDI to time out before the upload begins.
- Do not move the `IMAGE_SIZE` computation into the polling loop or after it — it must run before polling so the upload starts with zero delay once CDI is ready.
- Do not revert the polling loop back to two curl calls per iteration (one for HTTP code + one for body) — the single-curl approach with `-w '\nHTTPSTATUS:%{http_code}'` halves overhead and is intentional.
- Do not increase the poll sleep back to 2 s — 1 s is intentional to minimise detection latency for the `Initialized` condition.
- Do not remove or weaken `variable` validation blocks or `lifecycle.precondition` blocks — format and constraint validation lives in the Terraform modules.
- Do not remove the `--cpu` / `--memory` / `--disk-size` pre-flight checks in `harvester-vm.sh` — they mirror `vm/variables.tf` and must stay in sync with it so the script fails fast before touching any state.
- Do not add interactive prompts to `harvester-vm.sh` — it must remain fully non-interactive.
- Do not modify `%%{http_code}` or `$${VAR}` escaping in the heredoc.
- Do not default `--vm-namespace` in `harvester-vm.sh` — it is intentionally required to prevent accidental deployment into the wrong namespace.
- Do not change the `harvester-vm.sh` tfvars mechanism to use individual `-var` flags — the generated `.tfvars` files are intentionally kept on disk for plain `terraform destroy -var-file=...` / `tofu destroy -var-file=...` usage.
- Do not add new providers beyond `harvester/harvester` without a clear reason.
- Do not shorten the provider source `registry.terraform.io/harvester/harvester` back to `harvester/harvester` — the bare shorthand breaks OpenTofu, which resolves it to `registry.opentofu.org/harvester/harvester`.
- Do not flatten `vm_names`/`vm_ids` outputs back to singular values — they are always lists to support `vm_count > 1`.
- Do not remove or reduce the `timeouts` block on `harvester_virtualmachine` — 10 m create/update is required for disk cloning and DHCP lease acquisition.
- Do not remove the image format/size warnings from `harvester-vm.sh` — they prevent silent uploads of multi-GB raw or sparse files that would exhaust CDI or exceed nginx body limits.
