# 🚀 GCP-V2RAY: Xray Deployment on Google Cloud Run (VLESS/Trojan)

This repository contains the necessary files and a deployment script to easily run an Xray proxy service (supporting VLESS and Trojan) on Google Cloud Run. The setup leverages Cloud Run's built-in TLS/SSL features, keeping the container configuration simple and secure.

## 📦 Repository Contents

| File Name | Role | Description |
| :--- | :--- | :--- |
| `Dockerfile` | Container Image Definition | Defines the process to build a lightweight Xray-core container image for Cloud Run, listening on port 8080. |
| `config.json` | Xray Server Configuration | A template configuration file. The `deploy.sh` script automatically injects the chosen UUID, Password, and Path/ServiceName based on the selected protocol. |
| `deploy.sh` | Deployment Script | A comprehensive bash script to handle configuration selection (Protocol, Region, UUID), image building, and deployment to Google Cloud Run. |
| `README.md` | Documentation | This guide. |

## ⚙️ Deployment Steps

### Step 1: Prerequisites

1.  **Install Google Cloud SDK (gcloud CLI).**
2.  **Log in to gcloud and set your Project ID.**
    ```bash
    gcloud auth login
    gcloud config set project YOUR_PROJECT_ID
    ```
3.  **Ensure required APIs are enabled** (The script will attempt to enable them, but pre-enabling is recommended).
    ```bash
    gcloud services enable cloudbuild.googleapis.com run.googleapis.com
    ```

### Step 2: Clone the Repository

Clone this repository and give execution permission to the deployment script.

git clone [https://github.com/ahlflk/GCP-V2RAY-Cloud-Run.git](https://github.com/ahlflk/GCP-V2RAY-Cloud-Run.git)

cd GCP-V2RAY-Cloud-Run
chmod +x GCP-V2RAY-Cloud-Run.sh

## License
MIT License. Use at your own risk.

---

## 👤 Author

Made with ❤️ by [AHLFLK2025channel](https://t.me/AHLFLK2025channel)

---

## #Crd

---

## 🚀 Cloud Run One-Click GCP-V2RAY-Cloud-Run

Run this script directly in **Google Cloud Shell**:

```bash
bash <(curl -Ls https://raw.githubusercontent.com/ahlflk/GCP-V2RAY-Cloud-Run/refs/heads/main/gcp-v2ray-cloud-run.sh)

