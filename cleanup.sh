#!/bin/bash
set -e

export AWS_PAGER=""

echo "===================================="
echo "AWS EC2 Cleanup"
echo "===================================="
echo "Account : $(aws sts get-caller-identity --query Account --output text)"
echo "Region  : $(aws configure get region)"
echo ""

INSTANCE_IDS=$(aws ec2 describe-instances \
--filters "Name=tag:Project,Values=MobaxDevOps" \
          "Name=instance-state-name,Values=running" \
--query 'Reservations[].Instances[].InstanceId' \
--output text --no-cli-pager | tr -d '\r')

if [ -z "$INSTANCE_IDS" ]; then
  echo "No running project instances found."
  exit 0
fi

echo "Terminating instances:"
echo "$INSTANCE_IDS"
echo ""

for ID in $INSTANCE_IDS; do
  aws ec2 terminate-instances \
  --instance-ids $ID \
  --no-cli-pager
done

aws ec2 wait instance-terminated \
--instance-ids $INSTANCE_IDS \
--no-cli-pager

echo ""
echo "Cleanup completed successfully."
