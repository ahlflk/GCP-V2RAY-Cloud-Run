# Dockerfile will be copied from the GitHub repo during runtime, 
# but a local file is also needed for the build process.
# This template assumes a standard Xray build for Cloud Run.

FROM alpine/git AS clone

# Clone the actual repo to get the latest Xray binary if needed, 
# but for simplicity and stability, we use a known good base image for Cloud Run.
# We skip the git clone step here in Dockerfile since the script handles it.

# --- Stage 1: Build/Download Xray ---
FROM golang:1.22-alpine AS builder

# Install necessary tools
RUN apk add --no-cache git curl ca-certificates

# Download Xray (using a specific version for stability)
ENV XRAY_VERSION v1.8.4 
RUN wget -O /usr/local/bin/xray "https://github.com/XTLS/Xray-core/releases/download/${XRAY_VERSION}/Xray-linux-64.zip" && \
    unzip /usr/local/bin/xray -d /usr/local/bin/ && \
    rm /usr/local/bin/xray && \
    chmod +x /usr/local/bin/xray

# --- Stage 2: Final Image ---
FROM alpine:3.18

# Copy Xray binary from builder stage
COPY --from=builder /usr/local/bin/xray /usr/local/bin/xray

# Copy the generated config.json (script must ensure this file is present)
COPY config.json /etc/xray/config.json

# Expose the port (Cloud Run defaults to 8080)
EXPOSE 8080

# Run Xray with the config file
CMD ["/usr/local/bin/xray", "-c", "/etc/xray/config.json"]
