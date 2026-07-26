#!/bin/bash
set -euo pipefail

dnf install -y docker
systemctl enable docker
systemctl start docker
usermod -aG docker ec2-user

# Amazon Linux 2023's docker package doesn't bundle the Compose or Buildx
# plugins -- install both system-wide so `docker compose` and
# `docker compose build` work for any user. Without Compose, `docker
# compose ...` fails with a cryptic "unknown shorthand flag" error instead
# of "compose: not found" (the Docker CLI falls through to parsing
# compose's args as top-level docker flags). Without Buildx, `docker
# compose build` fails with "requires buildx 0.17.0 or later".
mkdir -p /usr/libexec/docker/cli-plugins

curl -SL "https://github.com/docker/compose/releases/latest/download/docker-compose-linux-$(uname -m)" \
  -o /usr/libexec/docker/cli-plugins/docker-compose
chmod +x /usr/libexec/docker/cli-plugins/docker-compose

case "$(uname -m)" in
  x86_64) buildx_arch=amd64 ;;
  aarch64) buildx_arch=arm64 ;;
esac
buildx_url=$(curl -s https://api.github.com/repos/docker/buildx/releases/latest \
  | grep "browser_download_url.*linux-$${buildx_arch}\"" \
  | cut -d '"' -f4)
curl -SL "$buildx_url" -o /usr/libexec/docker/cli-plugins/docker-buildx
chmod +x /usr/libexec/docker/cli-plugins/docker-buildx

mkdir -p /home/ec2-user/.ssh
chmod 700 /home/ec2-user/.ssh
touch /home/ec2-user/.ssh/authorized_keys
chmod 600 /home/ec2-user/.ssh/authorized_keys

%{ for key in ssh_public_keys ~}
echo "${key}" >> /home/ec2-user/.ssh/authorized_keys
%{ endfor ~}

chown -R ec2-user:ec2-user /home/ec2-user/.ssh
