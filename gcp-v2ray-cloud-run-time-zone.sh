#!/bin/bash

# ==============================================================================
# GCP Cloud Run V2RAY/XRAY Multi-Protocol Deployment (Fixed: UUID Gen Logic, Asia/Yangon TZ)
# ==============================================================================

# === Time Zone Function ===
# Set the time zone globally for the script
export TZ="Asia/Yangon"

# Helper function to format epoch time to local datetime
fmt_dt(){ 
    # Using 'date' command to format the epoch time in the set TZ (Asia/Yangon)
    date -d @"$1" "+%d.%m.%Y %I:%M %p"; 
}
# ==========================


set -euo pipefail

# ------------------------------------------------------------------------------
# 1. GLOBAL VARIABLES & STYLES
# ------------------------------------------------------------------------------

# Colors
RED='\033[0;31m'
GREEN='\033[1;32m'
LIGHT_GREEN='\033[1;92m'  
YELLOW='\033[1;33m'
ORANGE='\033[0;33m' # Header Color
BLUE='\033[1;34m'
CYAN='\033[1;36m'
WHITE='\033[1;37m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Protocol Selection and Defaults
PROTOCOL="" 
UUID="" 
TROJAN_PASSWORD="" 
REGION="us-central1"
CPU="2"
MEMORY="2Gi"
SERVICE_NAME="gcp-ahlflk"              
HOST_DOMAIN="m.googleapis.com"
VLESS_PATH="/vless-ws"                 
GRPC_SERVICE_NAME="ahlflk"             

# Telegram Variables 
TELEGRAM_DESTINATION="none"
TELEGRAM_BOT_TOKEN=""
TELEGRAM_CHANNEL_ID=""
TELEGRAM_CHAT_ID=""
TELEGRAM_GROUP_ID=""

# Project ID holder
PROJECT_ID=""

# Time Variables 
START_LOCAL=""
END_LOCAL=""

# Deployment Configuration
GIT_REPO="https://github.com/ahlflk/GCP-V2RAY-Cloud-Run.git"
OUTPUT_FOLDER="GCP-V2RAY-Cloud-Run"


# ------------------------------------------------------------------------------
# 2. UTILITY FUNCTIONS (LOGGING, UI, TIME, VALIDATION)
# ------------------------------------------------------------------------------

# Emoji Function
show_emojis() {
    EMOJI_SUCCESS="✅"
    EMOJI_WARN="⚠️"
    EMOJI_ERROR="❌"
    EMOJI_INFO="💡"
    EMOJI_SELECT="🎯"
    EMOJI_PROC="⚙️"
    EMOJI_DEPLOY="🚀"
    EMOJI_CHECK="📋"
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
    local title_line="${border_color}┃${NC} ${text_color}${BOLD}${title}${NC} ${border_color}┃${NC}"
    local bottom_line="${border_color}┗${top_bottom_fill}┛${NC}"
    
    echo -e "${top_bottom}"
    echo -e "${title_line}"
    echo -e "${bottom_line}"
}

# Simple Logs with Emoji
log() { echo -e "${GREEN}${BOLD}${EMOJI_SUCCESS} [LOG]${NC} ${WHITE}$1${NC}"; }
warn() { echo -e "${YELLOW}${BOLD}${EMOJI_WARN} [WARN]${NC} ${WHITE}$1${NC}"; }
error() { echo -e "${RED}${BOLD}${EMOJI_ERROR} [ERROR]${NC} ${WHITE}$1${NC}"; exit 1; }
info() { echo -e "${BLUE}${BOLD}${EMOJI_INFO} [INFO]${NC} ${WHITE}$1${NC}"; }
selected_info() { echo -e "${GREEN}${BOLD}${EMOJI_SELECT} Selected:${NC} ${CYAN}$1${NC}"; }


# Progress Bar
progress_bar() {
    local label="${1:-Processing}" 
    local duration=${2:-3}  
    local width=30         
    local start=$(date +%s)
    local elapsed=0
    
    while [ $elapsed -lt $duration ]; do
        local percent=$((elapsed * 100 / duration))
        local num_chars=$((percent * width / 100))
        local bar=$(printf '#%.0s' $(seq 1 $num_chars))
        local spaces=$(printf ' %.0s' $(seq 1 $((width - num_chars))))
        local remaining=$((duration - elapsed))
        printf "\r${BOLD}${EMOJI_PROC} ${label}... ${NC}[${LIGHT_GREEN}%s${NC}${ORANGE}%s${NC}] %d%% (ETA: %ds)${NC}" "$bar" "$spaces" "$percent" "$remaining"
        sleep 0.1
        elapsed=$(( $(date +%s) - start ))
    done
    
    printf "\r${BOLD}${EMOJI_PROC} ${label}... ${NC}[${LIGHT_GREEN}%s${NC}] 100%% Done! (0s)${NC}\n" "$(printf '#%.0s' $(seq 1 $width))"
}

# Function to calculate and initialize time variables
initialize_time_variables() {
    START_EPOCH="$(date +%s)"
    # Note: 5 hours is only for display/tracking, Cloud Run service is permanent unless deleted
    END_EPOCH="$(( START_EPOCH + 5*3600 ))" 
    START_LOCAL="$(fmt_dt "$START_EPOCH")"
    END_LOCAL="$(fmt_dt "$END_EPOCH")"
    log "Deployment validity times initialized (Asia/Yangon Time)."
}

# Validation Functions
validate_uuid() {
    local uuid_pattern='^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    # Check if the input is non-empty and matches the UUID pattern (case-insensitive)
    if [[ -z "$1" ]] || ! [[ "$1" =~ $uuid_pattern ]]; then 
        warn "Invalid UUID format. Must be 8-4-4-4-12 hex characters."
        return 1; 
    fi
    return 0
}

validate_trojan_password() {
    # Trojan password must be a simple string (no URL encoding/special chars issues)
    if [[ ${#1} -lt 6 ]]; then warn "Trojan password must be at least 6 characters long."; return 1; fi
    if [[ $1 =~ [[:space:]] ]]; then warn "Trojan password cannot contain spaces."; return 1; fi
    return 0
}

validate_id() {
    if [[ ! $1 =~ ^-?[0-9]+$ ]]; then warn "Invalid Telegram ID format. Must be a number."; return 1; fi
    return 0
}

validate_bot_token() {
    local token_pattern='^[0-9]{8,10}:[a-zA-Z0-9_-]{35}$'
    if [[ ! $1 =~ $token_pattern ]]; then warn "Invalid Telegram Bot Token format. Please try again."; return 1; fi
    return 0
}

# ------------------------------------------------------------------------------
# 3. USER INPUT FUNCTIONS 
# ------------------------------------------------------------------------------

# A. Protocol Selection (NEW - must be first)
select_protocol() {
    header "⛓️  Protocol Selection"
    echo -e "${CYAN}Choose the tunneling protocol for deployment:${NC}"
    echo -e "${BOLD}1.${NC} VLESS-WS (Recommended)"
    echo -e "${BOLD}2.${NC} VLESS-gRPC"
    echo -e "${BOLD}3.${NC} Trojan-WS"
    echo
    
    while true; do
        read -p "Select protocol (1): " protocol_choice
        protocol_choice=${protocol_choice:-1}
        case $protocol_choice in
            1) 
                PROTOCOL="VLESS-WS"
                VLESS_PATH="/vless-ws" # Hardcoded Default
                break 
                ;;
            2) 
                PROTOCOL="VLESS-gRPC"
                GRPC_SERVICE_NAME="ahlflk" # Hardcoded Default (as requested)
                break 
                ;;
            3) 
                PROTOCOL="Trojan-WS"
                VLESS_PATH="/trojan-ws" # Hardcoded Default
                break
                ;;
            *) echo -e "${RED}Invalid selection. Please enter 1, 2, or 3.${NC}" ;;
        esac
    done
    
    selected_info "Protocol: $PROTOCOL"
    echo
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
            *) echo -e "${RED}Invalid selection. Please enter a number between 1-5.${NC}"; continue ;;
        esac
    done

    if [[ "$TELEGRAM_DESTINATION" != "none" ]]; then
        echo
        
        # --- Token Header --- 
        header "🤖 Bot Token"
        while true; do
            read -p "Enter Telegram Bot Token: " TELEGRAM_BOT_TOKEN
            if validate_bot_token "$TELEGRAM_BOT_TOKEN"; then break; else continue; fi
        done
        
        if [[ "$TELEGRAM_DESTINATION" == "channel" || "$TELEGRAM_DESTINATION" == "both" ]]; then
            # --- Channel ID Header --- 
            header "📢 Channel ID"
            while true; do
                read -p "Enter Telegram Channel ID: " TELEGRAM_CHANNEL_ID
                if validate_id "$TELEGRAM_CHANNEL_ID"; then break; fi
            done
        fi
        
        if [[ "$TELEGRAM_DESTINATION" == "bot" || "$TELEGRAM_DESTINATION" == "both" ]]; then
            # --- Chat ID Header --- 
            header "👤 Chat ID"
            while true; do
                read -p "Enter your Chat ID (for bot private message): " TELEGRAM_CHAT_ID
                if validate_id "$TELEGRAM_CHAT_ID"; then break; fi
            done
        fi
        
        if [[ "$TELEGRAM_DESTINATION" == "group" ]]; then
            # --- Group ID Header --- 
            header "👥 Group ID"
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
    
    echo -e "${CYAN}Deployment Service Name (Default: $SERVICE_NAME):${NC}" 
    
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
    header "🌐 Host Domain Configuration (SNI)"
    
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

# H. Key/Password Configuration (UUID Generation Logic Fixed)
select_key_and_path() {
    header "🔑 Key/Password & Path/Service Configuration"
    
    if [[ "$PROTOCOL" == "VLESS-WS" || "$PROTOCOL" == "VLESS-gRPC" ]]; then
        # VLESS UUID Selection
        local default_uuid="3675119c-14fc-46a4-b5f3-9a2c91a7d802"
            
        while true; do
            echo -e "${CYAN}UUID Options:${NC}"
            echo -e "${BOLD}1.${NC} Use Default UUID (3675...802) ${GREEN}[DEFAULT]${NC}"
            echo -e "${BOLD}2.${NC} Generate New UUID"
            echo -e "${CYAN}You can also paste a custom UUID directly, or press Enter for default.${NC}"

            read -p "Enter 1, 2, or Paste Custom UUID: " uuid_input
            uuid_input=${uuid_input:-1} # Default to option 1: Default UUID

            if [[ "$uuid_input" == "1" ]]; then
                UUID="$default_uuid"
                log "Using Default UUID."
                break
            elif [[ "$uuid_input" == "2" ]]; then
                # *** FIXED: UUID Generation without Warning for Fallback ***
                local new_uuid=""
                
                # 1. Primary: Use uuidgen
                if command -v uuidgen &> /dev/null; then
                    new_uuid=$(uuidgen)
                # 2. Fallback: Use kernel's random UUID file (No 'warn' for this fallback)
                elif [ -f "/proc/sys/kernel/random/uuid" ]; then
                    new_uuid=$(cat /proc/sys/kernel/random/uuid)
                fi

                # 3. Validation and Final Assignment
                if validate_uuid "$new_uuid"; then
                    UUID="$new_uuid"
                    log "Generated New UUID successfully: $UUID"
                else
                    UUID="$default_uuid"
                    warn "UUID generation failed. Falling back to default UUID: $default_uuid"
                fi
                break
            elif validate_uuid "$uuid_input"; then
                UUID="$uuid_input"
                log "Using Custom UUID."
                break
            else
                echo -e "${RED}Invalid input. Please enter 1, 2, or a valid custom UUID.${NC}" 
            fi
        done
        selected_info "UUID: $UUID"
        echo
        
        # Path/Service Name for VLESS (Using Protocol Defaults)
        if [[ "$PROTOCOL" == "VLESS-WS" ]]; then
            read -p "$(echo -e "${CYAN}Enter WebSocket Path (Default: $VLESS_PATH): ${NC}")" custom_path
            VLESS_PATH=${custom_path:-$VLESS_PATH}
            if [[ ! "$VLESS_PATH" =~ ^/ ]]; then VLESS_PATH="/$VLESS_PATH"; fi
            selected_info "WS Path: $VLESS_PATH"
        elif [[ "$PROTOCOL" == "VLESS-gRPC" ]]; then
            read -p "$(echo -e "${CYAN}Enter gRPC Service Name (Default: $GRPC_SERVICE_NAME): ${NC}")" custom_grpc_svc
            GRPC_SERVICE_NAME=${custom_grpc_svc:-$GRPC_SERVICE_NAME}
            selected_info "gRPC Service Name: $GRPC_SERVICE_NAME"
        fi

    elif [[ "$PROTOCOL" == "Trojan-WS" ]]; then
        # Trojan Password Selection
        while true; do
            read -p "Enter Trojan Password: " TROJAN_PASSWORD
            if validate_trojan_password "$TROJAN_PASSWORD"; then break; fi
        done
        selected_info "Password: ${TROJAN_PASSWORD:0:3}***${TROJAN_PASSWORD: -3}"
        echo

        # Path for Trojan-WS (Using Protocol Defaults)
        read -p "$(echo -e "${CYAN}Enter WebSocket Path (Default: $VLESS_PATH): ${NC}")" custom_path
        VLESS_PATH=${custom_path:-$VLESS_PATH}
        if [[ ! "$VLESS_PATH" =~ ^/ ]]; then VLESS_PATH="/$VLESS_PATH"; fi
        selected_info "WS Path: $VLESS_PATH"
    fi
    echo
}


# I. Summary and Confirmation
show_config_summary() {
    local temp_project_id=$(gcloud config get-value project 2>/dev/null || echo "Not Configured (Deployment will fail)")
    
    header "${EMOJI_CHECK} Configuration Summary"
    
    printf "${CYAN}${BOLD}%-25s${NC} %s\n" "Project ID:"             "$temp_project_id"
    printf "${CYAN}${BOLD}%-25s${NC} %s\n" "Protocol:"               "$PROTOCOL"
    printf "${CYAN}${BOLD}%-25s${NC} %s\n" "Region:"                 "$REGION"
    printf "${CYAN}${BOLD}%-25s${NC} %s\n" "Service Name:"           "$SERVICE_NAME"
    printf "${CYAN}${BOLD}%-25s${NC} %s\n" "Host Domain (SNI):"     "$HOST_DOMAIN"

    if [[ "$PROTOCOL" == "VLESS-WS" || "$PROTOCOL" == "VLESS-gRPC" ]]; then
        printf "${CYAN}${BOLD}%-25s${NC} %s\n" "UUID:"               "$UUID"
    elif [[ "$PROTOCOL" == "Trojan-WS" ]]; then
        printf "${CYAN}${BOLD}%-25s${NC} %s\n" "Password:"           "${TROJAN_PASSWORD:0:3}***${TROJAN_PASSWORD: -3}"
    fi

    if [[ "$PROTOCOL" == "VLESS-WS" || "$PROTOCOL" == "Trojan-WS" ]]; then
        printf "${CYAN}${BOLD}%-25s${NC} %s\n" "WS Path:"            "$VLESS_PATH"
    elif [[ "$PROTOCOL" == "VLESS-gRPC" ]]; then
        printf "${CYAN}${BOLD}%-25s${NC} %s\n" "gRPC Service Name:"  "$GRPC_SERVICE_NAME"
    fi

    printf "${CYAN}${BOLD}%-25s${NC} %s\n" "CPU/Memory:"             "$CPU core(s) / $MEMORY"
    printf "${CYAN}${BOLD}%-25s${NC} %s\n" "Telegram:"             "$TELEGRAM_DESTINATION"
    
    header "⏳ Deployment Timeframe (Asia/Yangon)"
    printf "${CYAN}${BOLD}%-25s${NC} %s\n" "Deployment Start:"       "$START_LOCAL"
    printf "${CYAN}${BOLD}%-25s${NC} %s\n" "Estimated End Time:"     "$END_LOCAL (5 hours)"
    echo
    
    while true; do
        read -p "$(echo -e "${ORANGE}${BOLD}Proceed with deployment? (y/n): ${NC}")" confirm
        case $confirm in
            [Yy]* ) 
                auto_deployment_setup
                break
                ;;
            [Nn]* ) 
                info "Deployment cancelled by user"
                exit 0
                ;;
            * ) echo -e "${RED}Please answer yes (y) or no (n).${NC}";;
        esac
    done
}

# ------------------------------------------------------------------------------
# 4. CORE DEPLOYMENT FUNCTIONS 
# ------------------------------------------------------------------------------
auto_deployment_setup() {
    log "Starting initial GCP setup..."
    
    info "Fetching Project ID for CLI configuration."
    PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
    
    if [[ -z "$PROJECT_ID" ]]; then
        error "GCP Project ID is not configured in gcloud CLI. Please run 'gcloud config set project [PROJECT_ID]' and try again."
    fi
    selected_info "Using configured Project ID: $PROJECT_ID"

    log "Verifying gcloud CLI active project to: ${PROJECT_ID}"
    gcloud config set project "$PROJECT_ID" --quiet > /dev/null 2>&1
    progress_bar "Setting Project ID CLI" 1

    info "Enabling required APIs (Cloud Run, Container Registry, Cloud Build)..."
    gcloud services enable run.googleapis.com containerregistry.googleapis.com cloudbuild.googleapis.com --project "$PROJECT_ID" --quiet > /dev/null 2>&1
    progress_bar "Enabling APIs" 5

    log "Initial GCP setup complete. Proceeding with deployment..."
    echo
}

clone_and_extract() {
    log "Cloning repository from $GIT_REPO..."
    # Clone the repository to a temporary directory
    git clone $GIT_REPO temp-repo > /dev/null 2>&1
    progress_bar "Cloning Repository" 3

    if [ ! -d "temp-repo" ]; then
        error "Failed to clone repository. Check your network or permissions."
    fi
    
    # 1. Check/Copy Dockerfile from the cloned repo
    if [ ! -f "temp-repo/Dockerfile" ]; then
        error "Dockerfile not found in the cloned repository."
    fi
    cp temp-repo/Dockerfile ./Dockerfile > /dev/null 2>&1
    
    # 2. Check if the required config template exists in the current directory
    local config_template=""
    if [[ "$PROTOCOL" == "VLESS-WS" ]]; then
        config_template="temp-repo/config_vless.json"
    elif [[ "$PROTOCOL" == "VLESS-gRPC" ]]; then
        config_template="temp-repo/config_vless_grpc.json"
    elif [[ "$PROTOCOL" == "Trojan-WS" ]]; then
        config_template="temp-repo/config_trojan.json"
    fi

    if [ ! -f "$config_template" ]; then
        error "Required config template file '$config_template' not found in the repository."
    fi
    
    # 3. Rename the template to config.json for Docker build
    cp "$config_template" config.json > /dev/null 2>&1

    # 4. Clean up the cloned directory
    rm -rf temp-repo > /dev/null 2>&1
    
    log "Repository cloned and config template files prepared successfully."
}

prepare_config_files() {
    log "Preparing Xray config file for $PROTOCOL..."
    if [[ ! -f "config.json" ]]; then
        error "Internal Error: config.json was not created during extraction."
    fi

    if [[ "$PROTOCOL" == "VLESS-WS" || "$PROTOCOL" == "VLESS-gRPC" ]]; then
        sed -i "s/PLACEHOLDER_UUID/$UUID/g" config.json
    elif [[ "$PROTOCOL" == "Trojan-WS" ]]; then
        sed -i "s/PLACEHOLDER_PASSWORD/$TROJAN_PASSWORD/g" config.json
    fi

    if [[ "$PROTOCOL" == "VLESS-WS" || "$PROTOCOL" == "Trojan-WS" ]]; then
        # VLESS_PATH is already set (hardcoded default or user input)
        sed -i "s|PLACEHOLDER_PATH|$VLESS_PATH|g" config.json
    elif [[ "$PROTOCOL" == "VLESS-gRPC" ]]; then
        # GRPC_SERVICE_NAME is already set (hardcoded default or user input)
        sed -i "s/PLACEHOLDER_SERVICE_NAME/$GRPC_SERVICE_NAME/g" config.json
    fi
    
    progress_bar "Preparing Config" 1
}

create_share_link() {
    local SERVICE_NAME="$1"
    local DOMAIN="$2"
    local LINK=""
    
    # Clean up domain names
    DOMAIN="${DOMAIN#https://}"; DOMAIN="${DOMAIN#http://}"; DOMAIN="${DOMAIN%/}"
    local HOST_DOMAIN_CLEAN="${HOST_DOMAIN#https://}"; HOST_DOMAIN_CLEAN="${HOST_DOMAIN_CLEAN#http://}"; HOST_DOMAIN_CLEAN="${HOST_DOMAIN_CLEAN%/}"
    
    # URL Encode path (Using sed for basic encoding for a bash script)
    local PATH_ENCODED=$(echo "$VLESS_PATH" | sed 's/\//%2F/g')
    
    if [[ "$PROTOCOL" == "VLESS-WS" ]]; then
        LINK="vless://${UUID}@${HOST_DOMAIN_CLEAN}:443?path=${PATH_ENCODED}&security=tls&encryption=none&host=${DOMAIN}&fp=randomized&type=ws&sni=${DOMAIN}#${SERVICE_NAME}_VLESS-WS_${END_LOCAL}"
    elif [[ "$PROTOCOL" == "VLESS-gRPC" ]]; then
        LINK="vless://${UUID}@${HOST_DOMAIN_CLEAN}:443?security=tls&encryption=none&type=grpc&serviceName=${GRPC_SERVICE_NAME}&sni=${DOMAIN}&host=${DOMAIN}#${SERVICE_NAME}_VLESS-gRPC_${END_LOCAL}"
    elif [[ "$PROTOCOL" == "Trojan-WS" ]]; then
        LINK="trojan://${TROJAN_PASSWORD}@${HOST_DOMAIN_CLEAN}:443?path=${PATH_ENCODED}&security=tls&host=${DOMAIN}&type=ws&sni=${DOMAIN}#${SERVICE_NAME}_Trojan-WS_${END_LOCAL}"
    fi
    
    echo "$LINK"
}

send_to_telegram() {
    local chat_id="$1"
    local message="$2"
    # Escaping logic for Markdown 
    message=$(echo "$message" | sed 's/\*/\\*/g; s/_/\\_/g; s/`/\\`/g; s/\[/\\\[/g; s/\]/\\\]/g; s/(/\\(/g; s/)/\\)/g')
    message=$(echo "$message" | sed 's/\\\[VLESS Link\\\]/\[VLESS Link\]/g; s/\\\[Trojan Link\\\]/\[Trojan Link\]/g; s/\\((/((/g; s/\\))/))/g')
    
    curl -s -o /dev/null -w "%{http_code}" -X POST \
        -H "Content-Type: application/json" \
        -d "{\"chat_id\": \"${chat_id}\", \"text\": \"$message\", \"parse_mode\": \"MARKDOWN\", \"disable_web_page_preview\": true}" \
        https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage
}

send_deployment_notification() {
    local message="$1"
    
    case $TELEGRAM_DESTINATION in
        "channel"|"bot"|"group"|"both")
            log "Sending notification to Telegram..."
            local chats=()
            if [[ "$TELEGRAM_DESTINATION" == "channel" || "$TELEGRAM_DESTINATION" == "both" ]]; then chats+=("$TELEGRAM_CHANNEL_ID"); fi
            if [[ "$TELEGRAM_DESTINATION" == "bot" || "$TELEGRAM_DESTINATION" == "both" ]]; then chats+=("$TELEGRAM_CHAT_ID"); fi
            if [[ "$TELEGRAM_DESTINATION" == "group" ]]; then chats+=("$TELEGRAM_GROUP_ID"); fi

            for chat_id in "${chats[@]}"; do
                send_to_telegram "$chat_id" "$message" > /dev/null 2>&1
            done
            log "Notification sent to Telegram destination(s)."
            ;;
        "none")
            log "Skipping Telegram notification."
            ;;
    esac
}

deploy_to_cloud_run() {
    local project_id="$PROJECT_ID"

    log "Building and pushing Docker image..."
    gcloud builds submit --tag gcr.io/$project_id/$SERVICE_NAME:v1 . --quiet > /dev/null 2>&1
    progress_bar "Building Docker Image" 15

    log "Deploying to Cloud Run service..."
    gcloud run deploy $SERVICE_NAME \
      --image gcr.io/$project_id/$SERVICE_NAME:v1 \
      --platform managed \
      --region $REGION \
      --allow-unauthenticated \
      --port 8080 \
      --memory $MEMORY \
      --cpu $CPU \
      --quiet > /dev/null 2>&1
    progress_bar "Deploying Service" 8

    local service_url=$(gcloud run services describe $SERVICE_NAME --region $REGION --format='value(status.url)' --quiet 2>/dev/null)
    if [[ -z "$service_url" ]]; then
        error "Failed to retrieve service URL after deployment."
    fi

    local share_link=$(create_share_link "$SERVICE_NAME" "$service_url")
    
    local key_info=""
    local link_name="${PROTOCOL} Link"
    if [[ "$PROTOCOL" == "VLESS-WS" || "$PROTOCOL" == "VLESS-gRPC" ]]; then
        key_info="• UUID: $UUID"
    elif [[ "$PROTOCOL" == "Trojan-WS" ]]; then
        key_info="• Password: ${TROJAN_PASSWORD:0:3}***${TROJAN_PASSWORD: -3}"
    fi

    log "Deployment completed!"
    selected_info "Service URL: $service_url"
    selected_info "${PROTOCOL} Share Link: $share_link"

    # Telegram Message includes Start Time and End Time (as requested)
    local telegram_message="🚀 *GCP ${PROTOCOL} Deployment Complete (Asia/Yangon)!*\n\n📋 *Details:*\n• Protocol: $PROTOCOL\n• Region: $REGION\n• Service: $SERVICE_NAME\n${key_info}\n• Start Time: $START_LOCAL\n• End Time: $END_LOCAL (5 hours)\n\n🔗 [${link_name}]($share_link)"
    
    send_deployment_notification "$telegram_message"
}

create_project_folder() {
    local project_id="$PROJECT_ID"
    local service_url=$(gcloud run services describe $SERVICE_NAME --region $REGION --format='value(status.url)' --quiet 2>/dev/null)
    local share_link=$(create_share_link "$SERVICE_NAME" "$service_url")

    log "Saving project files and info to folder: $OUTPUT_FOLDER/"
    mkdir -p "$OUTPUT_FOLDER"
    
    # Check for Dockerfile and config.json before moving
    if [ -f "Dockerfile" ]; then mv Dockerfile "$OUTPUT_FOLDER"/ > /dev/null 2>&1; fi
    if [ -f "config.json" ]; then mv config.json "$OUTPUT_FOLDER"/xray_config.json > /dev/null 2>&1; fi
    
    local key_info=""
    local path_info=""

    if [[ "$PROTOCOL" == "VLESS-WS" || "$PROTOCOL" == "VLESS-gRPC" ]]; then
        key_info="UUID: $UUID"
    elif [[ "$PROTOCOL" == "Trojan-WS" ]]; then
        key_info="Password: $TROJAN_PASSWORD"
    fi

    if [[ "$PROTOCOL" == "VLESS-WS" || "$PROTOCOL" == "Trojan-WS" ]]; then
        path_info="Path: $VLESS_PATH"
    elif [[ "$PROTOCOL" == "VLESS-gRPC" ]]; then
        path_info="gRPC Service Name: $GRPC_SERVICE_NAME"
    fi

    cat > "$OUTPUT_FOLDER"/deployment-info.txt << EOF
GCP V2RAY/XRAY Cloud Run Deployment Info
========================================

Protocol: $PROTOCOL
Project ID: $project_id
Region: $REGION
Service Name: $SERVICE_NAME
Host Domain (SNI): $HOST_DOMAIN
$key_info
$path_info
CPU: $CPU
Memory: $MEMORY
Service URL: $service_url
Share Link: $share_link

Deployment Date: $START_LOCAL (Asia/Yangon)
Estimated End Time: $END_LOCAL (5 hours)

For more details, check GCP Console: https://console.cloud.google.com/run?project=$project_id
EOF
    
    log "Project files and info saved successfully in: $OUTPUT_FOLDER/"
    info "Check the '$OUTPUT_FOLDER' folder for your deployment files and details."
}


# ------------------------------------------------------------------------------
# 5. MAIN EXECUTION BLOCK
# ------------------------------------------------------------------------------

show_emojis
initialize_time_variables

run_user_inputs() {
    header "${EMOJI_DEPLOY} GCP Cloud Run V2RAY/XRAY Deployment"
    select_protocol 
    select_telegram_destination
    select_region
    select_cpu
    select_memory
    select_service_name
    select_host_domain
    select_key_and_path 
    show_config_summary 
}

run_user_inputs

# Core Deployment Steps run automatically after auto_deployment_setup completes
clone_and_extract
prepare_config_files
deploy_to_cloud_run
create_project_folder 

info "All done! Deployment files are in $OUTPUT_FOLDER/ folder."

