FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    git libarchive-tools syslinux-utils cpio genisoimage coreutils gettext-base whois \
    # clean up
    && apt-get autoremove -y \
    && apt-get clean -y \
    && rm -rf /var/lib/apt/lists/*