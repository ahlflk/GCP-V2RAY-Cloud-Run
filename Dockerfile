FROM alpine:latest

RUN apk add --no-cache wget unzip

RUN wget https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip && \
    unzip -q Xray-linux-64.zip && \
    mkdir -p /usr/local/share/xray && \
    mv xray /usr/local/bin/ && \
    wget https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat -O /usr/local/share/xray/geoip.dat && \
    wget https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat -O /usr/local/share/xray/geosite.dat && \
    rm Xray-linux-64.zip && \
    rm -f LICENSE README.md

RUN chmod +x /usr/local/bin/xray

COPY config.json /etc/xray/config.json

CMD ["/usr/local/bin/xray", "-config", "/etc/xray/config.json"]