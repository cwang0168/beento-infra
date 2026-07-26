#!/bin/bash
set -euo pipefail

dnf install -y docker
systemctl enable docker
systemctl start docker
usermod -aG docker ec2-user

mkdir -p /home/ec2-user/.ssh
chmod 700 /home/ec2-user/.ssh
touch /home/ec2-user/.ssh/authorized_keys
chmod 600 /home/ec2-user/.ssh/authorized_keys

%{ for key in ssh_public_keys ~}
echo "${key}" >> /home/ec2-user/.ssh/authorized_keys
%{ endfor ~}

chown -R ec2-user:ec2-user /home/ec2-user/.ssh
