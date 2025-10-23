# GCP Cloud Run V2Ray Deployment Script

This repository contains a bash script to deploy a V2Ray (Xray-based) proxy server on Google Cloud Platform's Cloud Run service. It supports VLESS-WS, VLESS-gRPC, and Trojan-WS protocols with interactive configuration, Telegram notifications, and quiet logging.

## Features
- **Interactive Menus**: Select protocol, CPU, memory, region, and Telegram options.
- **Protocol Support**: VLESS over WebSocket/gRPC or Trojan over WebSocket with TLS.
- **Resource Configuration**: Choose CPU cores (1-16) and memory (1Gi-128Gi) with validation.
- **Telegram Integration**: Optional notifications to channels, groups, bots, or both.
- **Quiet Mode**: Suppressed build logs for cleaner output.
- **Share Links**: Generates importable links for V2Ray clients.
- **Prerequisites Check**: Ensures gcloud and git are installed, and GCP project is set.

## Prerequisites
- Google Cloud SDK (gcloud) installed.
- Git installed.
- A GCP project with billing enabled.
- Run `gcloud auth login` and `gcloud config set project YOUR_PROJECT_ID`.

## Setup
1. Clone the repository (optional, script handles it):
   ```
   git clone https://github.com/ahlflk/GCP-V2RAY.git
   cd GCP-V2RAY
   ```
2. Ensure `Dockerfile` and `config.json` are in the directory (provided in the script discussion).
3. Make the script executable:
   ```
   chmod +x gcp-v2ray.sh
   ```

## Usage
Run the script:
```
./gcp-v2ray.sh
```
- Follow the interactive prompts to configure.
- Confirm the summary to deploy.
- Output: Deployment info in console and `deployment-info.txt`. Share link for V2Ray clients.

## Files
- **script.sh**: Main deployment script.
- **Dockerfile**: Builds the Xray container (downloads geo files separately).
- **config.json**: Xray configuration template (modified by script).

## Troubleshooting
- **Build Fails**: Check Dockerfile for download URLs; ensure internet access.
- **Logs Visible**: Script suppresses build logs; if needed, remove `> /dev/null 2>&1`.
- **Costs**: Cloud Run is pay-per-use; monitor billing.

## License
MIT License. Use at your own risk.

---

## 👤 Author

Made with ❤️ by [AHLFLK2025channel](https://t.me/AHLFLK2025channel)

---

## #Crd

---

## 🚀 Cloud Run One-Click GCP-VLESS

Run this script directly in **Google Cloud Shell**:

```bash
bash <(curl -Ls https://raw.githubusercontent.com/ahlflk/GCP-V2RAY/refs/heads/main/gcp-v2ray.sh)
