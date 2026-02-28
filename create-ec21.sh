#!/bin/bash

export AWS_PAGER=""

KEY_NAME="minikube"
INSTANCE_TYPE="t3.micro"
TODAY=$(date +%d%m)
INSTANCE_NAME="Instance_${TODAY}"

echo "Creating EC2: $INSTANCE_NAME"

# Get latest Amazon Linux 2 AMI
AMI_ID=$(aws ssm get-parameters \
--names /aws/service/ami-amazon-linux-latest/amzn2-ami-hvm-x86_64-gp2 \
--query 'Parameters[0].Value' \
--output text --no-cli-pager | tr -d '\r')

echo "Using AMI: $AMI_ID"

# Create key if not exists
aws ec2 describe-key-pairs --key-names $KEY_NAME --no-cli-pager >/dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "Creating key pair: $KEY_NAME"
    aws ec2 create-key-pair \
    --key-name $KEY_NAME \
    --query 'KeyMaterial' \
    --output text --no-cli-pager > ${KEY_NAME}.pem
    chmod 400 ${KEY_NAME}.pem
fi

# Launch instance
INSTANCE_ID=$(aws ec2 run-instances \
--image-id $AMI_ID \
--instance-type $INSTANCE_TYPE \
--key-name $KEY_NAME \
--associate-public-ip-address \
--tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$INSTANCE_NAME}]" \
--query 'Instances[0].InstanceId' \
--output text --no-cli-pager | tr -d '\r')

echo "Instance ID: $INSTANCE_ID"

# Wait until running
aws ec2 wait instance-running --instance-ids $INSTANCE_ID --no-cli-pager

# Get Public IP
PUBLIC_IP=$(aws ec2 describe-instances \
--instance-ids $INSTANCE_ID \
--query 'Reservations[0].Instances[0].PublicIpAddress' \
--output text --no-cli-pager | tr -d '\r')

echo "------------------------------------"
echo "✅ EC2 READY"
echo "Name: $INSTANCE_NAME"
echo "Public IP: $PUBLIC_IP"
echo "------------------------------------"

echo "Connecting via SSH..."
sleep 3

mkdir -p ~/.ssh
ssh-keyscan -H $PUBLIC_IP >> ~/.ssh/known_hosts 2>/dev/null

ssh -x -i ${KEY_NAME}.pem ec2-user@$PUBLIC_IP
