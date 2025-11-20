#!/bin/bash

################################################################################
# Notifications Library - Multi-channel notification system
# Version: 1.0.0
#
# This library provides a unified interface for sending notifications through:
# - Desktop notifications (notify-send)
# - Email (mail/sendmail)
# - System logs (logger)
# - Webhooks (Slack, Discord, etc.)
# - Push notifications (Pushover, Pushbullet)
################################################################################

# Prevent multiple sourcing
[[ -n "$_ABS_NOTIFICATIONS_LOADED" ]] && return 0
readonly _ABS_NOTIFICATIONS_LOADED=1

# Source common library
source "${ABS_LIB_DIR:-$(dirname "${BASH_SOURCE[0]}")}/common.sh"

################################################################################
# Configuration
################################################################################

# Notification channels
NOTIFY_DESKTOP="${NOTIFY_DESKTOP:-true}"
NOTIFY_EMAIL="${NOTIFY_EMAIL:-false}"
NOTIFY_SYSLOG="${NOTIFY_SYSLOG:-true}"
NOTIFY_WEBHOOK="${NOTIFY_WEBHOOK:-false}"
NOTIFY_PUSH="${NOTIFY_PUSH:-false}"

# Email configuration
NOTIFY_EMAIL_TO="${NOTIFY_EMAIL_TO:-}"
NOTIFY_EMAIL_FROM="${NOTIFY_EMAIL_FROM:-awesome-bash-scripts@$(hostname)}"
NOTIFY_EMAIL_SUBJECT_PREFIX="${NOTIFY_EMAIL_SUBJECT_PREFIX:-[ABS]}"

# Webhook configuration
NOTIFY_WEBHOOK_URL="${NOTIFY_WEBHOOK_URL:-}"
NOTIFY_WEBHOOK_TYPE="${NOTIFY_WEBHOOK_TYPE:-slack}"  # slack, discord, teams, custom

# Push notification configuration
NOTIFY_PUSH_SERVICE="${NOTIFY_PUSH_SERVICE:-pushover}"  # pushover, pushbullet
NOTIFY_PUSH_TOKEN="${NOTIFY_PUSH_TOKEN:-}"
NOTIFY_PUSH_USER="${NOTIFY_PUSH_USER:-}"

# Syslog configuration
NOTIFY_SYSLOG_TAG="${NOTIFY_SYSLOG_TAG:-awesome-bash-scripts}"
NOTIFY_SYSLOG_FACILITY="${NOTIFY_SYSLOG_FACILITY:-user}"

################################################################################
# Notification Levels
################################################################################

readonly NOTIFY_CRITICAL="critical"
readonly NOTIFY_ERROR="error"
readonly NOTIFY_WARNING="warning"
readonly NOTIFY_INFO="info"
readonly NOTIFY_SUCCESS="success"

################################################################################
# Desktop Notifications
################################################################################

# Send desktop notification
notify_desktop() {
    local title="$1"
    local message="$2"
    local level="${3:-info}"
    local icon="${4:-}"
    
    # Check if desktop notifications are enabled
    [[ "$NOTIFY_DESKTOP" != "true" ]] && return 0
    
    # Check if notify-send is available
    if ! command_exists notify-send; then
        log_debug "notify-send not available, skipping desktop notification"
        return 0
    fi
    
    # Map level to urgency
    local urgency="normal"
    case "$level" in
        critical|error)
            urgency="critical"
            [[ -z "$icon" ]] && icon="dialog-error"
            ;;
        warning)
            urgency="normal"
            [[ -z "$icon" ]] && icon="dialog-warning"
            ;;
        success)
            urgency="low"
            [[ -z "$icon" ]] && icon="dialog-information"
            ;;
        *)
            urgency="low"
            [[ -z "$icon" ]] && icon="dialog-information"
            ;;
    esac
    
    # Send notification
    notify-send \
        --urgency="$urgency" \
        ${icon:+--icon="$icon"} \
        "$title" \
        "$message" \
        2>/dev/null || log_debug "Failed to send desktop notification"
}

################################################################################
# Email Notifications
################################################################################

# Send email notification
notify_email() {
    local subject="$1"
    local message="$2"
    local level="${3:-info}"
    
    # Check if email notifications are enabled
    [[ "$NOTIFY_EMAIL" != "true" ]] && return 0
    
    # Check if email is configured
    if [[ -z "$NOTIFY_EMAIL_TO" ]]; then
        log_debug "Email recipient not configured, skipping email notification"
        return 0
    fi
    
    # Find mail command
    local mail_cmd=""
    if command_exists mail; then
        mail_cmd="mail"
    elif command_exists mailx; then
        mail_cmd="mailx"
    elif command_exists sendmail; then
        mail_cmd="sendmail"
    else
        log_debug "No mail command available, skipping email notification"
        return 0
    fi
    
    # Prepare subject with prefix and level
    local full_subject="$NOTIFY_EMAIL_SUBJECT_PREFIX [$level] $subject"
    
    # Add metadata to message
    local full_message="Notification Level: $level
Host: $(hostname)
Time: $(date '+%Y-%m-%d %H:%M:%S')
Script: ${0##*/}

$message"
    
    # Send email
    if [[ "$mail_cmd" == "sendmail" ]]; then
        {
            echo "From: $NOTIFY_EMAIL_FROM"
            echo "To: $NOTIFY_EMAIL_TO"
            echo "Subject: $full_subject"
            echo ""
            echo "$full_message"
        } | sendmail "$NOTIFY_EMAIL_TO" 2>/dev/null
    else
        echo "$full_message" | $mail_cmd -s "$full_subject" "$NOTIFY_EMAIL_TO" 2>/dev/null
    fi || log_debug "Failed to send email notification"
}

################################################################################
# Syslog Notifications
################################################################################

# Send syslog notification
notify_syslog() {
    local message="$1"
    local level="${2:-info}"
    
    # Check if syslog notifications are enabled
    [[ "$NOTIFY_SYSLOG" != "true" ]] && return 0
    
    # Check if logger is available
    if ! command_exists logger; then
        log_debug "logger not available, skipping syslog notification"
        return 0
    fi
    
    # Map level to syslog priority
    local priority
    case "$level" in
        critical)   priority="crit" ;;
        error)      priority="err" ;;
        warning)    priority="warning" ;;
        info)       priority="info" ;;
        success)    priority="notice" ;;
        *)          priority="info" ;;
    esac
    
    # Send to syslog
    logger \
        -t "$NOTIFY_SYSLOG_TAG" \
        -p "$NOTIFY_SYSLOG_FACILITY.$priority" \
        "$message" \
        2>/dev/null || log_debug "Failed to send syslog notification"
}

################################################################################
# Webhook Notifications
################################################################################

# Send webhook notification
notify_webhook() {
    local title="$1"
    local message="$2"
    local level="${3:-info}"
    
    # Check if webhook notifications are enabled
    [[ "$NOTIFY_WEBHOOK" != "true" ]] && return 0
    
    # Check if webhook is configured
    if [[ -z "$NOTIFY_WEBHOOK_URL" ]]; then
        log_debug "Webhook URL not configured, skipping webhook notification"
        return 0
    fi
    
    # Check if curl is available
    if ! command_exists curl; then
        log_debug "curl not available, skipping webhook notification"
        return 0
    fi
    
    # Prepare payload based on webhook type
    local payload
    case "$NOTIFY_WEBHOOK_TYPE" in
        slack)
            # Map level to emoji
            local emoji
            case "$level" in
                critical|error) emoji=":x:" ;;
                warning)        emoji=":warning:" ;;
                success)        emoji=":white_check_mark:" ;;
                *)              emoji=":information_source:" ;;
            esac
            
            payload=$(cat <<EOF
{
    "text": "$emoji *$title*",
    "attachments": [{
        "text": "$message",
        "color": "$(get_webhook_color "$level")",
        "footer": "$(hostname) - $(date '+%Y-%m-%d %H:%M:%S')"
    }]
}
EOF
            )
            ;;
            
        discord)
            payload=$(cat <<EOF
{
    "content": "**$title**",
    "embeds": [{
        "description": "$message",
        "color": $(get_webhook_color_decimal "$level"),
        "footer": {
            "text": "$(hostname) - $(date '+%Y-%m-%d %H:%M:%S')"
        }
    }]
}
EOF
            )
            ;;
            
        teams)
            payload=$(cat <<EOF
{
    "@type": "MessageCard",
    "@context": "http://schema.org/extensions",
    "themeColor": "$(get_webhook_color "$level")",
    "summary": "$title",
    "sections": [{
        "activityTitle": "$title",
        "activitySubtitle": "$(hostname) - $(date '+%Y-%m-%d %H:%M:%S')",
        "text": "$message"
    }]
}
EOF
            )
            ;;
            
        custom|*)
            payload=$(cat <<EOF
{
    "title": "$title",
    "message": "$message",
    "level": "$level",
    "host": "$(hostname)",
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
            )
            ;;
    esac
    
    # Send webhook
    curl -s -X POST \
        -H "Content-Type: application/json" \
        -d "$payload" \
        "$NOTIFY_WEBHOOK_URL" \
        &>/dev/null || log_debug "Failed to send webhook notification"
}

# Get color for webhook based on level
get_webhook_color() {
    local level="$1"
    case "$level" in
        critical|error) echo "#ff0000" ;;
        warning)        echo "#ff9900" ;;
        success)        echo "#00ff00" ;;
        *)              echo "#0099ff" ;;
    esac
}

# Get decimal color for Discord
get_webhook_color_decimal() {
    local level="$1"
    case "$level" in
        critical|error) echo "16711680" ;;   # Red
        warning)        echo "16753920" ;;   # Orange
        success)        echo "65280" ;;      # Green
        *)              echo "39423" ;;      # Blue
    esac
}

################################################################################
# Push Notifications
################################################################################

# Send push notification
notify_push() {
    local title="$1"
    local message="$2"
    local level="${3:-info}"
    
    # Check if push notifications are enabled
    [[ "$NOTIFY_PUSH" != "true" ]] && return 0
    
    # Check configuration
    if [[ -z "$NOTIFY_PUSH_TOKEN" ]]; then
        log_debug "Push notification token not configured"
        return 0
    fi
    
    case "$NOTIFY_PUSH_SERVICE" in
        pushover)
            notify_pushover "$title" "$message" "$level"
            ;;
        pushbullet)
            notify_pushbullet "$title" "$message" "$level"
            ;;
        *)
            log_debug "Unknown push service: $NOTIFY_PUSH_SERVICE"
            ;;
    esac
}

# Send Pushover notification
notify_pushover() {
    local title="$1"
    local message="$2"
    local level="$3"
    
    [[ -z "$NOTIFY_PUSH_USER" ]] && return 1
    
    # Map level to priority
    local priority=0
    case "$level" in
        critical)   priority=2 ;;   # Emergency
        error)      priority=1 ;;   # High
        warning)    priority=0 ;;   # Normal
        success)    priority=-1 ;;  # Low
        *)          priority=-2 ;;  # Lowest
    esac
    
    curl -s -X POST \
        -F "token=$NOTIFY_PUSH_TOKEN" \
        -F "user=$NOTIFY_PUSH_USER" \
        -F "title=$title" \
        -F "message=$message" \
        -F "priority=$priority" \
        -F "timestamp=$(date +%s)" \
        "https://api.pushover.net/1/messages.json" \
        &>/dev/null || log_debug "Failed to send Pushover notification"
}

# Send Pushbullet notification
notify_pushbullet() {
    local title="$1"
    local message="$2"
    local level="$3"
    
    curl -s -X POST \
        -H "Access-Token: $NOTIFY_PUSH_TOKEN" \
        -H "Content-Type: application/json" \
        -d "{\"type\": \"note\", \"title\": \"$title\", \"body\": \"$message\"}" \
        "https://api.pushbullet.com/v2/pushes" \
        &>/dev/null || log_debug "Failed to send Pushbullet notification"
}

################################################################################
# Main Notification Function
################################################################################

# Send notification through all configured channels
notify() {
    local title="$1"
    local message="$2"
    local level="${3:-info}"
    
    # Validate level
    case "$level" in
        critical|error|warning|info|success) ;;
        *) level="info" ;;
    esac
    
    # Log the notification
    log_info "Notification [$level]: $title - $message"
    
    # Send through all enabled channels
    notify_desktop "$title" "$message" "$level" &
    notify_email "$title" "$message" "$level" &
    notify_syslog "$title: $message" "$level" &
    notify_webhook "$title" "$message" "$level" &
    notify_push "$title" "$message" "$level" &
    
    # Wait for background jobs
    wait
}

# Convenience functions for different levels
notify_critical() {
    notify "$1" "$2" "$NOTIFY_CRITICAL"
}

notify_error() {
    notify "$1" "$2" "$NOTIFY_ERROR"
}

notify_warning() {
    notify "$1" "$2" "$NOTIFY_WARNING"
}

notify_info() {
    notify "$1" "$2" "$NOTIFY_INFO"
}

notify_success() {
    notify "$1" "$2" "$NOTIFY_SUCCESS"
}

################################################################################
# Configuration Helper
################################################################################

# Load notification configuration from file
load_notification_config() {
    local config_file="${1:-$ABS_CONFIG_DIR/notifications.conf}"
    
    if [[ -f "$config_file" ]]; then
        log_debug "Loading notification config from $config_file"
        source "$config_file"
    fi
}

# Save current notification configuration
save_notification_config() {
    local config_file="${1:-$ABS_CONFIG_DIR/notifications.conf}"
    
    cat > "$config_file" <<EOF
# Awesome Bash Scripts - Notification Configuration
# Generated on: $(date)

# Enable/disable notification channels
NOTIFY_DESKTOP="$NOTIFY_DESKTOP"
NOTIFY_EMAIL="$NOTIFY_EMAIL"
NOTIFY_SYSLOG="$NOTIFY_SYSLOG"
NOTIFY_WEBHOOK="$NOTIFY_WEBHOOK"
NOTIFY_PUSH="$NOTIFY_PUSH"

# Email configuration
NOTIFY_EMAIL_TO="$NOTIFY_EMAIL_TO"
NOTIFY_EMAIL_FROM="$NOTIFY_EMAIL_FROM"
NOTIFY_EMAIL_SUBJECT_PREFIX="$NOTIFY_EMAIL_SUBJECT_PREFIX"

# Webhook configuration
NOTIFY_WEBHOOK_URL="$NOTIFY_WEBHOOK_URL"
NOTIFY_WEBHOOK_TYPE="$NOTIFY_WEBHOOK_TYPE"

# Push notification configuration
NOTIFY_PUSH_SERVICE="$NOTIFY_PUSH_SERVICE"
NOTIFY_PUSH_TOKEN="$NOTIFY_PUSH_TOKEN"
NOTIFY_PUSH_USER="$NOTIFY_PUSH_USER"

# Syslog configuration
NOTIFY_SYSLOG_TAG="$NOTIFY_SYSLOG_TAG"
NOTIFY_SYSLOG_FACILITY="$NOTIFY_SYSLOG_FACILITY"
EOF
}

################################################################################
# Export Functions
################################################################################

export -f notify notify_critical notify_error notify_warning notify_info notify_success
export -f notify_desktop notify_email notify_syslog notify_webhook notify_push
export -f load_notification_config save_notification_config
