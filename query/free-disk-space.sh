#!/bin/bash
sudo systemd-run docker system prune --force --all --volumes
sudo systemd-run rm -rf \
  "$AGENT_TOOLSDIRECTORY" \
  /opt/* \
  /usr/local/* \
  /usr/share/az* \
  /usr/share/dotnet \
  /usr/share/gradle* \
  /usr/share/miniconda \
  /usr/share/swift \
  /var/lib/gems \
  /var/lib/mysql \
  /var/lib/snapd
sudo apt-get -y autoremove
sudo apt-get clean
df -h /
