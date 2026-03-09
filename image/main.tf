locals {
  # Parse the kubeconfig to extract Harvester API server URL and bearer token.
  # Used by the upload mechanism only; no external YAML tools required.
  kubeconfig       = yamldecode(file(var.kubeconfig_path))
  # The ?action=upload endpoint is on Harvester's own Steve API (https://host/v1/...),
  # NOT the Rancher cluster proxy (https://host/k8s/clusters/local/v1/...).
  # regex() extracts just https://host[:port], stripping both :6443 and any path.
  harvester_server = regex("^https://[^/]+", trimsuffix(local.kubeconfig.clusters[0].cluster.server, ":6443"))
  harvester_token  = local.kubeconfig.users[0].user.token

  image_id = var.image_source == "upload" ? (
    length(harvester_image.upload) > 0 ? harvester_image.upload[0].id : ""
  ) : (
    length(harvester_image.download) > 0 ? harvester_image.download[0].id : ""
  )
}

# ---------------------------------------------------------------------------
# Provider
# ---------------------------------------------------------------------------

provider "harvester" {
  kubeconfig = var.kubeconfig_path
}

# ---------------------------------------------------------------------------
# Image — download path (Harvester pulls from HTTP/HTTPS URL)
# ---------------------------------------------------------------------------

resource "harvester_image" "download" {
  count = var.image_source == "download" ? 1 : 0

  lifecycle {
    precondition {
      condition     = var.image_url != ""
      error_message = "image_url must be set when image_source is 'download'."
    }
    precondition {
      condition     = var.image_display_name != ""
      error_message = "image_display_name must be set when image_source is 'download'."
    }
  }

  name         = var.image_name
  namespace    = var.image_namespace
  display_name = var.image_display_name
  source_type  = "download"
  url          = var.image_url

  timeouts {
    create = "30m"
    read   = "5m"
    update = "10m"
    delete = "5m"
  }
}

# ---------------------------------------------------------------------------
# Image — upload path (CRD only; actual binary is pushed by terraform_data)
# ---------------------------------------------------------------------------

resource "harvester_image" "upload" {
  count = var.image_source == "upload" ? 1 : 0

  lifecycle {
    precondition {
      condition     = var.image_display_name != ""
      error_message = "image_display_name must be set when image_source is 'upload'."
    }
  }

  name         = var.image_name
  namespace    = var.image_namespace
  display_name = var.image_display_name
  source_type  = "upload"

  timeouts {
    create = "60m"
    read   = "5m"
    update = "10m"
    delete = "5m"
  }
}

# ---------------------------------------------------------------------------
# Binary upload — runs CONCURRENTLY with harvester_image.upload (no depends_on).
#
# Terraform runs independent resources in parallel goroutines.
# harvester_image.upload creates the CRD and then blocks waiting for the image
# to reach "Active" state.  This terraform_data resource polls the Harvester
# API until the CRD is visible, then streams the local file as a binary POST.
#
# The only external dependency is `curl`, universally available on Linux/macOS.
# All credentials are extracted by Terraform's yamldecode() above and injected
# as environment variables — no external YAML tools required.
# ---------------------------------------------------------------------------

resource "terraform_data" "upload_image" {
  count = var.image_source == "upload" ? 1 : 0

  # ⚠️ Intentionally NO depends_on harvester_image.upload — must run concurrently.

  lifecycle {
    precondition {
      condition     = var.local_image_path != ""
      error_message = "local_image_path must be set when image_source is 'upload'."
    }
    precondition {
      condition     = var.local_image_path == "" || fileexists(var.local_image_path)
      error_message = "The file specified in local_image_path does not exist: '${var.local_image_path}'."
    }
  }

  triggers_replace = [
    var.local_image_path != "" ? filemd5(var.local_image_path) : "",
    var.image_name,
    var.image_namespace,
  ]

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]

    environment = {
      SERVER     = local.harvester_server
      TOKEN      = local.harvester_token
      NAMESPACE  = var.image_namespace
      IMAGE_NAME = var.image_name
      IMAGE_PATH = var.local_image_path
    }

    command = <<-SHELL
      set -euo pipefail

      # Pre-flight: verify curl is available.
      if ! command -v curl >/dev/null 2>&1; then
        echo "ERROR: 'curl' is required for image upload but was not found in PATH." >&2
        exit 1
      fi

      # Pre-compute file size before the polling loop so the upload can start
      # immediately once CDI is ready. Prefer stat (no file read) over wc -c
      # (wc -c reads the entire file on macOS, burning seconds of CDI's timeout).
      IMAGE_SIZE=$(stat -c%s "$${IMAGE_PATH}" 2>/dev/null || stat -f%z "$${IMAGE_PATH}")

      # Harvester's upload action lives at /v1/harvester/{type}/{ns}/{name}?action=upload
      # (Harvester's own Steve router, pkg/server/router.go), NOT /v1/{type}/... which
      # is Rancher's Steve and does not have Harvester's custom action handlers.
      API_PATH="v1/harvester/harvesterhci.io.virtualmachineimages/$${NAMESPACE}/$${IMAGE_NAME}"

      # Poll until the CRD exists AND CDI upload proxy is initialised.
      # One curl per iteration (fetches body + HTTP code in a single request)
      # avoids the double TLS round-trip of the previous two-curl approach and
      # halves the sleep interval — together this minimises the gap between CDI
      # becoming ready and the upload starting.
      echo "==> Waiting for VirtualMachineImage CRD and CDI upload proxy to be ready..."
      MAX_WAIT=300   # 300 × 1 s = 5 minutes
      i=0
      while true; do
        if [ "$${i}" -ge "$${MAX_WAIT}" ]; then
          echo "ERROR: Timed out waiting for image to become upload-ready after $${MAX_WAIT}s." >&2
          exit 1
        fi

        # Single curl: body followed by a sentinel last line "HTTPSTATUS:<code>".
        RESP_RAW=$(curl -sk -w '\nHTTPSTATUS:%%{http_code}' \
          -H "Authorization: Bearer $${TOKEN}" \
          "$${SERVER}/$${API_PATH}" || true)
        HTTP_CODE=$(echo "$${RESP_RAW}" | grep '^HTTPSTATUS:' | cut -c12-)
        RESP=$(echo "$${RESP_RAW}" | grep -v '^HTTPSTATUS:')

        if [ "$${HTTP_CODE}" = "200" ]; then
          # Detect CDI retry exhaustion — image must be deleted before we can retry.
          if echo "$${RESP}" | grep -q 'RetryLimitExceeded'; then
            echo "ERROR: The image is in a failed state (RetryLimitExceeded)." >&2
            echo "       CDI exhausted its upload retries (usually caused by a previous" >&2
            echo "       interrupted upload). Delete the image resource and re-run:" >&2
            echo "       kubectl delete virtualmachineimage -n $${NAMESPACE} $${IMAGE_NAME}" >&2
            echo "       terraform -chdir=<image-dir> destroy -var-file=<your>.tfvars" >&2
            exit 1
          fi

          # Idempotent: skip if the image was already successfully uploaded.
          if echo "$${RESP}" | grep -q '"state":"Active"'; then
            echo "==> Image is already Active -- skipping upload."
            exit 0
          fi

          # CDI upload proxy is ready once the Initialized condition is present.
          if echo "$${RESP}" | grep -q '"Initialized"'; then
            echo "==> CDI upload proxy is ready."
            break
          fi
        fi

        i=$((i + 1))
        sleep 1
      done

      echo "==> Uploading image file: $${IMAGE_PATH} ($${IMAGE_SIZE} bytes)"
      # Longhorn's backing-image-manager requires:
      #   - ?size=<bytes> query parameter
      #   - multipart/form-data body with the file in field "chunk"
      # IMAGE_SIZE was pre-computed before the polling loop to eliminate any
      # delay between CDI becoming ready and the upload starting.
      CURL_EXIT=0
      HTTP_STATUS=$(curl -k --progress-bar -o /dev/null -w '%%{http_code}' \
        -X POST \
        -H "Authorization: Bearer $${TOKEN}" \
        -F "chunk=@$${IMAGE_PATH};type=application/octet-stream" \
        "$${SERVER}/$${API_PATH}?action=upload&size=$${IMAGE_SIZE}") || CURL_EXIT=$?

      # 2xx → definite success.
      if [ -n "$${HTTP_STATUS}" ] && [ "$${HTTP_STATUS}" -ge 200 ] && [ "$${HTTP_STATUS}" -lt 300 ]; then
        echo "==> Upload complete (HTTP $${HTTP_STATUS})."
        exit 0
      fi

      # curl error or non-2xx: a concurrent upload (e.g. harvester-vm.sh's Python3
      # uploader) may have already made the image Active. Re-check before failing.
      RECHECK=$(curl -sk \
        -H "Authorization: Bearer $${TOKEN}" \
        "$${SERVER}/$${API_PATH}" || true)
      if echo "$${RECHECK}" | grep -q '"state":"Active"'; then
        echo "==> Image became Active via concurrent upload -- skipping."
        exit 0
      fi

      echo "ERROR: Upload failed (curl exit $${CURL_EXIT}, HTTP $${HTTP_STATUS})" >&2
      exit 1
    SHELL
  }
}
