#!/bin/bash

# GCP Cloud Run V2Ray(VLESS/Trojan) Deployment

set -euo pipefail

# ------------------------------------------------------------------------------
# 1. GLOBAL VARIABLES & STYLES
# ------------------------------------------------------------------------------

# Colors
RED='\033[0;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
ORANGE='\033[0;33m' # Header Color
BLUE='\033[1;34m'
CYAN='\033[1;36m'
WHITE='\033[1;37m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Global Configuration Variables (Defaults)
PROTOCOL=""
UUID=""
TROJAN_PASSWORD="ahlflk"
REGION="us-central1"
CPU="2"
MEMORY="2Gi"
SERVICE_NAME="gcp-ahlflk"
HOST_DOMAIN="m.googleapis.com"
TELEGRAM_DESTINATION="none"

# Protocol Specific Defaults
VLESS_PATH="/ahlflk"
TROJAN_PATH="/ahlflk"
VLESS_GRPC_SERVICE_NAME="ahlflk"

# Telegram Variables (will be set during selection)
TELEGRAM_BOT_TOKEN=""
TELEGRAM_CHANNEL_ID=""
TELEGRAM_CHAT_ID=""
TELEGRAM_GROUP_ID=""

# Time Variables (Initialized later in run_user_inputs)
START_LOCAL=""
END_LOCAL=""

# =================== Time Zone Function ===================
export TZ="Asia/Yangon"
fmt_dt(){ date -d @"$1" "+%d.%m.%Y %I:%M %p"; }

initialize_time_variables() {
    START_EPOCH="$(date +%s)"
    END_EPOCH="$(( START_EPOCH + 5*3600 ))" # 5 hours validity
    START_LOCAL="$(fmt_dt "$START_EPOCH")"
    END_LOCAL="$(fmt_dt "$END_EPOCH")"
}
# ==========================================================

# ------------------------------------------------------------------------------
# 2. UTILITY FUNCTIONS (LOGGING, UI, VALIDATION)
# ------------------------------------------------------------------------------

# Emoji Function
show_emojis() {
    # Define Emojis
    EMOJI_SUCCESS="✅"
    EMOJI_WARN="⚠️"
    EMOJI_ERROR="❌"
    EMOJI_INFO="💡"
    EMOJI_SELECT="🎯"
    EMOJI_PROC="⚙️"
    EMOJI_DEPLOY="🚀"
    EMOJI_CHECK="📋"
    EMOJI_CLEAN="🧹"
}

# Beautiful Header/Banner (New Design: Fully enclosed box, adjusted to title width)
header() {
    local title="$1"
    local border_color="${ORANGE}"
    local text_color="${YELLOW}"
    
    # Calculate title length
    local title_length=${#title}
    local padding=4 # Space on both sides: " | <space> TITLE <space> | "
    local total_width=$((title_length + padding))
    
    # Create top/bottom border line (using Unicode box drawing characters)
    # The length of the line part inside the corners is total_width - 2
    local top_bottom_fill=$(printf '━%.0s' $(seq 1 $((total_width - 2))))
    local top_bottom="${border_color}┏${top_bottom_fill}┓${NC}"
    local bottom_line="${border_color}┗${top_bottom_fill}┛${NC}"
    
    # Create title line
    # "┃" + <space> + title + <space> + "┃"
    local title_line="${border_color}┃${NC} ${text_color}${BOLD}${title}${NC} ${border_color}┃${NC}"
    
    echo -e "${top_bottom}"
    echo -e "${title_line}"
    echo -e "${bottom_line}"
}

# Simple Logs with Emoji
log() {
    echo -e "${GREEN}${BOLD}${EMOJI_SUCCESS} [LOG]${NC} ${WHITE}$1${NC}"
}

warn() {
    echo -e "${YELLOW}${BOLD}${EMOJI_WARN} [WARN]${NC} ${WHITE}$1${NC}"
}

error() {
    echo -e "${RED}${BOLD}${EMOJI_ERROR} [ERROR]${NC} ${WHITE}$1${NC}"
    exit 1
}

info() {
    echo -e "${BLUE}${BOLD}${EMOJI_INFO} [INFO]${NC} ${WHITE}$1${NC}"
}

selected_info() {
    echo -e "${GREEN}${BOLD}${EMOJI_SELECT} Selected:${NC} ${CYAN}$1${NC}"
}

# Spinner for background processes
spinner() {
    local pid=$1
    local delay=0.1
    # Using standard ASCII characters to avoid encoding issues
    local spin='/-\|' 
    local i=0
    
    while kill -0 $pid 2>/dev/null; do
        local index=$((i % ${#spin}))
        echo -ne "\r${ORANGE}  [${spin:$index:1}]${NC} ${WHITE}$2...${NC}"
        sleep $delay
        i=$((i + 1))
    done
    echo -ne "\r${GREEN}  [${EMOJI_SUCCESS}]${NC} ${WHITE}$2... Done!${NC}\n"
}

# Function to validate UUID format
validate_uuid() {
    local uuid_pattern='^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    if [[ ! $1 =~ $uuid_pattern ]]; then
        warn "Invalid UUID format. Please ensure it is a valid 32-digit hexadecimal number with 4 hyphens."
        return 1
    fi
    return 0
}

# Function to validate Telegram IDs (combined for Channel/Group/Chat)
validate_id() {
    if [[ ! $1 =~ ^-?[0-9]+$ ]]; then
        # Changed 'error' to 'warn' and use return 1 to continue the loop
        warn "Invalid Telegram ID format. Must be a number (e.g., -1001234567890 or 123456789)."
        return 1
    fi
    return 0
}

# Function to validate Telegram Bot Token
validate_bot_token() {
    local token_pattern='^[0-9]{8,10}:[a-zA-Z0-9_-]{35}$'
    if [[ ! $1 =~ $token_pattern ]]; then
        warn "Invalid Telegram Bot Token format. Please try again."
        return 1
    fi
    return 0
}

# ------------------------------------------------------------------------------
# 3. USER INPUT FUNCTIONS (IN ORDER)
# ------------------------------------------------------------------------------

# A. Telegram Destination Selection
select_telegram_destination() {
    header "📱 Telegram Notification Settings"
    
    while true; do
        echo -e "${CYAN}Select where to send the deployment link:${NC}"
        echo -e "${BOLD}1.${NC} Don't send to Telegram ${GREEN}[DEFAULT]${NC}"
        echo -e "${BOLD}2.${NC} Send to Channel Only"
        echo -e "${BOLD}3.${NC} Send to Group Only"
        echo -e "${BOLD}4.${NC} Send to Bot Private Message" 
        echo -e "${BOLD}5.${NC} Send to Both Channel and Bot"
        echo
        
        read -p "Select destination (1): " telegram_choice
        telegram_choice=${telegram_choice:-1}
        
        case $telegram_choice in
            1) TELEGRAM_DESTINATION="none"; break ;;
            2) TELEGRAM_DESTINATION="channel"; break ;;
            3) TELEGRAM_DESTINATION="group"; break ;;
            4) TELEGRAM_DESTINATION="bot"; break ;;
            5) TELEGRAM_DESTINATION="both"; break ;;
            *) echo -e "${RED}Invalid selection. Please enter a number between 1-5.${NC}"; continue ;;
        esac
    done

    if [[ "$TELEGRAM_DESTINATION" != "none" ]]; then
        echo
        while true; do
            read -p "Enter Telegram Bot Token: " TELEGRAM_BOT_TOKEN
            if validate_bot_token "$TELEGRAM_BOT_TOKEN"; then break; else continue; fi
        done
        
        if [[ "$TELEGRAM_DESTINATION" == "channel" || "$TELEGRAM_DESTINATION" == "both" ]]; then
            while true; do
                read -p "Enter Telegram Channel ID: " TELEGRAM_CHANNEL_ID
                if validate_id "$TELEGRAM_CHANNEL_ID"; then break; fi
            done
        fi
        
        if [[ "$TELEGRAM_DESTINATION" == "bot" || "$TELEGRAM_DESTINATION" == "both" ]]; then
            while true; do
                read -p "Enter your Chat ID (for bot private message): " TELEGRAM_CHAT_ID
                if validate_id "$TELEGRAM_CHAT_ID"; then break; fi
            done
        fi
        
        if [[ "$TELEGRAM_DESTINATION" == "group" ]]; then
            while true; do
                read -p "Enter Telegram Group ID: " TELEGRAM_GROUP_ID
                if validate_id "$TELEGRAM_GROUP_ID"; then break; fi
            done
        fi
        selected_info "Bot Token: ${TELEGRAM_BOT_TOKEN:0:8}..."
    fi
    
    selected_info "Telegram Destination: $TELEGRAM_DESTINATION"
    echo
}

# B. Protocol Selection
select_protocol() {
    header "🌐 V2RAY Protocol Selection"
    echo -e "${CYAN}Choose your preferred V2Ray protocol for the Cloud Run instance:${NC}"
    echo -e "${BOLD}1.${NC} VLESS-WS (VLESS + WebSocket + TLS) ${GREEN}[DEFAULT]${NC}" # <-- FIX: Added [DEFAULT] here
    echo -e "${BOLD}2.${NC} VLESS-gRPC (VLESS + gRPC + TLS)"
    echo -e "${BOLD}3.${NC} Trojan-WS (Trojan + WebSocket + TLS)"
    echo
    
    while true; do
        read -p "Select V2Ray Protocol (1): " protocol_choice
        protocol_choice=${protocol_choice:-1}
        case $protocol_choice in
            1) PROTOCOL="VLESS-WS"; break ;;
            2) PROTOCOL="VLESS-gRPC"; break ;;
            3) PROTOCOL="Trojan-WS"; break ;;
            *) echo -e "${RED}Invalid selection. Please enter a number between 1-3.${NC}" ;;
        esac
    done
    
    selected_info "Protocol: $PROTOCOL"
    echo
}

# C. Region Selection
select_region() {
    header "🌍 GCP Region Selection"
    echo -e "${CYAN}Available GCP Regions:${NC}"
    echo -e "${BOLD}1.${NC}  🇺🇸 us-central1 (Council Bluffs, Iowa, North America) ${GREEN}[DEFAULT]${NC}"
    echo -e "${BOLD}2.${NC}  🇺🇸 us-east1 (Moncks Corner, South Carolina, North America)" 
    echo -e "${BOLD}3.${NC}  🇺🇸 us-south1 (Dallas, Texas, North America)"
    echo -e "${BOLD}4.${NC}  🇺🇸 us-west1 (The Dalles, Oregon, North America)"
    echo -e "${BOLD}5.${NC}  🇺🇸 us-west2 (Los Angeles, California, North America)"
    echo -e "${BOLD}6.${NC}  🇨🇦 northamerica-northeast2 (Toronto, Ontario, North America)"
    echo -e "${BOLD}7.${NC}  🇸🇬 asia-southeast1 (Jurong West, Singapore)"
    echo -e "${BOLD}8.${NC}  🇯🇵 asia-northeast1 (Tokyo, Japan)"
    echo -e "${BOLD}9.${NC}  🇹🇼 asia-east1 (Changhua County, Taiwan)"
    echo -e "${BOLD}10.${NC} 🇭🇰 asia-east2 (Hong Kong)"
    echo -e "${BOLD}11.${NC} 🇮🇳 asia-south1 (Mumbai, India)"
    echo -e "${BOLD}12.${NC} 🇮🇩 asia-southeast2 (Jakarta, Indonesia)${NC}"
    echo
    
    while true; do
        read -p "Select region (1): " region_choice
        region_choice=${region_choice:-1}
        case $region_choice in
            1) REGION="us-central1"; break ;;
            2) REGION="us-east1"; break ;;
            3) REGION="us-south1"; break ;;
            4) REGION="us-west1"; break ;;
            5) REGION="us-west2"; break ;;
            6) REGION="northamerica-northeast2"; break ;;
            7) REGION="asia-southeast1"; break ;;
            8) REGION="asia-northeast1"; break ;;
            9) REGION="asia-east1"; break ;;
            10) REGION="asia-east2"; break ;;
            11) REGION="asia-south1"; break ;;
            12) REGION="asia-southeast2"; break ;;
            *) echo -e "${RED}Invalid selection. Please enter a number between 1-12.${NC}" ;;
        esac
    done
    
    selected_info "Region: $REGION"
    echo
}

# D. CPU Configuration
select_cpu() {
    header "🖥️  CPU Configuration"
    echo -e "${CYAN}Available Options:${NC}"
    echo -e "${BOLD}1.${NC} 1  CPU Core (Lightweight traffic)"
    echo -e "${BOLD}2.${NC} 2  CPU Cores (Balanced) ${GREEN}[DEFAULT]${NC}"
    echo -e "${BOLD}3.${NC} 4  CPU Cores (Performance)"
    echo -e "${BOLD}4.${NC} 8  CPU Cores (High Performance)"
    echo -e "${BOLD}5.${NC} 16 CPU Cores (Extreme Load)" 
    echo
    
    while true; do
        read -p "Select CPU cores (2): " cpu_choice
        cpu_choice=${cpu_choice:-2}
        case $cpu_choice in
            1) CPU="1"; break ;;
            2) CPU="2"; break ;;
            3) CPU="4"; break ;;
            4) CPU="8"; break ;;
            5) CPU="16"; break ;;
            *) echo -e "${RED}Invalid selection. Please enter a number between 1-5.${NC}" ;;
        esac
    done
    
    selected_info "CPU: $CPU core(s)"
    echo
}

# E. Memory Configuration
select_memory() {
    header "💾 Memory Configuration"
    
    echo -e "${CYAN}Available Options:${NC}"
    echo -e "${BOLD}1.${NC} 512Mi (Minimum requirement)"
    echo -e "${BOLD}2.${NC} 1Gi (Basic usage)"
    echo -e "${BOLD}3.${NC} 2Gi (Balanced usage) ${GREEN}[DEFAULT]${NC}"
    echo -e "${BOLD}4.${NC} 4Gi (Moderate performance)"
    echo -e "${BOLD}5.${NC} 8Gi (High load/many connections)"
    echo -e "${BOLD}6.${NC} 16Gi (Advanced/Extreme load)"
    echo -e "${BOLD}7.${NC} 32Gi (Maximum limit for Cloud Run)"
    echo
    
    while true; do
        read -p "Select memory (3): " memory_choice
        memory_choice=${memory_choice:-3}
        case $memory_choice in
            1) MEMORY="512Mi"; break ;;
            2) MEMORY="1Gi"; break ;;
            3) MEMORY="2Gi"; break ;;
            4) MEMORY="4Gi"; break ;;
            5) MEMORY="8Gi"; break ;;
            6) MEMORY="16Gi"; break ;;
            7) MEMORY="32Gi"; break ;;
            *) echo -e "${RED}Invalid selection. Please enter a number between 1-7.${NC}" ;;
        esac
    done
    
    selected_info "Memory: $MEMORY"
    echo
}

# F. Service Name Configuration
select_service_name() {
    header "${EMOJI_PROC} Service Name Configuration"
    
    echo -e "${CYAN}Deployment Service Name (Default: gcp-ahlflk):${NC}"
    
    read -p "Enter custom name or press Enter to use default: " custom_name
    SERVICE_NAME=${custom_name:-$SERVICE_NAME}
    
    if [[ -z "$SERVICE_NAME" ]]; then
        warn "Service name cannot be empty. Using default: gcp-ahlflk."
        SERVICE_NAME="gcp-ahlflk"
    fi
    
    selected_info "Service Name: $SERVICE_NAME"
    echo
}

# G. Host Domain Configuration
select_host_domain() {
    header "🌐 Host Domain Configuration"
    
    echo -e "${CYAN}SNI/Host Domain (Default: m.googleapis.com):${NC}"
    
    read -p "Enter custom domain or press Enter to use default: " custom_domain
    HOST_DOMAIN=${custom_domain:-$HOST_DOMAIN}
    
    if [[ -z "$HOST_DOMAIN" ]]; then
        warn "Host Domain cannot be empty. Using default: m.googleapis.com."
        HOST_DOMAIN="m.googleapis.com"
    fi
    
    selected_info "Host Domain: $HOST_DOMAIN"
    echo
}

# H. UUID/Password Configuration
select_uuid_password() {
    header "🔑 UUID / Password Configuration"
    
    if [[ "$PROTOCOL" == "Trojan-WS" ]]; then
        selected_info "Protocol is Trojan-WS, Password default: ${TROJAN_PASSWORD}"
        echo
        echo -e "${CYAN}Trojan Password (Default: ahlflk):${NC}"
        read -p "Enter custom password or press Enter to use default: " custom_pw
        TROJAN_PASSWORD=${custom_pw:-$TROJAN_PASSWORD}
        selected_info "Trojan Password: ${TROJAN_PASSWORD}"
        
    else
        local default_uuid="3675119c-14fc-46a4-b5f3-9a2c91a7d802"
        
        while true; do
            echo -e "${CYAN}UUID Options:${NC}"
            echo -e "${BOLD}1.${NC} Use Default UUID (3675...802) ${GREEN}[DEFAULT]${NC}"
            echo -e "${BOLD}2.${NC} Generate New UUID"
            echo -e "${CYAN}You can also paste a custom UUID directly, or press Enter for default.${NC}"
            echo

            read -p "Enter 1, 2, or Paste Custom UUID: " uuid_input
            uuid_input=${uuid_input:-1}

            if [[ "$uuid_input" == "1" ]]; then
                UUID="$default_uuid"
                log "Using Default UUID."
                break
            elif [[ "$uuid_input" == "2" ]]; then
                if command -v uuidgen &> /dev/null; then
                    UUID=$(uuidgen)
                else
                    UUID=$(cat /proc/sys/kernel/random/uuid)
                fi
                log "Generated New UUID: $UUID"
                break
            elif validate_uuid "$uuid_input"; then
                # Custom UUID validation successful
                UUID="$uuid_input"
                log "Using Custom UUID: $UUID"
                break
            else
                echo -e "${RED}Invalid input. Please enter 1, 2, or a valid custom UUID.${NC}" 
            fi
        done
        
        selected_info "UUID: $UUID"
        echo
        
        # VLESS-gRPC ServiceName
        if [[ "$PROTOCOL" == "VLESS-gRPC" ]]; then
            echo -e "${CYAN}VLESS-gRPC ServiceName (Default: ahlflk):${NC}"
            read -p "Enter custom ServiceName or press Enter to use default: " custom_service_name
            VLESS_GRPC_SERVICE_NAME=${custom_service_name:-$VLESS_GRPC_SERVICE_NAME}
            selected_info "gRPC ServiceName: $VLESS_GRPC_SERVICE_NAME"
        fi
    fi
    echo
}

# I. Summary and Confirmation
show_config_summary() {
    header "${EMOJI_CHECK} Configuration Summary"
    # Project ID moved to top
    echo -e "${CYAN}${BOLD}Project ID:${NC}    $(gcloud config get-value project)"
    echo -e "${CYAN}${BOLD}Protocol:${NC}      $PROTOCOL"
    echo -e "${CYAN}${BOLD}Region:${NC}        $REGION"
    echo -e "${CYAN}${BOLD}Service Name:${NC}  $SERVICE_NAME"
    echo -e "${CYAN}${BOLD}Host Domain:${NC}   $HOST_DOMAIN"
    
    if [[ "$PROTOCOL" == "Trojan-WS" ]]; then
        echo -e "${CYAN}${BOLD}Password:${NC}      ${TROJAN_PASSWORD}"
        echo -e "${CYAN}${BOLD}Path:${NC}          $TROJAN_PATH"
    elif [[ "$PROTOCOL" == "VLESS-gRPC" ]]; then
        echo -e "${CYAN}${BOLD}UUID:${NC}          $UUID"
        echo -e "${CYAN}${BOLD}ServiceName:${NC}   $VLESS_GRPC_SERVICE_NAME"
    else
        echo -e "${CYAN}${BOLD}UUID:${NC}          $UUID"
        echo -e "${CYAN}${BOLD}Path:${NC}          $VLESS_PATH"
    fi
    
    echo -e "${CYAN}${BOLD}CPU/Memory:${NC}    $CPU core(s) / $MEMORY"
    
    if [[ "$TELEGRAM_DESTINATION" != "none" ]]; then
        echo -e "${CYAN}${BOLD}Telegram:${NC}      $TELEGRAM_DESTINATION (Token: ${TELEGRAM_BOT_TOKEN:0:8}...)"
    else
        echo -e "${CYAN}${BOLD}Telegram:${NC}      Not configured"
    fi
    
    # --- TimeFrame Summary ---
    header "⏳ Deployment TimeFrame (Asia/Yangon)"
    printf "${CYAN}${BOLD}%-20s${NC} %s\n" "Start Time:"       "$START_LOCAL"
    printf "${CYAN}${BOLD}%-20s${NC} %s\n" "End Time:"     "$END_LOCAL (5 hours)"
    echo
    
    while true; do
        # FIX: Using echo -e and subshell for the prompt to correctly handle color codes
        read -p "$(echo -e "${ORANGE}${BOLD}Proceed with deployment? (y/n): ${NC}")" confirm
        case $confirm in
            [Yy]* ) break;;
            [Nn]* ) 
                info "Deployment cancelled by user"
                exit 0
                ;;
            * ) echo -e "${RED}Please answer yes (y) or no (n).${NC}";;
        esac
    done
}


# ------------------------------------------------------------------------------
# 4. CORE DEPLOYMENT FUNCTIONS (LOGIC REMAINS THE SAME)
# ------------------------------------------------------------------------------

# Config File Preparation
prepare_config_files() {
    log "Preparing Xray config file based on $PROTOCOL..."
    
    if [[ ! -f "config.json" ]]; then
        error "config.json not found in GCP-V2RAY-Cloud-Run directory."
        return 1
    fi
    
    case $PROTOCOL in
        "VLESS-WS")
            sed -i "s/PLACEHOLDER_UUID/$UUID/g" config.json
            sed -i "s|/vless|$VLESS_PATH|g" config.json
            ;;
            
        "VLESS-gRPC")
            sed -i "s/PLACEHOLDER_UUID/$UUID/g" config.json
            sed -i "s|\"network\": \"ws\"|\"network\": \"grpc\"|g" config.json
            sed -i "s|\"wsSettings\": { \"path\": \"/vless\" }|\"grpcSettings\": { \"serviceName\": \"$VLESS_GRPC_SERVICE_NAME\" }|g" config.json
            ;;
            
        "Trojan-WS")
            sed -i 's|"protocol": "vless"|"protocol": "trojan"|g' config.json
            sed -i "s|\"clients\": \[ { \"id\": \"PLACEHOLDER_UUID\" } ]|\"users\": \[ { \"password\": \"$TROJAN_PASSWORD\" } ]|g" config.json
            sed -i "s|\"path\": \"/vless\"|\"path\": \"$TROJAN_PATH\"|g" config.json
            ;;
            
        *)
            error "Unknown protocol: $PROTOCOL. Cannot prepare config."
            ;;
    esac
}

# Share Link Creation (Uses the respective path variable)
create_share_link() {
    local service_name="$1"
    local domain="$2"
    local uuid_or_password="$3"
    local protocol_type="$4"
    local link=""
    
    # URL Encode path/serviceName
    local path_encoded
    if [[ "$protocol_type" == "VLESS-gRPC" ]]; then
        path_encoded=$(echo "$VLESS_GRPC_SERVICE_NAME" | sed 's/\//%2F/g')
    else
        path_encoded=$(echo "${VLESS_PATH:-$TROJAN_PATH}" | sed 's/\//%2F/g')
    fi
    
    local host_encoded=$(echo "$HOST_DOMAIN" | sed 's/\./%2E/g')
    
    case $protocol_type in
        "VLESS-WS")
            link="vless://${uuid_or_password}@${HOST_DOMAIN}:443?path=${path_encoded}&security=tls&encryption=none&host=${domain}&fp=randomized&type=ws&sni=${domain}#${service_name}_VLESS-WS_START=${START_LOCAL}_END=${END_LOCAL}"
            ;;
            
        "VLESS-gRPC")
            link="vless://${uuid_or_password}@${HOST_DOMAIN}:443?security=tls&encryption=none&host=${domain}&type=grpc&serviceName=${path_encoded}&sni=${domain}#${service_name}_VLESS-gRPC_START=${START_LOCAL}_END=${END_LOCAL}"
            ;;
            
        "Trojan-WS")
            link="trojan://${uuid_or_password}@${HOST_DOMAIN}:443?path=${path_encoded}&security=tls&host=${domain}&type=ws&sni=${domain}#${service_name}_Trojan-WS_START=${START_LOCAL}_END=${END_LOCAL}"
            ;;
    esac
    
    echo "$link"
}

# Telegram Notification Function (Simplified)
send_to_telegram() {
    local chat_id="$1"
    local message="$2"
    # Escape special Markdown chars, but specifically keep the [link](url) format
    message=$(echo "$message" | sed 's/\*/\\*/g; s/_/\\_/g; s/`/\\`/g; s/\[🔗 Xray Link\]([^)]*)/[&](/g; s/\[/\\\[/g; s/\]/\\\]/g')
    # Re-enable the specific link format
    message=$(echo "$message" | sed 's/\\\[🔗 Xray Link\\\]/\[🔗 Xray Link\]/g')
    
    curl -s -o /dev/null -w "%{http_code}" -X POST \
        -H "Content-Type: application/json" \
        -d "{\"chat_id\": \"${chat_id}\", \"text\": \"$message\", \"parse_mode\": \"MARKDOWN\", \"disable_web_page_preview\": true}" \
        https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage
}

send_deployment_notification() {
    local message="$1"
    
    case $TELEGRAM_DESTINATION in
        "channel")
            send_to_telegram "$TELEGRAM_CHANNEL_ID" "$message" > /dev/null 2>&1
            log "Notification sent to Telegram Channel."
            ;;
        "bot")
            send_to_telegram "$TELEGRAM_CHAT_ID" "$message" > /dev/null 2>&1
            log "Notification sent to Bot private message."
            ;;
        "group")
            send_to_telegram "$TELEGRAM_GROUP_ID" "$message" > /dev/null 2>&1
            log "Notification sent to Telegram Group."
            ;;
        "both")
            send_to_telegram "$TELEGRAM_CHANNEL_ID" "$message" > /dev/null 2>&1
            send_to_telegram "$TELEGRAM_CHAT_ID" "$message" > /dev/null 2>&1
            log "Notification sent to both Channel and Bot."
            ;;
        "none")
            log "Skipping Telegram notification."
            ;;
    esac
}

# ------------------------------------------------------------------------------
# 5. MAIN EXECUTION BLOCK
# ------------------------------------------------------------------------------

# Run user input functions in specified order
run_user_inputs() {
# Display main header
header "${EMOJI_DEPLOY} GCP Cloud Run V2Ray(VLESS/Trojan) Deployment"
    initialize_time_variables # FIX: Initialize time variables first
    select_telegram_destination
    select_protocol
    select_region
    select_cpu
    select_memory
    select_service_name
    select_host_domain
    select_uuid_password
    show_config_summary
}

# Core deployment logic
deploy_service() {
    local PROJECT_ID=$(gcloud config get-value project)
    
    log "${EMOJI_DEPLOY} Starting Cloud Run deployment for $PROTOCOL..."
    
    # Validation
    if ! command -v gcloud &> /dev/null; then error "${EMOJI_ERROR} gcloud CLI is not installed. Please install Google Cloud SDK."; fi
    if ! command -v git &> /dev/null; then error "${EMOJI_ERROR} git is not installed. Please install git."; fi
    if [[ -z "$PROJECT_ID" || "$PROJECT_ID" == "(unset)" ]]; then error "${EMOJI_ERROR} No project configured. Run: gcloud config set project PROJECT_ID"; fi
    
    # 1. Enable APIs (Quiet)
    local enable_apis_pid
    (
        gcloud services enable cloudbuild.googleapis.com run.googleapis.com iam.googleapis.com --quiet > /dev/null 2>&1
    ) &
    enable_apis_pid=$!
    spinner $enable_apis_pid "Enabling required GCP APIs"
    wait $enable_apis_pid || warn "${EMOJI_WARN} Failed to enable some APIs (may already be enabled)."
    
    # 2. Cleanup and Clone (Quiet)
    rm -rf GCP-V2RAY-Cloud-Run || true
    local clone_pid
    (
        # Assuming the user has a repository with Dockerfile and config.json ready.
        # If the original repository is used, we clone that.
        git clone https://github.com/ahlflk/GCP-V2RAY-Cloud-Run.git GCP-V2RAY-Cloud-Run > /dev/null 2>&1
    ) &
    clone_pid=$!
    spinner $clone_pid "Cloning repository"
    wait $clone_pid
    
    if [[ ! -d "GCP-V2RAY-Cloud-Run" ]]; then error "${EMOJI_ERROR} GCP-V2RAY-Cloud-Run directory not found (cloning failed or directory missing)."; fi
    
    cd GCP-V2RAY-Cloud-Run
    
    # 3. Prepare Config
    prepare_config_files
    
    # 4. Build Image (Quiet)
    log "Building container image (quiet mode)..."
    local build_pid
    (
        gcloud builds submit --tag gcr.io/${PROJECT_ID}/gcp-v2ray-image . --quiet > /dev/null 2>&1
    ) &
    build_pid=$!
    spinner $build_pid "Building and pushing container image"
    wait $build_pid || error "${EMOJI_ERROR} Build failed. Check the Dockerfile or repository for issues."
    
    # 5. Deploy Service (Quiet)
    log "Deploying to Cloud Run..."
    local deploy_cmd="gcloud run deploy ${SERVICE_NAME} \
        --image gcr.io/${PROJECT_ID}/gcp-v2ray-image \
        --platform managed \
        --region ${REGION} \
        --allow-unauthenticated \
        --cpu ${CPU} \
        --memory ${MEMORY} \
        --quiet"

    local deploy_pid
    (
        eval "$deploy_cmd" > /dev/null 2>&1
    ) &
    deploy_pid=$!
    spinner $deploy_pid "Deploying service to Cloud Run"
    wait $deploy_pid || error "${EMOJI_ERROR} Deployment failed. Check Cloud Run logs for details."
    
    # 6. Get URL and create Link
    SERVICE_URL=$(gcloud run services describe ${SERVICE_NAME} \
        --region ${REGION} \
        --format 'value(status.url)' \
        --quiet)
    
    DOMAIN=$(echo "$SERVICE_URL" | sed 's|https://||')
    
    local link_user_id
    if [[ "$PROTOCOL" == "Trojan-WS" ]]; then
        link_user_id="$TROJAN_PASSWORD"
    else
        link_user_id="$UUID"
    fi
    
    SHARE_LINK=$(create_share_link "$SERVICE_NAME" "$DOMAIN" "$link_user_id" "$PROTOCOL")
    
    # 7. Final Output & Notification
    
    # Telegram Message with Markdown Link Format
    MESSAGE="*${EMOJI_DEPLOY} Cloud Run ${PROTOCOL} Deploy → Successful ${EMOJI_SUCCESS}*
━━━━━━━━━━━━━━━━━━━━
*Project:* \`${PROJECT_ID}\`
*Service:* \`${SERVICE_NAME}\`
*Region:* \`${REGION}\`
*URL:* \`${SERVICE_URL}\`
*Start Date (MMT):* \`${START_LOCAL}\`
*End Date (MMT):* \`${END_LOCAL}\`

[🔗 Xray Link](${SHARE_LINK})

━━━━━━━━━━━━━━━━━━━━
*Usage:* Click the link above to copy and import to your V2Ray/Xray client."

    CONSOLE_MESSAGE="🚀 Cloud Run ${PROTOCOL} Deployment Successful! ${EMOJI_SUCCESS}
━━━━━━━━━━━━━━━━━━━━
Project: ${PROJECT_ID}
Service: ${SERVICE_NAME}
Region: ${REGION}
URL: ${SERVICE_URL}
Start Date (MMT): ${START_LOCAL}
End Date (MMT): ${END_LOCAL}

${SHARE_LINK}

Usage: Copy the above link and import to your V2Ray/Xray client.
━━━━━━━━━━━━━━━━━━━━"
    
    # Save to file
    echo "$CONSOLE_MESSAGE" > deployment-info.txt
    log "Deployment info saved to deployment-info.txt"
    
    # Display locally
    echo
    header "🎉 DEPLOYMENT COMPLETED! 🎉"
    echo "$CONSOLE_MESSAGE"
    echo
    
    # Send to Telegram
    send_deployment_notification "$MESSAGE"
    
    log "GCP Cloud Run $PROTOCOL Service is now active and ready! ${EMOJI_SUCCESS}"
}

# Clean up temporary directory
cleanup() {
    log "${EMOJI_CLEAN} Cleaning up temporary files..."
    if [[ -d "GCP-V2RAY-Cloud-Run" ]]; then
        cd .. || true
        rm -rf GCP-V2RAY-Cloud-Run
    fi
}

# --- Main Flow ---
show_emojis # Initialize Emojis
trap cleanup EXIT
run_user_inputs
deploy_service
