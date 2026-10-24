# drop-in replacement of the ngrok/ngrok image for the playground examples: same command line
# (start --all --config /etc/ngrok.yml), same agent API (http://127.0.0.1:4040/api/tunnels), tunnels opened with
# bore (https://github.com/ekzhang/bore) on the server of BORE_SERVER instead of ngrok
FROM alpine:3.22
ARG BORE_VERSION=v0.6.0
RUN apk add --no-cache busybox-extras \
    && arch=$(uname -m) \
    && wget -q -O - "https://github.com/ekzhang/bore/releases/download/${BORE_VERSION}/bore-${BORE_VERSION}-${arch}-unknown-linux-musl.tar.gz" | tar --no-same-owner -xz -C /usr/local/bin bore \
    && bore --version
COPY entrypoint.sh /entrypoint.sh
EXPOSE 4040
ENTRYPOINT ["/entrypoint.sh"]
