# Use a lightweight base image (e.g., Debian or Alpine)
FROM debian:bullseye-slim

# Install necessary packages (if any)
RUN apt-get update && apt-get install -y \
    curl \
    --no-install-recommends \
    && rm -rf /var/lib/apt/lists/*

# Download and install Xray (V2ray core)
# (You should use a known working version)
ENV XRAY_VERSION 1.8.4
RUN curl -L -H "Cache-Control: no-cache" -o /tmp/xray.zip "https://github.com/XTLS/Xray-core/releases/download/v${XRAY_VERSION}/Xray-linux-64.zip" && \
    unzip /tmp/xray.zip -d /usr/local/bin/ xray && \
    rm -f /tmp/xray.zip

# Set the working directory
WORKDIR /usr/local/etc/xray

# Copy the config file from the source to the container
# The config.json MUST be in the root of your Git repository
COPY config.json .

# Define the command to run Xray. Cloud Run requires port 8080.
# The server must listen on the port defined by the PORT environment variable (default 8080)
# We use '8080' explicitly in the command just in case, but Cloud Run sets the PORT env var.
CMD ["/usr/local/bin/xray", "-c", "/usr/local/etc/xray/config.json"]

# Expose the default Cloud Run port
EXPOSE 8080