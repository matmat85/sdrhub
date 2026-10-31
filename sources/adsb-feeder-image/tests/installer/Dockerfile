FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 python3-flask python3-requests python3-cryptography python3-pil fonts-dejavu-core device-tree-compiler git usbutils iproute2 nftables \
    && rm -rf /var/lib/apt/lists/*
COPY . /source
COPY tests/installer/mock-command.sh /mock/docker
COPY tests/installer/mock-command.sh /mock/systemctl
COPY tests/installer/mock-command.sh /mock/systemd-run
RUN chmod +x /mock/* && mkdir -p /usr/lib/systemd/system
ENV PATH="/mock:${PATH}"
CMD ["bash", "/source/tests/installer/local-source.test.sh"]
