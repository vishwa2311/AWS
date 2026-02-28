#!/bin/bash
set -e

export AWS_PAGER=""

KEY_NAME="minikube"
INSTANCE_TYPE="t3.micro"
TODAY=$(date +%d%m)
INSTANCE_NAME="Instance_${TODAY}"

echo "------------------------------------"
echo "Stage 1: Fetch Latest Amazon Linux AMI"
echo "------------------------------------"

AMI_ID=$(aws ssm get-parameters \
--names /aws/service/ami-amazon-linux-latest/amzn2-ami-hvm-x86_64-gp2 \
--query 'Parameters[0].Value' \
--output text)

echo "Using AMI: $AMI_ID"

echo "------------------------------------"
echo "Stage 2: Ensure Key Pair Exists"
echo "------------------------------------"

if ! aws ec2 describe-key-pairs --key-names $KEY_NAME >/dev/null 2>&1; then
    echo "Creating key pair: $KEY_NAME"
    aws ec2 create-key-pair \
    --key-name $KEY_NAME \
    --query 'KeyMaterial' \
    --output text > ${KEY_NAME}.pem
    chmod 400 ${KEY_NAME}.pem
fi

echo "------------------------------------"
echo "Stage 3: Launch EC2 Instance"
echo "------------------------------------"

INSTANCE_ID=$(aws ec2 run-instances \
--image-id $AMI_ID \
--instance-type $INSTANCE_TYPE \
--key-name $KEY_NAME \
--associate-public-ip-address \
--tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$INSTANCE_NAME}]" \
--query 'Instances[0].InstanceId' \
--output text)

echo "Instance ID: $INSTANCE_ID"

echo "------------------------------------"
echo "Stage 4: Wait Until Instance Running."
echo "------------------------------------"

aws ec2 wait instance-running --instance-ids $INSTANCE_ID

PUBLIC_IP=$(aws ec2 describe-instances \
--instance-ids $INSTANCE_ID \
--query 'Reservations[0].Instances[0].PublicIpAddress' \
--output text)

echo "------------------------------------"
echo "Stage 5: Connect via SSH"
echo "------------------------------------"

mkdir -p ~/.ssh
ssh-keyscan -H $PUBLIC_IP >> ~/.ssh/known_hosts 2>/dev/null

echo "Connecting to $PUBLIC_IP ..."
ssh -x -i ${KEY_NAME}.pem ec2-user@$PUBLIC_IP
