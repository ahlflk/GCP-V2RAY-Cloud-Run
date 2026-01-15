#!/bin/bash

# 🚀 GCP Cloud Run V2RAY Deployment

set -euo pipefail

# ------------------------------------------------------------------------------
# 1. GLOBAL VARIABLES & STYLES
# ------------------------------------------------------------------------------

# ANSI Color Codes
BLUE='\033[94m'
BOLD='\033[1m'
CYAN='\033[96m'
GREEN='\033[92m'
LIGHT_GREEN='\033[1;92m'
NC='\033[0m' # No Color
ORANGE='\033[38;5;208m' # Header Color
RED='\033[91m'
WHITE='\033[1;37m'
YELLOW='\033[93m'

# Global Configuration Variables (Defaults)
PROTOCOL="VLESS-WS"
UUID=""
PASSWORD=""
WS_PATH="/t.me/ahlflk2025channel"
GRPC_SERVICE="ahlflk2025"
REGION="us-central1"
CPU="2"
MEMORY="2Gi"
SERVICE_NAME="gcp-ahlflk"
HOST_DOMAIN="m.googleapis.com"

# Telegram Variables (will be set during selection)
TELEGRAM_DESTINATION="none"
TELEGRAM_BOT_TOKEN=""
TELEGRAM_CHANNEL_ID=""
TELEGRAM_CHAT_ID=""
TELEGRAM_GROUP_ID=""

# Project ID holder (Will be set during auto_deployment_setup after Yes/No)
PROJECT_ID=""

# ------------------------------------------------------------------------------
# 2. UTILITY FUNCTIONS (LOGGING, UI, VALIDATION)
# ------------------------------------------------------------------------------

# Emoji Function
show_emojis() {
    # Define Emojis
    EMOJI_SUCCESS="✅"   # General Success
    EMOJI_WARN="⚠️"     # Warning
    EMOJI_ERROR="❌"    # Error
    EMOJI_INFO="💡"     # General Information
    EMOJI_SELECT="👉"    # Selection/Input Indicator
    EMOJI_SPINNER="⏳"  # For spinner
}

# Beautiful Header/Banner
header() {
    local title="$1"
    local border_color="${ORANGE}"
    local text_color="${YELLOW}"
    
    local title_length=${#title}
    local padding=4
    local total_width=$((title_length + padding))
    
    local top_bottom_fill=$(printf '━%.0s' $(seq 1 $((total_width - 2))))
    local top_bottom="${border_color}┏${top_bottom_fill}┓${NC}"
    local bottom_line="${border_color}┗${top_bottom_fill}┛${NC}"
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
    echo -e "${LIGHT_GREEN}${BOLD}${EMOJI_SELECT} Selected:${NC} ${CYAN}$1${NC}"
}

# SPINNER
spinner() {
    local label="$1"
    shift
    local command="$*"
    local spinstr='|/-\'
    local i=0

    eval "$command" &
    local pid=$!

    while kill -0 $pid 2>/dev/null; do
        i=$(((i + 1) % 4))
        printf "\r${BOLD}${EMOJI_SPINNER} ${label}... ${NC}${YELLOW}[${spinstr:$i:1}]${NC}"
        sleep 0.1
    done

    wait $pid

    printf "\r${BOLD}${EMOJI_SPINNER} ${label}... ${NC}${GREEN}${EMOJI_SUCCESS} Done!${NC}\n"
}

# Validation Functions
validate_bot_token() {
    local token_pattern='^[0-9]{8,10}:[a-zA-Z0-9_-]{35}$'
    if [[ ! $1 =~ $token_pattern ]]; then
        warn "Invalid Telegram Bot Token format. Please try again. 🤖"
        return 1
    fi
    return 0
}

validate_id() {
    if [[ ! $1 =~ ^-?[0-9]+$ ]]; then
        warn "Invalid Telegram ID format. Must be a number. 📱"
        return 1
    fi
    return 0
}

validate_uuid() {
    local uuid_pattern='^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    if [[ ! $1 =~ $uuid_pattern ]]; then
        warn "Invalid UUID format. Please ensure it is a valid 32-digit hexadecimal number with 4 hyphens. 🔑"
        return 1
    fi
    return 0
}

# ------------------------------------------------------------------------------
# 3. USER INPUT FUNCTIONS (REORDERED TO YOUR SPECIFICATION)
# ------------------------------------------------------------------------------

# A. V2Ray Protocol Selection & Related Configurations (The main function)
select_v2ray_config() {
    header "🔌 V2Ray Protocol Selection & Configuration"
    
    # Protocol Selection
    while true; do
        echo -e "${CYAN}Select V2Ray Protocol:${NC}"
        echo -e "${BOLD}1.${NC} VLESS-WS ${GREEN}[DEFAULT]${NC}"
        echo -e "${BOLD}2.${NC} VLESS-gRPC"
        echo -e "${BOLD}3.${NC} Trojan-WS"
        echo
        
        read -p "Select protocol (1): " protocol_choice
        protocol_choice=${protocol_choice:-1}
        
        case $protocol_choice in
            1) PROTOCOL="VLESS-WS"; break ;;
            2) PROTOCOL="VLESS-GRPC"; break ;;
            3) PROTOCOL="TROJAN-WS"; break ;;
            *) error "Invalid selection. Please enter a number between 1-3."; continue ;;
        esac
    done

    selected_info "Protocol: $PROTOCOL"
    echo ""
        
    # Sequential V2Ray configs
    select_service_name
    select_host_domain
    
    # UUID, Path, Service, Password in the desired display/call order
    
    # 1. UUID (Required for VLESS)
    if [[ "$PROTOCOL" == "VLESS-WS" || "$PROTOCOL" == "VLESS-GRPC" ]]; then
        select_uuid
    fi
    
    # 2. WS Path (Required for VLESS-WS and TROJAN-WS)
    if [[ "$PROTOCOL" == "VLESS-WS" || "$PROTOCOL" == "TROJAN-WS" ]]; then
        select_ws_path
    fi
    
    # 3. gRPC Service (Required for VLESS-GRPC)
    if [[ "$PROTOCOL" == "VLESS-GRPC" ]]; then
        select_grpc_service
    fi
    
    # 4. Password (Required for TROJAN-WS)
    if [[ "$PROTOCOL" == "TROJAN-WS" ]]; then
        select_password
    fi    
}

# V2RAY PROTOCOL CONFIGURATION HELPERS

# Service Name Configuration
select_service_name() {
    header "⚙️ Service Name Configuration"
    
    echo -e "${CYAN}Deployment Service Name (Default: gcp-ahlflk):${NC}"
    read -p "Enter custom name or press Enter to use default: " custom_name
    SERVICE_NAME=${custom_name:-$SERVICE_NAME}
    
    selected_info "Service Name: $SERVICE_NAME"
    echo ""
}

# Host Domain Configuration
select_host_domain() {
    header "🌐 Host Domain Configuration"
    
    echo -e "${CYAN}SNI/Host Domain (Default: m.googleapis.com):${NC}"
    read -p "Enter custom domain or press Enter to use default: " custom_domain
    HOST_DOMAIN=${custom_domain:-$HOST_DOMAIN}
    
    selected_info "Host Domain: $HOST_DOMAIN"
    echo ""
}

# UUID Configuration (for VLESS protocols)
select_uuid() {
    header "🆔 UUID Configuration"
    
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
            log "Using Default UUID: $UUID ✅"
            break
        elif [[ "$uuid_input" == "2" ]]; then
            UUID=$(command -v uuidgen &> /dev/null && uuidgen || cat /proc/sys/kernel/random/uuid 2>/dev/null || echo "3675119c-14fc-46a4-b5f3-9a2c91a7d802")
            if [[ "$UUID" == "3675119c-14fc-46a4-b5f3-9a2c91a7d802" ]]; then
                 warn "UUID generator not found. Using default UUID: $UUID 🔄"
            fi
            log "Generated New UUID: $UUID ✨"
            break
        elif validate_uuid "$uuid_input"; then
            UUID="$uuid_input"
            log "Using Custom UUID: $UUID ✅"
            break
        else
            echo -e "${RED}Invalid input. Please enter 1, 2, or a valid custom UUID.${NC}" 
        fi
    done
    
    selected_info "UUID: $UUID"
    echo ""
}

# WS Path Configuration (Only for WS protocols)
select_ws_path() {
    header "📂 WS Path Configuration"
    
    local default_path="/t.me/ahlflk2025channel"
    echo -e "${CYAN}WS Path (Default: $default_path):${NC}"
    
    read -p "Enter custom WS Path or press Enter to use default: " custom_path
    WS_PATH="${custom_path:-$default_path}"
    
    selected_info "WS Path: $WS_PATH"
    echo ""
}

# gRPC Service Name Configuration (Only for VLESS-GRPC)
select_grpc_service() {
    header "⚙️ gRPC Service Name Configuration"
    
    local default_service="ahlflk2025"
    echo -e "${CYAN}gRPC Service Name (Default: $default_service):${NC}"
    
    read -p "Enter custom gRPC Service Name or press Enter to use default: " custom_service
    GRPC_SERVICE=${custom_service:-$default_service}
    
    selected_info "gRPC Service: $GRPC_SERVICE"
    echo ""
}

# Trojan Password Configuration (No generate option)
select_password() {
    header "🆔 Trojan Password Configuration"
    
    local default_password="ahlflk2025"
        
    while true; do
        echo -e "${CYAN}Password Options:${NC}"
        echo -e "${BOLD}1.${NC} Use Default Password (ahlflk2025) ${GREEN}[DEFAULT]${NC}"
        echo -e "${CYAN}You can also paste a custom password directly, or press Enter for default.${NC}"
        echo

        read -p "Enter 1 or Paste Custom Password: " password_input
        password_input=${password_input:-1}

        if [[ "$password_input" == "1" ]]; then
            PASSWORD="$default_password"
            log "Using Default Password: $PASSWORD ✅"
            break
        elif [[ -n "$password_input" ]]; then
            PASSWORD="$password_input"
            log "Using Custom Password: ${PASSWORD:0:8}... ✅"
            break
        else
            echo -e "${RED}Invalid input. Please enter 1 or a valid custom password.${NC}" 
        fi
    done
    
    selected_info "Password: $PASSWORD"
    echo ""
}

# B. Telegram Destination Selection
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
            *) error "Invalid selection. Please enter a number between 1-5."; continue ;;
        esac
    done

    selected_info "Telegram Destination: $TELEGRAM_DESTINATION"

    if [[ "$TELEGRAM_DESTINATION" != "none" ]]; then
        echo ""
        header "🤖 Bot Token Configuration"
        while true; do
            read -p "Enter Telegram Bot Token: " TELEGRAM_BOT_TOKEN
            if validate_bot_token "$TELEGRAM_BOT_TOKEN"; then break; else continue; fi
        done
        selected_info "Bot Token: ${TELEGRAM_BOT_TOKEN:0:8}..."
        
        if [[ "$TELEGRAM_DESTINATION" == "channel" || "$TELEGRAM_DESTINATION" == "both" ]]; then
            echo ""
            header "📢 Channel ID Configuration"
            while true; do
                read -p "Enter Telegram Channel ID: " TELEGRAM_CHANNEL_ID
                if validate_id "$TELEGRAM_CHANNEL_ID"; then break; fi
            done
            selected_info "Channel ID: $TELEGRAM_CHANNEL_ID"
        fi
        
        if [[ "$TELEGRAM_DESTINATION" == "bot" || "$TELEGRAM_DESTINATION" == "both" ]]; then
            echo ""
            header "💬 Chat ID Configuration"
            while true; do
                read -p "Enter your Chat ID (for bot private message): " TELEGRAM_CHAT_ID
                if validate_id "$TELEGRAM_CHAT_ID"; then break; fi
            done
            selected_info "Chat ID: $TELEGRAM_CHAT_ID"
        fi
        
        if [[ "$TELEGRAM_DESTINATION" == "group" ]]; then
            echo ""
            header "👥 Group ID Configuration"
            while true; do
                read -p "Enter Telegram Group ID: " TELEGRAM_GROUP_ID
                if validate_id "$TELEGRAM_GROUP_ID"; then break; fi
            done
            selected_info "Group ID: $TELEGRAM_GROUP_ID"
        fi
    fi
    
    echo ""
}

# C. Region Selection
select_region() {
    header "🗺️ GCP Region Selection"
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
            *) error "Invalid selection. Please enter a number between 1-12." ;;
        esac
    done
    
    selected_info "Region: $REGION"
    echo ""
}

# D. CPU Configuration
select_cpu() {
    header "💻 CPU Configuration"
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
            *) error "Invalid selection. Please enter a number between 1-5." ;;
        esac
    done
    
    selected_info "CPU: $CPU core(s)"
    echo ""
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
            *) error "Invalid selection. Please enter a number between 1-7." ;;
        esac
    done
    
    selected_info "Memory: $MEMORY"
    echo ""
}

# F. Summary and Confirmation (Ordered, FIXED INPUT)
show_config_summary() {
    local temp_project_id=$(gcloud config get-value project 2>/dev/null || echo "Not Configured (Deployment will fail)")
    
    header "📋 Configuration Summary"
    
    # Determine auth label and path/service line for display
    local auth_label
    local auth_value
    local path_label
    local path_value
    
    if [[ "$PROTOCOL" == "TROJAN-WS" ]]; then
        auth_label="Password"
        auth_value="$PASSWORD"
        path_label="WS Path"
        path_value="$WS_PATH"
    elif [[ "$PROTOCOL" == "VLESS-GRPC" ]]; then
        auth_label="UUID"
        auth_value="$UUID"
        path_label="gRPC Service"
        path_value="$GRPC_SERVICE"
    else
        auth_label="UUID"
        auth_value="$UUID"
        path_label="WS Path"
        path_value="$WS_PATH"
    fi
    
    # Using printf for alignment, ordered as requested
    printf "${CYAN}${BOLD}%-20s${NC} %s\n" "Protocol:"               "$PROTOCOL"
    printf "${CYAN}${BOLD}%-20s${NC} %s\n" "Service Name:"           "$SERVICE_NAME"
    printf "${CYAN}${BOLD}%-20s${NC} %s\n" "Host Domain:"            "$HOST_DOMAIN"
    printf "${CYAN}${BOLD}%-20s${NC} %s\n" "$auth_label:"            "$auth_value"
    printf "${CYAN}${BOLD}%-20s${NC} %s\n" "$path_label:"            "$path_value"
    
    printf "${CYAN}${BOLD}%-20s${NC} %s\n" "Region:"                 "$REGION"
    printf "${CYAN}${BOLD}%-20s${NC} %s\n" "CPU/Memory:"             "$CPU core(s) / $MEMORY" # Combined
    
    printf "${CYAN}${BOLD}%-20s${NC} %s\n" "Project ID:"             "$temp_project_id"

    if [[ "$TELEGRAM_DESTINATION" != "none" ]]; then
        printf "${CYAN}${BOLD}%-20s${NC} %s\n" "Telegram:" "$TELEGRAM_DESTINATION (Token: ${TELEGRAM_BOT_TOKEN:0:8}...)"
    else
        printf "${CYAN}${BOLD}%-20s${NC} %s\n" "Telegram:" "Not configured"
    fi
    echo
    
    # --- FIXED INPUT LOOP START ---
    while true; do
        read -p "$(echo -e "${ORANGE}${BOLD}Proceed with deployment? (y/n): ${NC}")" confirm
        
        # Convert input to lowercase for case-insensitive check
        confirm=$(echo "$confirm" | tr '[:upper:]' '[:lower:]')
        
        case $confirm in
            y ) 
                # Proceed with deployment
                auto_deployment_setup
                break
                ;;
            n ) 
                # Cancel deployment
                info "Deployment cancelled by user. 👋"
                exit 0
                ;;
            # Handle empty input (Enter) or any other invalid input gracefully
            "" | * ) 
                warn "Invalid input. Please enter 'y' to proceed or 'n' to cancel. Retrying..."
                # Loop continues, asking the question again
                ;;
        esac
    done
    # --- FIXED INPUT LOOP END ---
}

# ------------------------------------------------------------------------------
# 4. MODIFIED: AUTO DEPLOYMENT SETUP (Project ID CLI & API Enablement)
# ------------------------------------------------------------------------------
auto_deployment_setup() {
    log "Starting initial GCP setup... 🛠️"
    
    info "Fetching Project ID for CLI configuration. 🔍"
    PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
    
    if [[ -z "$PROJECT_ID" ]]; then
        error "GCP Project ID is not configured in gcloud CLI. Please run 'gcloud config set project [PROJECT_ID]' and try again. ⚠️"
    fi
    
    selected_info "Using configured Project ID: $PROJECT_ID"

    log "Verifying gcloud CLI active project to: ${PROJECT_ID} 📝"
    spinner "Setting Project ID CLI" "gcloud config set project \"$PROJECT_ID\" --quiet > /dev/null 2>&1"

    log "Enabling required APIs (Cloud Run, Container Registry, Cloud Build)... 🔓"
    spinner "Enabling APIs" "gcloud services enable run.googleapis.com containerregistry.googleapis.com cloudbuild.googleapis.com --project \"$PROJECT_ID\" --quiet > /dev/null 2>&1"

    log "Initial GCP setup complete. Proceeding with deployment... 🎉"
    spinner "GCP Setup" "sleep 0.5"
}

# ------------------------------------------------------------------------------
# 5. CORE DEPLOYMENT FUNCTIONS 
# ------------------------------------------------------------------------------

# Clone Repo and Extract Files 
clone_and_extract() {
    log "Cloning repository from https://github.com/ahlflk/GCP-V2RAY-Cloud-Run.git... 📥"
    spinner "Cloning Repository" "git clone https://github.com/ahlflk/GCP-V2RAY-Cloud-Run.git temp-repo > /dev/null 2>&1"

    if [ ! -d "temp-repo" ]; then
        error "Failed to clone repository. Check your network or permissions. 🌐"
    fi
    
    cd temp-repo

    if [ ! -f "Dockerfile" ]; then
        error "Dockerfile not found in repo. 🐳"
    fi
    if [ ! -f "config.json" ]; then
        error "config.json not found in repo. ⚙️"
    fi

    cp Dockerfile ../Dockerfile > /dev/null 2>&1
    cp config.json ../config.json > /dev/null 2>&1
    cd ..
    rm -rf temp-repo > /dev/null 2>&1
}

# Config File Preparation 
prepare_config_files() {
    log "Preparing Xray config file (replacing placeholders)... 📄"
    if [[ ! -f "config.json" ]]; then
        error "config.json not found. ❌"
    fi
    
    # Protocol-specific replacements
    if [[ "$PROTOCOL" != "TROJAN-WS" ]]; then
        sed -i "s/PLACEHOLDER_UUID/$UUID/g" config.json
    fi
    if [[ "$PROTOCOL" == "TROJAN-WS" ]]; then
        sed -i "s/PLACEHOLDER_PASSWORD/$PASSWORD/g" config.json
    fi
    if [[ "$PROTOCOL" == "VLESS-GRPC" ]]; then
        sed -i "s/PLACEHOLDER_GRPC_SERVICE/$GRPC_SERVICE/g" config.json
    fi
    if [[ "$PROTOCOL" == "VLESS-WS" || "$PROTOCOL" == "TROJAN-WS" ]]; then
        sed -i "s|PLACEHOLDER_WS_PATH|$WS_PATH|g" config.json
    fi
    
    spinner "Preparing Config" "sleep 0.1"
}

# Share Link Creation 
create_share_link() {
    local SERVICE_NAME="$1"
    local DOMAIN="$2"
    local UUID_OR_PASSWORD=""
    
    DOMAIN="${DOMAIN#https://}"
    DOMAIN="${DOMAIN%/}"
    
    if [[ "$PROTOCOL" == "TROJAN-WS" ]]; then
        UUID_OR_PASSWORD="$PASSWORD"
    else
        UUID_OR_PASSWORD="$UUID"
    fi
    
    local LINK=""
    case $PROTOCOL in
        "VLESS-WS")
            local PATH_ENCODED=$(echo "$WS_PATH" | sed 's/\//%2F/g')
            LINK="vless://${UUID_OR_PASSWORD}@${HOST_DOMAIN}:443?path=${PATH_ENCODED}&security=tls&encryption=none&host=${DOMAIN}&fp=randomized&type=ws&sni=${DOMAIN}#${SERVICE_NAME}_VLESS-WS"
            ;;
        "VLESS-GRPC")
            LINK="vless://${UUID_OR_PASSWORD}@${HOST_DOMAIN}:443?security=tls&encryption=none&host=${DOMAIN}&fp=randomized&type=grpc&serviceName=${GRPC_SERVICE}&sni=${DOMAIN}#${SERVICE_NAME}_VLESS-GRPC"
            ;;
        "TROJAN-WS")
            local PATH_ENCODED=$(echo "$WS_PATH" | sed 's/\//%2F/g')
            LINK="trojan://${UUID_OR_PASSWORD}@${HOST_DOMAIN}:443?path=${PATH_ENCODED}&security=tls&type=ws&host=${DOMAIN}&fp=randomized&sni=${DOMAIN}#${SERVICE_NAME}_TROJAN-WS"
            ;;
    esac
    
    echo "$LINK"
}

# Telegram Notification Function (Updated for HTML parse_mode)
send_to_telegram() {
    local chat_id="$1"
    local message="$2"
    # Escape double quotes for JSON
    message=$(echo "$message" | sed 's/"/\\"/g')
    
    curl -s -o /dev/null -w "%{http_code}" -X POST \
        -H "Content-Type: application/json" \
        -d "{\"chat_id\": \"${chat_id}\", \"text\": \"${message}\", \"parse_mode\": \"HTML\", \"disable_web_page_preview\": true}" \
        https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage
}

send_deployment_notification() {
    local message="$1"
    
    case $TELEGRAM_DESTINATION in
        "channel")
            send_to_telegram "$TELEGRAM_CHANNEL_ID" "$message" > /dev/null 2>&1
            log "Notification sent to Telegram Channel. 📢"
            ;;
        "bot")
            send_to_telegram "$TELEGRAM_CHAT_ID" "$message" > /dev/null 2>&1
            log "Notification sent to Bot private message. 💬"
            ;;
        "group")
            send_to_telegram "$TELEGRAM_GROUP_ID" "$message" > /dev/null 2>&1
            log "Notification sent to Telegram Group. 👥"
            ;;
        "both")
            send_to_telegram "$TELEGRAM_CHANNEL_ID" "$message" > /dev/null 2>&1
            send_to_telegram "$TELEGRAM_CHAT_ID" "$message" > /dev/null 2>&1
            log "Notification sent to both Channel and Bot. 📱"
            ;;
        "none")
            log "Skipping Telegram notification. ⏭️"
            ;;
    esac
}

# Deploy to Cloud Run (Telegram message structure modified for order and CPU/Memory)
deploy_to_cloud_run() {
    local project_id="$PROJECT_ID"

    log "Building and pushing Docker image... 🐳"
    spinner "Building Docker Image" "gcloud builds submit --tag gcr.io/$project_id/$SERVICE_NAME:v1 . --quiet > /dev/null 2>&1"

    log "Deploying to Cloud Run service... ☁️"
    spinner "Deploying Service" "gcloud run deploy $SERVICE_NAME --image gcr.io/$project_id/$SERVICE_NAME:v1 --platform managed --region $REGION --allow-unauthenticated --port 8080 --memory $MEMORY --cpu $CPU --quiet > /dev/null 2>&1"

    local service_url=$(gcloud run services describe $SERVICE_NAME --region $REGION --format='value(status.url)' --quiet 2>/dev/null)
    if [[ -z "$service_url" ]]; then
        error "Failed to retrieve service URL after deployment. 🌐"
    fi

    local share_link=$(create_share_link "$SERVICE_NAME" "$service_url")

    log "Deployment completed! 🎉"
    selected_info "Service URL: $service_url"
    selected_info "Share Link: $share_link"

    # Telegram Message structure (HTML format, VLESS in <code> for easy copy, no "Copy Code" text)
    local telegram_message="🚀 <b>GCP V2Ray Deployment Complete!</b>

📋 <b>Details:</b>

• <blockquote><b>🔌 Protocol:</b> ${PROTOCOL}

• <b>🗺️ Region:</b> ${REGION}

• <b>💻/💾 CPU/Memory:</b> ${CPU} core(s) / ${MEMORY}</blockquote>

<b>🔗 Share Link:</b>

<pre><code>${share_link}</code></pre>"
    
    send_deployment_notification "$telegram_message"
}

# Create Folder with deployment-info.txt (FIXED AND ORDERED, Combined CPU/Memory)
create_project_folder() {
    local project_id="$PROJECT_ID"
    local service_url=$(gcloud run services describe $SERVICE_NAME --region $REGION --format='value(status.url)' --quiet 2>/dev/null)
    local share_link=$(create_share_link "$SERVICE_NAME" "$service_url")

    log "Saving project files and info to folder: GCP-V2RAY-Cloud-Run/ 📁"
    mkdir -p GCP-V2RAY-Cloud-Run
    # Move/Copy the generated files into the new folder
    mv Dockerfile GCP-V2RAY-Cloud-Run/ > /dev/null 2>&1
    mv config.json GCP-V2RAY-Cloud-Run/ > /dev/null 2>&1
    
    # EOF block content is now ordered as requested, and the blank line is fixed.
    cat > GCP-V2RAY-Cloud-Run/deployment-info.txt << EOF
==============================
GCP V2Ray Cloud Run Deployment Info
==============================
Protocol: $PROTOCOL
Region: $REGION
CPU/Memory: $CPU core(s) / $MEMORY
==============================
Share Link: $share_link
==============================
Project ID: $project_id
Deployment Date: $(date)
==============================
EOF
    
    log "Project files and info saved successfully in: GCP-V2RAY-Cloud-Run/ 📁"
    info "Check the 'GCP-V2RAY-Cloud-Run' folder for your deployment files and details. 📁" 
}

# ------------------------------------------------------------------------------
# 6. MAIN EXECUTION BLOCK
# ------------------------------------------------------------------------------

# Initialize emojis
show_emojis

# Run user input functions in specified order
run_user_inputs() {
    header "🚀 GCP Cloud Run V2Ray Deployment"
    
    # 1. V2Ray Config (Calls all internally in sequence)
    select_v2ray_config
    
    # 2. Telegram Settings
    select_telegram_destination
    
    # 3. Region
    select_region
    
    # 4. CPU
    select_cpu
    
    # 5. Memory
    select_memory
    
    # 6. Summary and Confirmation (Calls auto_deployment_setup upon 'Yes')
    show_config_summary 
}

# Main execution
run_user_inputs

# Core Deployment Steps run automatically after auto_deployment_setup completes
clone_and_extract
prepare_config_files
deploy_to_cloud_run
create_project_folder 

info "All done! Check your GCP Console for the deployed service. 🎉"
