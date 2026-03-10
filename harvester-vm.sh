#!/usr/bin/env bash
# harvester-vm.sh — Provision a Harvester VM via Terraform.
#
# Image management (upload/download) is handled by the image/ module.
# VM creation is handled by the vm/ module.
# Both have independent state files so destroying the VM does not touch the image.
#
# Run with --help for full usage.
set -euo pipefail

# ──────────────────────────────────────────────
# Defaults
# ──────────────────────────────────────────────
KUBECONFIG_PATH="${KUBECONFIG:-}"
VM_NAME=""
VM_NAMESPACE=""
IMAGE_NAME=""
IMAGE_NAMESPACE="harvester-public"
IMAGE_DISPLAY_NAME=""
IMAGE_SOURCE=""         # upload | download | existing  (auto-detected if not set)
IMAGE_URL=""
NETWORK_NAME=""
NETWORK_NAMESPACE="default"
CPU=2
MEMORY="4Gi"
DISK_SIZE="40Gi"
STORAGE_CLASS=""
IMAGE_STORAGE_CLASS=""
VM_COUNT=1
MAC_ADDRESS=""
EFI=true
IMAGE_TF_DIR=""         # default: $SCRIPT_DIR/image
VM_TF_DIR=""            # default: $SCRIPT_DIR/vm
IMAGE_TFVARS_FILE=""    # default: $IMAGE_TF_DIR/<image-name>-<image-namespace>.tfvars
VM_TFVARS_FILE=""       # default: $VM_TF_DIR/<vm-name>-<vm-namespace>.tfvars
DESTROY_VM=false        # destroy VM module only
DESTROY_IMAGE=false     # destroy image module only
DESTROY_ALL=false       # destroy both VM and image modules
SKIP_IMAGE=false        # skip image module; image must already exist
IMAGE_ONLY=false        # only manage image; skip VM module
IMAGE_FILE=""
TF_CMD="${TF_CMD:-}"    # terraform binary: auto-detected if unset (terraform → tofu)

# ──────────────────────────────────────────────
# Helpers
# ──────────────────────────────────────────────
usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS] [<image-file>]

Provisions a VM on Harvester using two independent Terraform modules:
  image/  — manages image lifecycle (upload or download)
  vm/     — manages VM lifecycle (always references image by name)

The modules have separate state files: 'terraform destroy' on the VM module
does NOT destroy the image.

Image mode is auto-detected from the arguments, or set explicitly with --image-source:
  upload   — stream a local file to Harvester   (pass <image-file>)
  download — Harvester pulls image from a URL    (pass --image-url)
  existing — image already in Harvester          (image module is skipped)

REQUIRED (all modes):
  -k, --kubeconfig <path>         Path to the Harvester kubeconfig file.
                                  Defaults to \$KUBECONFIG env var.
  -n, --vm-name <name>            Name of the VM to create.
      --vm-namespace <ns>         Namespace where the VM will be created.
      --network <name>            Name of the existing Harvester network/VLAN.
      --image-name <name>         Kubernetes resource name of the image.
                                  Required for 'existing'/'download'; derived
                                  from filename for 'upload'.
                                  For 'existing': use the NAME column from:
                                    kubectl get virtualmachineimages.harvesterhci.io -A

REQUIRED for 'upload' mode:
  <image-file>                    Path to the local image file to upload.

REQUIRED for 'download' mode:
      --image-url <url>           HTTP/HTTPS URL of the image to download.

OPTIONAL:
      --image-source <mode>       Force image mode: upload, download, or existing.
      --image-namespace <ns>      Namespace for the image.       (default: harvester-public)
      --image-display-name <txt>  Human-readable image label.   (default: same as --image-name)
                                  Not used in 'existing' mode.
      --image-storage-class <nm>  Storage class for the image.  If not set, uses cluster default.
      --network-namespace <ns>    Namespace of the network.     (default: default)
      --cpu <n>                   vCPU count.                   (default: 2)
      --memory <size>             RAM, e.g. 4Gi or 2048Mi.      (default: 4Gi)
      --disk-size <size>          Root disk size, e.g. 40Gi.   (default: 40Gi)
      --storage-class <name>      Storage class for the root disk. If not set, uses cluster default.
      --count <n>                 Number of VMs to create.      (default: 1)
                                  Names are suffixed with the index when >1
                                  (e.g. my-vm-0, my-vm-1, …).
      --mac-address <macs>        MAC address(es) for the NIC(s), comma-separated.
                                  e.g. AA:BB:CC:DD:EE:FF or AA:BB:CC:DD:EE:FF,AA:BB:CC:DD:EE:FE
                                  Positionally matched to VMs; missing entries auto-assign.
      --boot <mode>               Boot firmware: uefi (default) or bios.
      --destroy-vm                Destroy the VM only (image is preserved).
      --destroy-image             Destroy the image only (VM must already be gone).
      --destroy-all               Destroy the VM first, then the image.
      --skip-image                Skip the image module; image must already exist.
      --image-only                Only manage the image; skip the VM module.
      --image-dir <path>          Path to the image Terraform module.
                                  (default: <script-dir>/image)
      --vm-dir <path>             Path to the VM Terraform module.
                                  (default: <script-dir>/vm)
      --image-tfvars-file <path>  Path for the image module .tfvars file.
                                  (default: <image-dir>/<image-name>-<image-ns>.tfvars)
      --vm-tfvars-file <path>     Path for the VM module .tfvars file.
                                  (default: <vm-dir>/<vm-name>-<vm-ns>.tfvars)
      --tofu                      Use 'tofu' instead of 'terraform'.
                                  Equivalent to: TF_CMD=tofu
  -h, --help                      Show this help message.

EXAMPLES:
  # Upload a local image and create a VM
  $(basename "$0") -k ~/.kube/harvester.yaml -n my-vm --vm-namespace default \\
    --network vlan10 ./openSUSE-Leap.qcow2

  # Have Harvester download an image, then create a VM
  $(basename "$0") -k ~/.kube/harvester.yaml -n my-vm --vm-namespace default \\
    --network vlan10 --image-name opensuse-leap \\
    --image-url https://example.com/openSUSE-Leap-15.6.qcow2

  # Create a VM from an image already in Harvester (image module is skipped)
  $(basename "$0") -k ~/.kube/harvester.yaml -n my-vm --vm-namespace default \\
    --network vlan10 --image-source existing --image-name image-74wx4

  # Destroy only the VM (image is preserved)
  $(basename "$0") -k ~/.kube/harvester.yaml -n my-vm --vm-namespace default \\
    --network vlan10 --image-name image-74wx4 --destroy-vm

  # Destroy only the image (VM must already be gone)
  $(basename "$0") -k ~/.kube/harvester.yaml -n my-vm --vm-namespace default \\
    --network vlan10 --image-name image-74wx4 --destroy-image

  # Destroy the VM and then the image
  $(basename "$0") -k ~/.kube/harvester.yaml -n my-vm --vm-namespace default \\
    --network vlan10 --image-name image-74wx4 --destroy-all
EOF
}

die()  { echo "ERROR: $*" >&2; exit 1; }
info() { echo "==> $*"; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "'$1' is required but not found in PATH."
}

sanitize_k8s_name() {
  local raw="$1"
  echo "$raw" \
    | tr '[:upper:]' '[:lower:]' \
    | sed 's/[^a-z0-9]/-/g; s/^-\+//; s/-\+$//' \
    | cut -c1-63
}

# ──────────────────────────────────────────────
# Parse arguments
# ──────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)               usage; exit 0 ;;
    -k|--kubeconfig)         KUBECONFIG_PATH="$2"; shift 2 ;;
    -n|--vm-name)            VM_NAME="$2"; shift 2 ;;
    --vm-namespace)          VM_NAMESPACE="$2"; shift 2 ;;
    --image-source)          IMAGE_SOURCE="$2"; shift 2 ;;
    --image-url)             IMAGE_URL="$2"; shift 2 ;;
    --image-name)            IMAGE_NAME="$2"; shift 2 ;;
    --image-namespace)       IMAGE_NAMESPACE="$2"; shift 2 ;;
    --image-display-name)    IMAGE_DISPLAY_NAME="$2"; shift 2 ;;
    --image-storage-class)   IMAGE_STORAGE_CLASS="$2"; shift 2 ;;
    --network)               NETWORK_NAME="$2"; shift 2 ;;
    --network-namespace)     NETWORK_NAMESPACE="$2"; shift 2 ;;
    --cpu)                   CPU="$2"; shift 2 ;;
    --memory)                MEMORY="$2"; shift 2 ;;
    --disk-size)             DISK_SIZE="$2"; shift 2 ;;
    --storage-class)         STORAGE_CLASS="$2"; shift 2 ;;
    --count)                 VM_COUNT="$2"; shift 2 ;;
    --mac-address)           MAC_ADDRESS="$2"; shift 2 ;;
    --boot)
      case "$2" in
        uefi) EFI=true ;;
        bios) EFI=false ;;
        *) die "--boot must be 'uefi' or 'bios', got: '$2'" ;;
      esac
      shift 2 ;;
    --destroy-vm)            DESTROY_VM=true; shift ;;
    --destroy-image)         DESTROY_IMAGE=true; shift ;;
    --destroy-all)           DESTROY_ALL=true; shift ;;
    --skip-image)            SKIP_IMAGE=true; shift ;;
    --image-only)            IMAGE_ONLY=true; shift ;;
    --image-dir)             IMAGE_TF_DIR="$2"; shift 2 ;;
    --vm-dir)                VM_TF_DIR="$2"; shift 2 ;;
    --image-tfvars-file)     IMAGE_TFVARS_FILE="$2"; shift 2 ;;
    --vm-tfvars-file)        VM_TFVARS_FILE="$2"; shift 2 ;;
    --tofu)                  TF_CMD=tofu; shift ;;
    --)                      shift; break ;;
    -*)                      die "Unknown option: $1. Run with --help for usage." ;;
    *)
      [[ -z "$IMAGE_FILE" ]] || die "Unexpected positional argument: '$1' (image file already set to '$IMAGE_FILE')"
      IMAGE_FILE="$1"
      shift
      ;;
  esac
done

# ──────────────────────────────────────────────
# Resolve module directories
# ──────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE_TF_DIR="${IMAGE_TF_DIR:-$SCRIPT_DIR/image}"
VM_TF_DIR="${VM_TF_DIR:-$SCRIPT_DIR/vm}"

# ──────────────────────────────────────────────
# Prerequisite binaries
# ──────────────────────────────────────────────
if [[ -z "$TF_CMD" ]]; then
  if command -v terraform >/dev/null 2>&1; then
    TF_CMD=terraform
  elif command -v tofu >/dev/null 2>&1; then
    TF_CMD=tofu
  else
    die "Neither 'terraform' nor 'tofu' found in PATH. Install one or set TF_CMD."
  fi
fi
require_cmd "$TF_CMD"

# ──────────────────────────────────────────────
# Auto-detect image source if not explicitly set
# ──────────────────────────────────────────────
if [[ -z "$IMAGE_SOURCE" ]]; then
  if [[ -n "$IMAGE_FILE" ]]; then
    IMAGE_SOURCE="upload"
  elif [[ -n "$IMAGE_URL" ]]; then
    IMAGE_SOURCE="download"
  else
    IMAGE_SOURCE="existing"
  fi
fi

case "$IMAGE_SOURCE" in
  upload|download|existing) ;;
  *) die "--image-source must be 'upload', 'download', or 'existing', got: '$IMAGE_SOURCE'" ;;
esac

# 'existing' mode always skips the image module.
[[ "$IMAGE_SOURCE" == "existing" ]] && SKIP_IMAGE=true

# ──────────────────────────────────────────────
# Validate required inputs (collect all errors, then fail once)
# ──────────────────────────────────────────────
ERRORS=()

[[ -n "$KUBECONFIG_PATH" ]] || ERRORS+=("--kubeconfig (or \$KUBECONFIG env var) is required.")
[[ -n "$VM_NAME" ]]         || ERRORS+=("--vm-name is required.")
[[ -n "$VM_NAMESPACE" ]]    || ERRORS+=("--vm-namespace is required.")
[[ -n "$NETWORK_NAME" ]]    || ERRORS+=("--network is required.")

# Validate resource sizing — mirror the regex used by vm/variables.tf so the
# script fails fast with a clear message rather than letting Terraform catch it.
[[ "$CPU" =~ ^[1-9][0-9]*$ ]]            || ERRORS+=("--cpu must be a positive integer, got: '$CPU'")
[[ "$MEMORY"    =~ ^[0-9]+(Mi|Gi)$ ]]    || ERRORS+=("--memory must be a value like '4Gi' or '2048Mi', got: '$MEMORY'")
[[ "$DISK_SIZE" =~ ^[0-9]+(Mi|Gi)$ ]]    || ERRORS+=("--disk-size must be a value like '40Gi' or '100Gi', got: '$DISK_SIZE'")

case "$IMAGE_SOURCE" in
  upload)
    [[ -n "$IMAGE_FILE" ]] || ERRORS+=("An image file path is required for 'upload' mode.")
    ;;
  download)
    [[ -n "$IMAGE_URL" ]]  || ERRORS+=("--image-url is required for 'download' mode.")
    [[ -n "$IMAGE_NAME" ]] || ERRORS+=("--image-name is required for 'download' mode.")
    ;;
  existing)
    [[ -n "$IMAGE_NAME" ]] || ERRORS+=("--image-name is required for 'existing' mode.")
    ;;
esac

if [[ ${#ERRORS[@]} -gt 0 ]]; then
  for e in "${ERRORS[@]}"; do echo "ERROR: $e" >&2; done
  echo "" >&2
  echo "Run $(basename "$0") --help for usage." >&2
  exit 1
fi

# Mode-specific setup (name derivation, curl prerequisite)
case "$IMAGE_SOURCE" in
  upload)
    require_cmd curl
    BASENAME="$(basename "$IMAGE_FILE")"
    STEM="${BASENAME%.*}"
    if [[ -z "$IMAGE_NAME" ]]; then
      IMAGE_NAME="$(sanitize_k8s_name "$STEM")"
      [[ -n "$IMAGE_NAME" ]] || die "Could not derive a valid Kubernetes name from filename '$BASENAME'. Use --image-name."
    fi
    IMAGE_DISPLAY_NAME="${IMAGE_DISPLAY_NAME:-$IMAGE_NAME}"
    ;;
  download)
    IMAGE_DISPLAY_NAME="${IMAGE_DISPLAY_NAME:-$IMAGE_NAME}"
    ;;
esac

# Resolve and verify file paths
if [[ "$IMAGE_SOURCE" == "upload" ]]; then
  IMAGE_FILE="$(cd "$(dirname "$IMAGE_FILE")" 2>/dev/null && pwd)/$(basename "$IMAGE_FILE")" \
    || die "Cannot resolve path for image file: '$IMAGE_FILE'"
  [[ -f "$IMAGE_FILE" ]] || die "Image file not found: '$IMAGE_FILE'"
  [[ -r "$IMAGE_FILE" ]] || die "Image file is not readable: '$IMAGE_FILE'"
fi

KUBECONFIG_PATH="$(cd "$(dirname "$KUBECONFIG_PATH")" 2>/dev/null && pwd)/$(basename "$KUBECONFIG_PATH")" \
  || die "Cannot resolve path for kubeconfig: '$KUBECONFIG_PATH'"
[[ -f "$KUBECONFIG_PATH" ]] || die "Kubeconfig file not found: '$KUBECONFIG_PATH'"
[[ -r "$KUBECONFIG_PATH" ]] || die "Kubeconfig file is not readable: '$KUBECONFIG_PATH'"

# Validate module directories
[[ "$IMAGE_ONLY" == "true" || "$SKIP_IMAGE" == "true" ]] || \
  { [[ -d "$IMAGE_TF_DIR" ]] || die "Image module directory not found: '$IMAGE_TF_DIR'"; }
[[ "$IMAGE_ONLY" == "true" ]] || \
  { [[ -d "$VM_TF_DIR" ]] || die "VM module directory not found: '$VM_TF_DIR'"; }

# Default tfvars paths (resolved after all names are known)
IMAGE_TFVARS_FILE="${IMAGE_TFVARS_FILE:-${IMAGE_TF_DIR}/${IMAGE_NAME}-${IMAGE_NAMESPACE}.tfvars}"
VM_TFVARS_FILE="${VM_TFVARS_FILE:-${VM_TF_DIR}/${VM_NAME}-${VM_NAMESPACE}.tfvars}"

# ──────────────────────────────────────────────
# Summary
# ──────────────────────────────────────────────
info "Image source     : $IMAGE_SOURCE"
info "Kubeconfig       : $KUBECONFIG_PATH"
case "$IMAGE_SOURCE" in
  upload)   info "Image file       : $IMAGE_FILE  ($(du -sh "$IMAGE_FILE" | cut -f1))" ;;
  download) info "Image URL        : $IMAGE_URL" ;;
esac
info "Image            : $IMAGE_NAMESPACE/$IMAGE_NAME"
info "VM               : $VM_NAMESPACE/$VM_NAME  (count: $VM_COUNT)"
info "Network          : $NETWORK_NAMESPACE/$NETWORK_NAME"
info "Resources        : ${CPU} vCPU, ${MEMORY} RAM, ${DISK_SIZE} disk"
echo ""

# ──────────────────────────────────────────────
# Helper: run terraform init + apply/destroy for a module
# ──────────────────────────────────────────────
tf_apply() {
  local module_dir="$1" tfvars="$2"
  info "[$module_dir] $TF_CMD init"
  "$TF_CMD" -chdir="$module_dir" init -upgrade -input=false
  info "[$module_dir] $TF_CMD apply"
  "$TF_CMD" -chdir="$module_dir" apply -auto-approve -input=false -var-file="$tfvars"
}

tf_destroy() {
  local module_dir="$1" tfvars="$2"
  info "[$module_dir] $TF_CMD init"
  "$TF_CMD" -chdir="$module_dir" init -upgrade -input=false
  info "[$module_dir] $TF_CMD destroy"
  "$TF_CMD" -chdir="$module_dir" destroy -auto-approve -input=false -var-file="$tfvars"
}

# ──────────────────────────────────────────────
# Image module
# ──────────────────────────────────────────────
run_image_module() {
  local action="$1"   # apply | destroy

  # Write image tfvars
  cat > "$IMAGE_TFVARS_FILE" <<TFVARS
# Generated by harvester-vm.sh — do not edit by hand.
kubeconfig_path    = "${KUBECONFIG_PATH}"
image_source       = "${IMAGE_SOURCE}"
image_name         = "${IMAGE_NAME}"
image_namespace    = "${IMAGE_NAMESPACE}"
image_display_name = "${IMAGE_DISPLAY_NAME}"
storage_class_name = "${IMAGE_STORAGE_CLASS}"
TFVARS

  case "$IMAGE_SOURCE" in
    upload)
      cat >> "$IMAGE_TFVARS_FILE" <<TFVARS
local_image_path   = "${IMAGE_FILE}"
TFVARS
      ;;
    download)
      cat >> "$IMAGE_TFVARS_FILE" <<TFVARS
image_url          = "${IMAGE_URL}"
TFVARS
      ;;
  esac

  info "Image tfvars saved to $IMAGE_TFVARS_FILE"

  if [[ "$action" == "apply" && "$IMAGE_SOURCE" == "upload" ]]; then
    local logical_size disk_size_bytes image_format=""
    logical_size=$(stat -c %s "$IMAGE_FILE" 2>/dev/null || stat -f %z "$IMAGE_FILE" 2>/dev/null || echo 0)
    disk_size_bytes=$(du -b "$IMAGE_FILE" 2>/dev/null | cut -f1 || echo 0)
    local outbase="${IMAGE_FILE%.*}"

    # Detect image format: prefer qemu-img (authoritative), fall back to extension.
    if command -v qemu-img &>/dev/null; then
      image_format=$(qemu-img info "$IMAGE_FILE" 2>/dev/null | awk '/^file format:/{print $3}')
    fi
    if [[ -z "$image_format" ]]; then
      case "${IMAGE_FILE,,}" in
        *.raw|*.img) image_format="raw"   ;;
        *.qcow2)     image_format="qcow2" ;;
        *.vmdk)      image_format="vmdk"  ;;
      esac
    fi

    # Warn: raw format — qcow2 stores only allocated blocks and uploads much faster.
    if [[ "$image_format" == "raw" ]]; then
      echo "" >&2
      echo "WARNING: $IMAGE_FILE is a raw disk image." >&2
      echo "         Raw images transfer every allocated block; qcow2 stores only" >&2
      echo "         the data actually written, typically reducing upload size by" >&2
      echo "         50-90% and avoiding reverse-proxy body-size limits." >&2
      echo "         Convert before uploading (Harvester/KubeVirt supports qcow2 natively):" >&2
      echo "           qemu-img convert -f raw -O qcow2 ${IMAGE_FILE} ${outbase}.qcow2" >&2
      echo "" >&2
    fi

    # Warn: sparse file (logical size >> physical disk usage).
    if [[ "$disk_size_bytes" -gt 0 && "$logical_size" -gt $((disk_size_bytes * 5)) ]]; then
      echo "" >&2
      echo "WARNING: $IMAGE_FILE is a sparse file." >&2
      echo "         Logical size : $((logical_size / 1024 / 1024)) MB" >&2
      echo "         Disk usage   : $((disk_size_bytes / 1024 / 1024)) MB" >&2
      echo "         Uploading the full logical size may exceed reverse-proxy body limits" >&2
      echo "         and is much slower than necessary." >&2
      echo "         Convert to qcow2 first (recommended — stores only allocated blocks):" >&2
      echo "           qemu-img convert -f raw -O qcow2 ${IMAGE_FILE} ${outbase}.qcow2" >&2
      echo "         Or convert to a dense raw file:" >&2
      echo "           qemu-img convert -f raw -O raw  ${IMAGE_FILE} ${outbase}-dense.raw" >&2
      echo "" >&2
    fi

    # Warn: large file (> 2 GiB) — upload will take several minutes.
    local large_threshold=$(( 2 * 1024 * 1024 * 1024 ))
    if [[ "$logical_size" -gt "$large_threshold" ]]; then
      local size_gib=$(( logical_size / 1024 / 1024 / 1024 ))
      echo "" >&2
      echo "WARNING: Image is large (${size_gib} GiB). Upload may take several minutes" >&2
      echo "         depending on your network bandwidth to the Harvester cluster." >&2
      if [[ "$image_format" != "qcow2" ]]; then
        echo "         Converting to qcow2 before uploading is strongly recommended" >&2
        echo "         to reduce the upload size:" >&2
        echo "           qemu-img convert -O qcow2 ${IMAGE_FILE} ${outbase}.qcow2" >&2
      fi
      echo "" >&2
    fi
  fi

  if [[ "$action" == "apply" ]]; then
    tf_apply "$IMAGE_TF_DIR" "$IMAGE_TFVARS_FILE"
  else
    tf_destroy "$IMAGE_TF_DIR" "$IMAGE_TFVARS_FILE"
  fi
}

# ──────────────────────────────────────────────
# VM module
# ──────────────────────────────────────────────
run_vm_module() {
  local action="$1"   # apply | destroy

  # Convert comma-separated MAC_ADDRESS into a Terraform list literal.
  local mac_tf_list='[]'
  if [[ -n "$MAC_ADDRESS" ]]; then
    IFS=',' read -ra _macs <<< "$MAC_ADDRESS"
    mac_tf_list='['
    for _m in "${_macs[@]}"; do
      mac_tf_list+="\"${_m}\","
    done
    mac_tf_list="${mac_tf_list%,}]"
    unset _macs _m
  fi

  # Write VM tfvars
  cat > "$VM_TFVARS_FILE" <<TFVARS
# Generated by harvester-vm.sh — do not edit by hand.
kubeconfig_path    = "${KUBECONFIG_PATH}"
vm_name            = "${VM_NAME}"
vm_namespace       = "${VM_NAMESPACE}"
image_name         = "${IMAGE_NAME}"
image_namespace    = "${IMAGE_NAMESPACE}"
network_name       = "${NETWORK_NAME}"
network_namespace  = "${NETWORK_NAMESPACE}"
cpu                = ${CPU}
memory             = "${MEMORY}"
disk_size          = "${DISK_SIZE}"
storage_class_name = "${STORAGE_CLASS}"
vm_count           = ${VM_COUNT}
mac_addresses      = ${mac_tf_list}
efi                = ${EFI}
TFVARS

  info "VM tfvars saved to $VM_TFVARS_FILE"

  if [[ "$action" == "apply" ]]; then
    tf_apply "$VM_TF_DIR" "$VM_TFVARS_FILE"
  else
    tf_destroy "$VM_TF_DIR" "$VM_TFVARS_FILE"
  fi
}

# ──────────────────────────────────────────────
# Orchestrate
# ──────────────────────────────────────────────
if [[ "$DESTROY_VM" == "true" ]]; then
  run_vm_module destroy

elif [[ "$DESTROY_IMAGE" == "true" ]]; then
  [[ "$SKIP_IMAGE" != "true" ]] && run_image_module destroy

elif [[ "$DESTROY_ALL" == "true" ]]; then
  # Destroy VM first so it's not referencing the image, then destroy the image
  run_vm_module destroy
  [[ "$SKIP_IMAGE" != "true" ]] && run_image_module destroy

else
  # Apply image module first (unless skipped or existing)
  [[ "$SKIP_IMAGE" != "true" ]] && run_image_module apply

  # Apply VM module (unless --image-only)
  [[ "$IMAGE_ONLY" != "true" ]] && run_vm_module apply
fi

info "Done."
