#!/bin/bash
set -e

export AWS_PAGER=""

INSTANCE_TYPE="t3.micro"
TODAY=$(date +%d%m)
INSTANCE_NAME="Instance_${TODAY}"

echo "------------------------------------"
echo "Stage 1: Fetch Latest Amazon Linux AMI"
echo "------------------------------------"

AMI_ID=$(aws ssm get-parameters \
--names /aws/service/ami-amazon-linux-latest/amzn2-ami-hvm-x86_64-gp2 \
--query 'Parameters[0].Value' \
--output text | tr -d '\r\n')

echo "Using AMI: $AMI_ID"

echo "------------------------------------"
echo "Stage 2: Select Key Pair"
echo "------------------------------------"

KEY_LIST=$(aws ec2 describe-key-pairs \
--query 'KeyPairs[*].KeyName' \
--output text)

echo "Available Key Pairs:"
select KEY_NAME in $KEY_LIST "Create-New"; do
    if [ "$KEY_NAME" == "Create-New" ]; then
        read -p "Enter new key name: " KEY_NAME
        aws ec2 create-key-pair \
        --key-name $KEY_NAME \
        --query 'KeyMaterial' \
        --output text > ${KEY_NAME}.pem
        chmod 400 ${KEY_NAME}.pem
        break
    elif [ -n "$KEY_NAME" ]; then
        echo "Selected key: $KEY_NAME"
        break
    else
        echo "Invalid selection"
    fi
done

echo "------------------------------------"
echo "Stage 3: Setup Network (VPC + Subnet + SG)"
echo "------------------------------------"

# Clean VPC
VPC_ID=$(aws ec2 describe-vpcs \
--filters Name=isDefault,Values=true \
--query 'Vpcs[0].VpcId' \
--output text | tr -d '\r\n')

echo "Using VPC: $VPC_ID"

# Clean Subnet
SUBNET_ID=$(aws ec2 describe-subnets \
--filters Name=vpc-id,Values=$VPC_ID \
--query 'Subnets[0].SubnetId' \
--output text | tr -d '\r\n')

echo "Using Subnet: $SUBNET_ID"

# Create fresh SG (cleaned)
SG_ID=$(aws ec2 create-security-group \
--group-name "ssh-${TODAY}-$$" \
--description "SSH Access" \
--vpc-id $VPC_ID \
--query 'GroupId' \
--output text | tr -d '\r\n')

echo "Using SG: $SG_ID"

# Allow SSH (clean ID)
aws ec2 authorize-security-group-ingress \
--group-id "$SG_ID" \
--protocol tcp \
--port 22 \
--cidr 0.0.0.0/0

echo "------------------------------------"
echo "Stage 4: Launch EC2 Instance"
echo "------------------------------------"

INSTANCE_ID=$(aws ec2 run-instances \
--image-id "$AMI_ID" \
--instance-type $INSTANCE_TYPE \
--key-name "$KEY_NAME" \
--network-interfaces "DeviceIndex=0,SubnetId=$SUBNET_ID,Groups=$SG_ID,AssociatePublicIpAddress=true" \
--tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$INSTANCE_NAME}]" \
--query 'Instances[0].InstanceId' \
--output text | tr -d '\r\n')

echo "Instance ID: $INSTANCE_ID"

echo "------------------------------------"
echo "Stage 5: Wait Until Instance Running"
echo "------------------------------------"

aws ec2 wait instance-running --instance-ids "$INSTANCE_ID"

PUBLIC_IP=$(aws ec2 describe-instances \
--instance-ids "$INSTANCE_ID" \
--query 'Reservations[0].Instances[0].PublicIpAddress' \
--output text | tr -d '\r\n')

echo "Public IP: $PUBLIC_IP"

echo "------------------------------------"
echo "Stage 6: Connect via SSH"
echo "------------------------------------"

sleep 15

if [ ! -f "${KEY_NAME}.pem" ]; then
    echo "❌ ERROR: ${KEY_NAME}.pem not found"
    exit 1
fi

mkdir -p ~/.ssh
ssh-keyscan -H "$PUBLIC_IP" >> ~/.ssh/known_hosts 2>/dev/null

echo "Connecting to $PUBLIC_IP ..."
ssh -o StrictHostKeyChecking=no -i "${KEY_NAME}.pem" ec2-user@"$PUBLIC_IP"
