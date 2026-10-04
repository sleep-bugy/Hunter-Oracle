#!/usr/bin/env bash
set -u
export PATH="$HOME/.local/bin:$HOME/lib/oracle-cli/bin:/usr/local/bin:$PATH"
export SUPPRESS_LABEL_WARNING=True

# ==============================================================================
# Oracle Ampere A1 Always Free Autopilot Hunter
# ==============================================================================
#
# Automatically captures an Oracle Cloud Ampere A1 (ARM64) instance by continuously
# polling the OCI API until host capacity becomes available.
#
# Available Modes:
#   MODE=1 : 2 OCPU / 12 GB RAM  (Balanced single VM)
#   MODE=2 : 1 OCPU / 6 GB RAM   (Allows launching up to 2 separate Always Free VMs)
#   MODE=3 : 4 OCPU / 24 GB RAM  (Maximum single VM capacity for Always Free tier)
#
# ==============================================================================

# ------------------------------------------------------------------------------
# REQUIRED CONFIGURATION (Replace with your Oracle Cloud details)
# ------------------------------------------------------------------------------
COMPARTMENT_ID="YOUR_COMPARTMENT_OR_TENANCY_OCID"
SUBNET_ID="YOUR_PUBLIC_SUBNET_OCID"

MODE=1
INSTANCE_NAME="oracle-a1-autopilot"

# Path to your SSH public key for instance access
SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_ed25519.pub}"

# ------------------------------------------------------------------------------
# OPTIONAL CONFIGURATION
# ------------------------------------------------------------------------------
# Telegram notifications upon successful instance capture
TELEGRAM_BOT_TOKEN=""
# Target Chat ID(s). Supports a single ID or multiple IDs separated by spaces/commas:
# Example: TELEGRAM_CHAT_ID="123456789 -12345678765432"
TELEGRAM_CHAT_ID=""
# Optional Telegram Topic / Message Thread ID (for Supergroups with Forum Topics enabled)
TELEGRAM_TOPIC_ID=""

# Polling interval in seconds (default: 20s to avoid API rate limits)
RETRY_SECONDS=20

# Optional custom image OCID. If left empty, automatically detects the latest
# Ubuntu Minimal ARM (Ubuntu 24.04 Minimal -> Ubuntu 22.04 Minimal)
CUSTOM_IMAGE_ID=""

# ==============================================================================
# SCRIPT LOGIC
# ==============================================================================

log() {
    printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

notify() {
    [[ -z "$TELEGRAM_BOT_TOKEN" ]] && return 0
    [[ -z "$TELEGRAM_CHAT_ID" ]] && return 0

    # Parse space/comma separated chat IDs
    local targets=(${TELEGRAM_CHAT_ID//,/ })
    for target in "${targets[@]}"; do
        [[ -z "$target" ]] && continue
        local extra_args=()
        # Include topic ID if target is a supergroup/channel (starts with -) and topic is set
        if [[ "$target" == -* && -n "${TELEGRAM_TOPIC_ID:-}" ]]; then
            extra_args+=(--data-urlencode "message_thread_id=${TELEGRAM_TOPIC_ID}")
        fi

        curl -fsS -X POST \
            "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
            --data-urlencode "chat_id=${target}" \
            "${extra_args[@]}" \
            --data-urlencode "parse_mode=HTML" \
            --data-urlencode "text=$1" >/dev/null 2>&1 || true
    done
}

die() {
    log "ERROR: $*"
    exit 1
}

# Prerequisites check
command -v oci >/dev/null 2>&1 || die "OCI CLI is not installed or not in PATH."
command -v curl >/dev/null 2>&1 || die "curl is not installed."

[[ "$COMPARTMENT_ID" != YOUR_* ]] || die "Please configure COMPARTMENT_ID in $(basename "$0")."
[[ "$SUBNET_ID" != YOUR_* ]] || die "Please configure SUBNET_ID in $(basename "$0")."
[[ -f "$SSH_KEY" ]] || die "SSH public key not found: $SSH_KEY"

# Allocate OCPU and Memory according to selected mode
case "$MODE" in
    1) OCPUS=2; MEMORY=12 ;;
    2) OCPUS=1; MEMORY=6 ;;
    3) OCPUS=4; MEMORY=24 ;;
    *) die "Invalid MODE '$MODE'. Choose 1, 2, or 3." ;;
esac

existing_instance() {
    oci compute instance list \
        --compartment-id "$COMPARTMENT_ID" \
        --display-name "$INSTANCE_NAME" \
        --all \
        --query 'data[?contains(`RUNNING,PROVISIONING,STARTING,STOPPED`, `"lifecycle-state"`)].id | [0]' \
        --raw-output 2>/dev/null
}

log "Checking for existing instance..."
EXISTING="$(existing_instance || true)"
if [[ -n "$EXISTING" && "$EXISTING" != "null" ]]; then
    log "Instance already exists: $EXISTING"
    notify "<b>Oracle A1 Autopilot</b>%0AInstance already exists.%0A<b>OCID:</b> <code>$EXISTING</code>"
    exit 0
fi

log "Fetching Availability Domains..."
ADS=( $(oci iam availability-domain list --compartment-id "$COMPARTMENT_ID" --query "data[].name" --raw-output 2>/dev/null | grep -oE '[A-Za-z0-9:-]+' | grep ':') )

[[ "${#ADS[@]}" -gt 0 ]] || die "Could not retrieve Availability Domains. Check your OCI credentials."
log "Availability Domains found: ${ADS[*]}"

# Resolve Ubuntu Minimal ARM Image
if [[ -n "$CUSTOM_IMAGE_ID" ]]; then
    IMAGE_ID="$CUSTOM_IMAGE_ID"
    IMAGE_NAME="Custom Image ($IMAGE_ID)"
else
    log "Searching for Ubuntu 24.04 Minimal ARM image..."
    IMAGE_INFO="$(
        oci compute image list \
            --compartment-id "$COMPARTMENT_ID" \
            --operating-system "Canonical Ubuntu" \
            --shape "VM.Standard.A1.Flex" \
            --query "data[?starts_with(\"display-name\", \`Canonical-Ubuntu-24.04-Minimal-aarch64\`)].[id, \"display-name\"] | [0]" \
            --raw-output 2>/dev/null || true
    )"

    if [[ -z "$IMAGE_INFO" || "$IMAGE_INFO" == "null" || "$IMAGE_INFO" == "[]" ]]; then
        log "Ubuntu 24.04 Minimal not found, falling back to Ubuntu 22.04 Minimal..."
        IMAGE_INFO="$(
            oci compute image list \
                --compartment-id "$COMPARTMENT_ID" \
                --operating-system "Canonical Ubuntu" \
                --shape "VM.Standard.A1.Flex" \
                --query "data[?starts_with(\"display-name\", \`Canonical-Ubuntu-22.04-Minimal-aarch64\`)].[id, \"display-name\"] | [0]" \
                --raw-output 2>/dev/null || true
        )"
    fi

    if [[ -z "$IMAGE_INFO" || "$IMAGE_INFO" == "null" || "$IMAGE_INFO" == "[]" ]]; then
        log "Falling back to any available Ubuntu Minimal ARM image..."
        IMAGE_INFO="$(
            oci compute image list \
                --compartment-id "$COMPARTMENT_ID" \
                --operating-system "Canonical Ubuntu" \
                --shape "VM.Standard.A1.Flex" \
                --query "data[?contains(\"display-name\", \`Minimal-aarch64\`)].[id, \"display-name\"] | [0]" \
                --raw-output 2>/dev/null || true
        )"
    fi

    IMAGE_ID="$(echo "$IMAGE_INFO" | grep -oE 'ocid1\.image\.[a-zA-Z0-9._-]+' | head -n 1 || true)"
    IMAGE_NAME="$(echo "$IMAGE_INFO" | grep -oE 'Canonical-Ubuntu-[a-zA-Z0-9._-]+' | head -n 1 || true)"
fi

[[ -n "$IMAGE_ID" && "$IMAGE_ID" != "null" ]] || die "Unable to find an Ubuntu Minimal ARM image for VM.Standard.A1.Flex."
log "Selected OS Image: ${IMAGE_NAME:-Ubuntu Minimal ARM} ($IMAGE_ID)"

log "=================================================="
log "Oracle A1 Always Free Autopilot Started"
log "Shape   : VM.Standard.A1.Flex"
log "RAM     : ${MEMORY} GB"
log "OCPU    : ${OCPUS}"
log "OS      : ${IMAGE_NAME:-Ubuntu Minimal ARM}"
log "ADs     : ${ADS[*]}"
log "=================================================="

ATTEMPT=0

while true; do
    EXISTING="$(existing_instance || true)"
    if [[ -n "$EXISTING" && "$EXISTING" != "null" ]]; then
        log "SUCCESS: Instance detected: $EXISTING"
        notify "🚀 <b>Oracle A1 Instance Created!</b>%0A%0A<b>Instance:</b> $INSTANCE_NAME%0A<b>OCID:</b> <code>$EXISTING</code>%0A<b>Resources:</b> ${OCPUS} OCPU / ${MEMORY} GB RAM%0A<b>OS:</b> ${IMAGE_NAME:-Ubuntu Minimal}"
        exit 0
    fi

    for AD in "${ADS[@]}"; do
        ATTEMPT=$((ATTEMPT + 1))
        OUTPUT_FILE="/tmp/oracle-a1-${$}-${ATTEMPT}.log"

        log "Attempt #$ATTEMPT | AD=$AD | ${OCPUS} OCPU / ${MEMORY} GB RAM"

        if oci compute instance launch \
            --compartment-id "$COMPARTMENT_ID" \
            --availability-domain "$AD" \
            --subnet-id "$SUBNET_ID" \
            --shape "VM.Standard.A1.Flex" \
            --shape-config "{\"ocpus\":${OCPUS},\"memoryInGBs\":${MEMORY}}" \
            --image-id "$IMAGE_ID" \
            --display-name "$INSTANCE_NAME" \
            --ssh-authorized-keys-file "$SSH_KEY" \
            --assign-public-ip true \
            --freeform-tags '{"CreatedBy":"Oracle-A1-Autopilot"}' \
            >"$OUTPUT_FILE" 2>&1; then

            INSTANCE_ID="$(grep -oE 'ocid1.instance[^"]+' "$OUTPUT_FILE" | head -1 || true)"

            log "🎉 SUCCESS! Instance launched successfully."
            [[ -n "$INSTANCE_ID" ]] && log "Instance OCID: $INSTANCE_ID"
            notify "🚀 <b>Oracle A1 Instance Created Successfully!</b>%0A%0A<b>Instance:</b> $INSTANCE_NAME%0A<b>OCID:</b> <code>${INSTANCE_ID:-Check OCI Console}</code>%0A<b>Resources:</b> ${OCPUS} OCPU / ${MEMORY} GB RAM%0A<b>OS:</b> ${IMAGE_NAME:-Ubuntu Minimal}%0A<b>Availability Domain:</b> $AD"

            rm -f "$OUTPUT_FILE"
            exit 0
        fi

        if grep -qiE 'TooManyRequests|429' "$OUTPUT_FILE"; then
            log "Rate limited by OCI API (429 TooManyRequests) → Cooling down for 60 seconds..."
            rm -f "$OUTPUT_FILE"
            sleep 60
            continue
        elif grep -qiE 'out.of.host.capacity|outofhostcapacity|capacity' "$OUTPUT_FILE"; then
            log "Host capacity exhausted in $AD → Retrying in ${RETRY_SECONDS}s..."
        else
            log "Request rejected (non-capacity error):"
            tail -n 12 "$OUTPUT_FILE"
        fi

        rm -f "$OUTPUT_FILE"
        sleep "$RETRY_SECONDS"
    done

    log "Completed sweep across all Availability Domains. Next cycle in ${RETRY_SECONDS}s..."
    sleep "$RETRY_SECONDS"
done
